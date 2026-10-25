$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 15 -UseBasicParsing

# Find view-more / pagination / ajax url
$m1 = [regex]::Matches($r.Content, "(?i)(view-more|xem-them|show-more|filterproduct|aj\/|Category)[^`"'\<\>]*")
Write-Host "Endpoints/Classes:"
$m1 | ForEach-Object { $_.Value } | Select-Object -Unique | Select-Object -First 20

# Let's inspect the html around class="view-more" or button
$idx = $r.Content.IndexOf("view-more")
if ($idx -ge 0) {
    $start = [Math]::Max(0, $idx - 200)
    $len = [Math]::Min(1000, $r.Content.Length - $start)
    Write-Host "view-more context:"
    Write-Host $r.Content.Substring($start, $len)
}
