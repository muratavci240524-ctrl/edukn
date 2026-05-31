Add-Type -AssemblyName System.Drawing
$srcPath = "c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\assets\images\google_auth_full_logo_light_orig.png"
$destPath = "c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\assets\images\google_auth_full_logo_light.png"

Copy-Item "c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\assets\images\google_auth_full_logo_light.png" $srcPath -Force

$img = [System.Drawing.Image]::FromFile($srcPath)
$newHeight = 160
$newWidth = [int]($img.Width * ($newHeight / $img.Height))

$bmp = New-Object System.Drawing.Bitmap $newWidth, $newHeight
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.DrawImage($img, 0, 0, $newWidth, $newHeight)
$g.Dispose()
$img.Dispose()

$bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
echo "SUCCESS"
