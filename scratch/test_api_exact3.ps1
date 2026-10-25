$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Content-Type" = "application/json"
    "Referer" = "https://www.thegioididong.com/dtdd"
    "os" = "WebTGDD"
    "siteid" = "1"
    "provinceid" = "3"
}

$ep = "https://api.thegioididong.com/gw/bus-tgdd-tmdt/api/Cate/GetproductCateV2"

$tests = @(
    @{ pageIndex = 0; pageSize = 20; provinceId = 3; urlCate = "/dtdd" },
    @{ pageIndex = 0; pageSize = 20; provinceId = 3; urlCate = "dtdd" },
    @{ pageIndex = 0; pageSize = 20; provinceId = 3; urlCate = "dtdd"; cateId = "42" },
    @{ pageIndex = 0; pageSize = 20; provinceId = 3; urlCate = "/dtdd"; cateId = "42" },
    @{ pageIndex = 0; pageSize = 20; provinceId = 3; cateId = "42" },
    @{ pageIndex = 1; pageSize = 20; provinceId = 3; urlCate = "/dtdd" }
)

foreach ($t in $tests) {
    $body = @{ reqs = $t } | ConvertTo-Json
    $r = Invoke-WebRequest -Uri $ep -Method Post -Body $body -Headers $headers -TimeoutSec 10 -UseBasicParsing
    $json = ConvertFrom-Json $r.Content
    Write-Host "Param: $(($t.Keys | ForEach-Object { "$_=$($t[$_])" }) -join ', ') -> total: $($json.data.totalProduct), products count: $($json.data.products.Count), remaining: $($json.data.remainingQuantity)"
}
