#!/usr/bin/env python3
"""CI/CD Circuit Breaker - vo boc.

Logic kiem dinh nam o DUY NHAT mot noi: tests/verify_scan.js.

Truoc day ton tai hai ban (verify_scan.py va verify_scan.js) voi cung mot muc dich
nhung noi dung da lech nhau, va chi ban .py duoc CI chay - nen ban .js cu chay local
co the bao PASS trong khi CI bao FAIL (va nguoc lai). File nay goi thang sang ban .js
de hai duong vao luon cho cung mot ket qua.

Chay: python tests/verify_scan.py   (tuong duong: node tests/verify_scan.js)
"""

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / "tests" / "verify_scan.js"


def main() -> int:
    node = shutil.which("node")
    if not node:
        print(
            "[CIRCUIT BREAKER ERROR] Khong tim thay Node.js tren PATH.\n"
            "Circuit breaker duoc trien khai tai tests/verify_scan.js.\n"
            "Cai Node.js roi chay lai, hoac chay truc tiep: node tests/verify_scan.js",
            file=sys.stderr,
        )
        return 1

    if not CHECKER.exists():
        print(f"[CIRCUIT BREAKER ERROR] Khong tim thay {CHECKER}", file=sys.stderr)
        return 1

    return subprocess.run([node, str(CHECKER)], cwd=str(ROOT)).returncode


if __name__ == "__main__":
    sys.exit(main())
