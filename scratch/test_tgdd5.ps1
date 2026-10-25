$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 15 -UseBasicParsing

$matches = [regex]::Matches($r.Content, 'href="(/dtdd/[^"?#]+)"')
Write-Host "Total href dtdd: $($matches.Count)"

for ($i = 0; $i -lt [Math]::Min(3, $matches.Count); $i++) {
    $idx = $matches[$i].Index
    $start = [Math]::Max(0, $idx - 100)
    $len = [Math]::Min(800, $r.Content.Length - $start)
    Write-Host "--- Snippet $i ---"
    Write-Host $r.Content.Substring($start, $len)
}
