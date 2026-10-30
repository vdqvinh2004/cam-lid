#!/usr/bin/env python3
"""Spec 015 T401 calibration: run one agent session in a temporary directory and record, once per second, the CPU
time of the agent's process subtree and the age of the newest write in the agent's own session directory.
Only metadata is read. The prompt must not need tools. Usage:
  python3 scripts/agent-activity-calibrate.py --agent claude --mode tui --model claude-haiku-5-5 --prompt "..." \
      --prompt-at 30 --observe 150 > timeline.csv
  python3 scripts/agent-activity-calibrate.py --agent claude --mode print --model claude-haiku-5-5 --prompt "..."
"""
import argparse, os, pty, select, signal, subprocess, sys, tempfile, time

SESSION_DIRS = {"claude": "~/.claude/projects", "codex": "~/.codex/sessions", "opencode": "~/.local/share/opencode"}

def cpu_seconds(text):
    # macOS `ps -o time`: [[dd-]hh:]mm:ss.cc
    days = 0
    if "-" in text: d, text = text.split("-", 1); days = int(d)
    parts = [float(p) for p in text.split(":")]
    secs = 0.0
    for p in parts: secs = secs * 60 + p
    return secs + days * 86400

def subtree_cpu(root):
    out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,time="], capture_output=True, text=True).stdout
    rows = {}
    kids = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) < 3: continue
        pid, ppid = int(f[0]), int(f[1])
        rows[pid] = cpu_seconds(f[2]); kids.setdefault(ppid, []).append(pid)
    if root not in rows: return None, 0
    total, stack, count = 0.0, [root], 0
    while stack:
        p = stack.pop(); total += rows.get(p, 0.0); count += 1; stack.extend(kids.get(p, []))
    return total, count - 1

def newest_age(agent):
    root = os.path.expanduser(SESSION_DIRS[agent]); newest = None
    for d, _, files in os.walk(root):
        for f in files:
            try: m = os.stat(os.path.join(d, f)).st_mtime
            except OSError: continue
            newest = m if newest is None or m > newest else newest
    return None if newest is None else max(0.0, time.time() - newest)

def main():
    a = argparse.ArgumentParser()
    a.add_argument("--agent", default="claude"); a.add_argument("--mode", choices=["tui", "print"], default="tui")
    a.add_argument("--model", default=None); a.add_argument("--prompt", required=True)
    a.add_argument("--prompt-at", type=float, default=30); a.add_argument("--observe", type=float, default=150)
    a.add_argument("--log", default=None, help="write the agent's terminal output here (for debugging the harness)")
    args = a.parse_args()
    work = tempfile.mkdtemp(prefix="camlid-calibrate-")
    cmd = [args.agent] + (["--model", args.model] if args.model else [])
    events = []
    start = time.time()
    if args.mode == "tui":
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(work); os.environ.setdefault("TERM", "xterm-256color"); os.execvp(cmd[0], cmd)
        sent_trust = sent_prompt = False
    else:
        proc = subprocess.Popen(cmd + ["-p", args.prompt], cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        pid, fd = proc.pid, None
    print("t,alive,cpu_total,cpu_rate,children,session_age,event"); sys.stdout.flush()
    last_cpu = None; last_t = None; exit_seen = None
    log = open(args.log, "ab") if args.log else None
    while True:
        t = time.time() - start
        event = ""
        if fd is not None:
            while select.select([fd], [], [], 0)[0]:
                try:
                    chunk = os.read(fd, 65536)
                    if not chunk: break
                    if log: log.write(chunk); log.flush()
                except OSError: break
            if not sent_trust and t >= 5 and exit_seen is None: os.write(fd, b"\x1b[B"); time.sleep(0.3); os.write(fd, b"\r"); sent_trust = True; event = "trustAccepted"  # Claude Code defaults to "No, exit"
            if not sent_prompt and t >= args.prompt_at and exit_seen is None:
                os.write(fd, args.prompt.encode()); time.sleep(0.3); os.write(fd, b"\r"); sent_prompt = True; event = "promptSent"
        if fd is not None and exit_seen is None:
            try:
                if os.waitpid(pid, os.WNOHANG)[0] == pid: exit_seen = t; event = event or "exited"
            except ChildProcessError: exit_seen = t
        cpu, children = (None, 0) if (fd is not None and exit_seen is not None) else subtree_cpu(pid)
        alive = cpu is not None
        rate = "" if cpu is None or last_cpu is None else f"{(cpu - last_cpu) / (t - last_t):.4f}"
        age = newest_age(args.agent)
        print(f"{t:.1f},{int(alive)},{'' if cpu is None else f'{cpu:.2f}'},{rate},{children},{'' if age is None else f'{age:.1f}'},{event}")
        sys.stdout.flush()
        last_cpu, last_t = cpu, t
        if args.mode == "print" and proc.poll() is not None and exit_seen is None: exit_seen = t
        if (exit_seen is not None and t - exit_seen > 5) or t >= args.observe: break
        time.sleep(1)
    if fd is not None:
        try: os.kill(pid, signal.SIGTERM)
        except OSError: pass
    elif proc.poll() is None: proc.terminate()

if __name__ == "__main__":
    main()
