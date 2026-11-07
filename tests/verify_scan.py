#!/usr/bin/env python3
"""CI/CD Circuit Breaker: Kiểm định tính toàn vẹn tuyệt đối của dữ liệu trước khi cho phép commit.
Nếu phát hiện bất kỳ lỗi nào, script thoát với mã lỗi 1 và hủy bước commit của GitHub Actions."""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCANS_DIR = ROOT / "data" / "scans"
LATEST_JS = ROOT / "data" / "latest.js"
SCANS_JS = ROOT / "data" / "scans.js"
PRODUCTS_CSV = ROOT / "scraper" / "products.csv"


def fail(msg):
    print(f"\n[CIRCUIT BREAKER ERROR] {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    print("=================================================================")
    print("   CHẠY CI/CD CIRCUIT BREAKER: KIỂM ĐỊNH TOÀN VẸN DỮ LIỆU       ")
    print("=================================================================")

    # 1. Kiểm tra products.csv đủ 95 SKU
    if not PRODUCTS_CSV.exists():
        fail(f"Không tìm thấy file danh mục {PRODUCTS_CSV}")
    lines = [l for l in PRODUCTS_CSV.read_text(encoding="utf-8").splitlines() if l.strip()]
    if len(lines) < 95:
        fail(f"products.csv chỉ có {len(lines)} dòng (yêu cầu đủ 95 SKU Master List)")

    # 2. Tìm file scan mới nhất trong data/scans/
    scan_files = sorted(SCANS_DIR.glob("scan_*.json"))
    if not scan_files:
        fail(f"Không tìm thấy file scan nào trong {SCANS_DIR}")

    latest_scan_path = scan_files[-1]
    print(f"Kiểm tra file scan mới nhất: {latest_scan_path.name}")
    try:
        scan_data = json.loads(latest_scan_path.read_text(encoding="utf-8-sig"))
    except Exception as e:
        fail(f"Lỗi cú pháp JSON trong file {latest_scan_path.name}: {e}")

    rows = scan_data.get("rows", [])
    if len(rows) < 90:
        fail(f"Số lượng SKU quét được quá thấp: {len(rows)} < 90")

    seen_models = set()
    for idx, r in enumerate(rows):
        model = r.get("model")
        if not model:
            fail(f"Dòng {idx} trong {latest_scan_path.name} bị thiếu tên model!")
        if model in seen_models:
            fail(f"Phát hiện model bị TRÙNG LẶP (Duplicate): {model}")
        seen_models.add(model)

        status = r.get("status")
        if status == "active":
            rrp = r.get("rrp")
            red = r.get("red")
            pmh = r.get("pmh")
            choice = r.get("choice", 0)
            rule = r.get("rule")

            if rrp is None or rrp <= 0:
                fail(f"Model {model} có RRP không hợp lệ: {rrp}")
            if red is not None and (red <= 0 or red > rrp):
                fail(f"Model {model} có giá đỏ không hợp lệ: red={red}, rrp={rrp}")
            if pmh is not None and (pmh < 0 or pmh > rrp):
                fail(f"Model {model} có PMH không hợp lệ: pmh={pmh}, rrp={rrp}")

            diff = rrp - red if red else 0

            # Invariant: Flash sale rule
            if rule == "flash_chon1":
                if pmh != choice:
                    fail(f"Model {model} vi phạm Domain Invariant 2.1: rule=flash_chon1 nhưng pmh={pmh} != choice={choice}")

            # Invariant: Non-flash sale rule
            if rule == "den_tru_do" and red is not None:
                expected_pmh = max(diff, choice)
                if pmh != expected_pmh and pmh != diff:
                    fail(f"Model {model} vi phạm Domain Invariant 2.1: rule=den_tru_do nhưng pmh={pmh} != expected={expected_pmh}")

    print(f"-> Kiểm tra {len(rows)} SKU trong {latest_scan_path.name}: 100% HỢP LỆ!")

    # 3. Kiểm tra data/latest.js
    if not LATEST_JS.exists():
        fail("Không tìm thấy data/latest.js")
    latest_content = LATEST_JS.read_text(encoding="utf-8")
    m = re.search(r"window\.LATEST\s*=\s*(\{.*?\});?\s*$", latest_content, re.DOTALL)
    if not m:
        fail("data/latest.js không định nghĩa window.LATEST hợp lệ!")
    try:
        latest_json = json.loads(m.group(1))
    except Exception as e:
        fail(f"Lỗi parse JSON trong data/latest.js: {e}")

    if latest_json.get("date") != scan_data.get("date"):
        fail(f"data/latest.js lệch date so với file scan ({latest_json.get('date')} vs {scan_data.get('date')})")

    # 4. Kiểm tra data/scans.js
    if not SCANS_JS.exists():
        fail("Không tìm thấy data/scans.js")
    scans_content = SCANS_JS.read_text(encoding="utf-8")
    if scan_data.get("date") not in scans_content:
        fail(f"data/scans.js thiếu đợt quét ngày {scan_data.get('date')}")

    print("=================================================================")
    print("   CIRCUIT BREAKER: 100% PASS - DỮ LIỆU ĐẠT CHUẨN ĐỂ COMMIT!   ")
    print("=================================================================")


if __name__ == "__main__":
    main()
