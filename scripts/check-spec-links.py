#!/usr/bin/env python3
"""Fails when a tracked Markdown file links to a path that is missing or ignored by git.

Spec 019 FR-006 and SC-004: tracked specs and docs must not point at ignored folders such as
docs/research/ or Tests/. Web links, mail links and in-page anchors are not checked.
Run: python3 scripts/check-spec-links.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LINK = re.compile(r"\]\(([^)\s]+)\)")
CHECKED_ROOTS = ("specs/", "docs/")
CHECKED_TOP = ("README.md", "SECURITY.md", "CONTRIBUTING.md")
# Local-only folders from .gitignore. Plain mentions must not point readers at them (spec 019 FR-006).
MENTION = re.compile(r"(?<![\w./-])((?:docs/(?:planning|research|qa|design)|Tests|\.pi|dist|\.local)/[\w./-]*)")


def git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True)


def main():
    files = git("ls-files", "--", "*.md").stdout.split()
    problems = []
    for rel in files:
        if not (rel.startswith(CHECKED_ROOTS) or rel in CHECKED_TOP):
            continue
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            text = handle.read()
        for match in LINK.finditer(text):
            link = match.group(1)
            if link.startswith(("http://", "https://", "mailto:", "#", "/")):
                continue
            path = link.split("#", 1)[0]
            if not path:
                continue
            target = os.path.normpath(os.path.join(os.path.dirname(rel), path))
            if not os.path.exists(os.path.join(ROOT, target)):
                problems.append(f"{rel}: missing target {link}")
            elif git("check-ignore", "-q", "--", target).returncode == 0:
                problems.append(f"{rel}: ignored by git {link}")
        for match in MENTION.finditer(text):
            if match.group(1).startswith("Tests/Contracts/"):
                continue
            problems.append(f"{rel}: mentions ignored path {match.group(1)}")
    for problem in problems:
        print(problem)
    print(f"{len(problems)} problem(s) in tracked specs and docs")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
