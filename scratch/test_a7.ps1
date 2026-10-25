$headers = @{ "User-Agent" = "Mozilla/5.0" }
try {
    $r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd/oppo-a7-pro-5g-6gb-256gb" -Headers $headers -TimeoutSec 10 -UseBasicParsing
    Write-Host "Status: $($r.StatusCode)"
    Write-Host "Title: $([regex]::Match($r.Content, '<title>([^<]+)</title>').Groups[1].Value)"
    
    # Check if there's text or redirect
    Write-Host "Content length: $($r.Content.Length)"
    if ($r.Content -match 'chưa có giá|ngừng kinh doanh|không tìm thấy') {
        Write-Host "Matched no price phrase"
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)"
}
