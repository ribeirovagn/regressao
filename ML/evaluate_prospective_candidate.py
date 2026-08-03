#!/usr/bin/env python3
"""Perform the frozen candidate's one-time prospective evaluation.

The readiness audit reads metadata only. Future label values are loaded only
after the frozen event-count, elapsed-time, schema, and artifact gates pass.
No threshold selection, fitting, or model mutation is allowed here.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np
import onnxruntime as ort
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    brier_score_loss,
    log_loss,
    roc_auc_score,
)

from check_prospective_holdout import DEFAULT_MANIFEST, audit_prospective_status
from train_breakout_model import (
    DEFAULT_CSV,
    MISSING_SENTINEL,
    PROJECT_ROOT,
    clean_json,
    economic_metrics,
    sha256_file,
)


DEFAULT_RECEIPT = PROJECT_ROOT / "ML" / "prospective_evaluation_receipt.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--receipt", type=Path, default=DEFAULT_RECEIPT)
    return parser.parse_args()


def classification_metrics(
    y_true: np.ndarray, probability: np.ndarray
) -> dict[str, Any]:
    predicted = (probability >= 0.50).astype(np.int64)
    has_both_classes = len(np.unique(y_true)) == 2
    return {
        "rows": len(y_true),
        "positive_rate": float(np.mean(y_true)),
        "accuracy_at_050": float(accuracy_score(y_true, predicted)),
        "balanced_accuracy_at_050": float(balanced_accuracy_score(y_true, predicted)),
        "roc_auc": float(roc_auc_score(y_true, probability)) if has_both_classes else None,
        "average_precision": float(average_precision_score(y_true, probability)),
        "log_loss": float(log_loss(y_true, probability, labels=[0, 1])),
        "brier_score": float(brier_score_loss(y_true, probability)),
    }


def prospective_checks(
    classification: dict[str, Any],
    economics: dict[str, Any],
    gate: dict[str, Any],
) -> dict[str, bool]:
    roc_auc = classification["roc_auc"]
    return {
        "roc_auc": roc_auc is not None and roc_auc >= float(gate["minimum_roc_auc"]),
        "selected_events": economics["selected"] >= int(gate["minimum_selected_events"]),
        "coverage": economics["coverage"] >= float(gate["minimum_coverage"]),
        "precision": economics["precision"] is not None
        and economics["precision"] >= float(gate["minimum_precision"]),
        "profit_factor": economics["profit_factor"] is not None
        and economics["profit_factor"] >= float(gate["minimum_profit_factor"]),
        "average_net_step_return": economics["average_net_step_return"] is not None
        and economics["average_net_step_return"]
        > float(gate["minimum_average_net_step_return_exclusive"]),
    }


def main() -> int:
    args = parse_args()
    receipt_path = args.receipt.resolve()
    if receipt_path.exists():
        print("PROSPECTIVE_EVALUATION=REFUSED")
        print("reason=one_time_receipt_already_exists")
        print("labels_read=false")
        return 4

    status = audit_prospective_status(args.csv, args.manifest)
    if status["status"] != "ready_for_one_time_evaluation":
        print("PROSPECTIVE_EVALUATION=BLOCKED")
        print(f"new_events={status['new_events']}/{status['minimum_new_events']}")
        print(
            "calendar_days_after_cutoff="
            f"{status['calendar_days_after_cutoff']:.2f}/"
            f"{status['minimum_calendar_days_after_cutoff']:.2f}"
        )
        print(
            "candidate_artifact_gate_passed="
            f"{str(status['candidate_artifact_gate_passed']).lower()}"
        )
        print("labels_read=false")
        return 2

    holdout_manifest = json.loads(args.manifest.resolve().read_text(encoding="utf-8"))
    candidate_manifest_path = Path(holdout_manifest["candidate_manifest"])
    if not candidate_manifest_path.is_absolute():
        candidate_manifest_path = PROJECT_ROOT / candidate_manifest_path
    candidate = json.loads(candidate_manifest_path.read_text(encoding="utf-8"))
    selected_features = candidate["selection"]["feature_names"]
    required_columns = [
        "meta_signal_time",
        "label_success",
        "label_net_points",
        "label_net_step_return",
        *selected_features,
    ]

    # This is the only label read in the workflow, and it is unreachable until
    # audit_prospective_status reports every frozen readiness gate as passed.
    frame = pd.read_csv(args.csv.resolve(), usecols=required_columns)
    frame["meta_signal_time"] = pd.to_datetime(
        frame["meta_signal_time"],
        format="%Y.%m.%d %H:%M:%S",
        errors="raise",
    )
    cutoff = pd.Timestamp(holdout_manifest["cutoff_signal_time"])
    frame = frame.loc[frame["meta_signal_time"] > cutoff].reset_index(drop=True)
    if len(frame) != int(status["new_events"]):
        raise RuntimeError("Prospective row count changed during the evaluation")

    target = pd.to_numeric(frame["label_success"], errors="raise").to_numpy(dtype=np.int64)
    if not set(np.unique(target)).issubset({0, 1}):
        raise ValueError("label_success must be binary")
    frame["label_net_points"] = pd.to_numeric(frame["label_net_points"], errors="raise")
    frame["label_net_step_return"] = pd.to_numeric(
        frame["label_net_step_return"], errors="raise"
    )
    features = (
        frame[selected_features]
        .apply(pd.to_numeric, errors="raise")
        .replace(MISSING_SENTINEL, np.nan)
        .to_numpy(dtype=np.float32)
    )

    onnx_path = Path(candidate["artifacts"]["onnx"]["path"])
    if not onnx_path.is_absolute():
        onnx_path = PROJECT_ROOT / onnx_path
    schema_path = Path(candidate["artifacts"]["feature_schema"]["path"])
    if not schema_path.is_absolute():
        schema_path = PROJECT_ROOT / schema_path
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    session = ort.InferenceSession(onnx_path.read_bytes(), providers=["CPUExecutionProvider"])
    outputs = session.run(
        [schema["probability_output_name"]],
        {schema["input_name"]: features},
    )
    probability = np.asarray(outputs[0])[:, schema["positive_class_probability_column"]]
    threshold = float(candidate["selection"]["threshold"])
    classification = classification_metrics(target, probability)
    economics = economic_metrics(frame, probability, threshold)
    gate = candidate["prospective_approval_gate"]
    checks = prospective_checks(classification, economics, gate)
    passed = all(checks.values())

    receipt = {
        "receipt_version": 1,
        "status": "evaluated_once",
        "labels_read": True,
        "candidate_manifest": str(candidate_manifest_path),
        "candidate_manifest_sha256": sha256_file(candidate_manifest_path),
        "prospective_dataset_sha256": sha256_file(args.csv.resolve()),
        "prospective_rows": len(frame),
        "first_prospective_signal_time": frame["meta_signal_time"].min(),
        "last_prospective_signal_time": frame["meta_signal_time"].max(),
        "locked_threshold": threshold,
        "classification": classification,
        "economics": economics,
        "approval_gate": gate,
        "checks": checks,
        "prospective_gate_passed": passed,
        "eligible_for_demo_forward_test": passed,
        "approved_for_mt5": False,
        "approved_for_live_trading": False,
        "decision": (
            "eligible_for_demo_forward_test" if passed else "rejected_no_retuning"
        ),
        "rule": (
            "This receipt is final for the frozen candidate. Do not retune from this holdout; "
            "a rejected candidate requires a new future holdout."
        ),
    }
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    with receipt_path.open("x", encoding="utf-8") as handle:
        handle.write(
            json.dumps(clean_json(receipt), indent=2, ensure_ascii=False, allow_nan=False)
            + "\n"
        )

    print("PROSPECTIVE_EVALUATION=COMPLETE")
    print(f"decision={receipt['decision']}")
    print(f"prospective_rows={len(frame)}")
    print(f"selected={economics['selected']}")
    print(f"prospective_gate_passed={str(passed).lower()}")
    print("labels_read=true")
    print("approved_for_mt5=false")
    print(f"receipt={receipt_path}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
