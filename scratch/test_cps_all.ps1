$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
$cpsTemplate = @'
query { products(filter:{static:{categories:["3"],province_id:30,stock:{from:0},filter_price:{from:0,to:200000000}},dynamic:{}}, page:{0}, size:100, sort:[{view:desc}]) { general{ name url_path manufacturer } filterable{ price special_price } } }
'@

for ($page = 1; $page -le 10; $page++) {
    $q = $cpsTemplate.Replace("{0}", "$page")
    $body = @{ query = $q; variables = @{} } | ConvertTo-Json
    $resp = Invoke-RestMethod -Method Post -Uri "https://api.cellphones.com.vn/v2/graphql/query" -UserAgent $UA -ContentType "application/json" -Body $body
    $items = $resp.data.products
    if (!$items) { break }
    $matched = $items | Where-Object { $_.general.name -like "*A17*" }
    foreach ($it in $matched) {
        Write-Host "Page $page : $($it.general.name) | special=$($it.filterable.special_price) | price=$($it.filterable.price) | url=$($it.general.url_path)"
    }
}
