"""Regression: a concurrent commit cannot split one verified scan across files."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scraper" / "publish_scan.py"


def run(cwd, *args):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(f"{args} failed:\n{result.stdout}\n{result.stderr}")
    return result


def latest(marker, minute):
    return ("window.LATEST = " + json.dumps({
        "scanned_at": f"2026-11-14T09:{minute:02d}:00+07:00", "marker": marker,
    }) + ";\n")


class PublishScanRaceTest(unittest.TestCase):
    def test_concurrent_commit_preserves_complete_newer_scan(self):
        for remote_minute, expected in [(5, "local"), (20, "remote")]:
            with self.subTest(remote_minute=remote_minute), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                origin = root / "origin.git"
                run(root, "git", "init", "--bare", "--initial-branch=main", str(origin))
                work = root / "work"
                other = root / "other"
                run(root, "git", "clone", str(origin), str(work))
                run(work, "git", "config", "user.name", "Test")
                run(work, "git", "config", "user.email", "test@example.com")
                (work / "data" / "scans").mkdir(parents=True)
                (work / "tests").mkdir()
                (work / "data" / "latest.js").write_text(latest("base", 0), encoding="utf-8")
                (work / "data" / "scans" / "today.json").write_text('{"marker":"base"}')
                (work / "index.html").write_text('<script src="data/latest.js?v=old"></script>')
                (work / "tests" / "verify_scan.js").write_text(
                    "const fs=require('fs'); const a=JSON.parse(fs.readFileSync('data/latest.js','utf8').split(' = ')[1].slice(0,-2)); "
                    "const b=JSON.parse(fs.readFileSync('data/scans/today.json')); "
                    "if(a.marker!==b.marker)process.exit(1);\n")
                run(work, "git", "add", ".")
                run(work, "git", "commit", "-m", "base")
                run(work, "git", "push", "-u", "origin", "HEAD:main")
                run(root, "git", "clone", str(origin), str(other))
                run(other, "git", "config", "user.name", "Test")
                run(other, "git", "config", "user.email", "test@example.com")
                (other / "data" / "latest.js").write_text(latest("remote", remote_minute), encoding="utf-8")
                (other / "data" / "scans" / "today.json").write_text('{"marker":"remote"}')
                (other / "data" / "fpt_live.json").write_text('{"fresh":true}')
                run(other, "git", "add", ".")
                run(other, "git", "commit", "-m", "concurrent")
                run(other, "git", "push", "origin", "main")
                (work / "data" / "latest.js").write_text(latest("local", 10), encoding="utf-8")
                (work / "data" / "scans" / "today.json").write_text('{"marker":"local"}')
                run(work, sys.executable, str(SCRIPT))
                run(other, "git", "pull", "--ff-only")
                published = json.loads((other / "data" / "latest.js").read_text().split(" = ")[1][:-2])
                scan = json.loads((other / "data" / "scans" / "today.json").read_text())
                self.assertEqual(published["marker"], expected)
                self.assertEqual(scan["marker"], expected)
                self.assertTrue((other / "data" / "fpt_live.json").exists())


if __name__ == "__main__":
    unittest.main()
