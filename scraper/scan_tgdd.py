"""Quét PMH trên thegioididong.com cho danh sách SKU trong scraper/products.csv.

Mỗi lần chạy tạo một đợt quét (ngày theo giờ Việt Nam), lưu:
  data/scans/scan_YYYY-MM-DD.json   bản ghi chi tiết của đợt quét
  data/scans.js                     window.SCANS = [...] cho web đọc

PMH (`pmh`), theo tab "Quy tắc tính PMH" của web:
  1. Có flash sale: PMH = khoản "Giảm giá X" trong mục "Chọn 1 trong".
     Không có mục đó thì PMH = 0 (không lấy chênh lệch giá đen và giá đỏ của flash sale).
  2. Không có flash sale: PMH = số lớn hơn giữa (giá đen − giá đỏ) và khoản "Chọn 1 trong".
Ghi kèm để đối chiếu: `online` = giá đen − giá đỏ, `choice` = khoản "Chọn 1 trong",
`rule` = quy tắc đã dùng (flash_chon1 / den_tru_do / chon1).
Không đoán số: trang lỗi/không đọc được giá thì để trống (null).
"""
import argparse
import csv
import json
import os
import re
import sys
import time
from datetime import date, datetime
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

import requests
from bs4 import BeautifulSoup

import alerts

ROOT = Path(__file__).resolve().parent.parent
PRODUCTS = ROOT / "scraper" / "products.csv"
SCAN_DIR = ROOT / "data" / "scans"
SCANS_JS = ROOT / "data" / "scans.js"
LATEST_JS = ROOT / "data" / "latest.js"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
    "Referer": "https://www.thegioididong.com/",
}

# Đi qua Cloudflare Worker (cloudflare-worker.js) vì TGDĐ chặn IP của GitHub Actions.
CF_PROXY_URL = os.environ.get("CF_PROXY_URL", "").rstrip("/")
CF_PROXY_TOKEN = os.environ.get("CF_PROXY_TOKEN", "")

BASE_RE = re.compile(r"Chọn 1 trong[^:]{0,30}:\s*Giảm giá\s*([\d.,]+)\s*[₫đ]", re.I)
BANNER_RE = re.compile(r"Online Giá Rẻ Quá", re.I)
SLOTS_RE = re.compile(r"Còn\s*\d+\s*/\s*\d+\s*suất", re.I)  # flash sale ở bố cục mới: "Còn 2/5 suất"
# Dạng flash sale thứ hai ở bố cục mới: dải đỏ "Ưu đãi ONLINE — Kết thúc sau 09 : 07 : 58".
ONLINE_DEAL_RE = re.compile(r"Ưu đãi ONLINE|Kết thúc sau\s*\d", re.I)
DISCONTINUED_RE = re.compile(r"ngừng kinh doanh|ngưng kinh doanh", re.I)


def http_get(url):
    if CF_PROXY_URL and CF_PROXY_TOKEN:
        return requests.get(f"{CF_PROXY_URL}/fetch?url={quote(url, safe='')}",
                            headers={"X-Proxy-Token": CF_PROXY_TOKEN}, timeout=30)
    return requests.get(url, headers=HEADERS, timeout=(10, 30))


def to_int(value):
    """Số trong thuộc tính data-*, ví dụ '13990000.0' -> 13990000."""
    digits = re.sub(r"[^0-9]", "", str(value or "").split(".")[0])
    return int(digits) if digits else 0


def money(text):
    """Giá dạng chữ hiển thị trên trang, ví dụ '11.190.000đ' -> 11190000."""
    digits = re.sub(r"[^0-9]", "", str(text or ""))
    return int(digits) if digits else 0


def build_result(rrp, red, banner, choice, kind, choice_in_red=True):
    """rrp/red = giá đen/giá đỏ khách thật sự trả (đã trừ khoản "Chọn 1 trong").
    choice = khoản "Giảm giá X" trong mục "Chọn 1 trong".
    choice_in_red = giá đỏ đã trừ sẵn khoản "Chọn 1 trong" hay chưa."""
    diff = max(rrp - red, 0)  # giá đen − giá đỏ
    if banner:  # có flash sale: chỉ lấy khoản "Chọn 1 trong", không có thì 0
        pmh, rule = choice, "flash_chon1"
    elif diff >= choice:  # không flash sale: lấy số lớn hơn
        pmh, rule = diff, "den_tru_do"
    else:
        pmh, rule = choice, "chon1"
    # Tổng khuyến mãi online khách thấy trên trang (gồm cả flash sale), chỉ để tham khảo.
    total = diff + (0 if choice_in_red else choice)
    return {"status": "active", "rrp": rrp, "red": red, "pmh": pmh, "online": diff,
            "total_online": total, "choice": choice, "kind": kind, "rule": rule}


def parse_next_layout(soup):
    """Bố cục mới của TGDĐ (không có .box_main): giá đỏ ở span.text-24.text-red-5,
    giá đen ở thẻ <del> cạnh đó. Flash sale có dòng "Còn x/y suất" cạnh giá."""
    page = soup.select_one("main")
    if page is None:
        return None
    reds = page.select("span.text-24.font-700.text-red-5")
    if not reds:
        return None
    red_node = next((r for r in reds if r.parent and r.parent.select_one("del")), reds[0])
    red = money(red_node.get_text())
    old = red_node.parent.select_one("del") if red_node.parent else None
    rrp = money(old.get_text()) if old is not None else red
    if not red or not rrp:
        return None
    text = page.get_text(" ", strip=True)
    match = BASE_RE.search(text)
    choice = money(match.group(1)) if match else 0
    # Chỉ xét khối giá của chính sản phẩm (vài tầng cha của giá đỏ), không xét sản phẩm gợi ý.
    box = red_node
    for _ in range(4):
        box = box.parent if box.parent is not None else box
    box_text = box.get_text(" ", strip=True)
    banner = bool(SLOTS_RE.search(box_text) or BANNER_RE.search(box_text)
                  or ONLINE_DEAL_RE.search(box_text))
    # Bố cục mới hiển thị giá đỏ chưa trừ khoản "Chọn 1 trong" (bấm chọn mới trừ tiếp).
    return build_result(rrp, red, banner, choice, "moi-banner" if banner else "moi",
                        choice_in_red=False)


def parse_page(html):
    soup = BeautifulSoup(html, "html.parser")
    main = soup.select_one(".box_main")
    if main is None:
        result = parse_next_layout(soup)
        if result is not None:
            return result
        text = soup.get_text(" ", strip=True)
        if DISCONTINUED_RE.search(text):
            return {"status": "ngung_kd"}
        if re.search(r"đăng ký nhận tin|sắp ra mắt", text, re.I):
            return {"status": "chua_mo_ban"}
        return {"status": "no_price"}

    choice = 0
    active = main.select_one('label.label-radio[data-active="1"]')
    if active is not None and re.match(r"^\s*Giảm giá", active.get_text(" ", strip=True), re.I):
        choice = to_int(active.get("data-discountchoose"))

    flash = next((box for box in main.select(".box_saving")
                  if "soldout" not in box.get("class", [])
                  and box.select_one(".bs_price[data-priceorg]")), None)
    if flash is not None:
        price = flash.select_one(".bs_price[data-priceorg]")
        area = flash.get_text(" ", strip=True)
    else:
        price = main.select_one(".box-price[data-priceorg]")
        area = main.get_text(" ", strip=True)
    if price is None:
        if DISCONTINUED_RE.search(main.get_text(" ", strip=True)):
            return {"status": "ngung_kd"}
        return {"status": "no_price"}

    rrp = to_int(price.get("data-priceorg"))
    discount = to_int(price.get("data-discountorigin"))
    if not rrp:
        return {"status": "no_price"}
    # Bố cục cũ chưa trừ lựa chọn "Giảm giá X" vào giá đỏ; bố cục mới (người dùng đang thấy) thì
    # đã trừ. Trừ thêm ở đây để hai bố cục cho cùng một giá đỏ.
    red = rrp - discount - (choice if flash is None else 0)
    return build_result(rrp, red, flash is not None, choice,
                        "banner" if flash is not None else "thuong",
                        choice_in_red=flash is None)


def scan_one(url, attempts=3):
    last_error, result = None, None
    for attempt in range(attempts):
        try:
            resp = http_get(url)
            if resp.status_code == 404:
                return {"status": "ngung_kd"}
            resp.raise_for_status()
            resp.encoding = "utf-8"
            result = parse_page(resp.text)
            last_error = None
            if result["status"] == "no_price" and attempt < attempts - 1:
                time.sleep(2)  # bố cục trang trả về ngẫu nhiên: tải lại một lần
                continue
            if result["status"] == "no_price":
                soup = BeautifulSoup(resp.text, "html.parser")
                h1 = soup.select_one("h1")
                result["debug"] = (f"len={len(resp.text)} box_main={bool(soup.select_one('.box_main'))} "
                                   f"main={bool(soup.select_one('main'))} h1={h1.get_text(strip=True)[:60] if h1 else None}")
            return result
        except Exception as error:  # mạng chập chờn: thử lại có giãn cách
            last_error = error
            time.sleep(3 * (attempt + 1))
    if last_error is None and result is not None:
        return result
    return {"status": "error", "error": str(last_error)}


def write_scans_js():
    """Chỉ đưa các đợt quét của thứ Hai và thứ Sáu lên web; ngày khác chỉ dùng để dò tăng giá."""
    keys = ("model", "rrp", "pmh", "status", "online", "total_online", "choice", "kind", "rule")
    scans = []
    for path in sorted(SCAN_DIR.glob("scan_*.json")):
        try:
            day = date.fromisoformat(path.stem.replace("scan_", ""))
        except ValueError:
            continue
        if day.weekday() not in alerts.KEEP_WEEKDAYS:
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        scans.append({"date": data["date"], "rows": [
            {k: r[k] for k in keys if k in r} for r in data["rows"]]})
    SCANS_JS.write_text(
        "/* Tự sinh bởi scraper/scan_tgdd.py, đừng sửa tay. */\n"
        "window.SCANS = " + json.dumps(scans, ensure_ascii=False) + ";\n",
        encoding="utf-8")


def write_latest_js(scan):
    """Đợt quét mới nhất, quét ngày nào cũng ghi, để web có cột "hôm nay" và các cột tham khảo.
    Trùng ngày với một cột đã lưu (thứ Hai/thứ Sáu) thì web ghi đè chính cột đó, không thêm cột mới."""
    keys = ("model", "rrp", "pmh", "status", "online", "total_online", "choice", "kind", "rule")
    latest = {"date": scan["date"], "rows": [
        {k: r[k] for k in keys if k in r} for r in scan["rows"]]}
    LATEST_JS.write_text(
        "/* Tự sinh bởi scraper/scan_tgdd.py, đừng sửa tay. */\n"
        "window.LATEST = " + json.dumps(latest, ensure_ascii=False) + ";\n",
        encoding="utf-8")


def pick_products(products, only):
    """--only "A17 8GB/128GB,A08": quét một phần, khớp tên không phân biệt hoa thường.
    --only missing: chỉ quét những model HÔM NAY chưa có số. Hôm nay chưa quét lần nào
    thì quét hết, không dựa vào đợt của ngày cũ để bỏ qua model nào."""
    if not only:
        return products
    if only.strip().lower() == "missing":
        path = SCAN_DIR / f"scan_{date.today().isoformat()}.json"
        if not path.exists():
            return products
        rows = json.loads(path.read_text(encoding="utf-8"))["rows"]
        done = {r["model"] for r in rows if isinstance(r.get("pmh"), int)}
        return [p for p in products if p["model"] not in done]
    keys = [k.strip().lower() for k in only.split(",") if k.strip()]
    return [p for p in products if any(k in p["model"].lower() for k in keys)]


def merge_into_today(rows, now):
    """Quét một phần thì ghép vào ĐÚNG đợt quét của hôm nay, không bao giờ lấy đợt ngày khác.
    Hôm nay chưa quét lần nào thì chỉ ghi các model vừa quét; model chưa quét để trống,
    tuyệt đối không bê số của ngày cũ sang."""
    path = SCAN_DIR / f"scan_{now.date().isoformat()}.json"
    if not path.exists():
        return None
    scan = json.loads(path.read_text(encoding="utf-8"))
    fresh = {r["model"]: r for r in rows}
    scan["rows"] = [fresh.pop(r["model"], r) for r in scan["rows"]] + list(fresh.values())
    scan["scanned_at"] = now.isoformat(timespec="seconds")
    return scan


def main():
    now = datetime.now(ZoneInfo("Asia/Ho_Chi_Minh"))
    parser = argparse.ArgumentParser(description="Quét PMH của các SKU đang theo dõi trên TGDĐ.")
    parser.add_argument("--only", default=os.environ.get("ONLY", ""),
                        help='Chỉ quét một phần: "missing" hoặc danh sách model cách nhau bằng dấu phẩy.')
    args = parser.parse_args()

    with PRODUCTS.open(encoding="utf-8-sig", newline="") as f:
        all_products = [p for p in csv.DictReader(f) if p["url"].strip()]
    products = pick_products(all_products, args.only)
    partial = len(products) != len(all_products)
    if not products:
        print("Không có model nào cần quét.")
        return
    if partial:
        print(f"Quét một phần: {len(products)}/{len(all_products)} model — "
              + ", ".join(p["model"] for p in products), flush=True)

    rows, errors = [], 0
    for i, product in enumerate(products, 1):
        # 3 trang đầu đều lỗi mạng = đang bị chặn IP: dừng ngay thay vì treo cả job.
        result = scan_one(product["url"].strip(), attempts=1 if i <= 3 else 3)
        if result["status"] == "error":
            errors += 1
            if errors == i == 3:
                sys.exit("ERROR: 3 trang đầu đều không kết nối được tới thegioididong.com "
                         "(thường do TGDĐ chặn IP của GitHub). Cần cấu hình CF_PROXY_URL/CF_PROXY_TOKEN.")
        row = {"model": product["model"], "url": product["url"], **result}
        if row["status"] != "active":
            row["pmh"] = None
        rows.append(row)
        print(f"[{i}/{len(products)}] {product['model']}: {result.get('status')} rrp={result.get('rrp')} "
              f"pmh={result.get('pmh')} online={result.get('online')} choice={result.get('choice')} "
              f"({result.get('kind', '')}/{result.get('rule', '')}) {result.get('debug', '')}", flush=True)
        time.sleep(1.5)

    ok = sum(1 for r in rows if r["status"] == "active")
    if ok < len(products) * 0.5:
        # Đa số trang lỗi (thường do bị chặn IP): không ghi đè dữ liệu.
        sys.exit(f"ERROR: chỉ đọc được {ok}/{len(products)} trang, không lưu đợt quét này.")

    # Dò giá đen tăng so với đợt quét gần nhất trước hôm nay.
    today = now.date().isoformat()
    previous = sorted(p for p in SCAN_DIR.glob("scan_*.json")
                      if p.stem.replace("scan_", "") < today)
    ups = []
    if previous:
        old = {r["model"]: r.get("rrp") for r in
               json.loads(previous[-1].read_text(encoding="utf-8"))["rows"]}
        for r in rows:
            before, after = old.get(r["model"]), r.get("rrp")
            if before and after and after > before:
                ups.append({"r": "TGDĐ", "n": r["model"], "old": before, "new": after})
    alerts.record("tgdd-86", today, now.strftime("%H:%M"), ups)
    print(f"Giá đen tăng (86 SKU): {len(ups)}"
          + ("; " + "; ".join(f"{u['n']} {u['old']:,}→{u['new']:,}" for u in ups[:10]) if ups else ""),
          flush=True)

    SCAN_DIR.mkdir(parents=True, exist_ok=True)
    scan = {"date": now.strftime("%d-%b"), "scanned_at": now.isoformat(timespec="seconds"), "rows": rows}
    if partial:
        merged = merge_into_today(rows, now)
        if merged is not None:
            scan = merged
        else:
            print("Hôm nay chưa có đợt quét nào, chỉ ghi các model vừa quét; "
                  "các model còn lại để trống chứ không lấy số của ngày cũ.", flush=True)
    (SCAN_DIR / f"scan_{now.date().isoformat()}.json").write_text(
        json.dumps(scan, ensure_ascii=False, indent=1), encoding="utf-8")
    write_scans_js()
    write_latest_js(scan)
    print(f"Đã lưu đợt {scan['date']}: {ok}/{len(products)} SKU đọc được giá, {errors} lỗi mạng. "
          f"Tổng cộng {len(scan['rows'])} model trong đợt.")


if __name__ == "__main__":
    main()
