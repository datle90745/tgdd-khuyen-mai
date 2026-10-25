$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}

# Test different URL patterns for pagination on dtdd
$testUrls = @(
    "https://www.thegioididong.com/dtdd",
    "https://www.thegioididong.com/dtdd?pi=1",
    "https://www.thegioididong.com/dtdd?page=2",
    "https://www.thegioididong.com/dtdd#pi=1"
)

foreach ($u in $testUrls) {
    try {
        $r = Invoke-WebRequest -Uri $u -Headers $headers -TimeoutSec 10 -UseBasicParsing
        $m = [regex]::Matches($r.Content, '<img aria-label="([^"]+)"')
        $names = $m | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        Write-Host "URL: $u -> Length: $($r.Content.Length), Products: $($names.Count)"
        if ($names.Count -gt 0) {
            Write-Host "  First 3: $($names[0..([Math]::Min(2, $names.Count-1))] -join ' | ')"
        }
    } catch {
        Write-Host "URL: $u -> Error: $($_.Exception.Message)"
    }
}
