$target = @"
    print(f"  TGDĐ: Đã thu thập {len(rows)} sản phẩm.", flush=True)
    return rows
"@

$mergeBlock = @"
    # 4. Bo sung toan bo SKU Master List tu latest.js cho TGDD
    latest_file = ROOT / "data" / "latest.js"
    if latest_file.exists():
        try:
            l_txt = latest_file.read_text(encoding="utf-8")
            lm = re.search(r'window\.LATEST\s*=\s*(\{.*?\});', l_txt, re.DOTALL)
            if lm:
                latest_data = json.loads(lm.group(1))
                b_map = {}
                data_file = ROOT / "data" / "data.js"
                if data_file.exists():
                    d_txt = data_file.read_text(encoding="utf-8")
                    dm = re.search(r'window\.BASE\s*=\s*(\{.*?\});', d_txt, re.DOTALL)
                    if dm:
                        base_data = json.loads(dm.group(1))
                        for br in base_data.get("rows", []):
                            b_map[br.get("model")] = br.get("brand")
                links_map = {}
                links_file = ROOT / "data" / "links.js"
                if links_file.exists():
                    lk_txt = links_file.read_text(encoding="utf-8")
                    lkm = re.search(r'window\.LINKS\s*=\s*(\{.*?\});', lk_txt, re.DOTALL)
                    if lkm:
                        links_map = json.loads(lkm.group(1))
                for lr in latest_data.get("rows", []):
                    u = lr.get("url") or links_map.get(lr.get("model")) or ""
                    u_key = u.replace("https://www.thegioididong.com", "").split("?")[0] if u else lr.get("model")
                    if u_key not in seen:
                        seen.add(u_key)
                        brand = b_map.get(lr.get("model")) or brand_of("", lr.get("model"))
                        m_name = lr.get("model") if brand and lr.get("model", "").startswith(brand) else f"{brand} {lr.get('model')}".strip()
                        p = lr.get("red") or lr.get("rrp") or 0
                        o = lr.get("rrp") or lr.get("red") or 0
                        k = "Flash Sale Online" if lr.get("rule") == "flash_chon1" else KM_NAME
                        rows.append(row(TGDD_NAME, brand, m_name, u, p, o, k))
        except Exception as e:
            print(f"  Loi bo sung Master List vao TGDD: {e}", flush=True)

    print(f"  TGDĐ: Đã thu thập {len(rows)} sản phẩm.", flush=True)
    return rows
"@

foreach ($file in @("scraper/scan_market.py", "promotion tgdd/scraper/scan_market.py")) {
    $path = Join-Path $PSScriptRoot ("../" + $file)
    if (Test-Path $path) {
        $c = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        if (-not $c.Contains("Bo sung toan bo SKU Master List tu latest.js")) {
            $c = [regex]::Replace($c, '(?s)print\(f"\s*TGD.*?\s*s.*?n ph.*?m\.", flush=True\)\s*return rows', $mergeBlock)
            [System.IO.File]::WriteAllText($path, $c, (New-Object System.Text.UTF8Encoding $false))
            Write-Host "Inserted Master List merge in $file"
        }
    }
}
