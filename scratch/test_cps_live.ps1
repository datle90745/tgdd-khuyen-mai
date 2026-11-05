$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
$cpsTemplate = @'
query { products(filter:{static:{categories:["3"],province_id:30,stock:{from:0},filter_price:{from:0,to:200000000}},dynamic:{}}, page:1, size:100, sort:[{view:desc}]) { general{ name url_path manufacturer } filterable{ price special_price } } }
'@
$body = @{ query = $cpsTemplate; variables = @{} } | ConvertTo-Json
$resp = Invoke-RestMethod -Method Post -Uri "https://api.cellphones.com.vn/v2/graphql/query" -UserAgent $UA -ContentType "application/json" -Body $body
$items = $resp.data.products | Where-Object { $_.general.name -like "*A17*" }
foreach ($it in $items) {
    Write-Host "$($it.general.name) | special=$($it.filterable.special_price) | price=$($it.filterable.price) | url=$($it.general.url_path)"
}
