"""Quét giá điện thoại toàn thị trường (tab "Toàn thị trường" của web) — chỉ để tham khảo.

Lấy từ trang danh sách của 4 nhà bán lẻ, chỉ 6 hãng đang theo dõi
(Apple, Samsung, OPPO, Xiaomi gồm Redmi/POCO, Vivo, Realme):
  - TGDĐ:          POST /Category/FilterProductBox?c=42&pi=N (20 máy/trang)
  - CellphoneS:    GraphQL api.cellphones.com.vn, danh mục 3, chỉ hàng đang bán (stock 46)
  - FPT Shop:      dữ liệu nhúng trong trang /dien-thoai/<hãng> (API của FPT chặn máy chủ)
  - Viettel Store: POST /Site/_Sys/GetUserControlAsync.aspx (CatID=010001)
Mỗi máy ghi: giá gốc (giá gạch), giá online (giá bán), giá trị KM = giá gốc − giá online.
Lưu data/market.js (window.MARKET), giữ tối đa KEEP_SCANS đợt gần nhất; quét lại trong
cùng ngày thì ghi đè đợt của ngày đó.
"""
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parent.parent
MARKET_JS = ROOT / "data" / "market.js"
KEEP_SCANS = 20

CF_PROXY_URL = os.environ.get("CF_PROXY_URL", "").rstrip("/")
CF_PROXY_TOKEN = os.environ.get("CF_PROXY_TOKEN", "")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36")

BRANDS = [  # (tên hiển thị, các từ nhận diện trong tên/hãng)
    ("Apple", ("apple", "iphone")),
    ("Samsung", ("samsung", "galaxy")),
    ("OPPO", ("oppo",)),
    ("Xiaomi", ("xiaomi", "redmi", "poco")),
    ("Vivo", ("vivo",)),
    ("Realme", ("realme",)),
]


def brand_of(*texts):
    text = " ".join(t or "" for t in texts).lower()
    for name, words in BRANDS:
        if any(re.search(rf"\b{w}\b", text) for w in words):
            return name
    return None


def money(text):
    """Giá dạng chữ hiển thị trên trang, ví dụ '45.490.000 ₫' -> 45490000."""
    digits = re.sub(r"[^0-9]", "", str(text or ""))
    return int(digits) if digits else 0


def num(value):
    """Số dạng 3.899e+07 / 6490000.0 / 6490000 -> int."""
    try:
        return int(round(float(value)))
    except (TypeError, ValueError):
        return 0


def request(method, url, *, headers=None, data=None, json_body=None, timeout=40):
    """Gửi thẳng; nếu lỗi mạng/bị chặn thì đi qua Cloudflare Worker (nếu có cấu hình)."""
    headers = {"User-Agent": UA, "Accept-Language": "vi-VN,vi;q=0.9", **(headers or {})}
    body = json.dumps(json_body) if json_body is not None else data
    if json_body is not None:
        headers["Content-Type"] = "application/json"
    errors = []
    for via_proxy in (False, True):
        if via_proxy and not (CF_PROXY_URL and CF_PROXY_TOKEN):
            break
        try:
            if via_proxy:
                resp = requests.request(method, f"{CF_PROXY_URL}/fetch?url={quote(url, safe='')}",
                                        headers={**headers, "X-Proxy-Token": CF_PROXY_TOKEN},
                                        data=body, timeout=timeout)
            else:
                resp = requests.request(method, url, headers=headers, data=body, timeout=(10, timeout))
            resp.raise_for_status()
            resp.encoding = "utf-8"
            return resp
        except Exception as error:
            errors.append(f"{'proxy' if via_proxy else 'direct'}: {error}")
    raise RuntimeError("; ".join(errors))


def row(retailer, brand, name, url, price, orig, kind="Khuyến mãi"):
    orig = orig if orig and orig > price else price
    return {"r": retailer, "b": brand, "n": " ".join(name.split()), "u": url,
            "p": price, "o": orig, "k": kind}


def scan_tgdd():
    rows, seen = [], set()
    for page in range(30):
        resp = request("POST", f"https://www.thegioididong.com/Category/FilterProductBox?c=42&o=13&pi={page}",
                       headers={"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                                "X-Requested-With": "XMLHttpRequest",
                                "Referer": "https://www.thegioididong.com/dtdd"},
                       data="IsParentCate=False&IsShowCompare=True&prevent=true")
        html = resp.json().get("listproducts") or ""
        links = BeautifulSoup(html, "html.parser").select("li.item[data-id] a.main-contain")
        if not links:
            break
        for a in links:
            li = a.find_parent("li")
            href = a.get("href", "")
            name = re.sub(r"^Điện thoại\s+", "", a.get("data-name", ""))
            brand = brand_of(a.get("data-brand"), name)
            if not brand or href in seen:
                continue
            seen.add(href)
            price = num(a.get("data-price"))
            old = li.select_one(".price-old")
            if not price:
                continue
            rows.append(row("TGDĐ", brand, name, "https://www.thegioididong.com" + href.split("?")[0],
                            price, money(old.get_text()) if old else 0,
                            "Flash Sale Online" if "utm_flashsale=1" in href else "Khuyến mãi"))
        time.sleep(1)
    return rows


CPS_QUERY = """query { products(filter:{static:{categories:["3"],province_id:30,stock:{from:0},
 stock_available_id:[46],filter_price:{from:0,to:200000000}},dynamic:{}}, page:%d, size:100,
 sort:[{view:desc}]) { general{ name url_path manufacturer } filterable{ price special_price } } }"""


def scan_cellphones():
    rows = []
    for page in range(1, 15):
        data = request("POST", "https://api.cellphones.com.vn/v2/graphql/query",
                       json_body={"query": CPS_QUERY % page, "variables": {}}).json()
        items = (data.get("data") or {}).get("products") or []
        for it in items:
            g, f = it.get("general") or {}, it.get("filterable") or {}
            name = re.sub(r"\s*\|.*$", "", g.get("name") or "")
            brand = brand_of(g.get("manufacturer"), name)
            orig, special = num(f.get("price")), num(f.get("special_price"))
            price = special if special else orig
            if brand and price:
                rows.append(row("CellphoneS", brand, name, "https://cellphones.com.vn/" + (g.get("url_path") or ""),
                                price, orig))
        if len(items) < 100:
            break
        time.sleep(1)
    return rows


FPT_BRAND_PAGES = ["apple-iphone", "samsung", "oppo", "xiaomi", "vivo", "realme"]


def fpt_pages_via_browser(urls):
    """FPT chặn mọi kết nối từ máy chủ bằng trang kiểm tra chống bot ("Just a moment"),
    nên mở bằng trình duyệt thật (Playwright) để trang tự vượt qua rồi lấy HTML."""
    from playwright.sync_api import sync_playwright

    pages = {}
    with sync_playwright() as pw:
        browser = pw.chromium.launch(args=["--disable-blink-features=AutomationControlled"])
        context = browser.new_context(user_agent=UA, locale="vi-VN",
                                      timezone_id="Asia/Ho_Chi_Minh",
                                      viewport={"width": 1366, "height": 768})
        page = context.new_page()
        for url in urls:
            html = ""
            try:
                page.goto(url, wait_until="domcontentloaded", timeout=60000)
                for _ in range(20):  # chờ trang kiểm tra tự chuyển sang nội dung thật
                    html = page.content()
                    if '"currentPrice"' in html.replace('\\"', '"'):
                        break
                    page.wait_for_timeout(2000)
            except Exception as error:
                print(f"  playwright {url}: {error}", flush=True)
            pages[url] = html
        browser.close()
    return pages


def scan_fpt():
    """Đọc dữ liệu nhúng sẵn trong trang danh sách theo hãng (/dien-thoai/<hãng>)."""
    urls = [f"https://fptshop.com.vn/dien-thoai/{p}" for p in FPT_BRAND_PAGES]
    pages, errors = {}, []
    try:  # thử đọc thẳng trước, nhanh hơn nhiều
        pages[urls[0]] = request("GET", urls[0], headers={"Accept": "text/html,application/xhtml+xml"}).text
        for url in urls[1:]:
            pages[url] = request("GET", url, headers={"Accept": "text/html,application/xhtml+xml"}).text
            time.sleep(1)
    except Exception as error:
        errors.append(str(error)[:120])
        print(f"  FPT đọc thẳng không được ({error}); chuyển sang trình duyệt thật.", flush=True)
        pages = fpt_pages_via_browser(urls)

    rows, seen = [], set()
    for html in pages.values():
        html = (html or "").replace('\\"', '"')
        for match in re.finditer(r'"currentPrice":(\d+)', html):
            back = html[max(0, match.start() - 2500):match.start()]
            slugs = list(re.finditer(r'"slug":"(dien-thoai/[a-z0-9-]+)(?:\?sku=\d+)?"', back))
            if not slugs:
                continue
            last = slugs[-1]
            slug = last.group(1)
            if slug in seen:
                continue
            origs = re.findall(r'"originalPrice":(\d+)', back[last.start():])
            names = re.findall(r'"(?:displayName|name)":"([^"]{3,80})"', back[:last.start()])
            name = names[-1] if names else slug.split("/")[-1].replace("-", " ")
            brand = brand_of(name, slug)
            price = int(match.group(1))
            if not brand or not price:
                continue
            seen.add(slug)
            rows.append(row("FPT Shop", brand, name, "https://fptshop.com.vn/" + slug,
                            price, int(origs[-1]) if origs else 0))
    if not rows:
        raise RuntimeError("không đọc được máy nào. " + "; ".join(errors))
    return rows


def scan_viettel():
    rows = []
    for page in range(1, 10):
        body = ("path=ProductList5Col2026&PaginationVisiable=0&CatID=010001&ManID=&Tags=&PageSize=100"
                f"&CurrentPage={page}&SpecOrder=DangHot&SpecFilter=&FeatureFilter=&PriceFrom=-1&PriceTo=-1&isHot=")
        html = request("POST", "https://viettelstore.vn/Site/_Sys/GetUserControlAsync.aspx",
                       headers={"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                                "X-Requested-With": "XMLHttpRequest",
                                "Referer": "https://viettelstore.vn/dien-thoai"}, data=body).text
        cards = BeautifulSoup(html, "html.parser").select(".product-info-container")
        for card in cards:
            a = card.select_one("a[data-name]")
            if a is None:
                continue
            name = re.sub(r"^Điện thoại\s+", "", a.get("data-name", ""))
            brand = brand_of(name)
            price_el, old_el = card.select_one(".price"), card.select_one(".price-old")
            price = money(price_el.get_text()) if price_el else 0
            if brand and price:
                rows.append(row("Viettel Store", brand, name, "https://viettelstore.vn" + a.get("href", ""),
                                price, money(old_el.get_text()) if old_el else 0))
        if len(cards) < 100:
            break
        time.sleep(1)
    return rows


def main():
    now = datetime.now(ZoneInfo("Asia/Ho_Chi_Minh"))
    rows, report = [], {}
    for name, fn in (("TGDĐ", scan_tgdd), ("CellphoneS", scan_cellphones),
                     ("FPT Shop", scan_fpt), ("Viettel Store", scan_viettel)):
        try:
            got = fn()
            rows += got
            report[name] = len(got)
            print(f"{name}: {len(got)} máy", flush=True)
        except Exception as error:  # một sàn lỗi không làm hỏng các sàn còn lại
            report[name] = f"lỗi: {error}"[:300]
            print(f"{name}: LỖI {error}", flush=True)
    if not rows:
        sys.exit("ERROR: không sàn nào đọc được, không lưu.")

    market = {"scans": []}
    if MARKET_JS.exists():
        text = MARKET_JS.read_text(encoding="utf-8")
        match = re.search(r"window\.MARKET\s*=\s*(\{.*\});", text, re.S)
        if match:
            market = json.loads(match.group(1))
    date = now.strftime("%d-%b")
    scan = {"date": date, "at": now.strftime("%H:%M"), "report": report, "rows": rows}
    market["scans"] = [s for s in market.get("scans", []) if s.get("date") != date] + [scan]
    market["scans"] = market["scans"][-KEEP_SCANS:]
    MARKET_JS.write_text("/* Tự sinh bởi scraper/scan_market.py, đừng sửa tay. */\n"
                         "window.MARKET = " + json.dumps(market, ensure_ascii=False, separators=(",", ":")) + ";\n",
                         encoding="utf-8")
    print(f"Đã lưu đợt {date} {scan['at']}: {len(rows)} máy. {report}")


if __name__ == "__main__":
    main()
