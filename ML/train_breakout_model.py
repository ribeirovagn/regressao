#!/usr/bin/env python3
"""Train and audit a chronological XAUUSD breakout meta-label model.

This script is deliberately research-only.  It keeps the final test period
untouched until model and threshold selection are complete, purges labels that
cross split boundaries, and records an explicit approval decision before an
ONNX candidate can be considered for MetaTrader integration.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
from typing import Any

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import onnx
import onnxruntime as ort
import pandas as pd
import sklearn
from sklearn.ensemble import (
    ExtraTreesClassifier,
    GradientBoostingClassifier,
    RandomForestClassifier,
)
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    brier_score_loss,
    log_loss,
    roc_auc_score,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CSV = PROJECT_ROOT.parents[1] / "Files" / "xauusd_breakout_ml_events.csv"
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "ML" / "artifacts" / "latest"
MISSING_SENTINEL = -999.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--train-fraction", type=float, default=0.60)
    parser.add_argument("--validation-fraction", type=float, default=0.20)
    parser.add_argument("--min-validation-coverage", type=float, default=0.15)
    parser.add_argument("--random-state", type=int, default=42)
    return parser.parse_args()


def finite_or_none(value: float | int | np.number | None) -> float | int | None:
    if value is None:
        return None
    if isinstance(value, (int, np.integer)):
        return int(value)
    numeric = float(value)
    return numeric if math.isfinite(numeric) else None


def clean_json(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): clean_json(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [clean_json(item) for item in value]
    if isinstance(value, (np.bool_, bool)):
        return bool(value)
    if isinstance(value, (np.integer, int)):
        return int(value)
    if isinstance(value, (np.floating, float)):
        return finite_or_none(value)
    if isinstance(value, (pd.Timestamp, np.datetime64)):
        return str(value)
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_dataset(csv_path: Path) -> tuple[pd.DataFrame, list[str]]:
    if not csv_path.is_file():
        raise FileNotFoundError(f"Dataset not found: {csv_path}")

    frame = pd.read_csv(csv_path)
    required = {
        "meta_schema_version",
        "meta_signal_time",
        "meta_entry_time",
        "meta_signal_kind",
        "meta_direction",
        "label_success",
        "label_exit_time",
        "label_exit_reason",
        "label_net_points",
        "label_net_step_return",
    }
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise ValueError(f"Dataset is missing required columns: {missing}")

    feature_names = [column for column in frame.columns if column.startswith("feature_")]
    if not feature_names:
        raise ValueError("Dataset has no feature_* columns")
    if any(column.startswith(("meta_", "label_")) for column in feature_names):
        raise ValueError("Leakage guard failed: meta/label column reached feature list")

    for column in ("meta_signal_time", "meta_entry_time", "label_exit_time"):
        frame[column] = pd.to_datetime(frame[column], format="%Y.%m.%d %H:%M:%S", errors="raise")

    frame = frame.sort_values(["meta_signal_time", "meta_signal_kind"], kind="stable").reset_index(drop=True)
    frame[feature_names] = frame[feature_names].apply(pd.to_numeric, errors="raise")
    frame["label_success"] = pd.to_numeric(frame["label_success"], errors="raise").astype(np.int64)
    frame["label_net_points"] = pd.to_numeric(frame["label_net_points"], errors="raise")
    frame["label_net_step_return"] = pd.to_numeric(frame["label_net_step_return"], errors="raise")

    if not set(frame["label_success"].unique()).issubset({0, 1}):
        raise ValueError("label_success must be binary")
    if frame["meta_signal_time"].duplicated().all():
        raise ValueError("Signal timestamps are unexpectedly degenerate")
    return frame, feature_names


def chronological_purged_split(
    frame: pd.DataFrame,
    train_fraction: float,
    validation_fraction: float,
) -> tuple[dict[str, np.ndarray], dict[str, Any]]:
    if train_fraction <= 0.0 or validation_fraction <= 0.0:
        raise ValueError("Split fractions must be positive")
    if train_fraction + validation_fraction >= 0.90:
        raise ValueError("At least 10% of rows must remain for the final test")

    row_count = len(frame)
    raw_train_cut = int(row_count * train_fraction)
    raw_test_cut = int(row_count * (train_fraction + validation_fraction))
    validation_start = frame.loc[raw_train_cut, "meta_signal_time"]
    test_start = frame.loc[raw_test_cut, "meta_signal_time"]

    signal_time = frame["meta_signal_time"]
    exit_time = frame["label_exit_time"]

    raw_train = signal_time < validation_start
    raw_validation = (signal_time >= validation_start) & (signal_time < test_start)
    test_mask = signal_time >= test_start

    # Labels that finish on/after the next split begin would leak future path
    # information across the chronological boundary and are removed.
    train_mask = raw_train & (exit_time < validation_start)
    validation_mask = raw_validation & (exit_time < test_start)

    indices = {
        "train": np.flatnonzero(train_mask.to_numpy()),
        "validation": np.flatnonzero(validation_mask.to_numpy()),
        "test": np.flatnonzero(test_mask.to_numpy()),
    }
    if min(len(index) for index in indices.values()) < 100:
        raise ValueError(f"A chronological split is too small: { {k: len(v) for k, v in indices.items()} }")

    audit = {
        "validation_start": validation_start,
        "test_start": test_start,
        "counts": {name: len(index) for name, index in indices.items()},
        "purged_train_rows": int(raw_train.sum() - train_mask.sum()),
        "purged_validation_rows": int(raw_validation.sum() - validation_mask.sum()),
        "ranges": {
            name: {
                "first_signal": frame.loc[index[0], "meta_signal_time"],
                "last_signal": frame.loc[index[-1], "meta_signal_time"],
            }
            for name, index in indices.items()
        },
    }
    return indices, audit


def make_models(random_state: int) -> dict[str, Pipeline]:
    linear = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            ("scale", StandardScaler()),
            (
                "model",
                LogisticRegression(
                    C=0.25,
                    max_iter=3000,
                    class_weight="balanced",
                    random_state=random_state,
                ),
            ),
        ]
    )
    random_forest = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            (
                "model",
                RandomForestClassifier(
                    n_estimators=500,
                    max_depth=6,
                    min_samples_leaf=20,
                    max_features="sqrt",
                    class_weight="balanced_subsample",
                    n_jobs=-1,
                    random_state=random_state,
                ),
            ),
        ]
    )
    extra_trees = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            (
                "model",
                ExtraTreesClassifier(
                    n_estimators=500,
                    max_depth=7,
                    min_samples_leaf=15,
                    max_features="sqrt",
                    class_weight="balanced",
                    n_jobs=-1,
                    random_state=random_state,
                ),
            ),
        ]
    )
    gradient_boosting = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            (
                "model",
                GradientBoostingClassifier(
                    n_estimators=150,
                    learning_rate=0.03,
                    max_depth=2,
                    min_samples_leaf=20,
                    subsample=0.80,
                    random_state=random_state,
                ),
            ),
        ]
    )
    return {
        "logistic_regression": linear,
        "random_forest": random_forest,
        "extra_trees": extra_trees,
        "gradient_boosting": gradient_boosting,
    }


def classification_metrics(y_true: np.ndarray, probability: np.ndarray) -> dict[str, Any]:
    predicted = (probability >= 0.50).astype(np.int64)
    return {
        "rows": len(y_true),
        "positive_rate": float(np.mean(y_true)),
        "accuracy_at_050": float(accuracy_score(y_true, predicted)),
        "balanced_accuracy_at_050": float(balanced_accuracy_score(y_true, predicted)),
        "roc_auc": float(roc_auc_score(y_true, probability)),
        "average_precision": float(average_precision_score(y_true, probability)),
        "log_loss": float(log_loss(y_true, probability, labels=[0, 1])),
        "brier_score": float(brier_score_loss(y_true, probability)),
    }


def economic_metrics(
    frame: pd.DataFrame,
    probability: np.ndarray,
    threshold: float,
) -> dict[str, Any]:
    selected = probability >= threshold
    selected_count = int(selected.sum())
    total_count = len(frame)
    if selected_count == 0:
        return {
            "threshold": float(threshold),
            "rows": total_count,
            "selected": 0,
            "coverage": 0.0,
            "precision": None,
            "net_points": 0.0,
            "average_net_points": None,
            "net_step_return": 0.0,
            "average_net_step_return": None,
            "profit_factor": None,
        }

    chosen = frame.loc[selected]
    net_points = chosen["label_net_points"].to_numpy(dtype=float)
    net_step = chosen["label_net_step_return"].to_numpy(dtype=float)
    gross_profit = float(net_points[net_points > 0.0].sum())
    gross_loss = float(-net_points[net_points < 0.0].sum())
    profit_factor = gross_profit / gross_loss if gross_loss > 0.0 else None
    return {
        "threshold": float(threshold),
        "rows": total_count,
        "selected": selected_count,
        "coverage": selected_count / total_count,
        "precision": float(chosen["label_success"].mean()),
        "net_points": float(net_points.sum()),
        "average_net_points": float(net_points.mean()),
        "net_step_return": float(net_step.sum()),
        "average_net_step_return": float(net_step.mean()),
        "profit_factor": profit_factor,
    }


def choose_threshold(
    frame: pd.DataFrame,
    probability: np.ndarray,
    min_coverage: float,
) -> tuple[float, dict[str, Any], list[dict[str, Any]]]:
    if not 0.05 <= min_coverage <= 0.80:
        raise ValueError("min_validation_coverage must stay inside 0.05..0.80")

    grid = np.linspace(0.05, 0.95, 181)
    quantiles = np.quantile(probability, np.linspace(0.0, 0.95, 96))
    thresholds = np.unique(np.concatenate((grid, quantiles)))
    minimum_selected = max(50, int(math.ceil(len(frame) * min_coverage)))

    curve: list[dict[str, Any]] = []
    eligible: list[dict[str, Any]] = []
    for threshold in thresholds:
        metrics = economic_metrics(frame, probability, float(threshold))
        curve.append(metrics)
        if metrics["selected"] >= minimum_selected:
            eligible.append(metrics)
    if not eligible:
        raise ValueError("No threshold satisfied minimum validation coverage")

    def ranking(metrics: dict[str, Any]) -> tuple[float, float, float]:
        average_step = metrics["average_net_step_return"]
        profit_factor = metrics["profit_factor"]
        precision = metrics["precision"]
        return (
            -math.inf if average_step is None else float(average_step),
            -math.inf if profit_factor is None else float(profit_factor),
            -math.inf if precision is None else float(precision),
        )

    best = max(eligible, key=ranking)
    return float(best["threshold"]), best, curve


def feature_importance(model: Pipeline, feature_names: list[str]) -> list[dict[str, Any]]:
    estimator = model.named_steps["model"]
    if hasattr(estimator, "feature_importances_"):
        signed = np.asarray(estimator.feature_importances_, dtype=float)
        absolute = np.abs(signed)
    elif hasattr(estimator, "coef_"):
        signed = np.asarray(estimator.coef_[0], dtype=float)
        absolute = np.abs(signed)
    else:
        return []

    order = np.argsort(absolute)[::-1]
    return [
        {
            "feature": feature_names[index],
            "importance": float(absolute[index]),
            "signed_value": float(signed[index]),
        }
        for index in order
    ]


def approval_decision(
    validation_economics: dict[str, Any],
    test_classification: dict[str, Any],
    test_economics: dict[str, Any],
    test_baseline: dict[str, Any],
) -> tuple[bool, list[str]]:
    checks = {
        "validation_average_net_step_positive": (validation_economics["average_net_step_return"] or -math.inf) > 0.0,
        "validation_profit_factor_at_least_1_05": (validation_economics["profit_factor"] or -math.inf) >= 1.05,
        "test_roc_auc_at_least_0_52": test_classification["roc_auc"] >= 0.52,
        "test_average_net_step_positive": (test_economics["average_net_step_return"] or -math.inf) > 0.0,
        "test_profit_factor_at_least_1_05": (test_economics["profit_factor"] or -math.inf) >= 1.05,
        "test_coverage_at_least_0_10": test_economics["coverage"] >= 0.10,
        "test_precision_improves_by_0_02": (
            (test_economics["precision"] or -math.inf)
            >= (test_baseline["precision"] or 0.0) + 0.02
        ),
    }
    failed = [name for name, passed in checks.items() if not passed]
    return not failed, failed


def save_threshold_plot(curve: list[dict[str, Any]], chosen_threshold: float, output_path: Path) -> None:
    plot_frame = pd.DataFrame(curve).dropna(subset=["average_net_step_return"])
    figure, left = plt.subplots(figsize=(10, 5))
    left.plot(plot_frame["threshold"], plot_frame["average_net_step_return"], color="#2f80ed")
    left.axvline(chosen_threshold, color="#eb5757", linestyle="--", label=f"chosen={chosen_threshold:.4f}")
    left.axhline(0.0, color="#777777", linewidth=0.8)
    left.set_xlabel("Probability threshold")
    left.set_ylabel("Validation average net step return")
    right = left.twinx()
    right.plot(plot_frame["threshold"], plot_frame["coverage"], color="#27ae60", alpha=0.55)
    right.set_ylabel("Validation coverage")
    left.legend(loc="best")
    figure.tight_layout()
    figure.savefig(output_path, dpi=150)
    plt.close(figure)


def save_importance_plot(importances: list[dict[str, Any]], output_path: Path) -> None:
    if not importances:
        return
    top = pd.DataFrame(importances[:20]).sort_values("importance")
    figure, axis = plt.subplots(figsize=(10, 7))
    axis.barh(top["feature"], top["importance"], color="#2f80ed")
    axis.set_xlabel("Absolute model importance")
    axis.set_title("Top 20 research-candidate features")
    figure.tight_layout()
    figure.savefig(output_path, dpi=150)
    plt.close(figure)


def main() -> int:
    args = parse_args()
    frame, feature_names = load_dataset(args.csv.resolve())
    indices, split_audit = chronological_purged_split(
        frame,
        args.train_fraction,
        args.validation_fraction,
    )

    features = frame[feature_names].replace(MISSING_SENTINEL, np.nan).astype(np.float32)
    target = frame["label_success"].to_numpy(dtype=np.int64)
    train_index = indices["train"]
    validation_index = indices["validation"]
    test_index = indices["test"]

    x_train = features.iloc[train_index]
    y_train = target[train_index]
    x_validation = features.iloc[validation_index]
    y_validation = target[validation_index]
    x_test = features.iloc[test_index]
    y_test = target[test_index]
    validation_frame = frame.iloc[validation_index].reset_index(drop=True)
    test_frame = frame.iloc[test_index].reset_index(drop=True)

    candidates: dict[str, dict[str, Any]] = {}
    trained_models: dict[str, Pipeline] = {}
    threshold_curves: dict[str, list[dict[str, Any]]] = {}
    for name, model in make_models(args.random_state).items():
        model.fit(x_train, y_train)
        validation_probability = model.predict_proba(x_validation)[:, 1]
        threshold, validation_economics, curve = choose_threshold(
            validation_frame,
            validation_probability,
            args.min_validation_coverage,
        )
        validation_classification = classification_metrics(y_validation, validation_probability)
        candidates[name] = {
            "threshold": threshold,
            "validation_classification": validation_classification,
            "validation_economics": validation_economics,
        }
        trained_models[name] = model
        threshold_curves[name] = curve

    def model_ranking(item: tuple[str, dict[str, Any]]) -> tuple[float, float, float]:
        metrics = item[1]
        economics = metrics["validation_economics"]
        classification = metrics["validation_classification"]
        return (
            float(economics["average_net_step_return"] or -math.inf),
            float(economics["profit_factor"] or -math.inf),
            float(classification["roc_auc"]),
        )

    selected_name, selected_validation = max(candidates.items(), key=model_ranking)
    selected_model = trained_models[selected_name]
    selected_threshold = float(selected_validation["threshold"])

    # The final test is first inspected only after model and threshold have
    # been locked by the chronological validation set above.
    test_probability = selected_model.predict_proba(x_test)[:, 1]
    test_classification = classification_metrics(y_test, test_probability)
    test_economics = economic_metrics(test_frame, test_probability, selected_threshold)
    test_baseline = economic_metrics(test_frame, np.ones(len(test_frame)), 0.50)
    approved, failed_checks = approval_decision(
        selected_validation["validation_economics"],
        test_classification,
        test_economics,
        test_baseline,
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    model_path = args.output_dir / "breakout_research_candidate.joblib"
    onnx_path = args.output_dir / "breakout_research_candidate.onnx"
    report_path = args.output_dir / "training_report.json"
    schema_path = args.output_dir / "feature_schema.json"
    predictions_path = args.output_dir / "holdout_predictions.csv"
    threshold_path = args.output_dir / "validation_threshold_curve.csv"

    joblib.dump(selected_model, model_path)
    estimator = selected_model.named_steps["model"]
    onnx_model = convert_sklearn(
        selected_model,
        initial_types=[("features", FloatTensorType([None, len(feature_names)]))],
        options={id(estimator): {"zipmap": False}},
        target_opset=17,
    )
    onnx.checker.check_model(onnx_model)
    onnx_path.write_bytes(onnx_model.SerializeToString())

    session = ort.InferenceSession(onnx_path.read_bytes(), providers=["CPUExecutionProvider"])
    onnx_outputs = session.run(None, {"features": x_test.to_numpy(dtype=np.float32)})
    onnx_probability = np.asarray(onnx_outputs[1])[:, 1]
    onnx_max_probability_difference = float(np.max(np.abs(test_probability - onnx_probability)))
    if onnx_max_probability_difference > 1e-5:
        raise RuntimeError(
            "ONNX parity failed: maximum probability difference "
            f"{onnx_max_probability_difference}"
        )

    importance = feature_importance(selected_model, feature_names)
    schema = {
        "schema_version": 1,
        "dataset_schema_version": sorted(frame["meta_schema_version"].astype(str).unique().tolist()),
        "feature_count": len(feature_names),
        "feature_names": feature_names,
        "input_name": "features",
        "input_dtype": "float32",
        "missing_sentinel": MISSING_SENTINEL,
        "missing_runtime_behavior": "replace sentinel with NaN; ONNX pipeline applies median imputer",
        "positive_class": 1,
        "probability_output_name": "probabilities",
        "probability_output_position": 1,
        "positive_class_probability_column": 1,
        "selected_threshold": selected_threshold,
        "approved_for_mt5": approved,
    }
    schema_path.write_text(json.dumps(clean_json(schema), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    prediction_parts = []
    for split_name, split_frame, probability in (
        ("validation", validation_frame, selected_model.predict_proba(x_validation)[:, 1]),
        ("test", test_frame, test_probability),
    ):
        part = pd.DataFrame(
            {
                "split": split_name,
                "meta_signal_time": split_frame["meta_signal_time"].dt.strftime("%Y-%m-%d %H:%M:%S"),
                "meta_signal_kind": split_frame["meta_signal_kind"],
                "meta_direction": split_frame["meta_direction"],
                "label_exit_reason": split_frame["label_exit_reason"],
                "label_success": split_frame["label_success"],
                "label_net_points": split_frame["label_net_points"],
                "label_net_step_return": split_frame["label_net_step_return"],
                "predicted_probability": probability,
                "selected_at_locked_threshold": (probability >= selected_threshold).astype(int),
            }
        )
        prediction_parts.append(part)
    pd.concat(prediction_parts, ignore_index=True).to_csv(predictions_path, index=False)

    selected_curve = pd.DataFrame(threshold_curves[selected_name])
    selected_curve.to_csv(threshold_path, index=False)
    save_threshold_plot(
        threshold_curves[selected_name],
        selected_threshold,
        args.output_dir / "validation_threshold_curve.png",
    )
    save_importance_plot(importance, args.output_dir / "feature_importance.png")

    report = {
        "research_only": True,
        "approved_for_mt5": approved,
        "failed_approval_checks": failed_checks,
        "dataset": {
            "path": str(args.csv.resolve()),
            "sha256": sha256_file(args.csv.resolve()),
            "rows": len(frame),
            "feature_count": len(feature_names),
            "first_signal": frame["meta_signal_time"].min(),
            "last_signal": frame["meta_signal_time"].max(),
            "positive_rate": float(frame["label_success"].mean()),
        },
        "split": split_audit,
        "selection_policy": {
            "model_selection_source": "chronological validation only",
            "threshold_objective": "maximize validation average label_net_step_return",
            "minimum_validation_coverage": args.min_validation_coverage,
            "test_access_policy": "test evaluated only after model and threshold lock",
            "economic_metric_scope": "event-level labels may overlap and are not portfolio PnL",
        },
        "candidates": candidates,
        "selected_model": selected_name,
        "selected_threshold": selected_threshold,
        "test_classification": test_classification,
        "test_economics": test_economics,
        "test_all_events_baseline": test_baseline,
        "onnx": {
            "path": str(onnx_path),
            "sha256": sha256_file(onnx_path),
            "max_probability_difference": onnx_max_probability_difference,
            "providers": session.get_providers(),
        },
        "joblib": {
            "path": str(model_path),
            "sha256": sha256_file(model_path),
        },
        "top_features": importance[:20],
        "versions": {
            "numpy": np.__version__,
            "pandas": pd.__version__,
            "scikit_learn": sklearn.__version__,
            "onnx": onnx.__version__,
            "onnxruntime": ort.__version__,
        },
    }
    report_path.write_text(
        json.dumps(clean_json(report), indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )

    print("TRAINING_PIPELINE=PASS")
    print(f"selected_model={selected_name}")
    print(f"selected_threshold={selected_threshold:.8f}")
    print(f"test_roc_auc={test_classification['roc_auc']:.6f}")
    print(f"test_selected={test_economics['selected']}/{test_economics['rows']}")
    print(f"test_profit_factor={test_economics['profit_factor']}")
    print(f"test_average_net_step_return={test_economics['average_net_step_return']}")
    print(f"approved_for_mt5={str(approved).lower()}")
    if failed_checks:
        print(f"failed_checks={','.join(failed_checks)}")
    print(f"report={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
