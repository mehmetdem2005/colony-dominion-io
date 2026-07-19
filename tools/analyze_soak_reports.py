#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import statistics
import sys
from pathlib import Path


def percentile_nearest_rank(values: list[float], percentile: float) -> float:
    if not values:
        return -1.0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(percentile * len(ordered)) - 1))
    return ordered[index]


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/soak")
    reports: list[dict[str, object]] = []
    unreadable: list[str] = []
    for path in sorted(root.glob("bot-*.json")):
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                reports.append(value)
            else:
                unreadable.append(path.name)
        except (OSError, json.JSONDecodeError):
            unreadable.append(path.name)
    if not reports:
        print(json.dumps({"ok": False, "error": "no_bot_reports", "unreadable": unreadable}))
        return 1

    pings = [
        float(report.get("ping_ms", -1))
        for report in reports
        if float(report.get("ping_ms", -1)) >= 0
    ]
    jitters = [float(report.get("jitter_ms", 0)) for report in reports]
    losses = [float(report.get("packet_loss_percent", 0)) for report in reports]
    gaps = [int(report.get("max_snapshot_gap_msec", 0)) for report in reports]
    summary = {
        "ok": all(bool(report.get("ok")) for report in reports) and not unreadable,
        "bots": len(reports),
        "unreadable_reports": unreadable,
        "median_ping_ms": round(statistics.median(pings), 2) if pings else -1,
        "p95_ping_ms": round(percentile_nearest_rank(pings, 0.95), 2),
        "max_jitter_ms": max(jitters, default=0),
        "max_packet_loss_percent": max(losses, default=0),
        "max_snapshot_gap_msec": max(gaps, default=0),
        "total_snapshots": sum(int(report.get("snapshot_count", 0)) for report in reports),
    }
    summary["acceptance_passed"] = (
        bool(summary["ok"])
        and int(summary["max_snapshot_gap_msec"]) <= 1000
        and float(summary["max_packet_loss_percent"]) <= 10.0
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if bool(summary["acceptance_passed"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
