# Windows Chrome Exe yollarını ara
$chromePaths = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
)

$chromePath = $null
foreach ($path in $chromePaths) {
    if (Test-Path $path) {
        $chromePath = $path
        break
    }
}

if ($chromePath -eq $null) {
    Write-Error "Google Chrome bilgisayarınızda bulunamadı!"
    exit 1
}

$templatePath = "c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\scratch\logo_template.html"
$assetsDir = "c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\assets\images"

# Assets/images klasörünün varlığından emin ol
if (!(Test-Path $assetsDir)) {
    New-Item -ItemType Directory -Path $assetsDir -Force
}

# Tüm Logolar ve Varyasyonları (Chevron Orijinal + Modern 3D Görseli)
$logos = @(
    # --- ORİJİNAL CHEVRON TEMA SETİ (Şeffaf - Artık 3D İkon ile Güncellendi!) ---
    @{ mode="iconKoyu"; w=512; h=512; filename="logo_icon_dark.png" },
    @{ mode="fullKoyu"; w=1200; h=400; filename="logo_full_dark.png" },
    @{ mode="textKoyu"; w=1200; h=400; filename="logo_text_dark.png" },
    @{ mode="iconAcik"; w=512; h=512; filename="logo_icon_light.png" },
    @{ mode="fullAcik"; w=1200; h=400; filename="logo_full_light.png" },
    @{ mode="textAcik"; w=1200; h=400; filename="logo_text_light.png" },
    
    # --- YENİ EKLENEN ANA VE LAUNCHER LOGOLARI ---
    @{ mode="iconKoyu"; w=512; h=512; filename="logo_icon_only.png" },
    @{ mode="fullAcik"; w=1200; h=400; filename="logo.png" },
    
    # --- MODERN 3D TEMA SETİ (Şeffaf - Çok Beğendiğiniz google_auth_logo İkonuyla) ---
    @{ mode="modernIcon"; w=512; h=512; filename="google_auth_logo.png" }, 
    @{ mode="modernIconLight"; w=512; h=512; filename="google_auth_logo_light.png" }, 
    @{ mode="modernFullKoyu"; w=1200; h=400; filename="google_auth_full_logo.png" }, 
    @{ mode="modernFullAcik"; w=1200; h=400; filename="google_auth_full_logo_light.png" }
)

Write-Host "Tüm logolar (Orijinal ve Modern 3D) Chrome Headless ile oluşturuluyor..." -ForegroundColor Green

foreach ($logo in $logos) {
    $mode = $logo.mode
    $w = $logo.w
    $h = $logo.h
    $filename = $logo.filename
    $targetPath = Join-Path $assetsDir $filename
    
    Write-Host "Oluşturuluyor: $filename ($w x $h)" -ForegroundColor Cyan
    
    $url = "file:///$templatePath`?mode=$mode"
    
    # Senkron çalıştırma (Mükemmel stabilite)
    Start-Process -FilePath $chromePath -ArgumentList "--headless", "--disable-gpu", "--hide-scrollbars", "--default-background-color=00000000", "--screenshot=""$targetPath""", "--window-size=""$w,$h""", "`"$url`"" -NoNewWindow -Wait
    
    Start-Sleep -Milliseconds 500
}

Write-Host "Tüm logolar başarıyla c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\assets\images\ klasörüne transparan PNG olarak kaydedildi!" -ForegroundColor Green
