#!/usr/bin/env python3
"""Đóng gói tự động toàn bộ dữ liệu (data/*.js, xlsx.full.min.js) vào các file HTML offline.
Chạy được trên cả Linux (GitHub Actions) và Windows."""

import base64
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INDEX_HTML = ROOT / "index.html"
XLSX_JS = ROOT / "xlsx.full.min.js"
PROMO_DIR = ROOT / "promotion tgdd"

DATA_FILES = [
    "data.js", "scans.js", "latest.js", "links.js", "rises.js",
    "fpt.js", "alerts.js", "market.js", "promos.js"
]

TARGETS = [
    ROOT / "promotion tgdd.html",
    ROOT / "promotion tgdd standalone.html",
    PROMO_DIR / "promotion tgdd.html"
]


def bundle():
    print("--- ĐANG ĐÓNG GÓI OFFLINE HTML BUNDLES ---")
    if not INDEX_HTML.exists():
        print(f"Lỗi: Không tìm thấy {INDEX_HTML}")
        return

    content = INDEX_HTML.read_text(encoding="utf-8")

    # 1. Nhúng thư viện SheetJS (Base64)
    if XLSX_JS.exists():
        b64 = base64.b64encode(XLSX_JS.read_bytes()).decode("ascii")
        data_uri = f"data:text/javascript;base64,{b64}"
        xlsx_pattern = re.compile(
            r'<script src="xlsx\.full\.min\.js"></script>\s*<script>if\(!window\.XLSX\).*?</script>|<script src="https://cdnjs\.cloudflare\.com/ajax/libs/xlsx/0\.18\.5/xlsx\.full\.min\.js"></script>',
            re.DOTALL
        )
        content = xlsx_pattern.sub(lambda _: f'<script src="{data_uri}"></script>', content)

    # 2. Nhúng toàn bộ các file data/*.js
    for df in DATA_FILES:
        p = ROOT / "data" / df
        if p.exists():
            c = p.read_text(encoding="utf-8")
            pattern = re.compile(rf'<script src="data/{re.escape(df)}[^"]*"></script>', re.DOTALL)
            replacement = f"<script>\n/* Embedded data/{df} */\n{c}\n</script>"
            # Dùng lambda để Python không coi các ký tự '\u' trong data.js là regex escape sequence
            content = pattern.sub(lambda _, r=replacement: r, content)

    # 3. Ghi vào các file đích
    PROMO_DIR.mkdir(parents=True, exist_ok=True)
    for t in TARGETS:
        t.write_text(content, encoding="utf-8")
        size_kb = round(t.stat().st_size / 1024, 1)
        print(f"Đã tạo: {t.name} ({size_kb} KB)")

    # 4. Đồng bộ index.html và xlsx vào promotion tgdd/
    sub_index = PROMO_DIR / "index.html"
    sub_index.write_text(INDEX_HTML.read_text(encoding="utf-8"), encoding="utf-8")
    print(f"Đã đồng bộ: {sub_index.relative_to(ROOT)}")

    if XLSX_JS.exists():
        (PROMO_DIR / "xlsx.full.min.js").write_bytes(XLSX_JS.read_bytes())

    # 5. Đồng bộ toàn bộ data/*.js vào promotion tgdd/data/ để bản sao không bao giờ bị cũ
    sub_data = PROMO_DIR / "data"
    sub_data.mkdir(parents=True, exist_ok=True)
    for df in DATA_FILES:
        p = ROOT / "data" / df
        if p.exists():
            (sub_data / df).write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
    print(f"Đã đồng bộ dữ liệu vào: {sub_data.relative_to(ROOT)}")

    print("Đóng gói offline hoàn tất 100%!")


if __name__ == "__main__":
    bundle()
