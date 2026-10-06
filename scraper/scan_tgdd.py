"""Quét PMH trên thegioididong.com cho danh sách SKU trong scraper/products.csv.

Mỗi lần chạy tạo một đợt quét (ngày theo giờ Việt Nam), lưu:
  data/scans/scan_YYYY-MM-DD.json   bản ghi chi tiết của đợt quét
  data/scans.js                     window.SCANS = [...] cho web đọc

Cách tính (theo tab "Quy tắc tính PMH" của web, đã đối chiếu với số liệu tay):
  - Có banner "Online Giá Rẻ Quá" (khối flash sale còn suất): PMH = giá đen − giá đỏ của khối đó.
  - Không có banner: PMH = giá đen − giá đỏ (giá gạch ngang − giá đang bán).
  - Không có giá gạch: PMH = khoản "Giảm giá Xđ" là lựa chọn đầu của mục "Chọn 1 trong"
    (trường hợp iPhone). Khoản này luôn được lưu riêng ở trường `choice`.
    Đặt ADD_CHOICE = True nếu muốn luôn cộng khoản đó vào PMH.
Không đoán số: trang lỗi/không đọc được giá thì PMH để trống (null).
"""
import csv
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

import os
import requests
from bs4 import BeautifulSoup

ADD_CHOICE = False

ROOT = Path(__file__).resolve().parent.parent
PRODUCTS = ROOT / "scraper" / "products.csv"
SCAN_DIR = ROOT / "data" / "scans"
SCANS_JS = ROOT / "data" / "scans.js"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
    "Referer": "https://www.thegioididong.com/",
}

# Tùy chọn: đi qua Cloudflare Worker nếu TGDĐ chặn IP của GitHub Actions
# (cùng cách với cf_proxy.py trong dự án IoT).
CF_PROXY_URL = os.environ.get("CF_PROXY_URL", "").rstrip("/")
CF_PROXY_TOKEN = os.environ.get("CF_PROXY_TOKEN", "")


def http_get(url):
    if CF_PROXY_URL and CF_PROXY_TOKEN:
        return requests.get(f"{CF_PROXY_URL}/fetch?url={quote(url, safe='')}",
                            headers={"X-Proxy-Token": CF_PROXY_TOKEN}, timeout=30)
    return requests.get(url, headers=HEADERS, timeout=(10, 30))


def to_int(value):
    digits = str(value or "").split(".")[0]
    digits = re.sub(r"[^0-9]", "", digits)
    return int(digits) if digits else 0


def money(text):
    """Giá dạng chữ hiển thị trên trang, ví dụ '11.190.000đ' -> 11190000."""
    digits = re.sub(r"[^0-9]", "", str(text or ""))
    return int(digits) if digits else 0


def final_pmh(discount, choice):
    """discount = giá đen − giá đỏ; choice = khoản "Giảm giá X" trong mục "Chọn 1 trong".
    Mặc định (khớp số liệu tay nhiều nhất): có giá gạch thì lấy discount, không có thì lấy choice."""
    if ADD_CHOICE:
        return discount + choice
    return discount if discount > 0 else choice


CHOICE_RE =re.compile(r"Chọn 1 trong[^:]{0,30}:\s*Giảm giá\s*([\d.,]+)\s*[₫đ]", re.I)


def parse_next_layout(soup):
    """Bố cục mới của TGDĐ (không có .box_main): giá đỏ ở span.text-24.text-red-5,
    giá đen ở thẻ <del> cạnh đó. Giá đỏ ở bố cục này đã trừ sẵn khoản "Giảm giá X"
    của mục "Chọn 1 trong", nên tách khoản đó ra để khớp với bố cục cũ."""
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
    match = CHOICE_RE.search(page.get_text(" ", strip=True))
    choice = money(match.group(1)) if match else 0
    banner = bool(re.search(r"Online Giá Rẻ Quá", page.get_text(" ", strip=True), re.I))
    discount = max(rrp - red - choice, 0)
    pmh = final_pmh(discount, choice)
    return {"status": "active", "rrp": rrp, "red": red, "pmh": pmh, "choice": choice,
            "kind": "moi-banner" if banner else "moi"}


def parse_page(html):
    """Trả về dict: status, rrp (giá đen), red (giá đỏ), pmh, choice, kind."""
    soup = BeautifulSoup(html, "html.parser")
    main = soup.select_one(".box_main")
    if main is None:
        result = parse_next_layout(soup)
        if result is not None:
            return result
        text = soup.get_text(" ", strip=True)
        if re.search(r"ngừng kinh doanh|ngưng kinh doanh", text, re.I):
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
        kind = "banner"
    else:
        price = main.select_one(".box-price[data-priceorg]")
        kind = "thuong"
    if price is None:
        text = main.get_text(" ", strip=True)
        if re.search(r"ngừng kinh doanh|ngưng kinh doanh", text, re.I):
            return {"status": "ngung_kd"}
        return {"status": "no_price"}

    rrp = to_int(price.get("data-priceorg"))
    discount = to_int(price.get("data-discountorigin"))
    if not rrp:
        return {"status": "no_price"}
    pmh = final_pmh(discount, choice)
    return {"status": "active", "rrp": rrp, "red": rrp - discount,
            "pmh": pmh, "choice": choice, "kind": kind}


def scan_one(url, attempts=3):
    last_error = None
    for attempt in range(attempts):
        try:
            resp = http_get(url)
            if resp.status_code == 404:
                return {"status": "ngung_kd"}
            resp.raise_for_status()
            resp.encoding = "utf-8"
            result = parse_page(resp.text)
            if result["status"] == "no_price" and attempt < attempts - 1:
                time.sleep(2)
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
    if last_error is None:
        return result
    return {"status": "error", "error": str(last_error)}


def write_scans_js():
    scans = []
    for path in sorted(SCAN_DIR.glob("scan_*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        scans.append({"date": data["date"], "rows": [
            {k: r[k] for k in ("model", "rrp", "pmh", "status", "choice") if k in r}
            for r in data["rows"]]})
    SCANS_JS.write_text(
        "/* Tự sinh bởi scraper/scan_tgdd.py, đừng sửa tay. */\n"
        "window.SCANS = " + json.dumps(scans, ensure_ascii=False) + ";\n",
        encoding="utf-8")


def main():
    now = datetime.now(ZoneInfo("Asia/Ho_Chi_Minh"))
    with PRODUCTS.open(encoding="utf-8-sig", newline="") as f:
        products = [p for p in csv.DictReader(f) if p["url"].strip()]

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
        print(f"[{i}/{len(products)}] {product['model']}: {result.get('status')} "
              f"rrp={result.get('rrp')} pmh={result.get('pmh')} choice={result.get('choice')} "
              f"({result.get('kind', '')}) {result.get('debug', '')}", flush=True)
        time.sleep(1.5)

    ok = sum(1 for r in rows if r["status"] == "active")
    if ok < len(products) * 0.5:
        # Đa số trang lỗi (thường do bị chặn IP): không ghi đè dữ liệu.
        sys.exit(f"ERROR: chỉ đọc được {ok}/{len(products)} trang, không lưu đợt quét này.")

    SCAN_DIR.mkdir(parents=True, exist_ok=True)
    scan = {"date": now.strftime("%d-%b"), "scanned_at": now.isoformat(timespec="seconds"),
            "add_choice": ADD_CHOICE, "rows": rows}
    (SCAN_DIR / f"scan_{now.date().isoformat()}.json").write_text(
        json.dumps(scan, ensure_ascii=False, indent=1), encoding="utf-8")
    write_scans_js()
    print(f"Đã lưu đợt {scan['date']}: {ok}/{len(products)} SKU đọc được giá, {errors} lỗi mạng.")


if __name__ == "__main__":
    main()
