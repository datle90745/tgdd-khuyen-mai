$path = "$PSScriptRoot/../index.html"
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

$oldSnippet = 'const RISE = RISE_RAW.filter(r => (r[7]||"") !== "FPT Shop").map((r,i)=>{ const [mo,b,m,o,n,d,p,ch]=r; return {i,mo,b,m,o,n,v:n-o,p,seg:rseg(n),d,ch:ch||"",k:rkey(b,m)}; });' + "`r`n" + 'const mnum = m => +m.slice(1);' + "`r`n" + 'const RB_CELL = b => `<td class="bcell" data-b="${RBD[b]||b}">${b}</td>`;'

$newSnippet = @'
const inferBrand = (b, m) => {
  if (b && String(b).trim()) return String(b).trim().toUpperCase();
  const mLower = String(m || "").toLowerCase();
  if (/apple|iphone/.test(mLower)) return "APPLE";
  if (/samsung|galaxy/.test(mLower)) return "SAMSUNG";
  if (/oppo/.test(mLower)) return "OPPO";
  if (/xiaomi|redmi|poco/.test(mLower)) return "XIAOMI";
  if (/vivo/.test(mLower)) return "VIVO";
  if (/realme/.test(mLower)) return "REALME";
  if (/honor/.test(mLower)) return "HONOR";
  return "";
};
const RISE = RISE_RAW.filter(r => (r[7]||"") !== "FPT Shop").map((r,i)=>{
  const [mo,rawB,m,o,n,d,p,ch]=r;
  const b = inferBrand(rawB, m);
  return {i,mo,b,m,o,n,v:n-o,p,seg:rseg(n),d,ch:ch||"",k:rkey(b,m)};
});
const mnum = m => +m.slice(1);
const RB_CELL = b => { const disp = RBD[b] || b || ""; return `<td class="bcell" data-b="${disp}">${disp}</td>`; };
'@

if ($content.Contains('const RB_CELL = b => `<td class="bcell" data-b="${RBD[b]||b}">${b}</td>`;')) {
    $idx1 = $content.IndexOf('const RISE = RISE_RAW.filter')
    $idx2 = $content.IndexOf('const rpct =', $idx1)
    if ($idx1 -ge 0 -and $idx2 -ge 0) {
        $before = $content.Substring(0, $idx1)
        $after = $content.Substring($idx2)
        $content = $before + $newSnippet.Trim() + "`r`n" + $after
        [System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "Updated index.html successfully!"
    } else {
        Write-Host "Indices not found"
    }
} else {
    Write-Host "Old snippet not found"
}
