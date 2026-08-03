#!/usr/bin/env python3
"""Calibrate a HUD-armed intrabar trailing stop on chronological windows.

The HUD is observed at a completed candle.  It may arm or tighten a protective
stop for the next candle; raw OHLC then determines whether that stop is hit.
When both the protected stop and the fixed target are possible in one candle,
the stop wins conservatively, matching the baseline ambiguity policy.
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

import numpy as np
import pandas as pd

from analyze_exit_hud_reversals import (
    DEFAULT_CSV,
    ExitPathData,
    baseline_metrics,
    clean_json,
    hud_votes,
    load_exit_path,
    metrics_by_group,
    policy_metrics,
    rolling_specs,
    sha256_file,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RATES_CSV = PROJECT_ROOT.parents[1] / "Files" / "xauusd_m1_rates.csv"
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "ML"
    / "artifacts"
    / "hud_armed_trailing"
    / "hud_armed_trailing_report.json"
)


@dataclass(frozen=True)
class TrailingRule:
    family: str
    arm_mfe_step: float
    trailing_distance_step: float
    locked_profit_step: float
    minimum_hold_bars: int
    minimum_giveback_step: float = 0.0
    hud_drop_threshold: float = 0.0
    hud_minimum_votes: int = 0


@dataclass(frozen=True)
class ExecutionBars:
    next_adverse_step: np.ndarray
    baseline_exit_on_execution_bar: np.ndarray
    joined_rows: int
    first_time: pd.Timestamp
    last_time: pd.Timestamp


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--rates-csv", type=Path, default=DEFAULT_RATES_CSV)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--window-days", type=int, default=90)
    parser.add_argument("--minimum-training-events", type=int, default=150)
    parser.add_argument("--minimum-validation-events", type=int, default=100)
    parser.add_argument("--minimum-triggered-events", type=int, default=30)
    parser.add_argument("--minimum-trigger-coverage", type=float, default=0.05)
    parser.add_argument("--max-windows", type=int, default=0)
    return parser.parse_args()


def load_execution_bars(data: ExitPathData, rates_csv: Path) -> ExecutionBars:
    if not rates_csv.is_file():
        raise FileNotFoundError(f"Rates dataset not found: {rates_csv}")
    rates = pd.read_csv(
        rates_csv,
        usecols=["meta_time", "open", "high", "low"],
        parse_dates=False,
    )
    rates["meta_time"] = pd.to_datetime(
        rates["meta_time"], format="%Y.%m.%d %H:%M:%S", errors="raise"
    )
    if rates["meta_time"].duplicated().any():
        raise ValueError("Rates dataset contains duplicate timestamps")
    rates = rates.set_index("meta_time")
    if not rates.index.is_unique:
        raise ValueError("Rates dataset contains duplicate timestamps")
    execution_time = data.frame["meta_execution_time"]
    missing = execution_time.loc[~execution_time.isin(rates.index)].drop_duplicates()
    if len(missing):
        raise ValueError(
            f"Rates dataset is missing {len(missing)} execution timestamps; "
            f"first missing={missing.iloc[0]}"
        )
    execution_rates = rates.loc[execution_time].reset_index(drop=True)
    direction = data.frame["meta_direction"].to_numpy(dtype=int)
    step = data.frame["feature_zone_step"].to_numpy(dtype=float)
    open_price = execution_rates["open"].to_numpy(dtype=float)
    adverse_distance = np.where(
        direction > 0,
        open_price - execution_rates["low"].to_numpy(dtype=float),
        execution_rates["high"].to_numpy(dtype=float) - open_price,
    ) / step
    next_adverse = data.action_step - adverse_distance
    final_bar = (
        execution_time.to_numpy()
        == data.frame["meta_baseline_exit_time"].to_numpy()
    )
    expected_final = np.zeros(len(data.frame), dtype=bool)
    expected_final[data.ends - 1] = True
    if not np.array_equal(final_bar, expected_final):
        raise ValueError(
            "Exactly the last decision of each event must execute on its baseline exit bar"
        )
    return ExecutionBars(
        next_adverse_step=next_adverse,
        baseline_exit_on_execution_bar=final_bar,
        joined_rows=len(execution_rates),
        first_time=rates.index.min(),
        last_time=rates.index.max(),
    )


def iter_rules(family: str) -> Iterable[TrailingRule]:
    if family == "price_trailing":
        for arm, distance, locked, hold in itertools.product(
            (0.20, 0.30, 0.40, 0.50),
            (0.15, 0.25, 0.35, 0.45),
            (-0.10, 0.00, 0.10),
            (1, 2),
        ):
            if locked >= arm:
                continue
            yield TrailingRule(family, arm, distance, locked, hold)
        return
    if family != "hud_armed_trailing":
        raise ValueError(f"Unknown trailing family: {family}")
    for arm, distance, locked, hold, giveback, drop, votes in itertools.product(
        (0.20, 0.30, 0.40),
        (0.15, 0.25, 0.35),
        (-0.10, 0.00),
        (1, 2),
        (0.05, 0.10, 0.20),
        (0.01, 0.03, 0.05),
        (2, 3, 4),
    ):
        if locked >= arm:
            continue
        yield TrailingRule(
            family,
            arm,
            distance,
            locked,
            hold,
            giveback,
            drop,
            votes,
        )


def apply_trailing_rule(
    data: ExitPathData,
    execution: ExecutionBars,
    rule: TrailingRule,
    vote_cache: dict[float, np.ndarray],
    event_mask: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    outcome = data.baseline_step.copy()
    triggered = np.zeros(len(data.event_frame), dtype=bool)
    selected_events = np.flatnonzero(event_mask)
    votes = vote_cache.get(rule.hud_drop_threshold)
    for event in selected_events:
        trailing_stop: float | None = None
        for row in range(data.starts[event], data.ends[event]):
            can_arm = (
                data.running_mfe[row] >= rule.arm_mfe_step
                and data.hold_bars[row] >= rule.minimum_hold_bars
            )
            if rule.family == "hud_armed_trailing":
                can_arm = (
                    can_arm
                    and data.giveback[row] >= rule.minimum_giveback_step
                    and votes is not None
                    and votes[row] >= rule.hud_minimum_votes
                )
            if trailing_stop is not None or can_arm:
                candidate = max(
                    rule.locked_profit_step,
                    data.running_mfe[row] - rule.trailing_distance_step,
                )
                # A newly tightened stop cannot be placed beyond the current
                # executable close.  Existing stops should already have been
                # checked on this candle by the prior decision row.
                candidate = min(candidate, data.current_net_step[row])
                trailing_stop = (
                    candidate
                    if trailing_stop is None
                    else max(trailing_stop, candidate)
                )

            if trailing_stop is not None:
                execution_open = data.action_step[row]
                if execution_open <= trailing_stop:
                    outcome[event] = execution_open
                    triggered[event] = True
                    break
                if execution.next_adverse_step[row] <= trailing_stop:
                    outcome[event] = trailing_stop
                    triggered[event] = True
                    break

            if execution.baseline_exit_on_execution_bar[row]:
                break
    return outcome, triggered


def choose_rule(
    data: ExitPathData,
    execution: ExecutionBars,
    family: str,
    training_mask: np.ndarray,
    training_subperiod_masks: list[np.ndarray],
    vote_cache: dict[float, np.ndarray],
    minimum_triggered_events: int,
    minimum_trigger_coverage: float,
) -> tuple[TrailingRule, dict[str, Any]]:
    required = max(
        minimum_triggered_events,
        int(math.ceil(training_mask.sum() * minimum_trigger_coverage)),
    )
    selected: tuple[tuple[float, ...], TrailingRule, dict[str, Any]] | None = None
    fallback: tuple[tuple[float, ...], TrailingRule, dict[str, Any]] | None = None
    for rule in iter_rules(family):
        outcome, triggered = apply_trailing_rule(
            data, execution, rule, vote_cache, training_mask
        )
        metrics = policy_metrics(data, outcome, triggered, training_mask)
        subperiod_metrics = [
            policy_metrics(data, outcome, triggered, mask)
            for mask in training_subperiod_masks
        ]
        subperiod_improvement = [
            float(item["average_improvement_vs_baseline_step"])
            for item in subperiod_metrics
        ]
        minimum_subperiod_triggers = [
            max(10, int(math.ceil(mask.sum() * 0.03)))
            for mask in training_subperiod_masks
        ]
        profit_factor = metrics["profit_factor"] or -math.inf
        ranking = (
            min(subperiod_improvement),
            float(np.mean(subperiod_improvement)),
            float(metrics["average_improvement_vs_baseline_step"]),
            float(metrics["average_net_step"]),
            float(profit_factor),
            -float(metrics["maximum_drawdown_step"]),
        )
        metrics = {
            **metrics,
            "selection_protocol": "maximize minimum improvement across three chronological training subperiods",
            "training_subperiod_metrics": subperiod_metrics,
            "minimum_subperiod_required_triggers": minimum_subperiod_triggers,
        }
        candidate = (ranking, rule, metrics)
        if fallback is None or ranking > fallback[0]:
            fallback = candidate
        if metrics["triggered_events"] < required or any(
            item["triggered_events"] < minimum
            for item, minimum in zip(
                subperiod_metrics, minimum_subperiod_triggers
            )
        ):
            continue
        if selected is None or ranking > selected[0]:
            selected = candidate
    winner = selected or fallback
    if winner is None:
        raise RuntimeError(f"No trailing candidates generated for {family}")
    metrics = dict(winner[2])
    metrics["minimum_required_triggers"] = required
    metrics["minimum_trigger_requirement_met"] = (
        metrics["triggered_events"] >= required
    )
    return winner[1], metrics


def chronological_subperiod_masks(
    training_mask: np.ndarray, count: int = 3
) -> list[np.ndarray]:
    indices = np.flatnonzero(training_mask)
    if len(indices) < count * 30:
        raise ValueError("Training window is too small for stability subperiods")
    masks: list[np.ndarray] = []
    for split in np.array_split(indices, count):
        mask = np.zeros(len(training_mask), dtype=bool)
        mask[split] = True
        masks.append(mask)
    return masks


def main() -> int:
    args = parse_args()
    csv_path = args.csv.resolve()
    rates_path = args.rates_csv.resolve()
    data = load_exit_path(csv_path)
    execution = load_execution_bars(data, rates_path)
    vote_cache = {
        threshold: hud_votes(data.frame, threshold)
        for threshold in (0.01, 0.03, 0.05)
    }
    specs = rolling_specs(
        data.event_frame,
        args.window_days,
        args.minimum_training_events,
        args.minimum_validation_events,
        args.max_windows,
    )
    families = ("price_trailing", "hud_armed_trailing")
    windows: list[dict[str, Any]] = []
    pooled: dict[str, dict[str, list[np.ndarray]]] = {
        family: {"outcome": [], "triggered": [], "indices": []}
        for family in families
    }
    for number, spec in enumerate(specs, start=1):
        training_mask = spec["training_mask"]
        validation_mask = spec["validation_mask"]
        subperiod_masks = chronological_subperiod_masks(training_mask)
        results: dict[str, Any] = {}
        for family in families:
            rule, training_metrics = choose_rule(
                data,
                execution,
                family,
                training_mask,
                subperiod_masks,
                vote_cache,
                args.minimum_triggered_events,
                args.minimum_trigger_coverage,
            )
            outcome, triggered = apply_trailing_rule(
                data, execution, rule, vote_cache, validation_mask
            )
            results[family] = {
                "selected_rule": asdict(rule),
                "training_metrics": training_metrics,
                "validation_metrics": policy_metrics(
                    data, outcome, triggered, validation_mask
                ),
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
            }
            pooled[family]["outcome"].append(outcome[validation_mask])
            pooled[family]["triggered"].append(triggered[validation_mask])
            pooled[family]["indices"].append(np.flatnonzero(validation_mask))
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
                "families": results,
            }
        )
        print(
            f"window={number}/{len(specs)} "
            f"price_improvement={results['price_trailing']['validation_metrics']['average_improvement_vs_baseline_step']:.6f} "
            f"hud_improvement={results['hud_armed_trailing']['validation_metrics']['average_improvement_vs_baseline_step']:.6f}",
            flush=True,
        )

    indices = np.concatenate(pooled["price_trailing"]["indices"])
    pooled_mask = np.zeros(len(data.event_frame), dtype=bool)
    pooled_mask[indices] = True
    pooled_results: dict[str, Any] = {}
    for family in families:
        temporary = ExitPathData(
            frame=data.frame,
            event_frame=data.event_frame.iloc[indices].reset_index(drop=True),
            event_code=np.array([], dtype=int),
            starts=np.array([], dtype=int),
            ends=np.array([], dtype=int),
            action_step=np.array([], dtype=float),
            current_net_step=np.array([], dtype=float),
            running_mfe=np.array([], dtype=float),
            giveback=np.array([], dtype=float),
            hold_bars=np.array([], dtype=int),
            direction=np.array([], dtype=int),
            baseline_step=data.baseline_step[indices],
            oracle_step=data.oracle_step[indices],
        )
        pooled_results[family] = policy_metrics(
            temporary,
            np.concatenate(pooled[family]["outcome"]),
            np.concatenate(pooled[family]["triggered"]),
            np.ones(len(indices), dtype=bool),
        )
    hud_improvement = [
        window["families"]["hud_armed_trailing"]["validation_metrics"][
            "average_improvement_vs_baseline_step"
        ]
        for window in windows
    ]
    report = {
        "protocol": "hud_armed_intrabar_trailing_nested_90d_train_90d_validation",
        "research_only": True,
        "approved_for_mt5": False,
        "approved_for_live_trading": False,
        "execution_assumptions": {
            "decision": "Completed candle HUD and path state only.",
            "activation": "Protective stop becomes active for the next candle.",
            "gap": "A gap through the stop exits at the next open.",
            "same_bar_ambiguity": "Protective stop wins over target conservatively.",
            "stop_update": "Once armed, the stop never loosens.",
            "future_ohlc_as_model_input": False,
        },
        "dataset": {
            "exit_path": str(csv_path),
            "exit_path_sha256": sha256_file(csv_path),
            "rates": str(rates_path),
            "rates_sha256": sha256_file(rates_path),
            "decision_rows": len(data.frame),
            "events": len(data.event_frame),
            "rates_rows": execution.joined_rows,
            "rates_first_time": execution.first_time,
            "rates_last_time": execution.last_time,
        },
        "window_days": args.window_days,
        "window_count": len(windows),
        "pooled_baseline_validation": baseline_metrics(data, pooled_mask),
        "pooled_family_validation": pooled_results,
        "hud_positive_validation_windows": sum(value > 0.0 for value in hud_improvement),
        "hud_validation_improvement_by_window": hud_improvement,
        "windows": windows,
        "conclusion": (
            "The trailing mechanism is historical research only. No stop rule is "
            "connected to MT5 without consistent unseen-window improvement and a demo test."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(clean_json(report), indent=2, ensure_ascii=False, allow_nan=False)
        + "\n",
        encoding="utf-8",
    )
    print("HUD_ARMED_TRAILING=COMPLETE")
    print(f"windows={len(windows)}")
    print(
        f"hud_positive_validation_windows={sum(value > 0.0 for value in hud_improvement)}/{len(hud_improvement)}"
    )
    print(
        "pooled_hud_average_improvement_step="
        f"{pooled_results['hud_armed_trailing']['average_improvement_vs_baseline_step']}"
    )
    print(
        f"pooled_hud_profit_factor={pooled_results['hud_armed_trailing']['profit_factor']}"
    )
    print("approved_for_mt5=false")
    print(f"report={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
