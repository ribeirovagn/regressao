#!/usr/bin/env python3
"""Train on 90 calendar days and validate once on the following 90 days.

Model family and probability threshold are selected only from expanding folds
inside the training window. The validation window never participates in that
selection. If validation passes the frozen economic and discrimination gates,
the same model family is refit on the latest 90-day window for a demo candidate.
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


DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "ML" / "artifacts" / "rolling_90d"
INNER_FRACTIONS = ((0.40, 0.60), (0.60, 0.80), (0.80, 1.00))
VALIDATION_GATE = {
    "minimum_roc_auc": 0.52,
    "minimum_selected_events": 50,
    "minimum_coverage": 0.10,
    "minimum_precision": 0.52,
    "minimum_profit_factor": 1.10,
    "minimum_average_net_step_return_exclusive": 0.0,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--window-days", type=int, default=90)
    parser.add_argument("--minimum-inner-coverage", type=float, default=0.15)
    parser.add_argument("--random-state", type=int, default=42)
    return parser.parse_args()


def rolling_windows(
    frame: pd.DataFrame, window_days: int
) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    if window_days < 30:
        raise ValueError("window_days must be at least 30")
    validation_end = frame["meta_signal_time"].max()
    validation_start = validation_end - pd.Timedelta(days=window_days)
    training_start = validation_start - pd.Timedelta(days=window_days)

    raw_training = frame.loc[
        (frame["meta_signal_time"] >= training_start)
        & (frame["meta_signal_time"] < validation_start)
    ]
    training = raw_training.loc[
        raw_training["label_exit_time"] < validation_start
    ].reset_index(drop=True)
    validation = frame.loc[
        (frame["meta_signal_time"] >= validation_start)
        & (frame["meta_signal_time"] <= validation_end)
    ].reset_index(drop=True)
    if min(len(training), len(validation)) < 250:
        raise ValueError("A rolling window has fewer than 250 completed events")

    audit = {
        "window_days": window_days,
        "training_start_inclusive": training_start,
        "training_end_exclusive": validation_start,
        "validation_start_inclusive": validation_start,
        "validation_end_inclusive": validation_end,
        "training_rows_before_purge": len(raw_training),
        "training_rows": len(training),
        "training_rows_purged": len(raw_training) - len(training),
        "validation_rows": len(validation),
        "training_first_signal": training["meta_signal_time"].min(),
        "training_last_signal": training["meta_signal_time"].max(),
        "training_last_exit": training["label_exit_time"].max(),
        "validation_first_signal": validation["meta_signal_time"].min(),
        "validation_last_signal": validation["meta_signal_time"].max(),
    }
    return training, validation, audit


def inner_folds(training: pd.DataFrame) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    folds: list[dict[str, Any]] = []
    audit: list[dict[str, Any]] = []
    row_count = len(training)
    for number, (start_fraction, end_fraction) in enumerate(INNER_FRACTIONS, start=1):
        validation_start = training.loc[
            int(row_count * start_fraction), "meta_signal_time"
        ]
        validation_end = (
            training.loc[int(row_count * end_fraction), "meta_signal_time"]
            if end_fraction < 1.0
            else None
        )
        train_mask = (training["meta_signal_time"] < validation_start) & (
            training["label_exit_time"] < validation_start
        )
        validation_mask = training["meta_signal_time"] >= validation_start
        if validation_end is not None:
            validation_mask &= training["meta_signal_time"] < validation_end
        train_index = np.flatnonzero(train_mask.to_numpy())
        validation_index = np.flatnonzero(validation_mask.to_numpy())
        if min(len(train_index), len(validation_index)) < 100:
            raise ValueError(f"Inner fold {number} has fewer than 100 events")
        folds.append(
            {
                "fold": number,
                "train_index": train_index,
                "validation_index": validation_index,
            }
        )
        audit.append(
            {
                "fold": number,
                "train_rows": len(train_index),
                "validation_rows": len(validation_index),
                "validation_start": validation_start,
                "validation_end_exclusive": validation_end,
            }
        )
    return folds, audit


def evaluate_inner_candidates(
    training: pd.DataFrame,
    features: pd.DataFrame,
    target: np.ndarray,
    folds: list[dict[str, Any]],
    minimum_coverage: float,
    random_state: int,
) -> dict[str, dict[str, Any]]:
    results: dict[str, dict[str, Any]] = {}
    for model_name in make_models(random_state):
        probabilities: list[np.ndarray] = []
        validation_frames: list[pd.DataFrame] = []
        fold_auc: list[float] = []
        for fold in folds:
            train_index = fold["train_index"]
            validation_index = fold["validation_index"]
            model = make_models(random_state)[model_name]
            model.fit(features.iloc[train_index], target[train_index])
            probability = model.predict_proba(features.iloc[validation_index])[:, 1]
            probabilities.append(probability)
            validation_frames.append(training.iloc[validation_index].reset_index(drop=True))
            fold_auc.append(
                float(roc_auc_score(target[validation_index], probability))
            )

        oof_probability = np.concatenate(probabilities)
        oof_frame = pd.concat(validation_frames, ignore_index=True)
        threshold, oof_economics, _ = choose_threshold(
            oof_frame, oof_probability, minimum_coverage
        )
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
        results[model_name] = {
            "model": model_name,
            "threshold": threshold,
            "fold_auc": fold_auc,
            "minimum_fold_auc": min(fold_auc),
            "median_fold_auc": float(np.median(fold_auc)),
            "oof_classification": classification_metrics(
                oof_frame["label_success"].to_numpy(dtype=np.int64),
                oof_probability,
            ),
            "oof_economics": oof_economics,
            "fold_economics": fold_economics,
            "positive_economic_folds": sum(
                (metrics["average_net_step_return"] or -math.inf) > 0.0
                for metrics in fold_economics
            ),
        }
    return results


def select_inner_candidate(
    candidates: dict[str, dict[str, Any]],
) -> tuple[str, dict[str, Any]]:
    """Select conservatively without consulting the final validation window."""

    def ranking(item: tuple[str, dict[str, Any]]) -> tuple[float, float, float, float]:
        candidate = item[1]
        economics = candidate["oof_economics"]
        return (
            float(candidate["minimum_fold_auc"]),
            float(candidate["median_fold_auc"]),
            float(economics["average_net_step_return"] or -math.inf),
            float(economics["profit_factor"] or -math.inf),
        )

    return max(candidates.items(), key=ranking)


def validation_checks(
    classification: dict[str, Any], economics: dict[str, Any]
) -> dict[str, bool]:
    return {
        "roc_auc": classification["roc_auc"] >= VALIDATION_GATE["minimum_roc_auc"],
        "selected_events": economics["selected"]
        >= VALIDATION_GATE["minimum_selected_events"],
        "coverage": economics["coverage"] >= VALIDATION_GATE["minimum_coverage"],
        "precision": economics["precision"] is not None
        and economics["precision"] >= VALIDATION_GATE["minimum_precision"],
        "profit_factor": economics["profit_factor"] is not None
        and economics["profit_factor"] >= VALIDATION_GATE["minimum_profit_factor"],
        "average_net_step_return": economics["average_net_step_return"] is not None
        and economics["average_net_step_return"]
        > VALIDATION_GATE["minimum_average_net_step_return_exclusive"],
    }


def export_current_candidate(
    model: Any,
    sample: pd.DataFrame,
    feature_names: list[str],
    threshold: float,
    model_name: str,
    output_dir: Path,
) -> dict[str, Any]:
    joblib_path = output_dir / "rolling_90d_current_candidate.joblib"
    onnx_path = output_dir / "rolling_90d_current_candidate.onnx"
    schema_path = output_dir / "rolling_90d_feature_schema.json"
    joblib.dump(model, joblib_path)
    estimator = model.named_steps["model"]
    onnx_model = convert_sklearn(
        model,
        initial_types=[("features", FloatTensorType([None, len(feature_names)]))],
        options={id(estimator): {"zipmap": False}},
        target_opset=17,
    )
    onnx.checker.check_model(onnx_model)
    onnx_path.write_bytes(onnx_model.SerializeToString())
    session = ort.InferenceSession(onnx_path.read_bytes(), providers=["CPUExecutionProvider"])
    expected = model.predict_proba(sample)[:, 1]
    actual = np.asarray(session.run(None, {"features": sample.to_numpy(np.float32)})[1])[:, 1]
    max_difference = float(np.max(np.abs(expected - actual)))
    if max_difference > 1e-5:
        raise RuntimeError(f"ONNX parity failed: {max_difference}")
    schema = {
        "schema_version": 1,
        "status": "eligible_for_demo_forward_test",
        "approved_for_live_trading": False,
        "model": model_name,
        "feature_count": len(feature_names),
        "feature_names": feature_names,
        "input_name": "features",
        "input_dtype": "float32",
        "missing_sentinel": MISSING_SENTINEL,
        "probability_output_name": "probabilities",
        "positive_class_probability_column": 1,
        "locked_threshold": threshold,
    }
    schema_path.write_text(
        json.dumps(clean_json(schema), indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    return {
        "joblib_path": str(joblib_path),
        "joblib_sha256": sha256_file(joblib_path),
        "onnx_path": str(onnx_path),
        "onnx_sha256": sha256_file(onnx_path),
        "schema_path": str(schema_path),
        "schema_sha256": sha256_file(schema_path),
        "onnx_max_probability_difference": max_difference,
    }


def main() -> int:
    args = parse_args()
    csv_path = args.csv.resolve()
    frame, feature_names = load_dataset(csv_path)
    training, validation, window_audit = rolling_windows(frame, args.window_days)
    inner_fold_list, inner_fold_audit = inner_folds(training)
    training_features = (
        training[feature_names].replace(MISSING_SENTINEL, np.nan).astype(np.float32)
    )
    training_target = training["label_success"].to_numpy(dtype=np.int64)
    candidates = evaluate_inner_candidates(
        training,
        training_features,
        training_target,
        inner_fold_list,
        args.minimum_inner_coverage,
        args.random_state,
    )
    selected_name, selected = select_inner_candidate(candidates)

    evaluation_model = make_models(args.random_state)[selected_name]
    evaluation_model.fit(training_features, training_target)
    validation_features = (
        validation[feature_names].replace(MISSING_SENTINEL, np.nan).astype(np.float32)
    )
    validation_target = validation["label_success"].to_numpy(dtype=np.int64)
    validation_probability = evaluation_model.predict_proba(validation_features)[:, 1]
    validation_classification = classification_metrics(
        validation_target, validation_probability
    )
    validation_economics = economic_metrics(
        validation, validation_probability, selected["threshold"]
    )
    checks = validation_checks(validation_classification, validation_economics)
    passed = all(checks.values())

    args.output_dir.mkdir(parents=True, exist_ok=True)
    artifacts = None
    if passed:
        current_model = make_models(args.random_state)[selected_name]
        current_model.fit(validation_features, validation_target)
        sample = validation_features.tail(min(256, len(validation_features)))
        artifacts = export_current_candidate(
            current_model,
            sample,
            feature_names,
            selected["threshold"],
            selected_name,
            args.output_dir,
        )

    report = {
        "protocol": "rolling_two_consecutive_calendar_windows",
        "approved_for_mt5": False,
        "approved_for_live_trading": False,
        "eligible_for_demo_forward_test": passed,
        "dataset": {
            "path": str(csv_path),
            "sha256": sha256_file(csv_path),
            "rows": len(frame),
            "feature_count": len(feature_names),
        },
        "windows": window_audit,
        "inner_folds": inner_fold_audit,
        "selection_rule": (
            "Highest minimum inner-fold ROC AUC, then median AUC, average net step "
            "return, and profit factor. Final validation is not consulted."
        ),
        "selected_model": selected_name,
        "locked_threshold": selected["threshold"],
        "inner_selected_candidate": selected,
        "inner_candidates": candidates,
        "validation_gate": VALIDATION_GATE,
        "validation_classification": validation_classification,
        "validation_economics": validation_economics,
        "validation_checks": checks,
        "validation_passed": passed,
        "current_candidate_refit_window": "validation_window" if passed else None,
        "artifacts": artifacts,
        "rule": (
            "Validation failure rejects this run. Do not select another model or threshold "
            "from the final 90-day results."
        ),
    }
    report_path = args.output_dir / "rolling_90d_report.json"
    report_path.write_text(
        json.dumps(clean_json(report), indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )

    print("ROLLING_90D_EVALUATION=COMPLETE")
    print(f"training_rows={len(training)}")
    print(f"validation_rows={len(validation)}")
    print(f"selected_model={selected_name}")
    print(f"locked_threshold={selected['threshold']:.8f}")
    print(f"validation_auc={validation_classification['roc_auc']:.6f}")
    print(f"validation_selected={validation_economics['selected']}")
    print(f"validation_profit_factor={validation_economics['profit_factor']}")
    print(
        "validation_average_net_step_return="
        f"{validation_economics['average_net_step_return']}"
    )
    print(f"validation_passed={str(passed).lower()}")
    print("approved_for_mt5=false")
    print(f"report={report_path}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
