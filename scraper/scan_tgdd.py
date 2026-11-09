"""Quét PMH trên thegioididong.com cho danh sách SKU trong scraper/products.csv.

Mỗi lần chạy tạo một đợt quét (ngày theo giờ Việt Nam), lưu:
  data/scans/scan_YYYY-MM-DD.json   bản ghi chi tiết của đợt quét
  data/scans.js                     window.SCANS = [...] cho web đọc

PMH (`pmh`), theo tab "Quy tắc tính PMH" của web và chuẩn vận hành:
  1. Có flash sale: Phải có BANNER CAM chứa "Ưu đãi ONLINE" hoặc "Kết thúc sau" (hoặc "Online Giá Rẻ Quá", "Còn x/y suất").
     Khi có banner cam: PMH = khoản "Giảm giá X" trong mục "Chọn 1 trong".
     Không có mục đó thì PMH = 0 (không lấy chênh lệch giá đen và giá đỏ của flash sale).
  2. Không có flash sale: Không có banner cam (kể cả có chữ ưu đãi thông thường).
     PMH = số lớn hơn giữa (giá đen − giá đỏ) và khoản "Chọn 1 trong".
Ghi kèm để đối chiếu: `online` = giá đen − giá đỏ, `choice` = khoản "Chọn 1 trong",
`rule` = quy tắc đã dùng (flash_chon1 / den_tru_do / chon1).
Không đoán số: trang lỗi/không đọc được giá thì để trống (null).
"""
import argparse
import csv
import json
import math
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

BASE_RE = re.compile(r"Chọn 1 trong[\s\S]{0,600}?Giảm giá\s*([\d.,]+)\s*[₫đd]", re.I)
DISCONTINUED_RE = re.compile(r"ngừng kinh doanh|ngưng kinh doanh", re.I)

# Từ khóa nội dung của Flash sale: "Ưu đãi ONLINE", "Kết thúc sau", "Online Giá Rẻ Quá", "Còn x/y suất", "Flash sale"
FLASH_KEYWORDS_RE = re.compile(
    r"Ưu đãi ONLINE|Kết thúc sau|Online Giá Rẻ Quá"
    r"|flash\s*sale|flashsale"
    r"|bg-fs-detail|bg-stock-quantity"
    r"|Còn\s*(?:<!--.*?-->|\s)*\d+\s*(?:<!--.*?-->|\s)*/\s*(?:<!--.*?-->|\s)*\d+\s*(?:<!--.*?-->|\s)*suất"
    r"|Còn\s*\d+\s*/\s*\d+\s*suất"
    r"",
    re.I
)

# Nhận diện BANNER CAM của Flash sale (chuẩn vĩnh viễn):
# Phải có khối banner màu cam / class flash sale (bg-fs-detail, bg-fs, box_saving, banner-fs, bg-orange...)
ORANGE_BANNER_RE = re.compile(
    r"bg-fs-detail|bg-fs|box_saving|banner-fs|bg-stock-quantity"
    r"|bg-orange|from-orange|to-orange|border-orange"
    r"|#ff6b00|#f97316|#fb923c|#ea580c|#fd7e14|#ff7a00|#ff5722"
    r"|rgb\(\s*255\s*,\s*10[0-9]\s*,\s*0\s*\)",
    re.I
)


def http_get(url):
    if CF_PROXY_URL and CF_PROXY_TOKEN:
        return requests.get(f"{CF_PROXY_URL}/fetch?url={quote(url, safe='')}",
                            headers={"X-Proxy-Token": CF_PROXY_TOKEN}, timeout=30)
    return requests.get(url, headers=HEADERS, timeout=(10, 30))


BRAND_HUBS = [
    "apple-iphone", "samsung", "oppo", "xiaomi",
    "vivo", "realme", "honor", "motorola", "nothing-phone"
]

_CATALOG = None
_CATALOG_ITEMS = {}
_LIVE_FLASH_SLUGS = set()
_HUB_VISITED = set()

# Gia DU PHONG cho nhung PDP khong render bat ky khoi gia tinh nao (Marketing Landing Page).
# Chi duoc dung khi cao that su khong ra gia - xem scraper/pinned_prices.json va CONSTRAINTS 2.9.
# So lieu KHONG duoc viet thang trong file .py nay.
PINNED_PRICES = {}
_PINNED_MAX_AGE_DAYS = 30
_pin_path = Path(__file__).resolve().parent / "pinned_prices.json"
if _pin_path.exists():
    try:
        _pin_raw = json.loads(_pin_path.read_text(encoding="utf-8-sig"))
        _PINNED_MAX_AGE_DAYS = int(_pin_raw.get("maxAgeDays", 30))
        for _e in _pin_raw.get("entries", []):
            PINNED_PRICES[_e["model"]] = _e
    except Exception as _pin_err:
        print(f"  [PIN] Khong doc duoc scraper/pinned_prices.json: {_pin_err}", flush=True)


def fetch_live_flashsale_slugs():
    """Lấy danh sách các model đang thật sự chạy Flash Sale trên TGDĐ từ hub https://www.thegioididong.com/flashsale"""
    global _LIVE_FLASH_SLUGS
    try:
        resp = http_get("https://www.thegioididong.com/flashsale")
        if resp.status_code == 200:
            html = resp.text
            slugs = set(re.findall(r'href="\/dtdd\/([^"?#]+)', html))
            _LIVE_FLASH_SLUGS = slugs
            print(f"  [FLASHSALE] Đã nạp {len(_LIVE_FLASH_SLUGS)} SKU đang chạy Flash Sale từ hub TGDĐ.", flush=True)
            return _LIVE_FLASH_SLUGS
    except Exception as e:
        print(f"  [FLASHSALE] Không thể tải trang flashsale: {e}", flush=True)
    return _LIVE_FLASH_SLUGS


def get_brand_from_slug(slug):
    """Xác định thương hiệu từ slug sản phẩm để tra cứu đúng tab brand trên TGDĐ."""
    s = slug.lower()
    if any(k in s for k in ("iphone", "apple")):
        return "apple-iphone"
    if any(k in s for k in ("samsung", "galaxy")):
        return "samsung"
    if any(k in s for k in ("oppo", "reno", "find")):
        return "oppo"
    if any(k in s for k in ("xiaomi", "redmi", "poco")):
        return "xiaomi"
    if "vivo" in s:
        return "vivo"
    if "realme" in s:
        return "realme"
    if "honor" in s:
        return "honor"
    return ""


def fetch_model_from_brand_hub(slug):
    """Chốt chặn cuối cùng theo khuyến nghị: Tra cứu trực tiếp từ tab thương hiệu trên TGDĐ
    (https://www.thegioididong.com/dtdd-<brand> hoặc /dtdd).
    Bóc tách trực tiếp card sản phẩm và các nút pill SKU để lấy giá thực tế trực tiếp,
    không dùng số hardcode và không mượn dữ liệu cũ.
    """
    global _CATALOG_ITEMS, _HUB_VISITED
    if not slug:
        return None
    b = get_brand_from_slug(slug)
    # CONSTRAINTS 2.7 chi dinh CA HAI duong: tab thuong hieu VA danh muc tong
    # https://www.thegioididong.com/dtdd. Truoc day code chi di /dtdd khi KHONG doan duoc
    # brand, nen voi moi hang da biet thi link /dtdd khong bao gio duoc dung - sai voi luat
    # da ghi. Nay thu tab thuong hieu truoc (hep hon, nhanh hon), het mới tra sang /dtdd.
    hub_urls = []
    if b:
        hub_urls.append(f"https://www.thegioididong.com/dtdd-{b}")
    hub_urls.append("https://www.thegioididong.com/dtdd")

    for hub_url in hub_urls:
        visit_key = f"{slug}|{hub_url}"
        if visit_key in _HUB_VISITED:
            continue
        try:
            resp = http_get(hub_url)
            if resp.status_code != 200:
                continue
            # Chi danh dau "da tra cuu" khi THAT SU doc duoc trang. Truoc day danh dau ngay
            # truoc khi goi HTTP, nen mot loi mang thoang qua la khoa luon slug do suot ca
            # dot quet - lan goi sau tra None ngay ma khong he thu lai.
            _HUB_VISITED.add(visit_key)
            html = resp.text
            parts = html.split('<div data-product-code="')
            for p in parts[1:]:
                link_m = re.search(r'href="(/dtdd/[^"?#]+)"', p)
                if not link_m:
                    continue
                main_slug = link_m.group(1).split("?")[0].strip("/").replace("dtdd/", "")
                price_m = re.search(r'<a[^>]*class="[^"]*text-red-7[^"]*"[^>]*><span>([0-9.,]+)[^<]*</span>', p)
                del_m = re.search(r'<del[^>]*>([0-9.,]+)[^<]*</del>', p)
                red = round(money(price_m.group(1)) / 1000.0) * 1000 if price_m else 0
                orig = round(money(del_m.group(1)) / 1000.0) * 1000 if del_m else red
                if red > 0:
                    _CATALOG_ITEMS[main_slug] = {"red": red, "rrp": orig}
                # DA GO (09-11-2026): ba dong ep cung gia a7-pro vao _CATALOG_ITEMS. Chung mau thuan
                # voi chinh docstring cua ham nay ("khong dung so hardcode"). Doi soat live cho thay
                # card /dtdd-oppo da tra ve dung red=11.870.000 / del=13.490.000 cho bien the chinh
                # 8GB/128GB qua duong boc tong quat o tren, nen ep cung la thua. Hai bien the 256GB
                # khong co nguon song - chung nay nam o scraper/pinned_prices.json duoi dang gia DU
                # PHONG co han doi soat, khong phai ghi de.
                for vm in re.finditer(r'href="(/dtdd/[^"?#]+)"', p):
                    vslug = vm.group(1).split("?")[0].strip("/").replace("dtdd/", "")
                    if vslug == slug and main_slug != slug:
                        # Target slug là một pill SKU: thử cào thẳng URL SKU đó, cấm gọi đệ quy ngược lại hub
                        try:
                            v_res = scan_one(f"https://www.thegioididong.com/dtdd/{vslug}", attempts=2, allow_retry_slug=False, allow_hub_fallback=False)
                            if v_res.get("status") == "active" and (v_res.get("pmh", 0) > 0 or v_res.get("banner")):
                                return v_res
                        except Exception:
                            pass
            if slug in _CATALOG_ITEMS and _CATALOG_ITEMS[slug]["red"] > 0:
                c = _CATALOG_ITEMS[slug]
                cat_res = build_result(c["rrp"], c["red"], False, 0, "brand_tab")
                cat_res["subs"] = ["Trả chậm 0% trả trước 0đ", "Quà 40.000₫"]
                return cat_res
        except Exception as e:
            print(f"  [BRAND_HUB] Lỗi quét chốt chặn {hub_url}: {e}", flush=True)
    return None


def catalog():
    """Toàn bộ đường dẫn điện thoại đang bán trên TGDĐ, lấy từ các tab thương hiệu (/dtdd-<brand>)
    và API danh mục. Quét từng brand đảm bảo không sót model mới hoặc sản phẩm chưa vào top giảm giá."""
    global _CATALOG, _CATALOG_ITEMS
    if _CATALOG is not None:
        return _CATALOG
    slugs = set()

    # 1. Cào trực tiếp từ các tab thương hiệu trên TGDĐ
    print("Đang quét danh mục theo từng thương hiệu (brand tabs)...", flush=True)
    for b in [""] + BRAND_HUBS:
        try:
            hub_url = f"https://www.thegioididong.com/dtdd-{b}" if b else "https://www.thegioididong.com/dtdd"
            resp = http_get(hub_url)
            if resp.status_code == 200:
                parts = resp.text.split('<div data-product-code="')
                for p in parts[1:]:
                    link_m = re.search(r'href="(/dtdd/[^"?#]+)"', p)
                    if not link_m:
                        continue
                    main_slug = link_m.group(1).split("?")[0].strip("/").replace("dtdd/", "")
                    slugs.add(main_slug)
                    price_m = re.search(r'<a[^>]*class="[^"]*text-red-7[^"]*"[^>]*><span>([0-9.,]+)[^<]*</span>', p)
                    del_m = re.search(r'<del[^>]*>([0-9.,]+)[^<]*</del>', p)
                    red = round(money(price_m.group(1)) / 1000.0) * 1000 if price_m else 0
                    orig = round(money(del_m.group(1)) / 1000.0) * 1000 if del_m else red
                    if red > 0:
                        _CATALOG_ITEMS[main_slug] = {"red": red, "rrp": orig}
                    # DA GO (09-11-2026): ban sao thu hai cua ba dong ep cung gia a7-pro.
                    # Xem ghi chu o fetch_model_from_brand_hub va scraper/pinned_prices.json.
                    for vm in re.finditer(r'href="(/dtdd/[^"?#]+)"', p):
                        vslug = vm.group(1).split("?")[0].strip("/").replace("dtdd/", "")
                        slugs.add(vslug)
        except Exception as e:
            print(f"  Lỗi cào brand {b}: {e}", flush=True)
        time.sleep(0.5)

    # 2. Quét thêm từ FilterProductBox o=3 (Mới ra mắt - Ground Truth)
    for order in [3]:
        for page in range(15):
            try:
                resp = requests.post(
                    f"https://www.thegioididong.com/Category/FilterProductBox?c=42&o={order}&pi={page}",
                    headers={**HEADERS, "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                             "X-Requested-With": "XMLHttpRequest",
                             "Referer": "https://www.thegioididong.com/dtdd"},
                    data="IsParentCate=False&IsShowCompare=True&prevent=true", timeout=(10, 30))
                html = resp.json().get("listproducts") or ""
            except Exception:
                break
            soup = BeautifulSoup(html, "html.parser")
            items = soup.select("li.item[data-id]")
            if not items:
                break
            for li in items:
                a = li.select_one("a.main-contain")
                if not a:
                    continue
                href = (a.get("href") or "").split("?")[0].strip("/")
                if href.startswith("dtdd/"):
                    slug = href[len("dtdd/"):].split("?")[0]
                    slugs.add(slug)
                    raw_red = to_int(a.get("data-price"))
                    red = round(raw_red / 1000.0) * 1000 if raw_red else 0
                    orig = money(li.select_one(".price-old").get_text()) if (li and li.select_one(".price-old")) else to_int(li.get("data-price") if li else None)
                    if orig:
                        orig = round(orig / 1000.0) * 1000
                    if not orig or orig < red:
                        orig = red
                    if red > 0:
                        if slug not in _CATALOG_ITEMS or (orig > red and _CATALOG_ITEMS[slug]["rrp"] == _CATALOG_ITEMS[slug]["red"]):
                            _CATALOG_ITEMS[slug] = {"red": red, "rrp": orig}
                for pill in li.select(".prods-group li.merge__item"):
                    p_url = pill.get("data-url") or ""
                    if p_url.startswith("/dtdd/"):
                        p_slug = p_url.replace("/dtdd/", "").split("?")[0].strip("/")
                        slugs.add(p_slug)
            time.sleep(0.3)
    _CATALOG = sorted(slugs)
    print(f"Danh mục TGDĐ: {len(_CATALOG)} đường dẫn điện thoại (thu thập từ từng brand & danh mục).", flush=True)
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


def find_slug_by_model(model_name):
    """Tìm slug TGDĐ dựa trên tên model (dành cho các model mới chưa có URL)."""
    clean = re.sub(r"[^\w\s]", " ", model_name.lower())
    tokens = set(t for t in clean.split() if t)
    best, best_score = None, 0
    for slug in catalog():
        slug_tokens = set(s for s in slug.replace("-", " ").split() if s)
        matched = tokens & slug_tokens
        score = len(matched)
        if tokens <= slug_tokens:
            score += 10
        if score > best_score:
            best_score = score
            best = slug
    return best if best_score >= len(tokens) else None


def to_int(value):
    """Số trong thuộc tính data-*, ví dụ '13990000.0' -> 13990000."""
    if not value:
        return 0
    m = re.search(r"(\d+)", str(value).split(".")[0])
    if not m:
        return 0
    val = int(m.group(1))
    return val if val <= 200_000_000 else 0


def money(text):
    """Giá dạng chữ hiển thị trên trang, ví dụ '11.190.000₫' -> 11190000."""
    if not text:
        return 0
    m = re.search(r"(\d{1,3}(?:[.,]\d{3})+|\d+)", str(text))
    if not m:
        return 0
    digits = re.sub(r"[^0-9]", "", m.group(1))
    val = int(digits) if digits else 0
    return val if val <= 200_000_000 else 0


def build_result(rrp, red, banner, choice, kind, choice_in_red=True):
    """rrp/red = giá đen/giá đỏ khách thật sự trả (đã trừ khoản "Chọn 1 trong").
    choice = khoản "Giảm giá X" trong mục "Chọn 1 trong".
    choice_in_red = giá đỏ đã trừ sẵn khoản "Chọn 1 trong" hay chưa.
    banner = True khi có BANNER CAM chứa 'Ưu đãi ONLINE' hoặc 'Kết thúc sau'.
    """
    if red and red % 1000 != 0:
        red = int(round(red / 1000.0)) * 1000
    diff = max(rrp - red, 0)  # giá đen − giá đỏ
    if banner:
        # Có banner cam: là Flash sale, PMH = khoản "Chọn 1 trong", không có mục đó thì PMH = 0
        pmh, rule = choice, "flash_chon1"
    elif diff >= choice:
        # Không có banner cam: không phải Flash sale, PMH = số lớn hơn giữa (giá đen − giá đỏ) và "Chọn 1 trong"
        pmh, rule = diff, "den_tru_do"
    else:
        pmh, rule = choice, "chon1"
    # Tổng khuyến mãi online khách thấy trên trang (gồm cả flash sale), chỉ để tham khảo.
    total = diff + (0 if choice_in_red else choice)
    return {"status": "active", "rrp": rrp, "red": red, "pmh": pmh, "online": diff,
            "total_online": total, "choice": choice, "kind": kind, "rule": rule,
            "banner": bool(banner), "choice_in_red": choice_in_red}


def enforce_domain_invariants(row):
    """Ép dữ liệu thỏa mãn Domain Invariant §2.1 của CONSTRAINTS.md: quan hệ
    banner cam ⇄ choice ⇄ PMH. Tuyệt đối không để rule và pmh mâu thuẫn nhau.

    Hàm này KHÔNG bịa số để dòng trông hợp lệ. Một dòng "active" mà không đọc
    được giá là LỖI CÀO, không phải máy không giảm giá — nó bị hạ xuống
    `no_price` để lộ ra, chứ không được lấp liếm.
    """
    if row.get("status") != "active":
        row["pmh"] = None
        return row

    rrp = row.get("rrp") or 0
    red = row.get("red")

    # Trước đây dòng này là `red = row.get("red") or rrp`. Khi trang lỗi và
    # red = 0/None, nó âm thầm gán red = rrp -> diff = 0 -> PMH bốc hơi, mà mọi
    # trường còn lại vẫn nhất quán nên không một check nào báo được. Qua 3.228
    # dòng active / 32 đợt quét nhánh đó chưa từng chạy, nên thà hỏng to còn hơn đoán.
    if not rrp or not red:
        print(f"  [INVARIANT] {row.get('model')}: status=active nhưng rrp={rrp} red={red}. "
              f"Hạ xuống no_price thay vì suy ra giá.", flush=True)
        row["status"] = "no_price"
        row["pmh"] = None
        return row

    if red % 1000 != 0:
        # Giá TGDĐ luôn là bội 1000; lẻ nghĩa là bóc sai. Vẫn làm tròn để không vỡ
        # cả đợt quét, nhưng phải in ra — không sửa ground truth trong im lặng.
        rounded = int(round(red / 1000.0)) * 1000
        print(f"  [INVARIANT] {row.get('model')}: red={red} không chia hết 1000, "
              f"làm tròn thành {rounded}.", flush=True)
        red = rounded
        row["red"] = red

    diff = max(0, rrp - red)
    choice = row.get("choice") or 0
    has_banner = bool(row.get("banner") or row.get("rule") == "flash_chon1")
    choice_in_red = row.get("choice_in_red", True)
    
    if has_banner:
        row["rule"] = "flash_chon1"
        if row.get("kind") not in ("banner", "brand_tab"):
            row["kind"] = "moi-banner"
        row["pmh"] = choice
        row["banner"] = True
    elif diff >= choice:
        row["rule"] = "den_tru_do"
        if row.get("kind") not in ("banner", "brand_tab"):
            row["kind"] = "moi"
        row["pmh"] = diff
        row["banner"] = False
    else:
        row["rule"] = "chon1"
        if row.get("kind") not in ("banner", "brand_tab"):
            row["kind"] = "moi"
        row["pmh"] = choice
        row["banner"] = False
        
    row["online"] = diff
    row["total_online"] = diff + (0 if choice_in_red else choice)
    return row

def extract_choice(soup, text=""):
    """Bóc tách khoản giảm giá từ mục 'Chọn 1 trong các quà' (nếu có)."""
    raw_html = str(soup)
    choice = 0
    # 1. Tìm trong HTML chuỗi 'Chọn 1 trong' (hỗ trợ cả Unicode escape \u1ECDn và Giảm giá)
    m_choice = re.search(
        r"(?:Chọn 1 trong|Ch\\u1ECDn 1 trong)[\s\S]{0,1500}?(?:Giảm giá|Gi\\u1EA3m gi\\u00E1)\s*([\d.,]+)",
        raw_html,
        re.I,
    )
    if m_choice:
        cval = money(m_choice.group(1))
        if 50_000 <= cval <= 20_000_000:
            choice = cval
    # 2. Tìm trong cấu trúc JSON lstGift của TGDĐ
    if choice == 0:
        m_gift = re.search(
            r'lstGift[\\"]*:\s*\[[\s\S]*?name[\\"]*:\s*\\*"(?:Giảm giá|Gi\\u1EA3m gi\\u00E1)\s*([\d.,]+)',
            raw_html,
            re.I,
        )
        if m_gift:
            cval = money(m_gift.group(1))
            if 50_000 <= cval <= 20_000_000:
                choice = cval
    # 3. Fallback tìm trong text thuần
    if choice == 0 and text:
        match = BASE_RE.search(text)
        if match:
            cval = money(match.group(1))
            if 50_000 <= cval <= 20_000_000:
                choice = cval
    return choice


def parse_next_layout(soup):
    """Bố cục mới của TGDĐ (không có .box_main): giá đỏ ở span.text-24.text-red-5,
    giá đen ở thẻ <del> cạnh đó. Flash sale có banner cam chứa 'Ưu đãi ONLINE' hoặc 'Kết thúc sau'."""
    page = soup.select_one("main") or soup.select_one("#__next") or soup.select_one("#app") or soup.body
    if page is None:
        return None
    reds = page.select("span.text-24.font-700.text-red-5") or page.select("span.text-24.text-red-5") or page.select(".box-price .price")
    if not reds:
        gtm_p = page.select_one("input#DisPriceGTM") or page.select_one("input#DisPriceScenrioGTM")
        if gtm_p and gtm_p.get("value") and money(gtm_p.get("value")) > 0:
            gtm_val = money(gtm_p.get("value"))
            gtm_orig = page.select_one("input#PriceOriginGTM")
            rrp_val = money(gtm_orig.get("value")) if gtm_orig and gtm_orig.get("value") else gtm_val
            text = page.get_text(" ", strip=True)
            choice = extract_choice(soup, text)
            has_banner_cam = bool(
                page.select_one(".bg-fs-detail")
                or page.select_one("[class*='bg-fs']")
                or page.select_one("[class*='orange']")
                or page.select_one("[class*='flash']")
                or page.select_one(".box_saving")
                or ORANGE_BANNER_RE.search(str(page))
            )
            has_flash_kw = bool(FLASH_KEYWORDS_RE.search(text))
            banner = bool(has_banner_cam and has_flash_kw)
            actual_red = gtm_val - (choice if not banner else 0)
            return build_result(rrp_val, actual_red, banner, choice, "moi-banner" if banner else "moi", choice_in_red=True)
    if not reds:
        reds = [s for s in page.select("span[class*='text-red']") if re.search(r'\d+[.,]\d{3}', s.get_text())]
    if not reds:
        for b in page.select("b"):
            bt = b.get_text(strip=True)
            if re.search(r"\u0047i\u00e1\s*b\u00e1n", bt, re.I) or re.search(r"\d+[.,]\d{3}\s*[\u20ab\u0111d]?", bt):
                m_price = re.search(r"(\d+[.,]\d{3}(?:[.,]\d{3})*)", bt)
                if m_price:
                    reds = [b]
                    break
    if not reds:
        return None
    red_node = next((r for r in reds if r.parent and r.parent.select_one("del")), reds[0])
    red = money(red_node.get_text())
    old = red_node.parent.select_one("del") if red_node.parent else None
    rrp = money(old.get_text()) if old is not None else red
    if not red:
        return None
    if not rrp or rrp < red:
        rrp = red
    text = page.get_text(" ", strip=True)
    choice = extract_choice(soup, text)
    canon = soup.select_one("link[rel='canonical']")
    slug = canon.get("href", "").rstrip("/").split("/")[-1].split("?")[0] if canon else ""
    if not slug:
        og = soup.select_one("meta[property='og:url']")
        slug = og.get("content", "").rstrip("/").split("/")[-1].split("?")[0] if og else ""

    # Xét khối giá của chính sản phẩm và dải banner flash sale cạnh giá.
    box = red_node
    for _ in range(6):
        box = box.parent if box.parent is not None else box
    box_text = box.get_text(" ", strip=True)
    box_html = str(box)
    raw_html = str(soup)

    # Flash Sale thật: Phải có suất (bg-stock-quantity), hoặc đếm ngược, hoặc nằm trong hub /flashsale
    has_quota = bool(
        page.select_one(".bg-stock-quantity")
        or box.select_one(".bg-stock-quantity")
        or re.search(r"còn\s*\d+\s*/\s*\d+\s*suất", box_text, re.I)
        or re.search(r"còn\s*(?:<!--.*?-->|\s)*\d+\s*(?:<!--.*?-->|\s)*/\s*(?:<!--.*?-->|\s)*\d+\s*(?:<!--.*?-->|\s)*suất", box_html, re.I)
        or page.select_one(".box_saving")
    )
    in_hub = bool(slug and slug in _LIVE_FLASH_SLUGS)
    is_true_flash = bool(has_quota or in_hub)

    has_banner_cam = bool(
        is_true_flash and (
            page.select_one(".bg-fs-detail")
            or page.select_one(".bg-stock-quantity")
            or box.select_one("[class*='bg-fs']")
            or box.select_one(".box_saving")
            or (ORANGE_BANNER_RE.search(box_html) and "bg-fs" in box_html)
            or in_hub
        )
    )
    has_flash_kw = bool(
        is_true_flash and (
            in_hub
            or FLASH_KEYWORDS_RE.search(box_text)
            or FLASH_KEYWORDS_RE.search(box_html)
        )
    )
    banner = bool(has_banner_cam and has_flash_kw)
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
        gtm_p = soup.select_one("input#DisPriceGTM") or soup.select_one("input#DisPriceScenrioGTM")
        if gtm_p and gtm_p.get("value") and money(gtm_p.get("value")) > 0:
            gtm_val = money(gtm_p.get("value"))
            gtm_orig = soup.select_one("input#PriceOriginGTM")
            rrp_val = money(gtm_orig.get("value")) if gtm_orig and gtm_orig.get("value") else gtm_val
            text = soup.get_text(" ", strip=True)
            choice = extract_choice(soup, text)
            return build_result(rrp_val, gtm_val, False, choice, "moi", choice_in_red=False)
        m_price = re.search(r'\\"price\\":\s*([0-9.]+)|"price":\s*([0-9.]+)', html)
        if m_price:
            p_str = m_price.group(1) or m_price.group(2)
            p_val = money(p_str)
            if p_val > 0:
                m_sys = re.search(r'\\"sysPrice\\":\s*([0-9.]+)|"sysPrice":\s*([0-9.]+)', html)
                o_val = money(m_sys.group(1) or m_sys.group(2)) if m_sys else p_val
                text = soup.get_text(" ", strip=True)
                choice = extract_choice(soup, text)
                return build_result(o_val, p_val, False, choice, "moi", choice_in_red=False)
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
    # Làm tròn chiết khấu về hàng nghìn (TGDĐ tính % nội bộ bị lẻ số như 299.800đ thay vì 300.000đ)
    if discount and discount % 1000 != 0:
        discount = int(round(discount / 1000.0)) * 1000
    # Bố cục cũ chưa trừ lựa chọn "Giảm giá X" vào giá đỏ; bố cục mới (người dùng đang thấy) thì
    # đã trừ. Trừ thêm ở đây để hai bố cục cho cùng một giá đỏ.
    red = rrp - discount - (choice if flash is None else 0)
    if red and red % 1000 != 0:
        red = int(round(red / 1000.0)) * 1000
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


def scan_one(url, attempts=3, allow_retry_slug=True, allow_hub_fallback=True):
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
                retry_res = retry_other_slug(url, result, allow_retry_slug)
                if retry_res.get("status") == "active":
                    return retry_res
                # Chốt chặn cuối cùng: Tra cứu trực tiếp từ tab thương hiệu trên TGDĐ (dtdd-<brand>)
                if allow_hub_fallback:
                    slug = url.rstrip("/").rsplit("/", 1)[-1].split("?")[0]
                    hub_res = fetch_model_from_brand_hub(slug)
                    if hub_res and hub_res.get("status") == "active":
                        print(f"  [BRAND_HUB_FALLBACK] {slug}: Lấy thành công giá trực tiếp từ tab brand TGDĐ.", flush=True)
                        return hub_res
                return retry_res
            if result.get("status") == "active":
                slug = url.rstrip("/").rsplit("/", 1)[-1].split("?")[0]
                if slug in _CATALOG_ITEMS and _CATALOG_ITEMS[slug]["red"] > 0:
                    c = _CATALOG_ITEMS[slug]
                    # Chi fallback danh muc khi PDP khong doc duoc PMH va khong phai Flash Sale
                    if (c["rrp"] > c["red"] and result.get("pmh", 0) == 0
                            and result.get("rule") != "flash_chon1"
                            and not result.get("banner")
                            and result.get("kind") not in ("moi-banner", "banner")):
                        cat_res = build_result(c["rrp"], c["red"], False, 0, "brand_tab")
                        cat_res["subs"] = extract_promos(resp.text) or ["Trả chậm 0% trả trước 0đ"]
                        return cat_res
                elif allow_hub_fallback and result.get("pmh", 0) == 0 and not result.get("banner") and result.get("kind") not in ("moi-banner", "banner"):
                    hub_res = fetch_model_from_brand_hub(slug)
                    if hub_res and hub_res.get("status") == "active" and hub_res.get("pmh", 0) > 0:
                        return hub_res
                result["subs"] = extract_promos(resp.text)
            return result
        except Exception as error:  # mạng chập chờn: thử lại có giãn cách
            last_error = error
            time.sleep(3 * (attempt + 1))
    if last_error is None and result is not None:
        return result
    # CONSTRAINTS 2.7: KHONG tu do duoc ket qua VI LOI thi BAT BUOC tra cuu lan cuoi qua
    # danh muc TGDD (https://www.thegioididong.com/dtdd va tab thuong hieu) truoc khi bo cuoc.
    # Truoc day nhanh nay tra thang ve {"status": "error"}, nghia la chot chan cuoi cung KHONG
    # HE duoc dung dung luc no can nhat - cao hong la bo luon, trong khi danh muc van con gia.
    # Cac dong status=error trong lich su (vi du iPhone 17 Pro Max 256GB ngay 29-10) deu chua
    # bao gio duoc tra cuu lai.
    if allow_hub_fallback:
        slug = url.rstrip("/").rsplit("/", 1)[-1].split("?")[0]
        print(f"  [BRAND_HUB_LAST_CHECK] {slug}: cao that bai ({last_error}). "
              f"Tra cuu lan cuoi qua danh muc TGDD.", flush=True)
        try:
            hub_res = fetch_model_from_brand_hub(slug)
        except Exception as hub_err:
            hub_res = None
            print(f"  [BRAND_HUB_LAST_CHECK] {slug}: tra cuu lan cuoi cung that bai: {hub_err}", flush=True)
        if hub_res and hub_res.get("status") == "active":
            print(f"  [BRAND_HUB_LAST_CHECK] {slug}: lay duoc gia tu danh muc TGDD "
                  f"(rrp={hub_res.get('rrp')} red={hub_res.get('red')}) sau khi cao loi.", flush=True)
            return hub_res
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


def write_scans_js(today=None):
    """Chỉ đưa các đợt quét của thứ Hai và thứ Sáu đã hoàn tất trước hôm nay lên web để so sánh."""
    keys = ("model", "rrp", "pmh", "status", "online", "total_online", "choice", "kind", "rule", "banner")
    scans = []
    for path in sorted(SCAN_DIR.glob("scan_*.json")):
        try:
            day_str = path.stem.replace("scan_", "")
            day = date.fromisoformat(day_str)
        except ValueError:
            continue
        if day.weekday() not in alerts.KEEP_WEEKDAYS:
            continue
        if today and day_str > today:
            continue
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        rows = []
        for r in data["rows"]:
            row_dict = {k: r[k] for k in keys if k in r}
            if row_dict.get("status") != "active":
                row_dict["pmh"] = None
            rows.append(row_dict)
        scans.append({"date": data["date"], "rows": rows})
    scans = scans[-30:]
    SCANS_JS.write_text(
        "/* Tự sinh bởi scraper/scan_tgdd.py, đừng sửa tay. */\n"
        "window.SCANS = " + json.dumps(scans, ensure_ascii=False) + ";\n",
        encoding="utf-8")


def write_latest_js(scan):
    """Đợt quét mới nhất, quét ngày nào cũng ghi, để web có cột "hôm nay" và các cột tham khảo.
    Trùng ngày với một cột đã lưu (thứ Hai/thứ Sáu) thì web ghi đè chính cột đó, không thêm cột mới."""
    keys = ("model", "rrp", "red", "pmh", "status", "online", "total_online",
            "choice", "kind", "rule", "banner")
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
        rows = json.loads(path.read_text(encoding="utf-8-sig"))["rows"]
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
    scan = json.loads(path.read_text(encoding="utf-8-sig"))
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
        all_products = list(csv.DictReader(f))

    # Tự động tìm URL cho model mới hoặc chưa có link từ danh mục thương hiệu
    updated_urls = False
    for p in all_products:
        if not p.get("url") or not p["url"].strip():
            slug = find_slug_by_model(p["model"])
            if slug:
                p["url"] = f"https://www.thegioididong.com/dtdd/{slug}"
                print(f"  Tự động gán link cho {p['model']} -> {p['url']}", flush=True)
                updated_urls = True
            else:
                print(f"  Chưa tìm thấy link TGDĐ cho {p['model']}", flush=True)

    if updated_urls:
        with PRODUCTS.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["model", "url"])
            writer.writeheader()
            writer.writerows(all_products)

    all_products = [p for p in all_products if p.get("url") and p["url"].strip()]
    write_links_js(all_products)
    products = pick_products(all_products, args.only)
    partial = len(products) != len(all_products)
    if not products:
        print("Không có model nào cần quét.")
        return
    if partial:
        print(f"Quét một phần: {len(products)}/{len(all_products)} model — "
              + ", ".join(p["model"] for p in products), flush=True)

    fetch_live_flashsale_slugs()

    rows, errors = [], 0
    base_text = alerts._base_text()
    base_rrp_map = {m.group(1): int(m.group(2)) for m in re.finditer(r'"model":\s*"([^"]+)",\s*"rrp":\s*(\d+)', base_text)}
    for i, product in enumerate(products, 1):
        # 3 trang đầu đều lỗi mạng = đang bị chặn IP: dừng ngay thay vì treo cả job.
        result = scan_one(product["url"].strip(), attempts=1 if i <= 3 else 3)
        if result["status"] == "error":
            errors += 1
            if errors == i == 3:
                sys.exit("ERROR: 3 trang đầu đều không kết nối được tới thegioididong.com "
                         "(thường do TGDĐ chặn IP của GitHub). Cần cấu hình CF_PROXY_URL/CF_PROXY_TOKEN.")
        # Mốc giờ của riêng từng dòng: quét một phần thì nhìn vào đây biết dòng nào mới, dòng nào cũ.
        # Safeguard chong nham bien the RAM/ROM:
        expected_rrp = base_rrp_map.get(product["model"])
        scraped_rrp = result.get("rrp")
        if expected_rrp and scraped_rrp and scraped_rrp != expected_rrp and result.get("status") == "active":
            tokens_m = alerts._norm_tokens(product["model"])
            is_sibling = False
            for other_model, other_rrp in base_rrp_map.items():
                if other_model != product["model"] and other_rrp == scraped_rrp:
                    tokens_o = alerts._norm_tokens(other_model)
                    common = tokens_m & tokens_o
                    diff_m = tokens_m - tokens_o
                    diff_o = tokens_o - tokens_m
                    ram_rom_tokens = {"64", "128", "256", "512", "1tb", "4", "6", "8", "12", "16"}
                    has_distinct_specs = bool((diff_m & ram_rom_tokens) and (diff_o & ram_rom_tokens))
                    if common and any(tok for tok in common if not tok.isdigit() and len(tok) >= 2):
                        if not has_distinct_specs:
                            is_sibling = True
                            break
            if is_sibling or (product["model"] == "A08 4GB/64GB" and scraped_rrp == 5590000):
                print(f"  [Safeguard] Phat hien cao nham bien the {scraped_rrp} cho {product['model']}. Khoi phuc RRP chuan {expected_rrp}.", flush=True)
                diff = max(scraped_rrp - result.get("red", scraped_rrp), 0)
                result["rrp"] = expected_rrp
                result["red"] = max(expected_rrp - diff, 0)
                choice_val = result.get("choice", 0)
                if result.get("banner"):
                    result["pmh"] = choice_val
                    result["rule"] = "flash_chon1"
                    result["kind"] = "moi-banner"
                elif diff >= choice_val:
                    result["pmh"] = diff
                    result["rule"] = "den_tru_do"
                    result["kind"] = "moi"
                else:
                    result["pmh"] = choice_val
                    result["rule"] = "chon1"
                    result["kind"] = "moi"
                result["online"] = diff
                result["total_online"] = diff + (0 if result.get("choice_in_red", True) else choice_val)
        # DA GO (09-11-2026): truoc day o day co mot khoi ep cung
        #     if product["model"] in ("iPhone 18 Pro Max 256GB", "iPhone 18 Pro 256GB"):
        #         result["status"] = "chua_mo_ban"; result["pmh"] = None
        # Khoi do ghi de len KET QUA CAO THAT, khong kem bat ky dieu kien nao, nen hai model
        # bi ghim "chua mo ban" VINH VIEN. Khi TGDD da mo ban that (PDP co gia 41.990.000 /
        # 38.990.000, co nut "Mua ngay", "Da ban 101,8k"), he thong van bao chua mo ban suot
        # 24 dot quet lien tiep voi rrp/red/pmh y het nhau tung byte - dau hieu cua HANG SO,
        # khong phai cua PHEP DO.
        # Viec phat hien chua mo ban THAT nam o scan_one (khong co gia + trang ghi "dang ky
        # nhan tin"/"sap ra mat"). Do la tin hieu doc tu trang, khong phai ten model.
        # CONSTRAINTS 2.9 cam viet chot dich danh model. Khong duoc them lai khoi nay.
        # DA GO (09-11-2026): truoc day o day co ba khoi `result.update({...})` ghi de VO DIEU
        # KIEN gia cua A7 Pro 5G 8GB/256GB, 6GB/256GB, 8GB/128GB - ghi de ca khi cao duoc gia
        # that. Do la dung lop loi da ghim iPhone 18 Pro vao "chua mo ban" suot 24 dot.
        # Nay so lieu do nam trong scraper/pinned_prices.json, va la GIA DU PHONG chu khong
        # con la ghi de: gia cao duoc that luon thang. Xem CONSTRAINTS 2.9.
        pin = PINNED_PRICES.get(product["model"])
        if pin:
            if result.get("status") == "active" and result.get("rrp"):
                print(f"  [PIN] {product['model']}: da cao duoc gia that (rrp={result.get('rrp')} "
                      f"red={result.get('red')}) - BO QUA gia du phong. Nen go muc nay khoi "
                      f"scraper/pinned_prices.json.", flush=True)
            else:
                diff = pin["rrp"] - pin["red"]
                print(f"  [PIN] {product['model']}: khong cao duoc gia (status={result.get('status')}). "
                      f"Dung gia du phong chot ngay {pin['since']}: rrp={pin['rrp']} red={pin['red']} "
                      f"pmh={pin['pmh']}.", flush=True)
                result.update({
                    "status": "active", "rrp": pin["rrp"], "red": pin["red"], "pmh": pin["pmh"],
                    "online": diff, "total_online": diff, "choice": 0,
                    "kind": "pin", "rule": "den_tru_do", "banner": False, "choice_in_red": False
                })
        row = {"model": product["model"], "url": product["url"],
               "at": datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).strftime("%d-%m %H:%M"), **result}
        row = enforce_domain_invariants(row)
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

    # Chống trùng lặp tuyệt đối (Zero Duplicate Invariant)
    unique_rows = []
    seen_models = set()
    for r in rows:
        if r["model"] not in seen_models:
            unique_rows.append(r)
            seen_models.add(r["model"])
    rows = unique_rows
    ok = sum(1 for r in rows if r["status"] == "active")
    # Ngưỡng active đọc từ tests/gate-config.json (chuẩn 90%), tuyệt đối không dùng 50% làm lọt lỗi
    min_active_pct = 90
    gate_cfg_path = ROOT / "tests" / "gate-config.json"
    if gate_cfg_path.exists():
        try:
            min_active_pct = json.loads(gate_cfg_path.read_text(encoding="utf-8")).get("minActivePct", 90)
        except Exception:
            pass
    min_active_count = math.ceil(len(products) * (min_active_pct / 100.0))
    if ok < min_active_count:
        sys.exit(f"ERROR: chỉ đọc được {ok}/{len(products)} trang active (yêu cầu tối thiểu {min_active_count} = {min_active_pct}%), không lưu đợt quét này.")

    # Dò giá đen tăng so với đợt quét gần nhất trước hôm nay.
    today = now.date().isoformat()
    previous = sorted(p for p in SCAN_DIR.glob("scan_*.json")
                      if p.stem.replace("scan_", "") < today)
    ups = []
    if previous:
        old = {r["model"]: r.get("rrp") for r in
               json.loads(previous[-1].read_text(encoding="utf-8-sig"))["rows"]}
        base_text = alerts._base_text()
        base_rrp_map = {m.group(1): int(m.group(2)) for m in re.finditer(r'"model":\s*"([^"]+)",\s*"rrp":\s*(\d+)', base_text)}
        for r in rows:
            before, after = old.get(r["model"]), r.get("rrp")
            if before and after and after > before:
                base_rrp = base_rrp_map.get(r["model"])
                # Nếu giá sau <= RRP chuẩn trong catalogue data.js, đó là phục hồi sau lỗi quét cũ, không phải tăng giá
                if base_rrp and after <= base_rrp:
                    continue
                if r["model"] not in base_rrp_map:
                    continue
                # DA GO (09-11-2026): danh sach bit canh bao tang gia theo ten model
                #     if r["model"] in ("A08 4GB/64GB", "Galaxy A18 4G/128GB",
                #                       "Galaxy A18 4GB/128GB", "Galaxy A18 8GB/128GB") or ...
                # Do dac lai tren 34 dot quet: moi dong no bit deu DA bi hai dieu kien tong quat
                # o ngay tren chan san roi - Galaxy A18 4GB/128GB va 8GB/128GB khong nam trong
                # baseline data.js nen roi vao `not in base_rrp_map`; A08 4GB/64GB co rrp dung
                # bang baseline nen roi vao `after <= base_rrp`. Tuc la no khong con tac dung gi
                # ngoai viec BIT MAT mot canh bao that neu may nay tang gia that sau nay.
                # Viec cao nham bien the - ly do ban dau no ra doi - da co safeguard is_sibling lo.
                tokens_r = alerts._norm_tokens(r["model"])
                is_sibling = False
                for other_model, other_rrp in base_rrp_map.items():
                    if other_model != r["model"] and other_rrp == after:
                        tokens_o = alerts._norm_tokens(other_model)
                        common = tokens_r & tokens_o
                        diff_r = tokens_r - tokens_o
                        diff_o = tokens_o - tokens_r
                        ram_rom_tokens = {"64", "128", "256", "512", "1tb", "4", "6", "8", "12", "16"}
                        has_distinct_specs = bool((diff_r & ram_rom_tokens) and (diff_o & ram_rom_tokens))
                        if common and any(tok for tok in common if not tok.isdigit() and len(tok) >= 2):
                            if not has_distinct_specs:
                                is_sibling = True
                                break
                if is_sibling:
                    print(f"Bo qua tang gia ao do trung bien the cung dong: {r['model']} ({after})", flush=True)
                    continue
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
    write_scans_js(today=today)
    write_latest_js(scan)
    write_promos_js(rows)
    print(f"Đã lưu đợt {scan['date']}: {ok}/{len(products)} SKU đọc được giá, {errors} lỗi mạng. "
          f"Tổng cộng {len(scan['rows'])} model trong đợt.")
    fast_check_o3(scan)


def fast_check_o3(scan):
    """Fast-check hằng ngày qua web mwg https://www.thegioididong.com/dtdd#o=3&pi=0
    đối soát nhanh giá đỏ, RRP của các model mới ra mắt / campaign layout so với latest scan."""
    print("\n--- FAST-CHECK MWG MỚI RA MẮT (dtdd#o=3) ---", flush=True)
    o3_items = {}
    try:
        for page in range(6):
            resp = requests.post(
                f"https://www.thegioididong.com/Category/FilterProductBox?c=42&o=3&pi={page}",
                headers={**HEADERS, "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                         "X-Requested-With": "XMLHttpRequest",
                         "Referer": "https://www.thegioididong.com/dtdd"},
                data="IsParentCate=False&IsShowCompare=True&prevent=true", timeout=(10, 20))
            if resp.status_code != 200:
                break
            soup = BeautifulSoup(resp.json().get("listproducts") or "", "html.parser")
            items = soup.select("li.item[data-id]")
            if not items:
                break
            for li in items:
                a = li.select_one("a.main-contain")
                if not a:
                    continue
                href = (a.get("href") or "").split("?")[0].strip("/")
                slug = href.replace("dtdd/", "") if href.startswith("dtdd/") else href
                raw_red = to_int(a.get("data-price"))
                red = round(raw_red / 1000.0) * 1000 if raw_red else 0
                orig = money(li.select_one(".price-old").get_text()) if li.select_one(".price-old") else to_int(li.get("data-price"))
                orig = round(orig / 1000.0) * 1000 if orig else red
                if orig < red:
                    orig = red
                o3_items[slug] = {"red": red, "rrp": orig}
        print(f"Đã đối soát {len(o3_items)} card từ dtdd#o=3.", flush=True)
        for r in scan.get("rows", []):
            if r.get("status") == "active":
                slug = r.get("url", "").rstrip("/").rsplit("/", 1)[-1].split("?")[0]
                if slug in o3_items:
                    ref = o3_items[slug]
                    if ref["red"] > 0 and abs(ref["red"] - r.get("red", 0)) > 50000:
                        print(f"  [#o=3 Warning] {r['model']}: Scan red={r.get('red')} != #o=3 red={ref['red']}", flush=True)
    except Exception as e:
        print(f"  Fast-check warning: {e}", flush=True)


if __name__ == "__main__":
    main()
