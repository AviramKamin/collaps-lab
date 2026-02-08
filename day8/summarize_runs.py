import csv
import os
import re
import sys
from pathlib import Path
from statistics import median

# -------- helpers --------

def find_first(run_dir: Path, patterns):
    for pat in patterns:
        hits = sorted(run_dir.glob(pat))
        if hits:
            return hits[0]
    return None

def parse_env(env_path: Path):
    d = {}
    if not env_path or not env_path.exists():
        return d
    for line in env_path.read_text(errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        d[k.strip()] = v.strip()
    return d

def quantiles(values, ps):
    if not values:
        return {p: "" for p in ps}
    vs = sorted(values)
    out = {}
    for p in ps:
        idx = int(round((p/100) * (len(vs)-1)))
        idx = max(0, min(len(vs)-1, idx))
        out[p] = vs[idx]
    return out

def parse_heartbeat(hb_path: Path):
    # tries to parse timestamps and compute deltas
    # supports lines like: "170723... 0.123" or ISO timestamps
    if not hb_path or not hb_path.exists():
        return {}

    ts = []
    for line in hb_path.read_text(errors="ignore").splitlines():
        line = line.strip()
        if not line:
            continue

        # pick first token that looks like float seconds or epoch seconds
        parts = re.split(r"\s+", line)
        token = parts[0]

        # epoch seconds float
        try:
            t = float(token)
            ts.append(t)
            continue
        except:
            pass

        # ISO-ish timestamp: 2026-02-06T17:48:55.123
        m = re.match(r"(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(\.\d+)?", token)
        if m:
            # fallback: ignore if not easily convertible without dateutil
            # user can adjust if format is ISO; for now skip
            continue

    if len(ts) < 5:
        return {}

    deltas = [ts[i] - ts[i-1] for i in range(1, len(ts))]
    qs = quantiles(deltas, [50, 95, 99])
    return {
        "hb_count": len(ts),
        "hb_delta_p50": qs[50],
        "hb_delta_p95": qs[95],
        "hb_delta_p99": qs[99],
        "hb_delta_max": max(deltas),
    }

def parse_retry_log(retry_path: Path):
    # generic parser that counts keywords and tries to extract latency ms and budget misses
    if not retry_path or not retry_path.exists():
        return {}

    text = retry_path.read_text(errors="ignore")
    lines = text.splitlines()

    attempts = 0
    success = 0
    fail = 0
    budget_miss = 0
    lat_ms = []

    # patterns you can tweak to match your logger
    lat_patterns = [
        re.compile(r"lat(?:ency)?[_ =:]+(\d+\.?\d*)\s*ms", re.IGNORECASE),
        re.compile(r"took[_ =:]+(\d+\.?\d*)\s*ms", re.IGNORECASE),
        re.compile(r"duration[_ =:]+(\d+\.?\d*)\s*ms", re.IGNORECASE),
    ]

    for ln in lines:
        l = ln.lower()
        if "attempt" in l:
            attempts += 1
        if "success" in l or "ok" in l:
            success += 1
        if "fail" in l or "error" in l:
            fail += 1
        if "budget" in l and ("miss" in l or "exceed" in l or "over" in l):
            budget_miss += 1

        for pat in lat_patterns:
            m = pat.search(ln)
            if m:
                try:
                    lat_ms.append(float(m.group(1)))
                except:
                    pass

    qs = quantiles(lat_ms, [50, 95, 99])
    return {
        "attempts": attempts,
        "success": success,
        "fail": fail,
        "budget_miss": budget_miss,
        "lat_ms_p50": qs[50],
        "lat_ms_p95": qs[95],
        "lat_ms_p99": qs[99],
        "lat_ms_max": max(lat_ms) if lat_ms else "",
    }

def parse_dmesg(dmesg_path: Path):
    if not dmesg_path or not dmesg_path.exists():
        return {}

    text = dmesg_path.read_text(errors="ignore").lower()
    keys = {
        "io_error": len(re.findall(r"\bio error\b|\bi/o error\b", text)),
        "ext4_err": len(re.findall(r"ext4.*error|ext4-fs error", text)),
        "throttle": len(re.findall(r"throttl|under-voltage|undervoltage", text)),
        "oom": len(re.findall(r"out of memory|oom-killer", text)),
    }
    return keys

def parse_meminfo(mem_path: Path):
    # expects periodic lines containing fields like MemAvailable, Dirty, Writeback, Slab with numbers (kB)
    if not mem_path or not mem_path.exists():
        return {}

    fields = ["MemAvailable", "Dirty", "Writeback", "Slab"]
    series = {f: [] for f in fields}

    for ln in mem_path.read_text(errors="ignore").splitlines():
        for f in fields:
            m = re.search(rf"\b{re.escape(f)}\b[:= ]+(\d+)", ln)
            if m:
                series[f].append(int(m.group(1)))

    out = {}
    for f, arr in series.items():
        if arr:
            out[f"{f}_min"] = min(arr)
            out[f"{f}_avg"] = sum(arr) / len(arr)
            out[f"{f}_max"] = max(arr)
        else:
            out[f"{f}_min"] = ""
            out[f"{f}_avg"] = ""
            out[f"{f}_max"] = ""
    return out

# -------- main --------

def main(root: Path):
    run_dirs = sorted([p for p in root.rglob("*") if p.is_dir() and re.search(r"day\d+_off\d+_", p.name)], key=lambda x: x.name)
    if not run_dirs:
        # fallback: treat direct children as runs
        run_dirs = sorted([p for p in root.iterdir() if p.is_dir()], key=lambda x: x.name)

    rows = []
    for rd in run_dirs:
        env_file = find_first(rd, ["*.env", "meta.env", "run.env", "config.env", "params.env"])
        env = parse_env(env_file) if env_file else {}

        hb = parse_heartbeat(find_first(rd, ["*heartbeat*.log", "heartbeat.log"]))
        retry = parse_retry_log(find_first(rd, ["*retry*.log", "retry.log", "*workload*.log"]))
        dm = parse_dmesg(find_first(rd, ["*dmesg*.log", "dmesg.log"]))
        mem = parse_meminfo(find_first(rd, ["*meminfo*.log", "meminfo.log"]))

        row = {
            "run_dir": str(rd),
            "run_name": env.get("RUN_NAME", rd.name),
            "probe_program": env.get("PROBE_PROGRAM", ""),
            "off_sec": env.get("OFF_SEC", ""),
            "on_sec": env.get("ON_SEC", ""),
            "bursts": env.get("BURSTS", ""),
            "budget_ms": env.get("BUDGET_MS", ""),
            "retries": env.get("RETRIES", ""),
        }
        row.update(hb)
        row.update(retry)
        row.update(dm)
        row.update(mem)
        rows.append(row)

    # stable column order
    cols = []
    for r in rows:
        for k in r.keys():
            if k not in cols:
                cols.append(k)

    out_path = root / "summary.csv"
    with out_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    print(f"Wrote: {out_path}")
    print(f"Runs: {len(rows)}")
    print("Example first row keys:", cols[:12])

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python summarize_runs.py /path/to/runs_root")
        sys.exit(1)
    main(Path(sys.argv[1]).expanduser().resolve())
