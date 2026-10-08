"""Ghi lại các lần giá đen (RRP) tăng mà bộ quét phát hiện, để báo cáo lại.

Quét chạy mỗi ngày, nhưng bảng lịch sử trên web chỉ thêm cột vào thứ Hai và thứ Sáu.
Các ngày còn lại chỉ dùng để dò tăng giá; kết quả dò nằm ở data/alerts.js.
"""
import json
import re
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
ALERTS_JS = DATA_DIR / "alerts.js"
RISES_JS = DATA_DIR / "rises.js"
BASE_JS = DATA_DIR / "data.js"
KEEP_ENTRIES = 120  # giữ khoảng 2 tháng gần nhất của cả hai nguồn
KEEP_WEEKDAYS = {0, 4}  # thứ Hai, thứ Sáu — ngày được lưu thành cột trên web


def load():
    if not ALERTS_JS.exists():
        return []
    match = re.search(r"window\.ALERTS\s*=\s*(\[.*\]);", ALERTS_JS.read_text(encoding="utf-8"), re.S)
    return json.loads(match.group(1)) if match else []


def _base_text():
    return BASE_JS.read_text(encoding="utf-8") if BASE_JS.exists() else ""


def brand_of(model):
    """Hãng của một model, lấy từ dữ liệu gốc của trang."""
    text = _base_text()
    match = re.search(r'"brand":\s*"([^"]+)",\s*"model":\s*"' + re.escape(model) + '"', text)
    return match.group(1).upper() if match else ""


def _rise_key(brand, model, old, new):
    return f"{str(brand).upper()}|{model}|{old}|{new}"


def load_rises():
    if not RISES_JS.exists():
        return []
    match = re.search(r"window\.RISE_AUTO\s*=\s*(\[.*\]);", RISES_JS.read_text(encoding="utf-8"), re.S)
    return json.loads(match.group(1)) if match else []


def record_rises(day, items):
    """Thêm các lần tăng giá vừa dò được vào Lịch sử tăng giá.

    Mỗi dòng: [tháng, hãng, model, giá cũ, giá mới, ngày, % đổi, kênh phát hiện].
    Bỏ qua dòng đã có sẵn trong dữ liệu gốc hoặc đã ghi ở lần quét trước, để không nhân đôi.
    """
    if not items:
        return load_rises()
    base = _base_text()
    rises = load_rises()
    seen = {_rise_key(r[1], r[2], r[3], r[4]) for r in rises}
    for row in re.findall(r'\["T\d+","([^"]+)","([^"]+)",(\d+),(\d+),', base):
        seen.add(_rise_key(row[0], row[1], int(row[2]), int(row[3])))
    month = f"T{int(day[5:7])}"
    added = 0
    for it in items:
        model, old, new = it.get("n"), it.get("old"), it.get("new")
        if not model or not old or not new or new <= old:
            continue
        brand = (it.get("b") or brand_of(model) or "").upper()
        key = _rise_key(brand, model, old, new)
        if key in seen:
            continue
        seen.add(key)
        rises.append([month, brand, model, old, new, day,
                      round((new - old) / old * 100, 1), it.get("r") or ""])
        added += 1
    rises.sort(key=lambda r: r[5])
    RISES_JS.parent.mkdir(parents=True, exist_ok=True)
    RISES_JS.write_text(
        "/* Tự sinh bởi bộ quét, đừng sửa tay. Các lần tăng giá đen do quét phát hiện. */\n"
        "window.RISE_AUTO = " + json.dumps(rises, ensure_ascii=False) + ";\n", encoding="utf-8")
    if added:
        print(f"Đã thêm {added} dòng vào Lịch sử tăng giá.", flush=True)
    return rises


def record(source, day, at, items):
    """source: 'tgdd-86' hoặc 'market'. day: ngày ISO. items: [{r,b,n,old,new}].

    Ghi đè phần của cùng (source, day) để chạy lại trong ngày không bị nhân đôi.
    """
    record_rises(day, items)
    entries = [e for e in load() if not (e.get("source") == source and e.get("day") == day)]
    entries.append({"source": source, "day": day, "at": at, "items": items})
    entries.sort(key=lambda e: (e.get("day", ""), e.get("at", "")))
    entries = entries[-KEEP_ENTRIES:]
    ALERTS_JS.parent.mkdir(parents=True, exist_ok=True)
    ALERTS_JS.write_text(
        "/* Tự sinh bởi bộ quét, đừng sửa tay. Các lần giá đen tăng theo từng ngày quét. */\n"
        "window.ALERTS = " + json.dumps(entries, ensure_ascii=False) + ";\n", encoding="utf-8")
    return entries
