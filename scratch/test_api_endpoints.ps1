$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Content-Type" = "application/json"
    "Referer" = "https://www.thegioididong.com/dtdd"
}

$endpoints = @(
    "https://www.thegioididong.com/Cate/GetproductCateV2",
    "https://api.thegioididong.com/Cate/GetproductCateV2",
    "https://www.thegioididong.com/api/Cate/GetproductCateV2"
)

$body = @{
    pageIndex = 0
    pageSize = 20
    provinceId = 3
    urlCate = "dtdd"
    cateId = 42
    filters = @()
} | ConvertTo-Json

foreach ($ep in $endpoints) {
    try {
        Write-Host "Testing $ep ..."
        $r = Invoke-WebRequest -Uri $ep -Method Post -Body $body -Headers $headers -TimeoutSec 10 -UseBasicParsing
        Write-Host "  Status: $($r.StatusCode), Length: $($r.Content.Length)"
        Write-Host "  Snippet: $($r.Content.Substring(0, [Math]::Min(300, $r.Content.Length)))"
    } catch {
        Write-Host "  Error: $($_.Exception.Message)"
    }
}
