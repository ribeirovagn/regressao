#!/usr/bin/env python3
"""Validate an event-grouped model for XAUUSD profit-giveback exits.

The model estimates whether an exit decided at the current candle close and
executed at the next open will improve the fixed stop/target/timeout baseline.
All fitting, model selection and threshold calibration happen inside the older
90-day window.  The following 90 days are used once for validation.  No model
artifact is exported by this research script.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from sklearn.ensemble import ExtraTreesClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from analyze_exit_hud_reversals import (
    DEFAULT_CSV,
    ExitPathData,
    baseline_metrics,
    clean_json,
    load_exit_path,
    metrics_by_group,
    policy_metrics,
    rolling_specs,
    sha256_file,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = (
    PROJECT_ROOT / "ML" / "artifacts" / "exit_policy" / "exit_policy_report.json"
)
TARGET_ADVANTAGE_STEP = 0.05
INNER_FRACTIONS = ((0.40, 0.60), (0.60, 0.80), (0.80, 1.00))
EXCLUDED_FEATURES = {
    # Raw price level is non-stationary.  Zone step is also excluded so the
    # model is driven by normalized path/HUD values rather than price scale.
    "feature_current_close",
    "feature_zone_step",
}


@dataclass(frozen=True)
class PolicyGate:
    probability_threshold: float
    arm_mfe_step: float
    minimum_giveback_step: float
    minimum_hold_bars: int
    minimum_current_net_step: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--window-days", type=int, default=90)
    parser.add_argument("--minimum-training-events", type=int, default=150)
    parser.add_argument("--minimum-validation-events", type=int, default=100)
    parser.add_argument("--minimum-triggered-events", type=int, default=30)
    parser.add_argument("--minimum-trigger-coverage", type=float, default=0.05)
    parser.add_argument("--max-windows", type=int, default=0)
    parser.add_argument("--random-state", type=int, default=42)
    return parser.parse_args()


def model_columns(data: ExitPathData) -> list[str]:
    features = [
        column
        for column in data.frame
        if column.startswith("feature_") and column not in EXCLUDED_FEATURES
    ]
    if not features:
        raise ValueError("No model features remain after exclusions")
    forbidden = [
        column
        for column in features
        if column.startswith(("label_", "meta_"))
        or "action_exit" in column
        or "execution_spread" in column
    ]
    if forbidden:
        raise ValueError(f"Future execution data reached model features: {forbidden}")
    # Direction is known when the trade opens and is explicitly audited as a
    # safe context column instead of silently allowing arbitrary meta fields.
    return [*features, "meta_direction"]


def make_models(random_state: int) -> dict[str, Pipeline]:
    return {
        "logistic_regression": Pipeline(
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
        ),
        "extra_trees": Pipeline(
            [
                ("imputer", SimpleImputer(strategy="median")),
                (
                    "model",
                    ExtraTreesClassifier(
                        n_estimators=350,
                        max_depth=7,
                        min_samples_leaf=20,
                        max_features="sqrt",
                        class_weight="balanced",
                        n_jobs=-1,
                        random_state=random_state,
                    ),
                ),
            ]
        ),
    }


def event_balanced_weights(data: ExitPathData, row_mask: np.ndarray) -> np.ndarray:
    row_events = data.event_code[row_mask]
    counts = np.bincount(row_events, minlength=len(data.event_frame))
    weights = 1.0 / counts[row_events]
    return weights * (len(weights) / weights.sum())


def fit_model(
    model: Pipeline,
    features: pd.DataFrame,
    target: np.ndarray,
    data: ExitPathData,
    row_mask: np.ndarray,
) -> Pipeline:
    weights = event_balanced_weights(data, row_mask)
    model.fit(
        features.loc[row_mask],
        target[row_mask],
        model__sample_weight=weights,
    )
    return model


def inner_folds(
    data: ExitPathData, outer_training_mask: np.ndarray
) -> tuple[list[tuple[np.ndarray, np.ndarray]], list[dict[str, Any]]]:
    outer_events = np.flatnonzero(outer_training_mask)
    if len(outer_events) < 150:
        raise ValueError("Outer training window has fewer than 150 events")
    signal = data.event_frame["meta_signal_time"]
    exit_time = data.event_frame["meta_baseline_exit_time"]
    folds: list[tuple[np.ndarray, np.ndarray]] = []
    audit: list[dict[str, Any]] = []
    for number, (start_fraction, end_fraction) in enumerate(
        INNER_FRACTIONS, start=1
    ):
        start_position = min(
            int(len(outer_events) * start_fraction), len(outer_events) - 1
        )
        validation_start = signal.iloc[outer_events[start_position]]
        validation_end = None
        if end_fraction < 1.0:
            end_position = min(
                int(len(outer_events) * end_fraction), len(outer_events) - 1
            )
            validation_end = signal.iloc[outer_events[end_position]]
        training = (
            outer_training_mask
            & (signal.to_numpy() < validation_start)
            & (exit_time.to_numpy() < validation_start)
        )
        validation = outer_training_mask & (
            signal.to_numpy() >= validation_start
        )
        if validation_end is not None:
            validation &= signal.to_numpy() < validation_end
        if min(int(training.sum()), int(validation.sum())) < 75:
            raise ValueError(f"Inner fold {number} has fewer than 75 events")
        folds.append((training, validation))
        audit.append(
            {
                "fold": number,
                "training_events": int(training.sum()),
                "validation_events": int(validation.sum()),
                "validation_start": validation_start,
                "validation_end_exclusive": validation_end,
            }
        )
    return folds, audit


def apply_probability_policy(
    data: ExitPathData,
    probability: np.ndarray,
    gate: PolicyGate,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    eligible = (
        np.isfinite(probability)
        & (probability >= gate.probability_threshold)
        & (data.running_mfe >= gate.arm_mfe_step)
        & (data.giveback >= gate.minimum_giveback_step)
        & (data.hold_bars >= gate.minimum_hold_bars)
        & (data.current_net_step >= gate.minimum_current_net_step)
    )
    sentinel = len(data.frame) + 1
    candidate = np.where(eligible, np.arange(len(data.frame)), sentinel)
    first_exit_row = np.minimum.reduceat(candidate, data.starts)
    triggered = first_exit_row < data.ends
    outcome = data.baseline_step.copy()
    outcome[triggered] = data.action_step[first_exit_row[triggered]]
    return outcome, triggered, first_exit_row


def probability_thresholds(probability: np.ndarray) -> list[float]:
    finite = probability[np.isfinite(probability)]
    if not len(finite):
        raise ValueError("No finite out-of-fold probabilities")
    values = np.quantile(
        finite, (0.40, 0.50, 0.60, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95)
    )
    return sorted({float(value) for value in values})


def select_gate(
    data: ExitPathData,
    probability: np.ndarray,
    event_mask: np.ndarray,
    minimum_triggered_events: int,
    minimum_trigger_coverage: float,
) -> tuple[PolicyGate, dict[str, Any]]:
    required_triggers = max(
        minimum_triggered_events,
        int(math.ceil(event_mask.sum() * minimum_trigger_coverage)),
    )
    selected: tuple[tuple[float, ...], PolicyGate, dict[str, Any]] | None = None
    fallback: tuple[tuple[float, ...], PolicyGate, dict[str, Any]] | None = None
    for threshold in probability_thresholds(probability):
        for arm in (0.10, 0.20, 0.30):
            for giveback in (0.05, 0.10, 0.20):
                for hold in (1, 2, 3):
                    for current_net in (-0.10, 0.00):
                        gate = PolicyGate(
                            threshold, arm, giveback, hold, current_net
                        )
                        outcome, triggered, _ = apply_probability_policy(
                            data, probability, gate
                        )
                        metrics = policy_metrics(
                            data, outcome, triggered, event_mask
                        )
                        profit_factor = metrics["profit_factor"] or -math.inf
                        ranking = (
                            float(
                                metrics[
                                    "average_improvement_vs_baseline_step"
                                ]
                            ),
                            float(metrics["average_net_step"]),
                            float(profit_factor),
                            -float(metrics["maximum_drawdown_step"]),
                        )
                        candidate = (ranking, gate, metrics)
                        if fallback is None or ranking > fallback[0]:
                            fallback = candidate
                        if metrics["triggered_events"] < required_triggers:
                            continue
                        if selected is None or ranking > selected[0]:
                            selected = candidate
    winner = selected or fallback
    if winner is None:
        raise RuntimeError("No probability gate candidate was generated")
    metrics = dict(winner[2])
    metrics["minimum_required_triggers"] = required_triggers
    metrics["minimum_trigger_requirement_met"] = (
        metrics["triggered_events"] >= required_triggers
    )
    return winner[1], metrics


def row_classification(
    target: np.ndarray, probability: np.ndarray, row_mask: np.ndarray
) -> dict[str, Any]:
    y = target[row_mask]
    p = probability[row_mask]
    return {
        "rows": len(y),
        "positive_rate": float(y.mean()),
        "roc_auc": float(roc_auc_score(y, p)),
        "average_precision": float(average_precision_score(y, p)),
    }


def top_features(model: Pipeline, names: list[str], limit: int = 15) -> list[dict[str, Any]]:
    estimator = model.named_steps["model"]
    if hasattr(estimator, "feature_importances_"):
        values = np.asarray(estimator.feature_importances_, dtype=float)
    elif hasattr(estimator, "coef_"):
        values = np.abs(np.asarray(estimator.coef_[0], dtype=float))
    else:
        return []
    order = np.argsort(values)[::-1][:limit]
    return [
        {"feature": names[index], "importance": float(values[index])}
        for index in order
    ]


def evaluate_model_oof(
    name: str,
    data: ExitPathData,
    features: pd.DataFrame,
    target: np.ndarray,
    folds: list[tuple[np.ndarray, np.ndarray]],
    random_state: int,
    minimum_triggered_events: int,
    minimum_trigger_coverage: float,
) -> dict[str, Any]:
    probability = np.full(len(data.frame), np.nan, dtype=float)
    oof_events = np.zeros(len(data.event_frame), dtype=bool)
    fold_classification: list[dict[str, Any]] = []
    for training_events, validation_events in folds:
        training_rows = training_events[data.event_code]
        validation_rows = validation_events[data.event_code]
        model = fit_model(
            make_models(random_state)[name],
            features,
            target,
            data,
            training_rows,
        )
        probability[validation_rows] = model.predict_proba(
            features.loc[validation_rows]
        )[:, 1]
        oof_events |= validation_events
        fold_classification.append(
            row_classification(target, probability, validation_rows)
        )
    oof_rows = oof_events[data.event_code]
    gate, policy = select_gate(
        data,
        probability,
        oof_events,
        minimum_triggered_events,
        minimum_trigger_coverage,
    )
    return {
        "model": name,
        "probability": probability,
        "oof_event_mask": oof_events,
        "oof_classification": row_classification(target, probability, oof_rows),
        "fold_classification": fold_classification,
        "selected_gate": gate,
        "oof_policy": policy,
    }


def select_model(candidates: list[dict[str, Any]]) -> dict[str, Any]:
    def ranking(candidate: dict[str, Any]) -> tuple[float, ...]:
        policy = candidate["oof_policy"]
        return (
            float(policy["average_improvement_vs_baseline_step"]),
            float(policy["average_net_step"]),
            float(candidate["oof_classification"]["roc_auc"]),
        )

    return max(candidates, key=ranking)


def main() -> int:
    args = parse_args()
    csv_path = args.csv.resolve()
    data = load_exit_path(csv_path)
    names = model_columns(data)
    features = (
        data.frame[names].replace(-999.0, np.nan).astype(np.float32)
    )
    target = (
        data.frame["label_action_advantage_vs_baseline_step"].to_numpy(dtype=float)
        >= TARGET_ADVANTAGE_STEP
    ).astype(np.int8)
    specs = rolling_specs(
        data.event_frame,
        args.window_days,
        args.minimum_training_events,
        args.minimum_validation_events,
        args.max_windows,
    )
    windows: list[dict[str, Any]] = []
    pooled_outcomes: list[np.ndarray] = []
    pooled_triggered: list[np.ndarray] = []
    pooled_indices: list[np.ndarray] = []

    for number, spec in enumerate(specs, start=1):
        training_mask = spec["training_mask"]
        validation_mask = spec["validation_mask"]
        folds, fold_audit = inner_folds(data, training_mask)
        candidates = [
            evaluate_model_oof(
                name,
                data,
                features,
                target,
                folds,
                args.random_state,
                args.minimum_triggered_events,
                args.minimum_trigger_coverage,
            )
            for name in make_models(args.random_state)
        ]
        selected = select_model(candidates)
        selected_name = selected["model"]
        gate = selected["selected_gate"]
        training_rows = training_mask[data.event_code]
        validation_rows = validation_mask[data.event_code]
        model = fit_model(
            make_models(args.random_state)[selected_name],
            features,
            target,
            data,
            training_rows,
        )
        probability = np.full(len(data.frame), np.nan, dtype=float)
        probability[validation_rows] = model.predict_proba(
            features.loc[validation_rows]
        )[:, 1]
        outcome, triggered, _ = apply_probability_policy(
            data, probability, gate
        )
        validation_policy = policy_metrics(
            data, outcome, triggered, validation_mask
        )
        candidate_summary = []
        for candidate in candidates:
            candidate_summary.append(
                {
                    key: value
                    for key, value in candidate.items()
                    if key not in {"probability", "oof_event_mask"}
                }
            )
            candidate_summary[-1]["selected_gate"] = asdict(
                candidate["selected_gate"]
            )
        windows.append(
            {
                "window": number,
                "window_audit": {
                    key: value
                    for key, value in spec.items()
                    if key not in {"training_mask", "validation_mask"}
                }
                | {
                    "training_events": int(training_mask.sum()),
                    "validation_events": int(validation_mask.sum()),
                    "baseline_training": baseline_metrics(data, training_mask),
                    "baseline_validation": baseline_metrics(data, validation_mask),
                },
                "inner_folds": fold_audit,
                "candidate_selection": candidate_summary,
                "selected_model": selected_name,
                "selected_gate": asdict(gate),
                "validation_row_classification": row_classification(
                    target, probability, validation_rows
                ),
                "validation_policy": validation_policy,
                "validation_by_direction": metrics_by_group(
                    data, outcome, triggered, validation_mask, "meta_direction"
                ),
                "validation_by_baseline_exit_reason": metrics_by_group(
                    data,
                    outcome,
                    triggered,
                    validation_mask,
                    "meta_baseline_exit_reason",
                ),
                "top_features": top_features(model, names),
                "validation_trigger_rows": int(triggered[validation_mask].sum()),
            }
        )
        pooled_outcomes.append(outcome[validation_mask])
        pooled_triggered.append(triggered[validation_mask])
        pooled_indices.append(np.flatnonzero(validation_mask))
        print(
            f"window={number}/{len(specs)} model={selected_name} "
            f"row_auc={windows[-1]['validation_row_classification']['roc_auc']:.4f} "
            f"triggered={validation_policy['triggered_events']} "
            f"improvement={validation_policy['average_improvement_vs_baseline_step']:.6f}",
            flush=True,
        )

    event_indices = np.concatenate(pooled_indices)
    outcome = np.concatenate(pooled_outcomes)
    triggered = np.concatenate(pooled_triggered)
    temporary = ExitPathData(
        frame=data.frame,
        event_frame=data.event_frame.iloc[event_indices].reset_index(drop=True),
        event_code=np.array([], dtype=int),
        starts=np.array([], dtype=int),
        ends=np.array([], dtype=int),
        action_step=np.array([], dtype=float),
        current_net_step=np.array([], dtype=float),
        running_mfe=np.array([], dtype=float),
        giveback=np.array([], dtype=float),
        hold_bars=np.array([], dtype=int),
        direction=np.array([], dtype=int),
        baseline_step=data.baseline_step[event_indices],
        oracle_step=data.oracle_step[event_indices],
    )
    pooled_policy = policy_metrics(
        temporary,
        outcome,
        triggered,
        np.ones(len(outcome), dtype=bool),
    )
    pooled_mask = np.zeros(len(data.event_frame), dtype=bool)
    pooled_mask[event_indices] = True
    improvements = [
        window["validation_policy"]["average_improvement_vs_baseline_step"]
        for window in windows
    ]
    report = {
        "protocol": "event_grouped_exit_policy_nested_90d_train_90d_validation",
        "research_only": True,
        "approved_for_mt5": False,
        "approved_for_live_trading": False,
        "target": {
            "definition": (
                "label_action_advantage_vs_baseline_step >= "
                f"{TARGET_ADVANTAGE_STEP:.2f}"
            ),
            "positive_rows": int(target.sum()),
            "positive_rate": float(target.mean()),
        },
        "leakage_control": {
            "feature_prefix_required": "feature_*",
            "explicit_safe_context": ["meta_direction"],
            "excluded_future_execution_columns": [
                "label_action_exit_price",
                "label_action_exit_step",
                "label_action_execution_spread_step",
            ],
            "row_weighting": "Each event has equal total training weight.",
            "split_unit": "Complete event grouped by signal/entry/kind/direction.",
            "execution": "First qualifying decision executes at the next open.",
        },
        "dataset": {
            "path": str(csv_path),
            "sha256": sha256_file(csv_path),
            "rows": len(data.frame),
            "events": len(data.event_frame),
            "first_signal": data.event_frame["meta_signal_time"].min(),
            "last_signal": data.event_frame["meta_signal_time"].max(),
            "model_columns": names,
            "model_feature_count": len(names),
        },
        "window_days": args.window_days,
        "window_count": len(windows),
        "positive_validation_windows": sum(value > 0.0 for value in improvements),
        "validation_improvement_by_window": improvements,
        "pooled_baseline_validation": baseline_metrics(data, pooled_mask),
        "pooled_policy_validation": pooled_policy,
        "windows": windows,
        "conclusion": (
            "This is a retrospective exit-policy diagnostic. No model file is "
            "exported and no result automatically authorizes MT5 execution."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(clean_json(report), indent=2, ensure_ascii=False, allow_nan=False)
        + "\n",
        encoding="utf-8",
    )
    print("EXIT_POLICY_MODEL=COMPLETE")
    print(f"windows={len(windows)}")
    print(
        f"positive_validation_windows={sum(value > 0.0 for value in improvements)}/{len(improvements)}"
    )
    print(
        "pooled_average_improvement_step="
        f"{pooled_policy['average_improvement_vs_baseline_step']}"
    )
    print(f"pooled_profit_factor={pooled_policy['profit_factor']}")
    print("approved_for_mt5=false")
    print(f"report={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
