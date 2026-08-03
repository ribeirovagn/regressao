#!/usr/bin/env python3
"""Freeze a development-only candidate for untouched prospective evaluation.

All labels in the frozen historical CSV have already been observed. They may
be used for walk-forward development, but never as a new approval test. The
resulting model remains blocked until the prospective holdout manifest is
ready and a one-time future evaluation is performed.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import onnx
import onnxruntime as ort
import pandas as pd
from sklearn.metrics import roc_auc_score
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

from train_breakout_model import (
    DEFAULT_CSV,
    MISSING_SENTINEL,
    PROJECT_ROOT,
    choose_threshold,
    classification_metrics,
    clean_json,
    economic_metrics,
    load_dataset,
    make_models,
    sha256_file,
)


DEFAULT_STABILITY_CSV = PROJECT_ROOT / "ML" / "artifacts" / "stability" / "feature_stability.csv"
DEFAULT_STABILITY_REPORT = (
    PROJECT_ROOT / "ML" / "artifacts" / "stability" / "stability_report.json"
)
DEFAULT_HOLDOUT_MANIFEST = PROJECT_ROOT / "ML" / "prospective_holdout_manifest.json"
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "ML" / "artifacts" / "prospective_candidate"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--stability-csv", type=Path, default=DEFAULT_STABILITY_CSV)
    parser.add_argument("--stability-report", type=Path, default=DEFAULT_STABILITY_REPORT)
    parser.add_argument("--holdout-manifest", type=Path, default=DEFAULT_HOLDOUT_MANIFEST)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--minimum-coverage", type=float, default=0.15)
    parser.add_argument("--random-state", type=int, default=42)
    return parser.parse_args()


def expanding_folds(frame: pd.DataFrame) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    boundaries = ((0.40, 0.55), (0.55, 0.70), (0.70, 0.85), (0.85, 1.00))
    folds: list[dict[str, Any]] = []
    audit: list[dict[str, Any]] = []
    row_count = len(frame)

    for fold_number, (train_fraction, validation_end_fraction) in enumerate(boundaries, start=1):
        validation_start = frame.loc[int(row_count * train_fraction), "meta_signal_time"]
        validation_end = (
            frame.loc[int(row_count * validation_end_fraction), "meta_signal_time"]
            if validation_end_fraction < 1.0
            else None
        )
        signal_time = frame["meta_signal_time"]
        exit_time = frame["label_exit_time"]
        train_mask = (signal_time < validation_start) & (exit_time < validation_start)
        validation_mask = signal_time >= validation_start
        if validation_end is not None:
            validation_mask &= (signal_time < validation_end) & (exit_time < validation_end)

        train_index = np.flatnonzero(train_mask.to_numpy())
        validation_index = np.flatnonzero(validation_mask.to_numpy())
        if min(len(train_index), len(validation_index)) < 250:
            raise ValueError(f"Walk-forward fold {fold_number} is too small")
        folds.append(
            {
                "fold": fold_number,
                "train_index": train_index,
                "validation_index": validation_index,
            }
        )
        audit.append(
            {
                "fold": fold_number,
                "train_rows": len(train_index),
                "validation_rows": len(validation_index),
                "validation_start": validation_start,
                "validation_end_exclusive": validation_end,
                "train_first_signal": frame.loc[train_index[0], "meta_signal_time"],
                "train_last_signal": frame.loc[train_index[-1], "meta_signal_time"],
                "validation_first_signal": frame.loc[
                    validation_index[0], "meta_signal_time"
                ],
                "validation_last_signal": frame.loc[
                    validation_index[-1], "meta_signal_time"
                ],
            }
        )
    return folds, audit


def feature_policies(stability: pd.DataFrame, all_features: list[str]) -> dict[str, list[str]]:
    policies = {
        "all": all_features,
        "psi_le_010": stability.loc[stability["max_psi"] <= 0.10, "feature"].tolist(),
        "psi_le_010_no_flip": stability.loc[
            (stability["max_psi"] <= 0.10)
            & (~stability["train_test_direction_flip"].astype(bool)),
            "feature",
        ].tolist(),
        "stable_direction": stability.loc[
            stability["direction_stable"].astype(bool), "feature"
        ].tolist(),
        "stable_direction_psi_le_010": stability.loc[
            stability["direction_stable"].astype(bool)
            & (stability["max_psi"] <= 0.10),
            "feature",
        ].tolist(),
    }
    for name, features in policies.items():
        if not features:
            raise ValueError(f"Feature policy {name} is empty")
        unknown = sorted(set(features).difference(all_features))
        if unknown:
            raise ValueError(f"Feature policy {name} contains unknown features: {unknown}")
    return policies


def development_gate(candidate: dict[str, Any]) -> tuple[bool, list[str]]:
    checks = {
        "minimum_fold_auc_at_least_0_52": candidate["minimum_fold_auc"] >= 0.52,
        "median_fold_auc_at_least_0_52": candidate["median_fold_auc"] >= 0.52,
        "oof_average_net_step_positive": (
            candidate["oof_economics"]["average_net_step_return"] or -math.inf
        )
        > 0.0,
        "oof_profit_factor_at_least_1_10": (
            candidate["oof_economics"]["profit_factor"] or -math.inf
        )
        >= 1.10,
        "all_four_folds_average_net_step_positive": candidate["positive_economic_folds"] == 4,
        "minimum_fold_profit_factor_at_least_1_05": (
            candidate["minimum_fold_profit_factor"] or -math.inf
        )
        >= 1.05,
        "oof_coverage_at_least_0_15": candidate["oof_economics"]["coverage"] >= 0.15,
    }
    failed = [name for name, passed in checks.items() if not passed]
    return not failed, failed


def evaluate_candidates(
    frame: pd.DataFrame,
    all_features: pd.DataFrame,
    target: np.ndarray,
    policies: dict[str, list[str]],
    folds: list[dict[str, Any]],
    minimum_coverage: float,
    random_state: int,
) -> dict[str, dict[str, Any]]:
    results: dict[str, dict[str, Any]] = {}

    for policy_name, feature_names in policies.items():
        for model_name in make_models(random_state):
            probabilities: list[np.ndarray] = []
            validation_frames: list[pd.DataFrame] = []
            fold_auc: list[float] = []

            for fold in folds:
                train_index = fold["train_index"]
                validation_index = fold["validation_index"]
                model = make_models(random_state)[model_name]
                model.fit(
                    all_features.iloc[train_index][feature_names],
                    target[train_index],
                )
                probability = model.predict_proba(
                    all_features.iloc[validation_index][feature_names]
                )[:, 1]
                probabilities.append(probability)
                validation_frames.append(frame.iloc[validation_index].reset_index(drop=True))
                fold_auc.append(float(roc_auc_score(target[validation_index], probability)))

            oof_probability = np.concatenate(probabilities)
            oof_frame = pd.concat(validation_frames, ignore_index=True)
            threshold, oof_economics, _ = choose_threshold(
                oof_frame,
                oof_probability,
                minimum_coverage,
            )
            oof_target = oof_frame["label_success"].to_numpy(dtype=np.int64)
            oof_classification = classification_metrics(oof_target, oof_probability)

            fold_economics: list[dict[str, Any]] = []
            cursor = 0
            for probability, validation_frame in zip(probabilities, validation_frames):
                row_count = len(validation_frame)
                fold_economics.append(
                    economic_metrics(
                        validation_frame,
                        oof_probability[cursor : cursor + row_count],
                        threshold,
                    )
                )
                cursor += row_count

            positive_folds = sum(
                (economics["average_net_step_return"] or -math.inf) > 0.0
                for economics in fold_economics
            )
            fold_profit_factors = [
                economics["profit_factor"]
                for economics in fold_economics
                if economics["profit_factor"] is not None
            ]
            candidate = {
                "feature_policy": policy_name,
                "feature_count": len(feature_names),
                "feature_names": feature_names,
                "model": model_name,
                "threshold": threshold,
                "fold_auc": fold_auc,
                "minimum_fold_auc": min(fold_auc),
                "median_fold_auc": float(np.median(fold_auc)),
                "oof_classification": oof_classification,
                "oof_economics": oof_economics,
                "fold_economics": fold_economics,
                "positive_economic_folds": positive_folds,
                "minimum_fold_profit_factor": (
                    min(fold_profit_factors) if fold_profit_factors else None
                ),
            }
            passed, failed_checks = development_gate(candidate)
            candidate["development_gate_passed"] = passed
            candidate["failed_development_checks"] = failed_checks
            results[f"{policy_name}__{model_name}"] = candidate
    return results


def select_candidate(results: dict[str, dict[str, Any]]) -> tuple[str, dict[str, Any]]:
    eligible = [(name, candidate) for name, candidate in results.items() if candidate["development_gate_passed"]]
    if not eligible:
        raise RuntimeError("No walk-forward candidate passed the development stability gate")

    def ranking(item: tuple[str, dict[str, Any]]) -> tuple[float, float, float, float]:
        candidate = item[1]
        return (
            float(candidate["minimum_fold_auc"]),
            float(candidate["median_fold_auc"]),
            float(candidate["minimum_fold_profit_factor"] or -math.inf),
            float(candidate["oof_economics"]["profit_factor"] or -math.inf),
        )

    return max(eligible, key=ranking)


def main() -> int:
    args = parse_args()
    manifest = json.loads(args.holdout_manifest.read_text(encoding="utf-8"))
    csv_path = args.csv.resolve()
    current_hash = sha256_file(csv_path)
    if current_hash != manifest["frozen_dataset_sha256"]:
        raise RuntimeError(
            "Development dataset changed after the prospective cutoff was frozen. "
            "Refusing to read possible future labels."
        )

    stability_report = json.loads(args.stability_report.read_text(encoding="utf-8"))
    if stability_report["dataset"]["sha256"] != current_hash:
        raise RuntimeError("Stability report does not match the frozen development dataset")

    frame, feature_names = load_dataset(csv_path)
    cutoff = pd.Timestamp(manifest["cutoff_signal_time"])
    if frame["meta_signal_time"].max() > cutoff:
        raise RuntimeError("Frozen development CSV contains a signal after the prospective cutoff")

    stability = pd.read_csv(args.stability_csv)
    policies = feature_policies(stability, feature_names)
    folds, fold_audit = expanding_folds(frame)
    features = frame[feature_names].replace(MISSING_SENTINEL, np.nan).astype(np.float32)
    target = frame["label_success"].to_numpy(dtype=np.int64)
    results = evaluate_candidates(
        frame,
        features,
        target,
        policies,
        folds,
        args.minimum_coverage,
        args.random_state,
    )
    selected_key, selected = select_candidate(results)
    selected_features = selected["feature_names"]

    final_model = make_models(args.random_state)[selected["model"]]
    final_model.fit(features[selected_features], target)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    joblib_path = args.output_dir / "prospective_breakout_candidate.joblib"
    onnx_path = args.output_dir / "prospective_breakout_candidate.onnx"
    report_path = args.output_dir / "walk_forward_report.json"
    schema_path = args.output_dir / "prospective_feature_schema.json"
    joblib.dump(final_model, joblib_path)

    estimator = final_model.named_steps["model"]
    onnx_model = convert_sklearn(
        final_model,
        initial_types=[("features", FloatTensorType([None, len(selected_features)]))],
        options={id(estimator): {"zipmap": False}},
        target_opset=17,
    )
    onnx.checker.check_model(onnx_model)
    onnx_path.write_bytes(onnx_model.SerializeToString())

    session = ort.InferenceSession(onnx_path.read_bytes(), providers=["CPUExecutionProvider"])
    sample_frame = features[selected_features].tail(min(256, len(frame)))
    sample = sample_frame.to_numpy(dtype=np.float32)
    expected = final_model.predict_proba(sample_frame)[:, 1]
    actual = np.asarray(session.run(None, {"features": sample})[1])[:, 1]
    onnx_max_difference = float(np.max(np.abs(expected - actual)))
    if onnx_max_difference > 1e-5:
        raise RuntimeError(f"ONNX parity failed: {onnx_max_difference}")

    schema = {
        "schema_version": 1,
        "status": "frozen_waiting_prospective_holdout",
        "approved_for_mt5": False,
        "development_dataset_sha256": current_hash,
        "development_cutoff_signal_time": cutoff,
        "feature_policy": selected["feature_policy"],
        "feature_count": len(selected_features),
        "feature_names": selected_features,
        "input_name": "features",
        "input_dtype": "float32",
        "missing_sentinel": MISSING_SENTINEL,
        "probability_output_name": "probabilities",
        "positive_class_probability_column": 1,
        "locked_threshold": selected["threshold"],
    }
    schema_path.write_text(
        json.dumps(clean_json(schema), indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )

    report = {
        "status": "frozen_waiting_prospective_holdout",
        "approved_for_mt5": False,
        "development_only": True,
        "future_labels_read": False,
        "dataset": {
            "path": str(csv_path),
            "sha256": current_hash,
            "rows": len(frame),
            "first_signal": frame["meta_signal_time"].min(),
            "last_signal": frame["meta_signal_time"].max(),
        },
        "folds": fold_audit,
        "development_gate": {
            "minimum_fold_auc": 0.52,
            "median_fold_auc": 0.52,
            "minimum_oof_profit_factor": 1.10,
            "minimum_fold_profit_factor": 1.05,
            "required_positive_economic_folds": 4,
            "minimum_oof_coverage": args.minimum_coverage,
        },
        "candidate_count": len(results),
        "eligible_candidate_count": sum(
            candidate["development_gate_passed"] for candidate in results.values()
        ),
        "selected_key": selected_key,
        "selected": selected,
        "candidates": results,
        "artifacts": {
            "joblib_path": str(joblib_path),
            "joblib_sha256": sha256_file(joblib_path),
            "onnx_path": str(onnx_path),
            "onnx_sha256": sha256_file(onnx_path),
            "onnx_max_probability_difference": onnx_max_difference,
            "schema_path": str(schema_path),
        },
        "prospective_rule": (
            "Do not retrain, retune, inspect future labels, or alter this threshold before the "
            "prospective holdout gates pass. Passing development gates is not MT5 approval."
        ),
    }
    report_path.write_text(
        json.dumps(clean_json(report), indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )

    print("WALK_FORWARD_CANDIDATE=PASS")
    print(f"selected={selected_key}")
    print(f"features={len(selected_features)}")
    print(f"threshold={selected['threshold']:.8f}")
    print(f"minimum_fold_auc={selected['minimum_fold_auc']:.6f}")
    print(f"median_fold_auc={selected['median_fold_auc']:.6f}")
    print(f"oof_profit_factor={selected['oof_economics']['profit_factor']:.6f}")
    print(f"minimum_fold_profit_factor={selected['minimum_fold_profit_factor']:.6f}")
    print("approved_for_mt5=false")
    print("future_labels_read=false")
    print(f"report={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
