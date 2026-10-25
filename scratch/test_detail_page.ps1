$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}

$testUrls = @(
    "https://www.thegioididong.com/dtdd/oppo-reno16-f",
    "https://www.thegioididong.com/dtdd/samsung-galaxy-a27-8gb-128gb",
    "https://www.thegioididong.com/dtdd/realme-c100x-6gb-128gb"
)

foreach ($u in $testUrls) {
    try {
        $r = Invoke-WebRequest -Uri $u -Headers $headers -TimeoutSec 10 -UseBasicParsing
        $html = $r.Content
        
        $titleM = [regex]::Match($html, '<h1[^>]*>([^<]+)</h1>')
        if (!$titleM.Success) { $titleM = [regex]::Match($html, '<title>([^<]+)</title>') }
        $name = if ($titleM.Success) { $titleM.Groups[1].Value.Trim() } else { "" }
        
        # Check how scan_tgdd parses price:
        # red price: box-price-present or bs-price or similar
        $priceM = [regex]::Match($html, 'class="[^"]*(?:bs-price|box-price-present|text-red-7)[^"]*"[^>]*>.*?([0-9.,]{5,12})')
        $delM = [regex]::Match($html, '<del[^>]*>.*?([0-9.,]{5,12})')
        
        Write-Host "URL: $u"
        Write-Host "  Name: $name"
        Write-Host "  Price: $(if ($priceM.Success) { $priceM.Groups[1].Value } else { 'not found' })"
        Write-Host "  Del: $(if ($delM.Success) { $delM.Groups[1].Value } else { 'not found' })"
    } catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
}
