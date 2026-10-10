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
from html import unescape as html_unescape
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
LINKS_JS = ROOT / "data" / "links.js"
PROMOS_JS = ROOT / "data" / "promos.js"

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


_CATALOG = None


def catalog():
    """Toàn bộ đường dẫn điện thoại đang bán trên TGDĐ, lấy từ API danh mục (đọc được từ máy chủ,
    khác với trang tìm kiếm vốn dựng bằng JS). Chỉ tải một lần cho cả đợt quét."""
    global _CATALOG
    if _CATALOG is not None:
        return _CATALOG
    slugs = set()
    for page in range(30):
        try:
            resp = requests.post(
                f"https://www.thegioididong.com/Category/FilterProductBox?c=42&o=13&pi={page}",
                headers={**HEADERS, "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                         "X-Requested-With": "XMLHttpRequest",
                         "Referer": "https://www.thegioididong.com/dtdd"},
                data="IsParentCate=False&IsShowCompare=True&prevent=true", timeout=(10, 30))
            html = resp.json().get("listproducts") or ""
        except Exception:
            break
        links = BeautifulSoup(html, "html.parser").select("li.item[data-id] a.main-contain")
        if not links:
            break
        for a in links:
            href = (a.get("href") or "").split("?")[0].strip("/")
            if href.startswith("dtdd/"):
                slugs.add(href[len("dtdd/"):])
        time.sleep(1)
    _CATALOG = sorted(slugs)
    print(f"Danh mục TGDĐ: {len(_CATALOG)} đường dẫn điện thoại.", flush=True)
    return _CATALOG


#   Những từ phân biệt phiên bản: thừa một từ trong nhóm này là MÁY KHÁC, không phải đổi link.
VARIANT_WORDS = {"5g", "4g", "pro", "plus", "max", "ultra", "lite", "fe", "mini",
                 "s", "e", "t", "c", "x", "i", "f", "neo", "turbo", "edge", "air"}


def find_slug(old_slug):
    """TGDĐ hay đổi đường dẫn. Tìm lại máy đó trong danh mục bằng cách so bộ từ của đường dẫn.
    Đường dẫn mới phải chứa đủ mọi từ của đường dẫn cũ, và phần dư ra không được là từ phân biệt
    phiên bản — để không bao giờ nhảy nhầm từ bản thường sang bản 5G/Pro/Plus."""
    want = set(t for t in old_slug.split("-") if t)
    best = None
    for slug in catalog():
        have = set(t for t in slug.split("-") if t)
        if not want <= have:
            continue
        if (have - want) & VARIANT_WORDS:
            continue
        if best is None or len(slug) < len(best):
            best = slug
    return best


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
        page = soup.select_one("main")
        if page is None:
            # Không có khối sản phẩm: trang lỗi/chặn chứ không phải TGDĐ gỡ SKU.
            # Không được kết luận "ngừng kinh doanh" từ một trang mình còn không đọc được.
            return {"status": "no_price", "debug": "khong-co-main"}
        # Chỉ xét chữ trong khối sản phẩm, tránh bắt nhầm chữ ở mục "sản phẩm tương tự".
        text = page.get_text(" ", strip=True)
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


def retry_other_slug(url, bad_result, allowed):
    """Link hỏng thì đi tìm lại máy đó trong danh mục TGDĐ trước khi kết luận gì.
    Chỉ ghi "ngừng kinh doanh" khi chính trang sản phẩm nói vậy, không phải vì link cũ hỏng."""
    if not allowed:
        return bad_result
    old = url.rstrip("/").rsplit("/", 1)[-1].split("?")[0]
    new = find_slug(old)
    if not new or new == old:
        return bad_result
    print(f"  đường dẫn đổi: {old} -> {new}", flush=True)
    fresh = scan_one(f"https://www.thegioididong.com/dtdd/{new}", attempts=2, allow_retry_slug=False)
    if fresh.get("status") == "active":
        fresh["new_url"] = f"https://www.thegioididong.com/dtdd/{new}"
        return fresh
    return bad_result


def scan_one(url, attempts=3, allow_retry_slug=True):
    last_error, result = None, None
    for attempt in range(attempts):
        try:
            resp = http_get(url)
            if resp.status_code == 404:
                return retry_other_slug(url, {"status": "ngung_kd", "debug": "404"}, allow_retry_slug)
            resp.raise_for_status()
            resp.encoding = "utf-8"
            result = parse_page(resp.text)
            last_error = None
            # Bố cục trang trả về ngẫu nhiên, và đôi khi TGDĐ trả trang "ngừng kinh doanh"
            # cho máy chủ dù trang thật vẫn bán: tải lại trước khi tin kết quả xấu.
            if result["status"] in ("no_price", "ngung_kd") and attempt < attempts - 1:
                time.sleep(2)
                continue
            if result["status"] in ("no_price", "ngung_kd"):
                soup = BeautifulSoup(resp.text, "html.parser")
                h1 = soup.select_one("h1")
                result["debug"] = (f"len={len(resp.text)} box_main={bool(soup.select_one('.box_main'))} "
                                   f"main={bool(soup.select_one('main'))} h1={h1.get_text(strip=True)[:60] if h1 else None}")
                return retry_other_slug(url, result, allow_retry_slug)
            if result.get("status") == "active":
                result["subs"] = extract_promos(resp.text)
            return result
        except Exception as error:  # mạng chập chờn: thử lại có giãn cách
            last_error = error
            time.sleep(3 * (attempt + 1))
    if last_error is None and result is not None:
        return result
    return {"status": "error", "error": str(last_error)}


EXCLUDE_PROMO_RE = re.compile(r"(?i)thẻ tín dụng|mở thẻ|vpbank|máy lọc nước|máy đọc sách")


def extract_promos(html):
    """Trích xuất quà tặng và khuyến mãi phụ kiện trực tiếp từ trang TGDĐ."""
    if not html:
        return []
    items = []
    # 1. Bố cục Next.js spans (ưu đãi quà tặng, PMH phụ kiện, bảo hành...)
    for m in re.finditer(r'<span class=" \[&amp;_a\]:text-blue-500">([^<]+)</span>', html):
        text = html_unescape(m.group(1)).strip()
        text = re.sub(r"^(?:\d+[\.\s\-\:]+|[•\-\*]\s*)", "", text).strip()
        if text and not EXCLUDE_PROMO_RE.search(text) and text not in items:
            items.append(text)
    # 2. Bố cục cũ .content-promo
    for m in re.finditer(r'(?i)<div[^>]*class="[^"]*content-promo[^"]*"[^>]*>([^<]+)</div>', html):
        text = html_unescape(m.group(1)).strip()
        text = re.sub(r"^(?:\d+[\.\s\-\:]+|[•\-\*]\s*)", "", text).strip()
        if text and not EXCLUDE_PROMO_RE.search(text) and text not in items:
            items.append(text)
    return items


def write_promos_js(rows):
    """Cập nhật quà tặng & khuyến mãi phụ kiện TGDĐ vào data/promos.js."""
    promos = {}
    if PROMOS_JS.exists():
        try:
            content = PROMOS_JS.read_text(encoding="utf-8")
            start = content.find("{")
            end = content.rfind("}")
            if start != -1 and end != -1:
                promos = json.loads(content[start:end + 1])
        except Exception:
            promos = {}

    for r in rows:
        m = r.get("model")
        subs = r.get("subs")
        if not m:
            continue
        if m not in promos:
            promos[m] = {"name": m, "subs": subs or [], "offline_note": ""}
        elif subs:
            promos[m]["subs"] = subs
            promos[m]["name"] = m

    # Kế thừa quà tặng giữa các phiên bản bộ nhớ RAM/ROM cùng dòng máy
    for m, p in promos.items():
        if not p.get("subs"):
            base_name = re.sub(r"\s+\d+GB(?:/\d+GB)?.*$", "", m)
            for other_m, other_p in promos.items():
                if other_m != m and other_m.startswith(base_name) and other_p.get("subs"):
                    p["subs"] = list(other_p["subs"])
                    break

    now_str = datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).strftime("%d-%b %H:%M")
    text = (f"/* Tự động cào ưu đãi & quà tặng kèm từ Thế Giới Di Động */\n"
            f"/* Cập nhật: {now_str} */\n"
            f"window.PROMOS = {json.dumps(promos, ensure_ascii=False)};\n")
    PROMOS_JS.write_text(text, encoding="utf-8")


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
    keys = ("model", "rrp", "red", "pmh", "status", "online", "total_online",
            "choice", "kind", "rule")
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


def write_links_js(all_products):
    """Link trang sản phẩm để bấm thẳng từ web sang TGDĐ mà tra cứu."""
    links = {p["model"]: p["url"].strip() for p in all_products if p["url"].strip()}
    LINKS_JS.write_text(
        "/* Tự sinh bởi scraper/scan_tgdd.py, đừng sửa tay. */\n"
        "window.LINKS = " + json.dumps(links, ensure_ascii=False) + ";\n",
        encoding="utf-8")


def main():
    now = datetime.now(ZoneInfo("Asia/Ho_Chi_Minh"))
    parser = argparse.ArgumentParser(description="Quét PMH của các SKU đang theo dõi trên TGDĐ.")
    parser.add_argument("--only", default=os.environ.get("ONLY", ""),
                        help='Chỉ quét một phần: "missing" hoặc danh sách model cách nhau bằng dấu phẩy.')
    args = parser.parse_args()

    with PRODUCTS.open(encoding="utf-8-sig", newline="") as f:
        all_products = [p for p in csv.DictReader(f) if p["url"].strip()]
    write_links_js(all_products)
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
        # Mốc giờ của riêng từng dòng: quét một phần thì nhìn vào đây biết dòng nào mới, dòng nào cũ.
        row = {"model": product["model"], "url": product["url"],
               "at": datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).strftime("%d-%m %H:%M"), **result}
        if row["status"] != "active":
            row["pmh"] = None
        rows.append(row)
        print(f"[{i}/{len(products)}] {product['model']}: {result.get('status')} rrp={result.get('rrp')} "
              f"pmh={result.get('pmh')} online={result.get('online')} choice={result.get('choice')} "
              f"({result.get('kind', '')}/{result.get('rule', '')}) {result.get('debug', '')}", flush=True)
        time.sleep(1.5)

    # TGDĐ đổi đường dẫn thì ghi luôn link mới vào danh sách để lần sau khỏi phải dò lại.
    moved = {r["model"]: r["new_url"] for r in rows if r.get("new_url")}
    if moved:
        for p in all_products:
            if p["model"] in moved:
                p["url"] = moved[p["model"]]
        with PRODUCTS.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["model", "url"])
            writer.writeheader()
            writer.writerows({"model": p["model"], "url": p["url"]} for p in all_products)
        print("Đã cập nhật link mới: " + "; ".join(f"{m} -> {u}" for m, u in moved.items()), flush=True)

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
    write_promos_js(rows)
    print(f"Đã lưu đợt {scan['date']}: {ok}/{len(products)} SKU đọc được giá, {errors} lỗi mạng. "
          f"Tổng cộng {len(scan['rows'])} model trong đợt.")


if __name__ == "__main__":
    main()
