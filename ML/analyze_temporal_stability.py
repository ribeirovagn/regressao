#!/usr/bin/env python3
"""Audit feature drift and directional stability across chronological splits."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score

from train_breakout_model import (
    DEFAULT_CSV,
    MISSING_SENTINEL,
    PROJECT_ROOT,
    chronological_purged_split,
    clean_json,
    load_dataset,
    sha256_file,
)


DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "ML" / "artifacts" / "stability"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--train-fraction", type=float, default=0.60)
    parser.add_argument("--validation-fraction", type=float, default=0.20)
    parser.add_argument("--psi-bins", type=int, default=10)
    return parser.parse_args()


def population_stability_index(reference: np.ndarray, current: np.ndarray, bins: int) -> float:
    reference = np.asarray(reference, dtype=float)
    current = np.asarray(current, dtype=float)
    reference_median = float(np.nanmedian(reference))
    reference = np.nan_to_num(reference, nan=reference_median)
    current = np.nan_to_num(current, nan=reference_median)

    edges = np.unique(np.quantile(reference, np.linspace(0.0, 1.0, bins + 1)))
    if len(edges) < 3:
        return 0.0
    edges[0] = -np.inf
    edges[-1] = np.inf
    expected = np.histogram(reference, bins=edges)[0] / len(reference)
    actual = np.histogram(current, bins=edges)[0] / len(current)
    expected = np.clip(expected, 1e-6, None)
    actual = np.clip(actual, 1e-6, None)
    return float(np.sum((actual - expected) * np.log(actual / expected)))


def univariate_auc(values: np.ndarray, target: np.ndarray) -> float:
    if np.unique(values).size < 2:
        return 0.5
    return float(roc_auc_score(target, values))


def feature_rows(
    frame: pd.DataFrame,
    feature_names: list[str],
    indices: dict[str, np.ndarray],
    psi_bins: int,
) -> pd.DataFrame:
    features = frame[feature_names].replace(MISSING_SENTINEL, np.nan)
    target = frame["label_success"].to_numpy(dtype=np.int64)
    rows: list[dict[str, Any]] = []

    for feature_name in feature_names:
        train_values = features.iloc[indices["train"]][feature_name]
        train_median = float(train_values.median())
        values = {
            split: features.iloc[index][feature_name].fillna(train_median).to_numpy(dtype=float)
            for split, index in indices.items()
        }
        auc = {
            split: univariate_auc(values[split], target[index])
            for split, index in indices.items()
        }
        signs = {split: int(np.sign(value - 0.5)) for split, value in auc.items()}
        direction_stable = (
            signs["train"] != 0
            and signs["train"] == signs["validation"]
            and signs["validation"] == signs["test"]
        )
        psi_validation = population_stability_index(values["train"], values["validation"], psi_bins)
        psi_test = population_stability_index(values["train"], values["test"], psi_bins)

        rows.append(
            {
                "feature": feature_name,
                "psi_validation": psi_validation,
                "psi_test": psi_test,
                "max_psi": max(psi_validation, psi_test),
                "auc_train": auc["train"],
                "auc_validation": auc["validation"],
                "auc_test": auc["test"],
                "direction_train": signs["train"],
                "direction_validation": signs["validation"],
                "direction_test": signs["test"],
                "direction_stable": direction_stable,
                "train_test_direction_flip": signs["train"] != signs["test"],
                "minimum_absolute_auc_edge": min(abs(value - 0.5) for value in auc.values()),
                "missing_rate_train": float(train_values.isna().mean()),
                "missing_rate_validation": float(
                    features.iloc[indices["validation"]][feature_name].isna().mean()
                ),
                "missing_rate_test": float(features.iloc[indices["test"]][feature_name].isna().mean()),
            }
        )
    return pd.DataFrame(rows).sort_values("max_psi", ascending=False).reset_index(drop=True)


def save_psi_plot(stability: pd.DataFrame, output_path: Path) -> None:
    top = stability.nlargest(20, "max_psi").sort_values("max_psi")
    figure, axis = plt.subplots(figsize=(11, 8))
    axis.barh(top["feature"], top["max_psi"], color="#2f80ed")
    axis.axvline(0.10, color="#f2c94c", linestyle="--", label="PSI 0.10")
    axis.axvline(0.25, color="#eb5757", linestyle="--", label="PSI 0.25")
    axis.set_xlabel("Maximum PSI versus train")
    axis.set_title("Top temporal feature drift")
    axis.legend(loc="lower right")
    figure.tight_layout()
    figure.savefig(output_path, dpi=150)
    plt.close(figure)


def records(frame: pd.DataFrame, count: int = 15) -> list[dict[str, Any]]:
    return frame.head(count).to_dict(orient="records")


def main() -> int:
    args = parse_args()
    if args.psi_bins < 3:
        raise ValueError("psi_bins must be >= 3")

    frame, feature_names = load_dataset(args.csv.resolve())
    indices, split_audit = chronological_purged_split(
        frame,
        args.train_fraction,
        args.validation_fraction,
    )
    stability = feature_rows(frame, feature_names, indices, args.psi_bins)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    csv_path = args.output_dir / "feature_stability.csv"
    report_path = args.output_dir / "stability_report.json"
    plot_path = args.output_dir / "feature_psi.png"
    stability.to_csv(csv_path, index=False)
    save_psi_plot(stability, plot_path)

    stable = stability[stability["direction_stable"]]
    strong_stable = stable[stable["minimum_absolute_auc_edge"] >= 0.02]
    flips = stability[stability["train_test_direction_flip"]].sort_values(
        "auc_test", key=lambda values: (values - 0.5).abs(), ascending=False
    )
    report = {
        "research_only": True,
        "must_not_be_used_for_current_test_tuning": True,
        "dataset": {
            "path": str(args.csv.resolve()),
            "sha256": sha256_file(args.csv.resolve()),
            "rows": len(frame),
            "feature_count": len(feature_names),
        },
        "split": split_audit,
        "label_positive_rates": {
            split: float(frame.iloc[index]["label_success"].mean())
            for split, index in indices.items()
        },
        "summary": {
            "psi_above_0_10": int((stability["max_psi"] > 0.10).sum()),
            "psi_above_0_25": int((stability["max_psi"] > 0.25).sum()),
            "direction_stable_features": len(stable),
            "direction_stable_with_minimum_auc_edge_0_02": len(strong_stable),
            "train_test_direction_flips": int(stability["train_test_direction_flip"].sum()),
        },
        "top_drift": records(stability),
        "top_stable_direction": records(
            stable.sort_values("minimum_absolute_auc_edge", ascending=False)
        ),
        "top_train_test_direction_flips": records(flips),
        "interpretation": (
            "Drift and direction flips are diagnostics only. Because the final test labels have now "
            "been observed, they cannot be used to approve a redesigned model; approval requires "
            "the frozen prospective holdout."
        ),
    }
    report_path.write_text(
        json.dumps(clean_json(report), indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )

    print("TEMPORAL_STABILITY=PASS")
    print(f"features={len(feature_names)}")
    print(f"psi_above_0_10={report['summary']['psi_above_0_10']}")
    print(f"psi_above_0_25={report['summary']['psi_above_0_25']}")
    print(f"train_test_direction_flips={report['summary']['train_test_direction_flips']}")
    print(
        "stable_with_minimum_auc_edge_0_02="
        f"{report['summary']['direction_stable_with_minimum_auc_edge_0_02']}"
    )
    print(f"report={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
