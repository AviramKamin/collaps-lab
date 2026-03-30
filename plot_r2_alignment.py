#!/usr/bin/env python3
import argparse
import os
import re
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import matplotlib.pyplot as plt

NS = 1_000_000_000

@dataclass
class MarkWindow:
    start_ns: int
    end_ns: int

def read_marks(path: str) -> Dict[str, int]:
    marks: Dict[str, int] = {}
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(maxsplit=1)
            if len(parts) != 2:
                continue
            ts, name = parts
            if ts.isdigit():
                marks[name] = int(ts)
    return marks

def get_r2_windows(marks: Dict[str, int], cycles: int) -> Dict[int, MarkWindow]:
    out: Dict[int, MarkWindow] = {}
    for c in range(1, cycles + 1):
        s = marks.get(f"C{c}_RECOVERY_R2_START")
        e = marks.get(f"C{c}_RECOVERY_R2_END")
        if s and e and e > s:
            out[c] = MarkWindow(s, e)
    return out

def read_heartbeat(path: str) -> List[Tuple[int, int]]:
    # heartbeat.log: "<ts_ns> <dt_ns>"
    rows: List[Tuple[int, int]] = []
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            a = line.split()
            if len(a) < 2:
                continue
            if a[0].isdigit() and a[1].isdigit():
                rows.append((int(a[0]), int(a[1])))
    return rows

_probe_line_re = re.compile(r"^(?P<ts>\d+)\s+(?P<evt>(PROBE_[ABC]_(START|END)|R2_.*|SKIP_PROBE_[ABC]).*)$")

def read_probes(path: str) -> List[Tuple[int, str]]:
    ev: List[Tuple[int, str]] = []
    if not os.path.exists(path):
        return ev
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            m = _probe_line_re.match(line)
            if not m:
                continue
            ts = int(m.group("ts"))
            evt = m.group("evt")
            ev.append((ts, evt))
    return ev

def classify_probe_events(events: List[Tuple[int, str]]) -> Dict[str, List[int]]:
    # returns dict for A/B/C start/end arrays
    out = {
        "A_START": [], "A_END": [],
        "B_START": [], "B_END": [],
        "C_START": [], "C_END": [],
    }
    for ts, evt in events:
        if evt.startswith("PROBE_A_START"): out["A_START"].append(ts)
        elif evt.startswith("PROBE_A_END"): out["A_END"].append(ts)
        elif evt.startswith("PROBE_B_START"): out["B_START"].append(ts)
        elif evt.startswith("PROBE_B_END"): out["B_END"].append(ts)
        elif evt.startswith("PROBE_C_START"): out["C_START"].append(ts)
        elif evt.startswith("PROBE_C_END"): out["C_END"].append(ts)
    return out

def read_telemetry(path: str) -> List[Tuple[int, Dict[str, float]]]:
    # telemetry.log lines like: "<ts_ns> key=value key=value ..."
    rows: List[Tuple[int, Dict[str, float]]] = []
    if not os.path.exists(path):
        return rows
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if not parts or not parts[0].isdigit():
                continue
            ts = int(parts[0])
            kv: Dict[str, float] = {}
            for p in parts[1:]:
                if "=" not in p:
                    continue
                k, v = p.split("=", 1)
                try:
                    kv[k] = float(v)
                except ValueError:
                    pass
            rows.append((ts, kv))
    return rows

def within(ts: int, w: MarkWindow) -> bool:
    return w.start_ns <= ts <= w.end_ns

def ns_to_s(ts_ns: int, origin_ns: int) -> float:
    return (ts_ns - origin_ns) / NS

def plot_cycle(
    ax,
    hb_rows: List[Tuple[int, int]],
    probe_events: Dict[str, List[int]],
    tele_rows: List[Tuple[int, Dict[str, float]]],
    r2: MarkWindow,
    threshold_ns: int,
    title: str,
    show_telemetry: bool,
):
    origin = r2.start_ns

    # Heartbeat R2 only
    xs = []
    ys_ms = []
    spikes_x = []
    spikes_y = []
    for ts, dt in hb_rows:
        if not within(ts, r2):
            continue
        x = ns_to_s(ts, origin)
        y = dt / 1_000_000.0  # ms
        xs.append(x)
        ys_ms.append(y)
        if dt > threshold_ns:
            spikes_x.append(x)
            spikes_y.append(y)

    ax.plot(xs, ys_ms, linewidth=1.0, label="heartbeat_dt_ms")
    if spikes_x:
        ax.scatter(spikes_x, spikes_y, s=30, label=f"stall > {threshold_ns/1e6:.0f}ms")

    # Probe markers (vertical lines)
    def vlines(ts_list: List[int], label: str):
        for i, ts in enumerate(ts_list):
            if not within(ts, r2):
                continue
            x = ns_to_s(ts, origin)
            ax.axvline(x, linewidth=1.0, alpha=0.6, label=label if i == 0 else None)

    vlines(probe_events.get("A_START", []), "PROBE_A_START")
    vlines(probe_events.get("A_END", []), "PROBE_A_END")
    vlines(probe_events.get("B_START", []), "PROBE_B_START")
    vlines(probe_events.get("B_END", []), "PROBE_B_END")
    vlines(probe_events.get("C_START", []), "PROBE_C_START")
    vlines(probe_events.get("C_END", []), "PROBE_C_END")

    ax.set_title(title)
    ax.set_xlabel("seconds into R2")
    ax.set_ylabel("heartbeat dt (ms)")
    ax.grid(True, alpha=0.3)

    # Telemetry overlay (secondary axis)
    if show_telemetry and tele_rows:
        ax2 = ax.twinx()
        tx = []
        wq = []
        wticks = []
        ioticks = []
        for ts, kv in tele_rows:
            if not within(ts, r2):
                continue
            tx.append(ns_to_s(ts, origin))
            wq.append(kv.get("disk_wq_d", 0.0))
            wticks.append(kv.get("disk_wticks_d", 0.0))
            ioticks.append(kv.get("disk_ioticks_d", 0.0))

        # plot only if non-empty
        if tx:
            ax2.plot(tx, wq, linewidth=1.0, label="disk_wq_d")
            ax2.plot(tx, wticks, linewidth=1.0, label="disk_wticks_d")
            ax2.plot(tx, ioticks, linewidth=1.0, label="disk_ioticks_d")
            ax2.set_ylabel("telemetry (disk deltas)")
            # merge legends
            h1, l1 = ax.get_legend_handles_labels()
            h2, l2 = ax2.get_legend_handles_labels()
            ax.legend(h1 + h2, l1 + l2, loc="upper right")
        else:
            ax.legend(loc="upper right")
    else:
        ax.legend(loc="upper right")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True, help="Path to run directory (contains heartbeat.log, heartbeat_marks.log, cycle_*/)")
    ap.add_argument("--cycles", type=int, default=3, help="How many cycles to plot (default 3)")
    ap.add_argument("--threshold-ms", type=float, default=200.0, help="Stall threshold in ms (default 200)")
    ap.add_argument("--out", default=None, help="Output PNG path (default: <run>/r2_alignment.png)")
    ap.add_argument("--telemetry", action="store_true", help="Overlay telemetry on secondary axis")
    args = ap.parse_args()

    run = os.path.expanduser(args.run)
    marks_path = os.path.join(run, "heartbeat_marks.log")
    hb_path = os.path.join(run, "heartbeat.log")

    if not os.path.exists(marks_path) or not os.path.exists(hb_path):
        raise SystemExit("Run directory missing heartbeat_marks.log or heartbeat.log")

    marks = read_marks(marks_path)
    r2_windows = get_r2_windows(marks, args.cycles)
    if not r2_windows:
        raise SystemExit("No R2 windows found in heartbeat_marks.log")

    hb = read_heartbeat(hb_path)
    threshold_ns = int(args.threshold_ms * 1_000_000)

    n = len(r2_windows)
    fig, axes = plt.subplots(n, 1, figsize=(14, 4.2 * n), constrained_layout=True)
    if n == 1:
        axes = [axes]

    for idx, (c, w) in enumerate(sorted(r2_windows.items(), key=lambda x: x[0])):
        cycle_dir = os.path.join(run, f"cycle_{c}")
        probes_path = os.path.join(cycle_dir, "probes.log")
        tele_path = os.path.join(cycle_dir, "telemetry.log")

        probes_raw = read_probes(probes_path)
        probes = classify_probe_events(probes_raw)
        tele = read_telemetry(tele_path) if args.telemetry else []

        plot_cycle(
            axes[idx],
            hb,
            probes,
            tele,
            w,
            threshold_ns,
            title=f"Cycle {c} R2 alignment",
            show_telemetry=args.telemetry,
        )

    out = args.out or os.path.join(run, "r2_alignment.png")
    fig.savefig(out, dpi=150)
    print(out)

if __name__ == "__main__":
    main()
