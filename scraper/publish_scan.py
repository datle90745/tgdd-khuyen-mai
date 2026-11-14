"""Publish one verified scan without mixing files from competing runs."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path


PUBLISH_PATHS = (
    "data/scans", "data/scans.js", "data/latest.js", "data/links.js",
    "data/promos.js", "data/market.js", "data/alerts.js", "data/rises.js",
    "data/fpt.js", "data/market_last.json", "scraper/products.csv",
    "index.html", "promotion tgdd.html", "promotion tgdd standalone.html",
    "promotion tgdd",
)


def git(*args: str, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args], check=check, capture_output=capture,
        text=False if capture else True,
    )


def scan_time(source: str) -> datetime:
    match = re.search(r"window\.LATEST\s*=\s*(\{.*\});", source, re.S)
    if not match:
        raise ValueError("data/latest.js lacks window.LATEST")
    value = json.loads(match.group(1))["scanned_at"]
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("scanned_at has no timezone")
    return parsed


def remote_scan_time() -> datetime | None:
    result = git("show", "origin/main:data/latest.js", check=False, capture=True)
    if result.returncode:
        return None
    try:
        return scan_time(result.stdout.decode("utf-8-sig"))
    except (ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"Remote latest.js cannot be dated: {error}", flush=True)
        return None


def verify() -> None:
    subprocess.run(["node", "tests/verify_scan.js"], check=True)


def main() -> int:
    local_time = scan_time(Path("data/latest.js").read_text(encoding="utf-8-sig"))
    git("config", "user.name", "github-actions[bot]")
    git("config", "user.email", "github-actions[bot]@users.noreply.github.com")
    tag = "sync_" + datetime.now(timezone(timedelta(hours=7))).strftime("%Y%m%d_%H%M")
    index = Path("index.html")
    html = index.read_text(encoding="utf-8")
    index.write_text(re.sub(r"\?v=[^\"]+", f"?v={tag}", html), encoding="utf-8")
    for path in PUBLISH_PATHS:
        if Path(path).exists():
            git("add", "--", path)
    if git("diff", "--cached", "--quiet", check=False).returncode == 0:
        print("No scan changes to publish", flush=True)
        return 0
    git("commit", "-m", "Đợt quét PMH " + local_time.strftime("%d-%m-%Y"))
    scan_commit = git("rev-parse", "HEAD", capture=True).stdout.decode().strip()
    changed = git("diff-tree", "--no-commit-id", "--name-only", "-r", "-z", scan_commit,
                  capture=True).stdout.decode("utf-8").rstrip("\0").split("\0")
    for attempt in range(1, 6):
        if git("push", check=False).returncode == 0:
            print(f"Published verified scan {scan_commit}", flush=True)
            return 0
        print(f"Push attempt {attempt} failed; checking origin/main", flush=True)
        if git("fetch", "origin", "main", check=False).returncode:
            time.sleep(10)
            continue
        remote_time = remote_scan_time()
        if remote_time is not None and remote_time >= local_time:
            print("A scan at least as new is already published; skipping older result", flush=True)
            return 0
        # Reset to the new head, then restore every generated file from ONE
        # verified commit. A line-based rebase can mix latest.js with scan JSON.
        git("reset", "--hard", "origin/main")
        git("restore", f"--source={scan_commit}", "--staged", "--worktree", "--", *changed)
        verify()
        if git("diff", "--cached", "--quiet", check=False).returncode == 0:
            return 0
        git("commit", "-m", "Đợt quét PMH " + local_time.strftime("%d-%m-%Y"))
        if attempt < 5:
            time.sleep(2)
    print("Could not push scan after 5 attempts", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
