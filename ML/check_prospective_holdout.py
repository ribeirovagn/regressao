#!/usr/bin/env python3
"""Check future holdout accumulation without reading any future label value."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import pandas as pd

from train_breakout_model import DEFAULT_CSV, PROJECT_ROOT, clean_json, sha256_file


DEFAULT_MANIFEST = PROJECT_ROOT / "ML" / "prospective_holdout_manifest.json"
DEFAULT_OUTPUT = PROJECT_ROOT / "ML" / "artifacts" / "prospective_holdout_status.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def audit_prospective_status(csv_path: Path, manifest_path: Path) -> dict:
    """Audit readiness using metadata only; never load any label_* value."""
    csv_path = csv_path.resolve()
    manifest_path = manifest_path.resolve()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    candidate_manifest_path = Path(manifest["candidate_manifest"])
    if not candidate_manifest_path.is_absolute():
        candidate_manifest_path = PROJECT_ROOT / candidate_manifest_path
    candidate_manifest_sha256 = sha256_file(candidate_manifest_path)
    candidate = json.loads(candidate_manifest_path.read_text(encoding="utf-8"))

    candidate_bindings_ok = (
        candidate_manifest_sha256 == manifest["candidate_manifest_sha256"]
        and candidate["status"] == manifest["candidate_status"]
        and candidate["approved_for_mt5"] is False
        and candidate["future_labels_read"] is False
        and candidate["development_dataset"]["sha256"] == manifest["frozen_dataset_sha256"]
        and candidate["development_dataset"]["cutoff_signal_time"]
        == manifest["cutoff_signal_time"]
        and int(candidate["prospective_gate"]["minimum_new_events"])
        == int(manifest["minimum_new_events"])
        and float(candidate["prospective_gate"]["minimum_calendar_days_after_cutoff"])
        == float(manifest["minimum_calendar_days_after_cutoff"])
    )
    locked_files = {
        "training_script": candidate["training_script"],
        "evaluation_script": candidate["evaluation_script"],
        **candidate["artifacts"],
    }
    locked_file_audit = {}
    for name, locked in locked_files.items():
        path = Path(locked["path"])
        if not path.is_absolute():
            path = PROJECT_ROOT / path
        actual_sha256 = sha256_file(path) if path.is_file() else None
        locked_file_audit[name] = {
            "path": str(path),
            "expected_sha256": locked["sha256"],
            "actual_sha256": actual_sha256,
            "passed": actual_sha256 == locked["sha256"],
        }
    candidate_artifact_gate = candidate_bindings_ok and all(
        audit["passed"] for audit in locked_file_audit.values()
    )

    header = pd.read_csv(csv_path, nrows=0).columns.tolist()
    feature_names = [column for column in header if column.startswith("feature_")]
    feature_names_sha256 = hashlib.sha256(
        ("\n".join(feature_names) + "\n").encode("utf-8")
    ).hexdigest()
    required_meta = {"meta_schema_version", "meta_signal_time"}
    if not required_meta.issubset(header):
        raise ValueError(
            "Dataset is missing prospective-audit metadata: "
            f"{required_meta.difference(header)}"
        )

    # Deliberately load only metadata. No label_* value enters this process
    # until both prospective sample-size gates have been satisfied.
    metadata = pd.read_csv(
        csv_path,
        usecols=["meta_schema_version", "meta_signal_time"],
        dtype={"meta_schema_version": "string"},
    )
    metadata["meta_signal_time"] = pd.to_datetime(
        metadata["meta_signal_time"],
        format="%Y.%m.%d %H:%M:%S",
        errors="raise",
    )
    cutoff = pd.Timestamp(manifest["cutoff_signal_time"])
    prospective = metadata[metadata["meta_signal_time"] > cutoff]
    new_events = len(prospective)
    latest_signal = prospective["meta_signal_time"].max() if new_events else None
    calendar_days = (
        float((latest_signal - cutoff).total_seconds() / 86400.0)
        if latest_signal is not None
        else 0.0
    )
    schema_versions = sorted(metadata["meta_schema_version"].dropna().unique().tolist())
    schema_ok = (
        schema_versions == [str(manifest["dataset_schema_version"])]
        and len(feature_names) == int(manifest["feature_count"])
        and feature_names_sha256 == manifest["feature_names_sha256"]
    )
    event_gate = new_events >= int(manifest["minimum_new_events"])
    time_gate = calendar_days >= float(manifest["minimum_calendar_days_after_cutoff"])
    ready = schema_ok and candidate_artifact_gate and event_gate and time_gate

    status = {
        "status": "ready_for_one_time_evaluation" if ready else "collecting",
        "labels_read": False,
        "cutoff_signal_time": cutoff,
        "latest_prospective_signal_time": latest_signal,
        "new_events": new_events,
        "calendar_days_after_cutoff": calendar_days,
        "minimum_new_events": int(manifest["minimum_new_events"]),
        "minimum_calendar_days_after_cutoff": float(
            manifest["minimum_calendar_days_after_cutoff"]
        ),
        "event_gate_passed": event_gate,
        "time_gate_passed": time_gate,
        "schema_gate_passed": schema_ok,
        "candidate_manifest": str(candidate_manifest_path),
        "expected_candidate_manifest_sha256": manifest["candidate_manifest_sha256"],
        "actual_candidate_manifest_sha256": candidate_manifest_sha256,
        "candidate_manifest_bindings_passed": candidate_bindings_ok,
        "candidate_artifact_gate_passed": candidate_artifact_gate,
        "candidate_locked_files": locked_file_audit,
        "observed_dataset_schema_versions": schema_versions,
        "observed_feature_count": len(feature_names),
        "observed_feature_names_sha256": feature_names_sha256,
        "next_action": (
            "Perform one final prospective evaluation without retraining or retuning."
            if ready
            else (
                "Restore the exact frozen candidate files before continuing."
                if not candidate_artifact_gate
                else "Continue exporting new completed events; do not inspect future label outcomes."
            )
        ),
    }
    return status


def main() -> int:
    args = parse_args()
    status = audit_prospective_status(args.csv, args.manifest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(clean_json(status), indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )

    print("PROSPECTIVE_HOLDOUT_CHECK=PASS")
    print(f"status={status['status']}")
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
    print(f"labels_read={str(status['labels_read']).lower()}")
    print(f"output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
