"""Quét giá điện thoại toàn thị trường (tab "Toàn thị trường" của web) — chỉ để tham khảo.

Lấy từ trang danh sách của 4 nhà bán lẻ, chỉ 6 hãng đang theo dõi
(Apple, Samsung, OPPO, Xiaomi gồm Redmi/POCO, Vivo, Realme):
  - TGDĐ:          POST /Category/FilterProductBox?c=42&pi=N (20 máy/trang)
  - CellphoneS:    GraphQL api.cellphones.com.vn, danh mục 3, chỉ hàng đang bán (stock 46)
  - FPT Shop:      mở /dien-thoai/<hãng> bằng trình duyệt thật (FPT chặn kết nối từ máy chủ)
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

import alerts

ROOT = Path(__file__).resolve().parent.parent
MARKET_JS = ROOT / "data" / "market.js"
LAST_JSON = ROOT / "data" / "market_last.json"  # giá lần quét trước, chỉ dùng để dò tăng giá
KEEP_SCANS = 20

CF_PROXY_URL = os.environ.get("CF_PROXY_URL", "").rstrip("/")
CF_PROXY_TOKEN = os.environ.get("CF_PROXY_TOKEN", "")
ERP_PORTAL_COOKIE = os.environ.get("ERP_PORTAL_COOKIE", "").strip()
# Trình duyệt cho FPT: có màn hình ảo (xvfb-run) thì để hiện, chạy máy thường thì ẩn.
HEADLESS = os.environ.get("DISPLAY", "") == ""
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


# Bóc từng thẻ sản phẩm ngay trên giao diện: tên ở <h3>, giá gạch ở .line-through,
# giá bán ở đoạn b1-semibold.
FPT_EXTRACT_JS = """() => {
  const money = s => +String(s || '').replace(/[^0-9]/g, '') || 0;
  return [...document.querySelectorAll('a[href^="/dien-thoai/"]')]
    .filter(a => a.querySelector('h3'))
    .map(a => ({
      n: a.querySelector('h3').textContent.trim(),
      u: a.getAttribute('href').split('?')[0],
      o: money((a.querySelector('.line-through') || {}).textContent),
      p: money((a.querySelector('p[class*="b1-semibold"]') || {}).textContent),
    }));
}"""

FPT_SHOW_ALL_JS = """async () => {
  const count = () => document.querySelectorAll('a[href^="/dien-thoai/"] h3').length;
  for (let i = 0; i < 10; i++) {
    const btn = [...document.querySelectorAll('button')]
      .find(b => /xem thêm/i.test(b.textContent) && b.offsetParent !== null);
    if (!btn) break;
    const before = count();
    btn.scrollIntoView({block: 'center'});
    btn.click();
    await new Promise(r => setTimeout(r, 2500));
    if (count() === before) break;
  }
  return count();
}"""


def parse_fpt_nextjs(html):
    """Trích xuất dữ liệu sản phẩm từ khối Next.js nhúng sẵn trong HTML của FPT Shop."""
    clean_html = html.replace(r'\"', '"')
    items = []
    seen = set()
    for m in re.finditer(r'"currentPrice":(\d+)', clean_html):
        pos = m.start()
        start = max(0, pos - 2500)
        back = clean_html[start:pos]
        slug_matches = list(re.finditer(r'"slug":"(dien-thoai/[a-z0-9-]+)(?:\?sku=\d+)?"', back))
        if not slug_matches:
            continue
        last_slug = slug_matches[-1].group(1)
        if last_slug in seen:
            continue
        seen.add(last_slug)
        after = back[slug_matches[-1].start():]
        orig_m = re.findall(r'"originalPrice":(\d+)', after)
        orig = int(orig_m[-1]) if orig_m else 0
        before = back[:slug_matches[-1].start()]
        names = re.findall(r'"(?:displayName|name)":"([^"]{3,80})"', before)
        name = names[-1] if names else last_slug.split("/")[-1]
        items.append({
            "n": name,
            "u": f"https://fptshop.com.vn/{last_slug}",
            "p": int(m.group(1)),
            "o": orig
        })
    return items


def fpt_rows_via_http():
    """Tải nhanh danh mục FPT Shop bằng HTTP request (qua Cloudflare proxy nếu có).
    Cực nhanh (1-2s/trang), không tốn RAM và tránh tải nặng Playwright."""
    rows, seen = [], set()
    fpt_headers = {
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
        "Referer": "https://fptshop.com.vn/",
        "sec-ch-ua": '"Chromium";v="138", "Not?A_Brand";v="8", "Google Chrome";v="138"',
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": '"Windows"',
        "sec-fetch-dest": "document",
        "sec-fetch-mode": "navigate",
        "sec-fetch-site": "same-origin",
        "upgrade-insecure-requests": "1",
    }
    for slug in FPT_BRAND_PAGES:
        url = f"https://fptshop.com.vn/dien-thoai/{slug}"
        items = []
        for attempt in range(2):
            try:
                resp = request("GET", url, headers=fpt_headers, timeout=30)
                if resp.status_code == 200 and "currentPrice" in resp.text:
                    items = parse_fpt_nextjs(resp.text)
                    if items:
                        break
            except Exception as e:
                if attempt == 1:
                    print(f"  FPT HTTP {slug} không thành công: {e}", flush=True)
                time.sleep(2)
        print(f"  FPT HTTP {slug}: {len(items)} máy", flush=True)
        for it in items:
            brand = brand_of(it["n"], it["u"])
            if not brand or not it["p"] or it["u"] in seen:
                continue
            seen.add(it["u"])
            rows.append(row("FPT Shop", brand, it["n"], it["u"], it["p"], it["o"]))
        time.sleep(1)
    return rows


def fpt_rows_via_browser():
    """FPT chặn mọi kết nối từ máy chủ bằng trang kiểm tra chống bot ("Just a moment").
    Mở bằng trình duyệt thật một lần để lấy cookie hợp lệ, kèm stealth script chống phát hiện
    automation, rồi tải 6 trang hãng."""
    from playwright.sync_api import sync_playwright

    rows, seen, failed = [], set(), []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=HEADLESS, args=[
            "--disable-blink-features=AutomationControlled", "--no-sandbox",
            "--disable-infobars", "--disable-dev-shm-usage"])
        context = browser.new_context(user_agent=UA, locale="vi-VN",
                                      timezone_id="Asia/Ho_Chi_Minh",
                                      viewport={"width": 1366, "height": 900})
        page = context.new_page()
        page.add_init_script("""
            Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
            window.chrome = { runtime: {} };
            Object.defineProperty(navigator, 'languages', { get: () => ['vi-VN', 'vi', 'en-US', 'en'] });
            Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
        """)

        passed = False
        for attempt in range(6):  # vượt trang kiểm tra, mỗi lần chờ tối đa 40 giây
            try:
                page.goto("https://fptshop.com.vn/dien-thoai/samsung",
                          wait_until="domcontentloaded", timeout=90000)
                page.wait_for_selector('a[href^="/dien-thoai/"] h3', timeout=40000)
                passed = True
                break
            except Exception as error:
                print(f"  FPT vượt trang kiểm tra lần {attempt + 1}: "
                      f"{page.title()[:40]} | {str(error)[:80]}", flush=True)
                page.wait_for_timeout(10000)
        if not passed:
            browser.close()
            raise RuntimeError("không vượt được trang kiểm tra chống bot của FPT")

        for slug in FPT_BRAND_PAGES:
            items = []
            for attempt in range(5):
                try:
                    page.goto(f"https://fptshop.com.vn/dien-thoai/{slug}",
                              wait_until="domcontentloaded", timeout=90000)
                    page.wait_for_selector('a[href^="/dien-thoai/"] h3', timeout=45000)
                    page.evaluate(FPT_SHOW_ALL_JS)
                    items = page.evaluate(FPT_EXTRACT_JS)
                except Exception as error:
                    print(f"  FPT {slug} lần {attempt + 1}: [{page.title()[:40]}] "
                          f"{str(error)[:80]}", flush=True)
                if items:
                    break
                page.wait_for_timeout(8000)
            print(f"  FPT Browser {slug}: {len(items)} máy", flush=True)
            if not items:
                failed.append(slug)
            for it in items:
                url_full = "https://fptshop.com.vn" + it["u"]
                brand = brand_of(it["n"], it["u"])
                if not brand or not it["p"] or url_full in seen:
                    continue
                seen.add(url_full)
                rows.append(row("FPT Shop", brand, it["n"], url_full, it["p"], it["o"]))
            page.wait_for_timeout(2000)
        browser.close()
    if failed:
        print(f"  FPT Browser không đọc được trang: {', '.join(failed)}", flush=True)
    return rows


def _parse_erp_portal_deals(deals):
    rows, seen = [], set()
    for it in deals:
        if it.get("category") != "Điện thoại":
            continue
        p = int(it.get("sale_price") or 0)
        o = int(it.get("original_price") or 0)
        u = it.get("url") or ""
        name = (it.get("name") or "").strip()
        brand = brand_of(name, u) or it.get("brand") or "Khác"
        if not u or not p or u in seen:
            continue
        seen.add(u)
        rows.append(row("FPT Shop", brand, name, u, p, o, it.get("promo_type") or "Khuyến mãi"))
    return rows


def fpt_rows_via_erp_api():
    """Tải dữ liệu FPT Shop từ API nội bộ promotion.erp-portal.vn nếu có ERP_PORTAL_COOKIE."""
    cookie = ERP_PORTAL_COOKIE
    if not cookie:
        local_file = ROOT / "data" / "fpt_portal_deals.json"
        if local_file.exists():
            try:
                deals = json.loads(local_file.read_text(encoding="utf-8"))
                return _parse_erp_portal_deals(deals)
            except Exception:
                pass
        return []

    url = "https://promotion.erp-portal.vn/api/deals?retailer=FPT%20Shop"
    headers = {
        "User-Agent": UA,
        "Accept": "application/json",
        "Cookie": cookie if "auth" in cookie else f"auth-token={cookie}",
    }
    resp = requests.get(url, headers=headers, timeout=30)
    if resp.status_code == 200:
        return _parse_erp_portal_deals(resp.json())
    print(f"  FPT ERP Portal trả về HTTP {resp.status_code}", flush=True)
    return []


def scan_fpt():
    """Chỉ lấy dữ liệu LIVE trong đợt quét này:
    1. Thử Retail Deal Crawler API nội bộ (promotion.erp-portal.vn) nếu có cookie/token.
    2. Thử HTTP NextJS request (nhanh, qua proxy nếu có cấu hình).
    3. Thử Playwright trình duyệt thật có stealth script.
    Nếu cả 3 cách live đều bị chặn, báo lỗi rõ ràng và để trống dữ liệu đợt này.
    Tuyệt đối KHÔNG lấy số cũ từ các ngày trước để tránh gây hiểu lầm về giá thực tế."""
    # 1. Thử Retail Deal Crawler API nội bộ
    try:
        rows = fpt_rows_via_erp_api()
        if len(rows) >= 15:
            print(f"  FPT thành công qua Retail Deal API: {len(rows)} máy", flush=True)
            return rows
    except Exception as e:
        print(f"  FPT Retail Deal API không thành công: {e}", flush=True)

    # 2. Thử HTTP NextJS request trực tiếp / qua proxy
    try:
        rows = fpt_rows_via_http()
        if len(rows) >= 15:
            print(f"  FPT thành công qua HTTP: {len(rows)} máy", flush=True)
            return rows
    except Exception as e:
        print(f"  FPT HTTP không thành công: {e}", flush=True)

    # 3. Thử Playwright trình duyệt thật có stealth chống bot
    try:
        rows = fpt_rows_via_browser()
        if len(rows) >= 15:
            print(f"  FPT thành công qua Browser: {len(rows)} máy", flush=True)
            return rows
    except Exception as e:
        print(f"  FPT Browser không thành công: {e}", flush=True)

    # Không đoán số, không dùng số cũ: để trống và báo lỗi đợt quét
    raise RuntimeError("FPT Shop chặn chống bot trong đợt này (không dùng dữ liệu cũ để tránh gây hiểu lầm)")


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

    # Dò giá gốc tăng so với lần quét trước (bất kể ngày nào).
    today, label, at = now.date().isoformat(), now.strftime("%d-%b"), now.strftime("%H:%M")
    old = {}
    if LAST_JSON.exists():
        old = json.loads(LAST_JSON.read_text(encoding="utf-8")).get("prices", {})
    ups = []
    for r in rows:
        key = r["r"] + "|" + r["u"]
        before = old.get(key)
        if before and r["o"] > before:
            ups.append({"r": r["r"], "b": r["b"], "n": r["n"], "old": before, "new": r["o"]})
    alerts.record("market", today, at, ups)
    LAST_JSON.write_text(json.dumps({"day": today, "at": at,
                                     "prices": {r["r"] + "|" + r["u"]: r["o"] for r in rows}},
                                    ensure_ascii=False), encoding="utf-8")
    print(f"Giá gốc tăng (toàn thị trường): {len(ups)}"
          + ("; " + "; ".join(f"{u['r']} {u['n']} {u['old']:,}→{u['new']:,}" for u in ups[:10]) if ups else ""),
          flush=True)

    # Tab "Toàn thị trường" chỉ để tham khảo nên cập nhật mỗi ngày; quy tắc chỉ lưu
    # thứ Hai/thứ Sáu là dành cho cột KM base của 91 SKU, không áp vào đây.
    market = {"scans": []}
    if MARKET_JS.exists():
        text = MARKET_JS.read_text(encoding="utf-8")
        match = re.search(r"window\.MARKET\s*=\s*(\{.*\});", text, re.S)
        if match:
            market = json.loads(match.group(1))
    scan = {"date": label, "at": at, "report": report, "rows": rows}
    market["scans"] = [s for s in market.get("scans", []) if s.get("date") != label] + [scan]
    market["scans"] = market["scans"][-KEEP_SCANS:]
    MARKET_JS.write_text("/* Tự sinh bởi scraper/scan_market.py, đừng sửa tay. */\n"
                         "window.MARKET = " + json.dumps(market, ensure_ascii=False, separators=(",", ":")) + ";\n",
                         encoding="utf-8")
    print(f"Đã lưu đợt {label} {at}: {len(rows)} máy. {report}")


if __name__ == "__main__":
    main()
