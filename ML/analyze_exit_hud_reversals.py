#!/usr/bin/env python3
"""Map HUD changes around profit reversals and validate simple exit rules.

The input is the candle-by-candle exit-path dataset produced by
ExportXAUUSDBreakoutMLDataset.mq5.  Rules are calibrated only on an older
90-day window and evaluated on the following 90 days.  This is a research
diagnostic: it neither exports a trading model nor approves an MT5 exit.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

import numpy as np
import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CSV = PROJECT_ROOT.parents[1] / "Files" / "xauusd_breakout_exit_path.csv"
DEFAULT_OUTPUT = (
    PROJECT_ROOT / "ML" / "artifacts" / "exit_hud" / "exit_hud_report.json"
)
MISSING_SENTINEL = -999.0
EVENT_COLUMNS = [
    "meta_signal_time",
    "meta_entry_time",
    "meta_signal_kind",
    "meta_direction",
]
TIME_COLUMNS = [
    "meta_signal_time",
    "meta_entry_time",
    "meta_decision_bar_time",
    "meta_execution_time",
    "meta_baseline_exit_time",
]
REQUIRED_COLUMNS = {
    *EVENT_COLUMNS,
    *TIME_COLUMNS,
    "meta_schema_version",
    "meta_hold_bars",
    "meta_baseline_exit_reason",
    "label_action_exit_step",
    "feature_running_mfe_step",
    "feature_running_mae_step",
    "feature_giveback_from_mfe_step",
    "feature_body_directional_step",
    "feature_close_location_directional",
    "feature_bias_with_trade_fast",
    "feature_microtrend_with_trade_fast",
    "feature_volume_bias_with_trade_fast",
    "feature_bias_with_trade_slow",
    "feature_microtrend_with_trade_slow",
    "feature_volume_bias_with_trade_slow",
    "feature_strength_delta_previous_fast",
    "feature_break_quality_delta_previous_fast",
    "feature_slope_delta_previous_fast",
    "feature_volume_confirm_delta_previous_fast",
    "feature_strength_delta_previous_slow",
    "feature_break_quality_delta_previous_slow",
    "feature_slope_delta_previous_slow",
    "feature_volume_confirm_delta_previous_slow",
    "label_baseline_net_step",
    "label_baseline_mfe_step",
    "label_baseline_mae_step",
    "label_future_best_action_step",
    "label_peak_action_row",
}
PROFILE_FEATURES = [
    "feature_current_net_step",
    "label_action_exit_step",
    "feature_running_mfe_step",
    "feature_giveback_from_mfe_step",
    "feature_current_boundary_distance_step",
    "feature_body_directional_step",
    "feature_close_location_directional",
    "feature_bias_with_trade_fast",
    "feature_microtrend_with_trade_fast",
    "feature_strength_fast",
    "feature_exhaustion_fast",
    "feature_break_quality_fast",
    "feature_slope_fast",
    "feature_r2_fast",
    "feature_er_fast",
    "feature_volume_bias_with_trade_fast",
    "feature_volume_confirm_fast",
    "feature_bias_with_trade_slow",
    "feature_microtrend_with_trade_slow",
    "feature_strength_slow",
    "feature_exhaustion_slow",
    "feature_break_quality_slow",
    "feature_slope_slow",
    "feature_r2_slow",
    "feature_er_slow",
    "feature_volume_bias_with_trade_slow",
    "feature_volume_confirm_slow",
    "feature_strength_delta_previous_fast",
    "feature_exhaustion_delta_previous_fast",
    "feature_break_quality_delta_previous_fast",
    "feature_slope_delta_previous_fast",
    "feature_volume_confirm_delta_previous_fast",
    "feature_strength_delta_previous_slow",
    "feature_exhaustion_delta_previous_slow",
    "feature_break_quality_delta_previous_slow",
    "feature_slope_delta_previous_slow",
    "feature_volume_confirm_delta_previous_slow",
]


@dataclass(frozen=True)
class ExitRule:
    family: str
    arm_mfe_step: float
    giveback_step: float
    minimum_hold_bars: int
    minimum_current_net_step: float
    direction_scope: int
    hud_drop_threshold: float = 0.0
    hud_minimum_votes: int = 0


@dataclass
class ExitPathData:
    frame: pd.DataFrame
    event_frame: pd.DataFrame
    event_code: np.ndarray
    starts: np.ndarray
    ends: np.ndarray
    action_step: np.ndarray
    current_net_step: np.ndarray
    running_mfe: np.ndarray
    giveback: np.ndarray
    hold_bars: np.ndarray
    direction: np.ndarray
    baseline_step: np.ndarray
    oracle_step: np.ndarray


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
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def finite_or_none(value: Any) -> Any:
    if isinstance(value, (np.bool_, bool)):
        return bool(value)
    if isinstance(value, (np.integer, int)):
        return int(value)
    if isinstance(value, (np.floating, float)):
        numeric = float(value)
        return numeric if math.isfinite(numeric) else None
    if isinstance(value, (pd.Timestamp, np.datetime64)):
        return str(value)
    return value


def clean_json(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): clean_json(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [clean_json(item) for item in value]
    return finite_or_none(value)


def load_exit_path(csv_path: Path) -> ExitPathData:
    if not csv_path.is_file():
        raise FileNotFoundError(f"Exit-path dataset not found: {csv_path}")
    frame = pd.read_csv(csv_path)
    missing = sorted(REQUIRED_COLUMNS.difference(frame.columns))
    if missing:
        raise ValueError(f"Exit-path dataset is missing columns: {missing}")
    if frame.columns.duplicated().any():
        raise ValueError("Exit-path dataset contains duplicate column names")
    feature_names = [column for column in frame if column.startswith("feature_")]
    if not feature_names:
        raise ValueError("Exit-path dataset contains no feature_* columns")
    if any(column.startswith(("meta_", "label_")) for column in feature_names):
        raise ValueError("Leakage guard failed while selecting feature columns")

    for column in TIME_COLUMNS:
        frame[column] = pd.to_datetime(
            frame[column], format="%Y.%m.%d %H:%M:%S", errors="raise"
        )
    numeric_columns = [
        column
        for column in frame
        if column.startswith(("feature_", "label_"))
        or column in {"meta_direction", "meta_hold_bars"}
    ]
    frame[numeric_columns] = frame[numeric_columns].apply(pd.to_numeric, errors="raise")
    frame = frame.sort_values(
        [*EVENT_COLUMNS, "meta_hold_bars"], kind="stable"
    ).reset_index(drop=True)
    if not (frame["meta_execution_time"] > frame["meta_decision_bar_time"]).all():
        raise ValueError("Execution must occur strictly after the decision candle")

    event_index = pd.MultiIndex.from_frame(frame[EVENT_COLUMNS])
    event_code, unique_events = pd.factorize(event_index, sort=False)
    if np.any(event_code[1:] < event_code[:-1]):
        raise ValueError("Event rows are not contiguous after chronological sorting")
    starts = np.flatnonzero(np.r_[True, event_code[1:] != event_code[:-1]])
    ends = np.r_[starts[1:], len(frame)]
    if not np.array_equal(event_code[starts], np.arange(len(starts))):
        raise ValueError("Unexpected event coding in exit-path dataset")
    for start, end in zip(starts, ends):
        holds = frame["meta_hold_bars"].to_numpy()[start:end]
        if len(np.unique(holds)) != len(holds) or np.any(np.diff(holds) <= 0):
            raise ValueError("Hold bars must be unique and increasing inside each event")

    first = frame.iloc[starts].reset_index(drop=True)
    event_frame = first[
        [
            *EVENT_COLUMNS,
            "meta_baseline_exit_time",
            "meta_baseline_exit_reason",
            "label_baseline_net_step",
            "label_baseline_mfe_step",
            "label_baseline_mae_step",
            "label_future_best_action_step",
        ]
    ].copy()
    event_frame["event_rows"] = ends - starts
    repeated_columns = [
        "meta_baseline_exit_time",
        "meta_baseline_exit_reason",
        "label_baseline_net_step",
        "label_baseline_mfe_step",
        "label_baseline_mae_step",
    ]
    for column in repeated_columns:
        counts = frame.groupby(event_code, sort=False)[column].nunique(dropna=False)
        if not (counts == 1).all():
            raise ValueError(f"{column} changes inside an event")

    return ExitPathData(
        frame=frame,
        event_frame=event_frame,
        event_code=event_code,
        starts=starts,
        ends=ends,
        action_step=frame["label_action_exit_step"].to_numpy(dtype=float),
        current_net_step=frame["feature_current_net_step"].to_numpy(dtype=float),
        running_mfe=frame["feature_running_mfe_step"].to_numpy(dtype=float),
        giveback=frame["feature_giveback_from_mfe_step"].to_numpy(dtype=float),
        hold_bars=frame["meta_hold_bars"].to_numpy(dtype=int),
        direction=frame["meta_direction"].to_numpy(dtype=int),
        baseline_step=event_frame["label_baseline_net_step"].to_numpy(dtype=float),
        oracle_step=event_frame["label_future_best_action_step"].to_numpy(dtype=float),
    )


def valid_drop(values: np.ndarray, threshold: float) -> np.ndarray:
    return (values > MISSING_SENTINEL + 1.0) & (values <= -threshold)


def hud_votes(frame: pd.DataFrame, drop_threshold: float) -> np.ndarray:
    votes = np.zeros(len(frame), dtype=np.int16)
    for column in (
        "feature_bias_with_trade_fast",
        "feature_microtrend_with_trade_fast",
        "feature_bias_with_trade_slow",
        "feature_microtrend_with_trade_slow",
    ):
        votes += (frame[column].to_numpy(dtype=float) <= 0.0).astype(np.int16)
    for alignment, confirmation in (
        ("feature_volume_bias_with_trade_fast", "feature_volume_confirm_fast"),
        ("feature_volume_bias_with_trade_slow", "feature_volume_confirm_slow"),
    ):
        valid = frame[confirmation].to_numpy(dtype=float) > MISSING_SENTINEL + 1.0
        votes += (
            valid & (frame[alignment].to_numpy(dtype=float) <= 0.0)
        ).astype(np.int16)
    for column in (
        "feature_strength_delta_previous_fast",
        "feature_break_quality_delta_previous_fast",
        "feature_slope_delta_previous_fast",
        "feature_volume_confirm_delta_previous_fast",
        "feature_strength_delta_previous_slow",
        "feature_break_quality_delta_previous_slow",
        "feature_slope_delta_previous_slow",
        "feature_volume_confirm_delta_previous_slow",
    ):
        votes += valid_drop(frame[column].to_numpy(dtype=float), drop_threshold).astype(
            np.int16
        )
    votes += (
        frame["feature_body_directional_step"].to_numpy(dtype=float) <= -0.05
    ).astype(np.int16)
    votes += (
        frame["feature_close_location_directional"].to_numpy(dtype=float) <= 0.35
    ).astype(np.int16)
    return votes


def iter_rules(family: str) -> Iterable[ExitRule]:
    common = itertools.product(
        (0.20, 0.30, 0.40, 0.50),
        (0.10, 0.20, 0.30),
        (1, 2, 3),
        (-0.10, 0.00),
        (0, 1, -1),
    )
    if family == "giveback_only":
        for arm, giveback, hold, action, direction in common:
            yield ExitRule(family, arm, giveback, hold, action, direction)
        return
    if family != "hud_reversal":
        raise ValueError(f"Unknown rule family: {family}")
    for arm, giveback, hold, action, direction in common:
        for drop, minimum_votes in itertools.product((0.01, 0.03, 0.05), (2, 3, 4)):
            yield ExitRule(
                family,
                arm,
                giveback,
                hold,
                action,
                direction,
                drop,
                minimum_votes,
            )


def apply_rule(
    data: ExitPathData,
    rule: ExitRule,
    vote_cache: dict[float, np.ndarray],
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    eligible = (
        (data.running_mfe >= rule.arm_mfe_step)
        & (data.giveback >= rule.giveback_step)
        & (data.hold_bars >= rule.minimum_hold_bars)
        & (data.current_net_step >= rule.minimum_current_net_step)
    )
    if rule.direction_scope != 0:
        eligible &= data.direction == rule.direction_scope
    if rule.family == "hud_reversal":
        eligible &= (
            vote_cache[rule.hud_drop_threshold] >= rule.hud_minimum_votes
        )
    sentinel = len(data.frame) + 1
    candidate = np.where(eligible, np.arange(len(data.frame)), sentinel)
    first_exit_row = np.minimum.reduceat(candidate, data.starts)
    triggered = first_exit_row < data.ends
    outcome = data.baseline_step.copy()
    outcome[triggered] = data.action_step[first_exit_row[triggered]]
    return outcome, triggered, first_exit_row


def policy_metrics(
    data: ExitPathData,
    outcome: np.ndarray,
    triggered: np.ndarray,
    event_mask: np.ndarray,
) -> dict[str, Any]:
    pnl = outcome[event_mask]
    baseline = data.baseline_step[event_mask]
    oracle = data.oracle_step[event_mask]
    fired = triggered[event_mask]
    improvement = pnl - baseline
    gross_profit = float(pnl[pnl > 0.0].sum())
    gross_loss = float(-pnl[pnl < 0.0].sum())
    cumulative = np.cumsum(pnl)
    peaks = np.maximum.accumulate(np.r_[0.0, cumulative])
    drawdowns = peaks[1:] - cumulative
    triggered_improvement = improvement[fired]
    opportunity = oracle - baseline
    opportunity_mask = opportunity > 1.0e-9
    capture = np.full(len(pnl), np.nan, dtype=float)
    capture[opportunity_mask] = (
        improvement[opportunity_mask] / opportunity[opportunity_mask]
    )
    return {
        "events": len(pnl),
        "triggered_events": int(fired.sum()),
        "trigger_coverage": float(fired.mean()) if len(fired) else None,
        "total_net_step": float(pnl.sum()),
        "average_net_step": float(pnl.mean()) if len(pnl) else None,
        "median_net_step": float(np.median(pnl)) if len(pnl) else None,
        "win_rate": float((pnl > 0.0).mean()) if len(pnl) else None,
        "profit_factor": gross_profit / gross_loss if gross_loss > 0.0 else None,
        "maximum_drawdown_step": float(drawdowns.max()) if len(drawdowns) else 0.0,
        "total_improvement_vs_baseline_step": float(improvement.sum()),
        "average_improvement_vs_baseline_step": (
            float(improvement.mean()) if len(improvement) else None
        ),
        "triggered_improvement_rate": (
            float((triggered_improvement > 0.0).mean())
            if len(triggered_improvement)
            else None
        ),
        "average_triggered_improvement_step": (
            float(triggered_improvement.mean())
            if len(triggered_improvement)
            else None
        ),
        "average_regret_to_oracle_step": (
            float((oracle - pnl).mean()) if len(pnl) else None
        ),
        "average_opportunity_capture": (
            float(np.nanmean(capture)) if opportunity_mask.any() else None
        ),
    }


def baseline_metrics(data: ExitPathData, event_mask: np.ndarray) -> dict[str, Any]:
    return policy_metrics(
        data,
        data.baseline_step,
        np.zeros(len(data.baseline_step), dtype=bool),
        event_mask,
    )


def choose_rule(
    data: ExitPathData,
    family: str,
    training_mask: np.ndarray,
    vote_cache: dict[float, np.ndarray],
    minimum_triggered_events: int,
    minimum_trigger_coverage: float,
) -> tuple[ExitRule, dict[str, Any]]:
    required_triggers = max(
        minimum_triggered_events,
        int(math.ceil(training_mask.sum() * minimum_trigger_coverage)),
    )
    selected: tuple[tuple[float, ...], ExitRule, dict[str, Any]] | None = None
    fallback: tuple[tuple[float, ...], ExitRule, dict[str, Any]] | None = None
    for rule in iter_rules(family):
        outcome, triggered, _ = apply_rule(data, rule, vote_cache)
        metrics = policy_metrics(data, outcome, triggered, training_mask)
        profit_factor = metrics["profit_factor"] or -math.inf
        ranking = (
            float(metrics["average_improvement_vs_baseline_step"]),
            float(metrics["average_net_step"]),
            float(profit_factor),
            -float(metrics["maximum_drawdown_step"]),
        )
        candidate = (ranking, rule, metrics)
        if fallback is None or ranking > fallback[0]:
            fallback = candidate
        if metrics["triggered_events"] < required_triggers:
            continue
        if selected is None or ranking > selected[0]:
            selected = candidate
    winner = selected or fallback
    if winner is None:
        raise RuntimeError(f"No candidate rules generated for {family}")
    metrics = dict(winner[2])
    metrics["minimum_required_triggers"] = required_triggers
    metrics["minimum_trigger_requirement_met"] = (
        metrics["triggered_events"] >= required_triggers
    )
    return winner[1], metrics


def rolling_specs(
    event_frame: pd.DataFrame,
    window_days: int,
    minimum_training_events: int,
    minimum_validation_events: int,
    max_windows: int,
) -> list[dict[str, Any]]:
    if window_days < 30:
        raise ValueError("window_days must be at least 30")
    signal = event_frame["meta_signal_time"]
    exit_time = event_frame["meta_baseline_exit_time"]
    validation_end = signal.max()
    include_end = True
    specs: list[dict[str, Any]] = []
    while True:
        validation_start = validation_end - pd.Timedelta(days=window_days)
        training_start = validation_start - pd.Timedelta(days=window_days)
        if training_start < signal.min():
            break
        training = (
            (signal >= training_start)
            & (signal < validation_start)
            & (exit_time < validation_start)
        )
        validation_end_mask = (
            signal <= validation_end if include_end else signal < validation_end
        )
        validation = (signal >= validation_start) & validation_end_mask
        if (
            int(training.sum()) >= minimum_training_events
            and int(validation.sum()) >= minimum_validation_events
        ):
            specs.append(
                {
                    "training_start": training_start,
                    "validation_start": validation_start,
                    "validation_end": validation_end,
                    "validation_end_inclusive": include_end,
                    "training_mask": training.to_numpy(),
                    "validation_mask": validation.to_numpy(),
                }
            )
            if max_windows > 0 and len(specs) >= max_windows:
                break
        validation_end = validation_start
        include_end = False
    if not specs:
        raise ValueError("No complete train/validation window is available")
    return list(reversed(specs))


def summarize_profile_rows(rows: pd.DataFrame) -> dict[str, Any]:
    result: dict[str, Any] = {"rows": len(rows)}
    for column in PROFILE_FEATURES:
        values = rows[column].to_numpy(dtype=float)
        values = values[values > MISSING_SENTINEL + 1.0]
        result[column] = {
            "available": len(values),
            "mean": float(values.mean()) if len(values) else None,
            "median": float(np.median(values)) if len(values) else None,
        }
    return result


def reversal_profile(data: ExitPathData) -> dict[str, Any]:
    frame = data.frame.copy()
    frame["_event_code"] = data.event_code
    peak_rows = np.flatnonzero(frame["label_peak_action_row"].to_numpy(dtype=int) == 1)
    recoverable_event = (
        (data.oracle_step - data.baseline_step >= 0.10)
        & (data.oracle_step > 0.0)
        & (data.event_frame["label_baseline_mfe_step"].to_numpy(dtype=float) >= 0.20)
    )
    peak_rows = np.array(
        [row for row in peak_rows if recoverable_event[data.event_code[row]]],
        dtype=int,
    )
    offsets: dict[str, Any] = {}
    for offset in (-2, -1, 0, 1, 2):
        selected_rows = peak_rows + offset
        valid = (selected_rows >= 0) & (selected_rows < len(frame))
        selected_rows = selected_rows[valid]
        origin = peak_rows[valid]
        same_event = data.event_code[selected_rows] == data.event_code[origin]
        selected_rows = selected_rows[same_event]
        offsets[str(offset)] = summarize_profile_rows(frame.iloc[selected_rows])

    transitions: dict[str, Any] = {}
    for name, left_offset, right_offset in (
        ("previous_to_peak", -1, 0),
        ("peak_to_next", 0, 1),
    ):
        left = peak_rows + left_offset
        right = peak_rows + right_offset
        within_bounds = (left >= 0) & (right >= 0) & (left < len(frame)) & (
            right < len(frame)
        )
        left = left[within_bounds]
        right = right[within_bounds]
        same_event = data.event_code[left] == data.event_code[right]
        left = left[same_event]
        right = right[same_event]
        feature_changes: list[dict[str, Any]] = []
        for column in PROFILE_FEATURES:
            before = frame.iloc[left][column].to_numpy(dtype=float)
            after = frame.iloc[right][column].to_numpy(dtype=float)
            available = (before > MISSING_SENTINEL + 1.0) & (
                after > MISSING_SENTINEL + 1.0
            )
            delta = after[available] - before[available]
            if not len(delta):
                continue
            scale = np.median(np.abs(before[available] - np.median(before[available])))
            standardized = float(np.median(delta) / max(scale, 1.0e-6))
            feature_changes.append(
                {
                    "feature": column,
                    "pairs": len(delta),
                    "mean_delta": float(delta.mean()),
                    "median_delta": float(np.median(delta)),
                    "share_decreasing": float((delta < 0.0).mean()),
                    "robust_standardized_median_delta": standardized,
                }
            )
        transitions[name] = {
            "pairs": len(left),
            "features_by_absolute_standardized_change": sorted(
                feature_changes,
                key=lambda item: abs(item["robust_standardized_median_delta"]),
                reverse=True,
            ),
        }
    return {
        "definition": (
            "Events with baseline MFE >= 0.20 step, positive actionable peak, and "
            "at least 0.10 step of recoverable advantage over the baseline exit."
        ),
        "eligible_events": int(recoverable_event.sum()),
        "peak_rows": len(peak_rows),
        "offsets_around_peak": offsets,
        "transitions": transitions,
    }


def metrics_by_group(
    data: ExitPathData,
    outcome: np.ndarray,
    triggered: np.ndarray,
    event_mask: np.ndarray,
    column: str,
) -> list[dict[str, Any]]:
    result = []
    values = data.event_frame[column]
    for value in values[event_mask].drop_duplicates():
        group_mask = event_mask & (values.to_numpy() == value)
        result.append(
            {"group": finite_or_none(value), **policy_metrics(data, outcome, triggered, group_mask)}
        )
    return result


def main() -> int:
    args = parse_args()
    csv_path = args.csv.resolve()
    data = load_exit_path(csv_path)
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
    window_results: list[dict[str, Any]] = []
    pooled: dict[str, dict[str, list[np.ndarray]]] = {
        family: {"outcome": [], "triggered": [], "event_mask": []}
        for family in ("giveback_only", "hud_reversal")
    }
    for number, spec in enumerate(specs, start=1):
        training_mask = spec.pop("training_mask")
        validation_mask = spec.pop("validation_mask")
        family_results: dict[str, Any] = {}
        for family in ("giveback_only", "hud_reversal"):
            rule, training_metrics = choose_rule(
                data,
                family,
                training_mask,
                vote_cache,
                args.minimum_triggered_events,
                args.minimum_trigger_coverage,
            )
            outcome, triggered, first_exit_row = apply_rule(data, rule, vote_cache)
            validation_metrics = policy_metrics(
                data, outcome, triggered, validation_mask
            )
            triggered_rows = first_exit_row[validation_mask & triggered]
            family_results[family] = {
                "selected_rule": asdict(rule),
                "training_metrics": training_metrics,
                "validation_metrics": validation_metrics,
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
                "trigger_hud_votes": {
                    "mean": (
                        float(
                            vote_cache.get(
                                rule.hud_drop_threshold,
                                np.zeros(len(data.frame), dtype=float),
                            )[triggered_rows].mean()
                        )
                        if len(triggered_rows)
                        else None
                    ),
                    "rows": len(triggered_rows),
                },
            }
            pooled[family]["outcome"].append(outcome[validation_mask])
            pooled[family]["triggered"].append(triggered[validation_mask])
            pooled[family]["event_mask"].append(np.flatnonzero(validation_mask))
        window_results.append(
            {
                "window": number,
                "window_audit": {
                    **spec,
                    "training_events": int(training_mask.sum()),
                    "validation_events": int(validation_mask.sum()),
                    "baseline_training": baseline_metrics(data, training_mask),
                    "baseline_validation": baseline_metrics(data, validation_mask),
                },
                "families": family_results,
            }
        )
        print(
            f"window={number}/{len(specs)} "
            f"giveback_improvement={family_results['giveback_only']['validation_metrics']['average_improvement_vs_baseline_step']:.6f} "
            f"hud_improvement={family_results['hud_reversal']['validation_metrics']['average_improvement_vs_baseline_step']:.6f}",
            flush=True,
        )

    pooled_results: dict[str, Any] = {}
    pooled_indices = np.concatenate(pooled["giveback_only"]["event_mask"])
    pooled_mask = np.zeros(len(data.event_frame), dtype=bool)
    pooled_mask[pooled_indices] = True
    pooled_baseline = baseline_metrics(data, pooled_mask)
    for family in ("giveback_only", "hud_reversal"):
        outcome = np.concatenate(pooled[family]["outcome"])
        triggered = np.concatenate(pooled[family]["triggered"])
        baseline = data.baseline_step[pooled_indices]
        oracle = data.oracle_step[pooled_indices]
        temporary_data = ExitPathData(
            frame=data.frame,
            event_frame=data.event_frame.iloc[pooled_indices].reset_index(drop=True),
            event_code=np.array([], dtype=int),
            starts=np.array([], dtype=int),
            ends=np.array([], dtype=int),
            action_step=np.array([], dtype=float),
            current_net_step=np.array([], dtype=float),
            running_mfe=np.array([], dtype=float),
            giveback=np.array([], dtype=float),
            hold_bars=np.array([], dtype=int),
            direction=np.array([], dtype=int),
            baseline_step=baseline,
            oracle_step=oracle,
        )
        pooled_results[family] = policy_metrics(
            temporary_data,
            outcome,
            triggered,
            np.ones(len(outcome), dtype=bool),
        )

    hud_improvements = [
        window["families"]["hud_reversal"]["validation_metrics"][
            "average_improvement_vs_baseline_step"
        ]
        for window in window_results
    ]
    report = {
        "protocol": "exit_path_hud_reversal_nested_90d_train_90d_validation",
        "research_only": True,
        "approved_for_mt5": False,
        "approved_for_live_trading": False,
        "leakage_control": {
            "decision": "feature_* values at a completed candle",
            "execution": "next candle open including historical costs",
            "calibration": "older 90-day window only",
            "validation": "following non-overlapping 90-day window",
            "future_oracle_columns_used_by_rule": [],
        },
        "dataset": {
            "path": str(csv_path),
            "sha256": sha256_file(csv_path),
            "rows": len(data.frame),
            "events_with_actionable_rows": len(data.event_frame),
            "first_signal": data.event_frame["meta_signal_time"].min(),
            "last_signal": data.event_frame["meta_signal_time"].max(),
            "columns": len(data.frame.columns),
            "feature_columns": sum(column.startswith("feature_") for column in data.frame),
        },
        "hud_vote_definition": {
            "not_aligned": (
                "Fast/slow bias, microtrend and valid volume bias that are neutral or "
                "opposed to the trade."
            ),
            "deteriorating": (
                "Fast/slow strength, break quality, slope and volume-confirmation "
                "one-candle deltas at or below the calibrated negative threshold."
            ),
            "price_confirmation": (
                "Directional candle body <= -0.05 step and directional close location <= 0.35."
            ),
        },
        "reversal_profile": reversal_profile(data),
        "window_days": args.window_days,
        "window_count": len(window_results),
        "pooled_baseline_validation": pooled_baseline,
        "pooled_family_validation": pooled_results,
        "hud_positive_validation_windows": sum(value > 0.0 for value in hud_improvements),
        "hud_validation_improvement_by_window": hud_improvements,
        "windows": window_results,
        "conclusion": (
            "The report maps HUD behavior and tests chronological exit rules. "
            "No rule is connected to MT5 until it improves unseen windows consistently "
            "and is then confirmed in a demo forward test."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(clean_json(report), indent=2, ensure_ascii=False, allow_nan=False)
        + "\n",
        encoding="utf-8",
    )
    print("EXIT_HUD_ANALYSIS=COMPLETE")
    print(f"rows={len(data.frame)}")
    print(f"events={len(data.event_frame)}")
    print(f"windows={len(window_results)}")
    print(f"hud_positive_validation_windows={sum(value > 0.0 for value in hud_improvements)}/{len(hud_improvements)}")
    print(
        "pooled_hud_average_improvement_step="
        f"{pooled_results['hud_reversal']['average_improvement_vs_baseline_step']}"
    )
    print("approved_for_mt5=false")
    print(f"report={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
