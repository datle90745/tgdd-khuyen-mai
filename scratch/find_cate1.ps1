$headers = @{ "User-Agent" = "Mozilla/5.0" }
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 15 -UseBasicParsing
$scripts = [regex]::Matches($r.Content, 'src="([^"]+\.js)"') | ForEach-Object { $_.Groups[1].Value }

foreach ($s in $scripts) {
    try {
        $c = (Invoke-WebRequest -Uri $s -Headers $headers -TimeoutSec 10 -UseBasicParsing).Content
        if ($c -match 'GET_PRODUCT_CATE\b') {
            Write-Host "FOUND in: $s"
            $idx = $c.IndexOf("GET_PRODUCT_CATE")
            Write-Host $c.Substring([Math]::Max(0, $idx - 50), [Math]::Min(500, $c.Length - $idx + 50))
        }
    } catch {}
}
