"""Ghi lại các lần giá đen (RRP) tăng mà bộ quét phát hiện, để báo cáo lại.

Quét chạy mỗi ngày, nhưng bảng lịch sử trên web chỉ thêm cột vào thứ Hai và thứ Sáu.
Các ngày còn lại chỉ dùng để dò tăng giá; kết quả dò nằm ở data/alerts.js.
"""
import json
import re
from pathlib import Path

ALERTS_JS = Path(__file__).resolve().parent.parent / "data" / "alerts.js"
KEEP_ENTRIES = 120  # giữ khoảng 2 tháng gần nhất của cả hai nguồn
KEEP_WEEKDAYS = {0, 4}  # thứ Hai, thứ Sáu — ngày được lưu thành cột trên web


def load():
    if not ALERTS_JS.exists():
        return []
    match = re.search(r"window\.ALERTS\s*=\s*(\[.*\]);", ALERTS_JS.read_text(encoding="utf-8"), re.S)
    return json.loads(match.group(1)) if match else []


def record(source, day, at, items):
    """source: 'tgdd-86' hoặc 'market'. day: ngày ISO. items: [{r,b,n,old,new}].

    Ghi đè phần của cùng (source, day) để chạy lại trong ngày không bị nhân đôi.
    """
    entries = [e for e in load() if not (e.get("source") == source and e.get("day") == day)]
    entries.append({"source": source, "day": day, "at": at, "items": items})
    entries.sort(key=lambda e: (e.get("day", ""), e.get("at", "")))
    entries = entries[-KEEP_ENTRIES:]
    ALERTS_JS.parent.mkdir(parents=True, exist_ok=True)
    ALERTS_JS.write_text(
        "/* Tự sinh bởi bộ quét, đừng sửa tay. Các lần giá đen tăng theo từng ngày quét. */\n"
        "window.ALERTS = " + json.dumps(entries, ensure_ascii=False) + ";\n", encoding="utf-8")
    return entries
