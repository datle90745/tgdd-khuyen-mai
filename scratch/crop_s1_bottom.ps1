Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile('C:/Users/toquo/.gemini/antigravity/brain/4201d6fe-7d9c-41aa-9469-7328dab9583e/scratch/slice_1.png')
$top = [int]($img.Height - 150)
$rect = New-Object System.Drawing.Rectangle(0, $top, $img.Width, 150)
$bmp = New-Object System.Drawing.Bitmap($rect.Width, $rect.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $rect.Width, $rect.Height)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
$outPath = 'C:/Users/toquo/.gemini/antigravity/brain/4201d6fe-7d9c-41aa-9469-7328dab9583e/scratch/zoom_s1_bottom.png'
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
$img.Dispose()
Write-Host "Saved $outPath"
