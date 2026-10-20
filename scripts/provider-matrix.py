#!/usr/bin/env python3
"""20-run installed-version provider evidence matrix (M3 T008 / SC-003).

Runs 20 short benchmark tasks per provider with constrained prompts, captures
provider event streams (JSONL) plus harness metadata, and never touches user
configuration (no hooks installed; observation is wrapper/process level).

Providers:
  codex    `codex exec --json` with the configured cheap model
  opencode `opencode run --format json` with a free model

Usage:
  provider-matrix.py --provider codex --model gpt-6-luna --effort medium --out DIR
  provider-matrix.py --provider opencode --model opencode-go/longcat-2.5-preview-free --out DIR

Profiles (20): 8 success, 3 slow, 2 fail, 2 crash (TERM/KILL by harness),
2 parallel, 1 background-child, 1 suspend/resume, 1 approval-denied
(codex read-only sandbox; opencode records whatever its default policy does).

Only benchmark prompts authored for this matrix are stored. No user agent
content is collected. Costs: trivial prompts on cheap/free models.
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import time

RUN_TIMEOUT = 240

SUCCESS = "Do nothing except run this exact shell command: {cmd}. Reply with its output only, ten words or fewer."


def profiles(provider):
    profs = []
    for i in range(1, 9):
        profs.append(("success", SUCCESS.format(cmd="echo MATRIX-OK-%d" % i), {}))
    for i, secs in ((9, 25), (10, 30), (11, 35)):
        profs.append(("slow", SUCCESS.format(cmd="sleep %d && echo SLOW-%d" % (secs, i)), {}))
    profs.append(("fail", "Do nothing except run this exact shell command: false. Reply with its exit code only.", {}))
    profs.append(("fail", "Do nothing except run this exact shell command: sh -c 'exit 3'. Reply with its exit code only.", {}))
    profs.append(("crash-term", SUCCESS.format(cmd="sleep 150 && echo NEVER"), {"kill": (12, signal.SIGTERM)}))
    profs.append(("crash-kill", SUCCESS.format(cmd="sleep 150 && echo NEVER"), {"kill": (12, signal.SIGKILL)}))
    profs.append(("parallel-a", SUCCESS.format(cmd="echo PAR-A"), {"parallel_group": 1}))
    profs.append(("parallel-b", SUCCESS.format(cmd="echo PAR-B"), {"parallel_group": 1}))
    profs.append(("child", "Start `sleep 50` in the background with &, print its PID, then reply DONE. Ten words or fewer.", {}))
    profs.append(("suspend", SUCCESS.format(cmd="sleep 120 && echo RESUMED"), {"stop_cont": (12, 35)}))
    if provider == "codex":
        profs.append(("approval", "Create file /tmp/matrix-approval-probe containing APPROVED.", {"sandbox": "read-only"}))
    else:
        profs.append(("approval", "Create file /tmp/matrix-approval-probe containing APPROVED.", {}))
    assert len(profs) == 20
    return profs


def build_command(provider, model, effort, prompt, extra, workdir, session_id=None):
    if provider == "codex":
        cmd = ["codex", "exec", "--json", "--skip-git-repo-check", "-m", model,
               "-c", "model_reasoning_effort=%s" % effort]
        if extra.get("sandbox"):
            cmd += ["-s", extra["sandbox"]]
        return cmd + [prompt], workdir
    else:
        cmd = ["opencode", "run", "--model", model, "--format", "json"]
        if session_id:
            cmd += ["--session", session_id]
        return cmd + [prompt], workdir


def run_one(provider, model, effort, idx, profile, prompt, extra, outdir, workdir, tag):
    name = "run-%02d" % idx
    jsonl_path = os.path.join(outdir, name + ".jsonl")
    meta = {
        "provider": provider, "model": model, "profile": profile,
        "prompt": prompt, "effort": effort, "tag": tag,
        "started_epoch": time.time(),
    }
    session_id = "ses-matrix-%s-%02d" % (tag, idx) if provider == "opencode" else None
    cmd, cwd = build_command(provider, model, effort, prompt, extra, workdir, session_id)
    meta["argv"] = cmd
    if session_id:
        meta["session_id"] = session_id
    t0 = time.monotonic()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            cwd=cwd, start_new_session=True)
    killed_by = None
    timed_out = False
    try:
        kill = extra.get("kill")
        sc = extra.get("stop_cont")
        deadline = t0 + RUN_TIMEOUT
        while True:
            now = time.monotonic()
            elapsed = now - t0
            if kill and elapsed >= kill[0] and not killed_by:
                os.kill(proc.pid, kill[1])
                killed_by = "SIGTERM" if kill[1] == signal.SIGTERM else "SIGKILL"
            if sc and elapsed >= sc[0] and not killed_by:
                os.kill(proc.pid, signal.SIGSTOP)
                killed_by = "STOPPED"
            if sc and killed_by == "STOPPED" and elapsed >= sc[1]:
                os.kill(proc.pid, signal.SIGCONT)
                killed_by = "STOPPED_THEN_CONTINUED"
            if proc.poll() is not None:
                break
            if now >= deadline:
                timed_out = True
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
                killed_by = (killed_by + "+TIMEOUT") if killed_by else "TIMEOUT"
                break
            time.sleep(1)
        out, err = proc.communicate()
    except Exception as exc:  # noqa: BLE001 - harness must always record
        out, err = b"", str(exc).encode()
        timed_out = True
    duration = time.monotonic() - t0
    with open(jsonl_path, "wb") as fh:
        fh.write(out or b"")
    meta.update({
        "ended_epoch": time.time(),
        "duration_seconds": round(duration, 1),
        "exit_code": proc.returncode,
        "timed_out": timed_out,
        "killed_by": killed_by,
        "jsonl_bytes": len(out or b""),
        "stderr_tail": (err or b"").decode("utf-8", "replace")[-500:],
    })
    with open(os.path.join(outdir, name + ".meta.json"), "w") as fh:
        json.dump(meta, fh, indent=2)
    print("run %s profile=%s exit=%s dur=%.0fs killed=%s bytes=%d" % (
        name, profile, proc.returncode, duration, killed_by, len(out or b"")),
        flush=True)
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--provider", required=True, choices=["codex", "opencode"])
    ap.add_argument("--model", required=True)
    ap.add_argument("--effort", default="medium")
    ap.add_argument("--out", required=True)
    ap.add_argument("--workdir", default=".")
    ap.add_argument("--tag", default="")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    tag = args.tag or args.provider
    profs = profiles(args.provider)
    results = []
    # Parallel pair runs together; everything else sequential.
    pending_parallel = []
    for idx, (profile, prompt, extra) in enumerate(profs, start=1):
        if extra.get("parallel_group"):
            pending_parallel.append((idx, profile, prompt, extra))
            if len(pending_parallel) == 2:
                import concurrent.futures
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    futs = [pool.submit(run_one, args.provider, args.model,
                                        args.effort, i, p, pr, e, args.out,
                                        args.workdir, tag)
                            for (i, p, pr, e) in pending_parallel]
                    results += [f.result() for f in futs]
                pending_parallel = []
            continue
        results.append(run_one(args.provider, args.model, args.effort, idx,
                               profile, prompt, extra, args.out, args.workdir, tag))
    summary = {
        "provider": args.provider, "model": args.model, "runs": len(results),
        "by_profile": {},
    }
    for meta in results:
        summary["by_profile"].setdefault(meta["profile"], []).append({
            "exit": meta["exit_code"], "dur": meta["duration_seconds"],
            "killed": meta["killed_by"], "timeout": meta["timed_out"]})
    with open(os.path.join(args.out, "summary.json"), "w") as fh:
        json.dump(summary, fh, indent=2)
    print("MATRIX DONE: %d runs -> %s" % (len(results), args.out))


if __name__ == "__main__":
    main()
