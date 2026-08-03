#!/usr/bin/env python3
"""Run nested 90-day train/90-day validation windows across history.

Each window selects its model family and threshold exclusively from expanding
folds inside that window's training period. Validation periods do not overlap.
This is retrospective stability research and never exports a trading model.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from train_breakout_model import (
    DEFAULT_CSV,
    MISSING_SENTINEL,
    PROJECT_ROOT,
    classification_metrics,
    clean_json,
    feature_importance,
    load_dataset,
    make_models,
    sha256_file,
)
from train_rolling_90d_model import (
    VALIDATION_GATE,
    evaluate_inner_candidates,
    inner_folds,
    select_inner_candidate,
    validation_checks,
)


DEFAULT_OUTPUT = (
    PROJECT_ROOT / "ML" / "artifacts" / "rolling_90d_history" / "rolling_history_report.json"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--window-days", type=int, default=90)
    parser.add_argument("--minimum-inner-coverage", type=float, default=0.15)
    parser.add_argument("--random-state", type=int, default=42)
    parser.add_argument("--max-windows", type=int, default=0)
    return parser.parse_args()


def window_specs(
    frame: pd.DataFrame, window_days: int, max_windows: int
) -> list[dict[str, Any]]:
    if window_days < 30:
        raise ValueError("window_days must be at least 30")
    first_signal = frame["meta_signal_time"].min()
    validation_end = frame["meta_signal_time"].max()
    include_end = True
    specs: list[dict[str, Any]] = []
    while True:
        validation_start = validation_end - pd.Timedelta(days=window_days)
        training_start = validation_start - pd.Timedelta(days=window_days)
        if training_start < first_signal:
            break
        specs.append(
            {
                "training_start": training_start,
                "validation_start": validation_start,
                "validation_end": validation_end,
                "validation_end_inclusive": include_end,
            }
        )
        if max_windows > 0 and len(specs) >= max_windows:
            break
        validation_end = validation_start
        include_end = False
    if len(specs) < 2:
        raise ValueError("Dataset does not contain at least two complete rolling pairs")
    return list(reversed(specs))


def extract_window(
    frame: pd.DataFrame, spec: dict[str, Any]
) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    raw_training = frame.loc[
        (frame["meta_signal_time"] >= spec["training_start"])
        & (frame["meta_signal_time"] < spec["validation_start"])
    ]
    training = raw_training.loc[
        raw_training["label_exit_time"] < spec["validation_start"]
    ].reset_index(drop=True)
    validation_end_mask = (
        frame["meta_signal_time"] <= spec["validation_end"]
        if spec["validation_end_inclusive"]
        else frame["meta_signal_time"] < spec["validation_end"]
    )
    validation = frame.loc[
        (frame["meta_signal_time"] >= spec["validation_start"])
        & validation_end_mask
    ].reset_index(drop=True)
    if min(len(training), len(validation)) < 250:
        raise ValueError("A rolling history window has fewer than 250 completed events")
    audit = {
        **spec,
        "training_rows_before_purge": len(raw_training),
        "training_rows": len(training),
        "training_rows_purged": len(raw_training) - len(training),
        "validation_rows": len(validation),
        "training_first_signal": training["meta_signal_time"].min(),
        "training_last_signal": training["meta_signal_time"].max(),
        "validation_first_signal": validation["meta_signal_time"].min(),
        "validation_last_signal": validation["meta_signal_time"].max(),
    }
    return training, validation, audit


def aggregate_economics(frame: pd.DataFrame) -> dict[str, Any]:
    selected = frame.loc[frame["_selected"]].copy()
    net_points = selected["label_net_points"].to_numpy(dtype=float)
    net_step = selected["label_net_step_return"].to_numpy(dtype=float)
    gross_profit = float(net_points[net_points > 0.0].sum())
    gross_loss = float(-net_points[net_points < 0.0].sum())
    return {
        "rows": len(frame),
        "selected": len(selected),
        "coverage": len(selected) / len(frame) if len(frame) else 0.0,
        "precision": float(selected["label_success"].mean()) if len(selected) else None,
        "net_points": float(net_points.sum()) if len(selected) else 0.0,
        "average_net_points": float(net_points.mean()) if len(selected) else None,
        "net_step_return": float(net_step.sum()) if len(selected) else 0.0,
        "average_net_step_return": float(net_step.mean()) if len(selected) else None,
        "profit_factor": (
            gross_profit / gross_loss if len(selected) and gross_loss > 0.0 else None
        ),
    }


def grouped_economics(frame: pd.DataFrame, column: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for value, group in frame.groupby(column, dropna=False, sort=True):
        rows.append({"group": value, **aggregate_economics(group)})
    return rows


def all_event_baseline(frame: pd.DataFrame) -> pd.DataFrame:
    baseline = frame.copy()
    baseline["_selected"] = True
    return baseline


def summarize_top_features(windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    appearances: Counter[str] = Counter()
    ranks: defaultdict[str, list[int]] = defaultdict(list)
    importances: defaultdict[str, list[float]] = defaultdict(list)
    for window in windows:
        for rank, item in enumerate(window["top_features"], start=1):
            feature = item["feature"]
            appearances[feature] += 1
            ranks[feature].append(rank)
            importances[feature].append(item["importance"])
    summary = []
    for feature, count in appearances.items():
        summary.append(
            {
                "feature": feature,
                "top_10_appearances": count,
                "mean_rank_when_present": float(np.mean(ranks[feature])),
                "mean_importance_when_present": float(np.mean(importances[feature])),
            }
        )
    return sorted(
        summary,
        key=lambda item: (
            -item["top_10_appearances"],
            item["mean_rank_when_present"],
            item["feature"],
        ),
    )


def main() -> int:
    args = parse_args()
    csv_path = args.csv.resolve()
    frame, feature_names = load_dataset(csv_path)
    specs = window_specs(frame, args.window_days, args.max_windows)
    window_results: list[dict[str, Any]] = []
    pooled_frames: list[pd.DataFrame] = []

    for number, spec in enumerate(specs, start=1):
        training, validation, window_audit = extract_window(frame, spec)
        training_features = (
            training[feature_names].replace(MISSING_SENTINEL, np.nan).astype(np.float32)
        )
        training_target = training["label_success"].to_numpy(dtype=np.int64)
        folds, fold_audit = inner_folds(training)
        candidates = evaluate_inner_candidates(
            training,
            training_features,
            training_target,
            folds,
            args.minimum_inner_coverage,
            args.random_state,
        )
        selected_name, selected = select_inner_candidate(candidates)
        model = make_models(args.random_state)[selected_name]
        model.fit(training_features, training_target)
        validation_features = (
            validation[feature_names].replace(MISSING_SENTINEL, np.nan).astype(np.float32)
        )
        validation_target = validation["label_success"].to_numpy(dtype=np.int64)
        probability = model.predict_proba(validation_features)[:, 1]
        threshold = float(selected["threshold"])
        classification = classification_metrics(validation_target, probability)
        validation_frame = validation.copy()
        validation_frame["_probability"] = probability
        validation_frame["_threshold"] = threshold
        validation_frame["_selected"] = probability >= threshold
        validation_frame["_window"] = number
        economics = aggregate_economics(validation_frame)
        baseline_frame = all_event_baseline(validation_frame)
        baseline_economics = aggregate_economics(baseline_frame)
        checks = validation_checks(classification, economics)
        top_features = feature_importance(model, feature_names)[:10]
        pooled_frames.append(validation_frame)
        window_results.append(
            {
                "window": number,
                "window_audit": window_audit,
                "inner_folds": fold_audit,
                "selected_model": selected_name,
                "locked_threshold": threshold,
                "inner_selected_candidate": selected,
                "validation_classification": classification,
                "validation_economics": economics,
                "all_event_baseline_economics": baseline_economics,
                "validation_checks": checks,
                "validation_passed": all(checks.values()),
                "top_features": top_features,
                "by_signal_kind": grouped_economics(
                    validation_frame, "meta_signal_kind"
                ),
                "by_direction": grouped_economics(validation_frame, "meta_direction"),
                "by_slow_regime": grouped_economics(
                    validation_frame, "feature_regime_slow"
                ),
            }
        )
        print(
            f"window={number}/{len(specs)} model={selected_name} "
            f"auc={classification['roc_auc']:.4f} selected={economics['selected']} "
            f"pf={economics['profit_factor']} passed={str(all(checks.values())).lower()}",
            flush=True,
        )

    pooled = pd.concat(pooled_frames, ignore_index=True)
    pooled_baseline = all_event_baseline(pooled)
    pooled_classification = classification_metrics(
        pooled["label_success"].to_numpy(dtype=np.int64),
        pooled["_probability"].to_numpy(dtype=float),
    )
    pooled_economics = aggregate_economics(pooled)
    passed_windows = sum(result["validation_passed"] for result in window_results)
    report = {
        "protocol": "nested_non_overlapping_rolling_90d_train_90d_validation",
        "research_only": True,
        "approved_for_mt5": False,
        "approved_for_live_trading": False,
        "dataset": {
            "path": str(csv_path),
            "sha256": sha256_file(csv_path),
            "rows": len(frame),
            "first_signal": frame["meta_signal_time"].min(),
            "last_signal": frame["meta_signal_time"].max(),
            "feature_count": len(feature_names),
        },
        "window_days": args.window_days,
        "validation_gate": VALIDATION_GATE,
        "window_count": len(window_results),
        "passed_windows": passed_windows,
        "all_windows_passed": passed_windows == len(window_results),
        "selected_model_counts": dict(
            Counter(result["selected_model"] for result in window_results)
        ),
        "validation_auc_by_window": [
            result["validation_classification"]["roc_auc"]
            for result in window_results
        ],
        "validation_profit_factor_by_window": [
            result["validation_economics"]["profit_factor"]
            for result in window_results
        ],
        "pooled_classification": pooled_classification,
        "pooled_economics": pooled_economics,
        "pooled_all_event_baseline": aggregate_economics(pooled_baseline),
        "pooled_by_signal_kind": grouped_economics(pooled, "meta_signal_kind"),
        "pooled_by_direction": grouped_economics(pooled, "meta_direction"),
        "pooled_by_slow_regime": grouped_economics(pooled, "feature_regime_slow"),
        "pooled_by_exit_reason": grouped_economics(pooled, "label_exit_reason"),
        "pooled_baseline_by_signal_kind": grouped_economics(
            pooled_baseline, "meta_signal_kind"
        ),
        "pooled_baseline_by_direction": grouped_economics(
            pooled_baseline, "meta_direction"
        ),
        "pooled_baseline_by_slow_regime": grouped_economics(
            pooled_baseline, "feature_regime_slow"
        ),
        "top_feature_stability": summarize_top_features(window_results),
        "windows": window_results,
        "conclusion": (
            "No model is exported. Validation results diagnose temporal stability and must "
            "not be used as automatic MT5 approval."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(clean_json(report), indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    print("ROLLING_90D_HISTORY=COMPLETE")
    print(f"windows={len(window_results)}")
    print(f"passed_windows={passed_windows}/{len(window_results)}")
    print(f"pooled_auc={pooled_classification['roc_auc']:.6f}")
    print(f"pooled_selected={pooled_economics['selected']}")
    print(f"pooled_profit_factor={pooled_economics['profit_factor']}")
    print(
        "pooled_average_net_step_return="
        f"{pooled_economics['average_net_step_return']}"
    )
    print("approved_for_mt5=false")
    print(f"report={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
