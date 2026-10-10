$cookie = "auth-token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzIjoiTkRJNU9ERT0iLCJtcGIiOnRydWUsIm1wYl9jZW50ZXIiOnRydWUsIm1wdyI6dHJ1ZX0.N83FJvj7sT_sldg5oB4xEvK4Q0uQ7jp1A6EH3-LjrCE; p=knksu3o5biifl8ueo45g7g2ceh"
# Find a TGDD url from data/links.js
$linksRaw = Get-Content "data\links.js" -Raw -Encoding UTF8
$links = $linksRaw | ConvertFrom-Json
$firstKey = ($links.PSObject.Properties | Select-Object -First 1).Name
$firstUrl = $links.$firstKey
Write-Host "Testing URL: $firstKey -> $firstUrl"

$encUrl = [System.Web.HttpUtility]::UrlEncode($firstUrl)
$res = C:\Windows\System32\curl.exe -s -H "Cookie: $cookie" "https://promotion.erp-portal.vn/api/product/history?url=$encUrl"
Write-Host "Result:" $res
