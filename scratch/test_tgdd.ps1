$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}
try {
    Write-Host "Fetching https://www.thegioididong.com/dtdd ..."
    $r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 15 -UseBasicParsing
    Write-Host "Status: $($r.StatusCode)"
    Write-Host "Length: $($r.Content.Length)"
    
    $matches = [regex]::Matches($r.Content, 'href="(/dtdd/[^"?#]+)"')
    Write-Host "Total href dtdd matches: $($matches.Count)"
    
    $uniqueUrls = $matches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    Write-Host "Unique product URLs: $($uniqueUrls.Count)"
    
    # Check if there is pagination or "xem-them" or AJAX api
    if ($r.Content -match 'data-total="(\d+)"') {
        Write-Host "Found data-total: $($matches[0].Groups[1].Value)"
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)"
}
