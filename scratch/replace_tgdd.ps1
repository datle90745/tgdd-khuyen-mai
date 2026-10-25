$path = (Resolve-Path "scraper/scan_market.py").Path
$lines = [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)

$prefix = $lines[0..102]
$suffix = $lines[184..($lines.Length - 1)]

$newBlock = @'
TGDD_SOURCES = [
    ("https://www.thegioididong.com/dtdd", None),
    ("https://www.thegioididong.com/dtdd-apple-iphone", "Apple"),
    ("https://www.thegioididong.com/dtdd-samsung", "Samsung"),
    ("https://www.thegioididong.com/dtdd-oppo", "OPPO"),
    ("https://www.thegioididong.com/dtdd-xiaomi", "Xiaomi"),
    ("https://www.thegioididong.com/dtdd-vivo", "Vivo"),
    ("https://www.thegioididong.com/dtdd-realme", "Realme"),
    ("https://www.thegioididong.com/dtdd-honor", "Honor"),
    ("https://www.thegioididong.com/dtdd?p=duoi-2-trieu", None),
    ("https://www.thegioididong.com/dtdd?p=tu-2-4-trieu", None),
    ("https://www.thegioididong.com/dtdd?p=tu-4-7-trieu", None),
    ("https://www.thegioididong.com/dtdd?p=tu-7-13-trieu", None),
    ("https://www.thegioididong.com/dtdd?p=tu-13-20-trieu", None),
    ("https://www.thegioididong.com/dtdd?p=tren-20-trieu", None),
]


def scan_tgdd():
    rows, seen = [], set()

    # 1. Cào toàn bộ danh mục TGDĐ (trang chủ dtdd, brand hubs, và các bộ lọc phân khúc giá)
    print("  TGDĐ: Đang quét danh mục toàn thị trường (trang dtdd + brand tabs + phân khúc giá)...", flush=True)
    unseen_variants = []
    for url, b_hint in TGDD_SOURCES:
        try:
            resp = request("GET", url, headers={"Referer": "https://www.thegioididong.com/dtdd"})
            html = resp.text
            parts = html.split('<div data-product-code="')
            for p in parts[1:]:
                link_m = re.search(r'href="(/dtdd/[^"?#]+)"', p)
                if not link_m:
                    continue
                href = link_m.group(1).split("?")[0]
                name_m = re.search(r'<img [^>]*alt="([^"]+)"', p) or re.search(r'<a[^>]*title="([^"]+)"', p)
                base_name = re.sub(r"^Điện thoại\s+", "", name_m.group(1) if name_m else "").strip()
                brand = brand_of(b_hint, base_name)
                
                # Bắt các biến thể RAM/ROM trong cùng thẻ card
                variant_links = re.findall(r'<a[^>]*href="(/dtdd/[^"?#]+)"[^>]*>([0-9]+\s*(?:GB|TB))</a>', p)
                for v_href, v_cap in variant_links:
                    v_clean = v_href.split("?")[0]
                    if v_clean not in seen and v_clean != href:
                        unseen_variants.append((v_clean, base_name, brand, v_cap))

                if href in seen or not brand or not base_name:
                    continue
                price_m = re.search(r'<a[^>]*class="[^"]*text-red-7[^"]*"[^>]*><span>([0-9.,]+)[^<]*</span>', p)
                del_m = re.search(r'<del[^>]*>([0-9.,]+)[^<]*</del>', p)
                price = money(price_m.group(1)) if price_m else 0
                orig = money(del_m.group(1)) if del_m else 0
                if price <= 0:
                    continue
                seen.add(href)
                rows.append(row("TGDĐ", brand, base_name, "https://www.thegioididong.com" + href,
                                price, orig, "Khuyến mãi"))
            time.sleep(0.3)
        except Exception as e:
            print(f"    Lỗi cào URL {url}: {e}", flush=True)

    # 2. Cào bổ sung các biến thể chưa có trong danh sách chính
    if unseen_variants:
        print(f"  TGDĐ: Đang quét {len(unseen_variants)} biến thể dung lượng/RAM riêng biệt...", flush=True)
        for v_href, parent_name, brand, v_cap in unseen_variants:
            if v_href in seen:
                continue
            try:
                v_url = "https://www.thegioididong.com" + v_href
                resp = request("GET", v_url, headers={"Referer": "https://www.thegioididong.com/dtdd"})
                v_html = resp.text
                t_m = re.search(r'<h1[^>]*>([^<]+)</h1>', v_html) or re.search(r'<title>([^<]+)</title>', v_html)
                v_name = re.sub(r"^Điện thoại\s+", "", t_m.group(1) if t_m else "").strip()
                if not v_name:
                    v_name = f"{parent_name} {v_cap}".strip()
                v_brand = brand_of(brand, v_name) or brand
                price_m = re.search(r'class="[^"]*(?:bs-price|box-price-present|text-red-7)[^"]*"[^>]*>.*?([0-9.,]{5,12})', v_html)
                del_m = re.search(r'<del[^>]*>.*?([0-9.,]{5,12})', v_html)
                v_price = money(price_m.group(1)) if price_m else 0
                v_orig = money(del_m.group(1)) if del_m else v_price
                if v_price > 0:
                    seen.add(v_href)
                    rows.append(row("TGDĐ", v_brand, v_name, v_url, v_price, v_orig, "Khuyến mãi"))
                time.sleep(0.2)
            except Exception:
                pass

    # 3. Cào thêm từ FilterProductBox để bổ sung các máy khác
    print("  TGDĐ: Quét bổ sung từ danh mục FilterProductBox...", flush=True)
    for page in range(25):
        try:
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
                href = (a.get("href") or "").split("?")[0]
                name = re.sub(r"^Điện thoại\s+", "", a.get("data-name", ""))
                brand = brand_of(a.get("data-brand"), name)
                if not brand or href in seen:
                    continue
                seen.add(href)
                price = num(a.get("data-price"))
                old = li.select_one(".price-old") if li else None
                if not price:
                    continue
                rows.append(row("TGDĐ", brand, name, "https://www.thegioididong.com" + href,
                                price, money(old.get_text()) if old else 0,
                                "Flash Sale Online" if "utm_flashsale=1" in (a.get("href") or "") else "Khuyến mãi"))
            time.sleep(0.3)
        except Exception:
            break
    print(f"  TGDĐ: Đã thu thập {len(rows)} sản phẩm.", flush=True)
    return rows
'@ -split "\r?\n"

$combined = $prefix + $newBlock + $suffix
[System.IO.File]::WriteAllLines($path, $combined, [System.Text.Encoding]::UTF8)
Write-Host "Updated scraper/scan_market.py successfully. New line count: $($combined.Length)"
