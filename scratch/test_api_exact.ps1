$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Content-Type" = "application/json"
    "Referer" = "https://www.thegioididong.com/dtdd"
}

$ep = "https://api.thegioididong.com/gw/bus-tgdd-tmdt/api/Cate/GetproductCateV2"
$body = @{
    pageIndex = 0
    pageSize = 20
    provinceId = 3
    urlCate = "dtdd"
    cateId = 42
    filters = @()
} | ConvertTo-Json

try {
    $r = Invoke-WebRequest -Uri $ep -Method Post -Body $body -Headers $headers -TimeoutSec 10 -UseBasicParsing
    Write-Host "Success: $($r.Content)"
} catch {
    Write-Host "Exception: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $respBody = $reader.ReadToEnd()
        Write-Host "Response Body: $respBody"
    }
}
