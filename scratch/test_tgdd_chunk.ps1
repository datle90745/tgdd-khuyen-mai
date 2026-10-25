$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
}
# Find all js script tags in dtdd
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 15 -UseBasicParsing

$scripts = [regex]::Matches($r.Content, 'src="([^"]+\.js)"') | ForEach-Object { $_.Groups[1].Value }

Write-Host "Scripts found: $($scripts.Count)"
$catScript = $scripts | Where-Object { $_ -match 'category' }
Write-Host "Category script: $catScript"

if ($catScript) {
    $js = Invoke-WebRequest -Uri $catScript -Headers $headers -TimeoutSec 15 -UseBasicParsing
    Write-Host "Cat script length: $($js.Content.Length)"
    
    # Search for api endpoints, URLs, or POST endpoints
    $endpoints = [regex]::Matches($js.Content, '(?i)(?:/api/[a-zA-Z0-9_/]+|https?://[a-zA-Z0-9_./-]+/api/[a-zA-Z0-9_./-]+)') | ForEach-Object { $_.Value } | Select-Object -Unique
    Write-Host "Endpoints in cat script:"
    $endpoints
    
    # Search for fetch calls
    $fetches = [regex]::Matches($js.Content, '(?i)(?:fetch|post|get)\(["'']([^"'']+)["'']') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    Write-Host "Fetches:"
    $fetches
}
