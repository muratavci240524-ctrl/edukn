$base64 = Get-Content -Path "c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\scratch\base64_logo.txt" -Raw
$base64 = $base64 -replace '\s+', ''

# ----------------- 1. logo_template.html -----------------
$templateHtml = @"
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <title>Logo Template</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,900;1,900&display=swap" rel="stylesheet">
    <style>
        html, body {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            overflow: hidden;
            background-color: transparent;
        }
        canvas {
            display: block;
            width: 100%;
            height: 100%;
        }
    </style>
</head>
<body>

<canvas id="myCanvas"></canvas>

<script>
    // 1. Orijinal Chevron Koordinatları (Orijinal logolar için)
    const path1_raw = [[0, 15], [35, 15], [55, 40], [35, 65], [0, 65], [20, 40]];
    const path2_raw = [[25, 15], [60, 15], [80, 40], [60, 65], [25, 65], [45, 40]];
    const path3_raw = [[50, 15], [85, 15], [105, 40], [85, 65], [50, 65], [70, 40]];

    function drawChevron(ctx, points) {
        ctx.beginPath();
        ctx.moveTo(points[0][0], points[0][1]);
        for (let i = 1; i < points.length; i++) {
            ctx.lineTo(points[i][0], points[i][1]);
        }
        ctx.closePath();
    }

    const urlParams = new URLSearchParams(window.location.search);
    const mode = urlParams.get('mode') || 'fullKoyu';

    const canvas = document.getElementById('myCanvas');
    const ctx = canvas.getContext('2d');

    // Modlara göre boyut ayarla
    let isIcon = mode.startsWith('icon') || mode.startsWith('modernIcon');
    if (isIcon) {
        canvas.width = 512;
        canvas.height = 512;
    } else {
        canvas.width = 1200;
        canvas.height = 400;
    }

    let isDarkBg = mode.endsWith('Koyu') || mode === 'modernFullKoyu' || mode === 'fullKoyu';

    // Base64 görseli yükle (Çok beğenilen 3D ikon)
    const img = new Image();
    img.src = "data:image/png;base64,$base64"; 

    img.onload = function() {
        drawAll();
    };

    img.onerror = function() {
        drawAll();
    };

    function draw3DLogoIcon(ctx, destX, destY, destW, destH) {
        if (img.complete && img.naturalWidth !== 0) {
            const tempCanvas = document.createElement('canvas');
            tempCanvas.width = img.width;
            tempCanvas.height = img.height;
            const tempCtx = tempCanvas.getContext('2d');
            tempCtx.drawImage(img, 0, 0);
            
            const imgData = tempCtx.getImageData(0, 0, tempCanvas.width, tempCanvas.height);
            const data = imgData.data;
            
            const centerX = img.width / 2;
            const centerY = img.height / 2;
            
            for (let y = 0; y < img.height; y++) {
                for (let x = 0; x < img.width; x++) {
                    const idx = (y * img.width + x) * 4;
                    let r = data[idx];
                    let g = data[idx+1];
                    let b = data[idx+2];
                    let brightness = (r + g + b) / 3;
                    
                    // 1. Dış dairesel gri halka/gölge temizliği (dist > 145 ve nötr renkler için)
                    let dx = x - centerX;
                    let dy = y - centerY;
                    let dist = Math.sqrt(dx*dx + dy*dy);
                    
                    if (dist > 145) {
                        let maxDiff = Math.max(Math.abs(r - g), Math.abs(g - b), Math.abs(r - b));
                        if (maxDiff < 40 && brightness > 100) {
                            data[idx+3] = 0; // Tamamen transparan
                            continue;
                        }
                    }
                    
                    // 2. Açık mavi/cyan tüylü gölge kalıntılarını temizle (dist > 125 ve r > 160 açık parıltı)
                    if (dist > 125) {
                        if (r > 160 && b > 180 && g > 180) {
                            data[idx+3] = 0; // Tamamen transparan yap
                            continue;
                        }
                    }
                    
                    // 3. GELİŞMİŞ PÜRÜZSÜZLEŞTİRİCİ V2 (Siyah Nokta Korumalı)
                    let distToWhite = Math.sqrt((255-r)*(255-r) + (255-g)*(255-g) + (255-b)*(255-b));
                    let maxDiff = Math.max(r, g, b) - Math.min(r, g, b);
                    let effDist = distToWhite + maxDiff * 1.5;
                    
                    let thresholdMin = 45;
                    let thresholdMax = 190;
                    
                    if (effDist < thresholdMin) {
                        data[idx+3] = 0; // Tamamen transparan arka plan
                    } else if (effDist < thresholdMax) {
                        // Kenar yumuşatma (Yumuşak kenar anti-aliasing)
                        let A = (effDist - thresholdMin) / (thresholdMax - thresholdMin);
                        data[idx+3] = Math.round(A * 255);
                        
                        // Sadece parlak ve renkli pikselleri unmultiply yap (Koyu gölgelerin siyaha düşmesini önler)
                        if (A > 0.05 && maxDiff > 30 && r > 90 && g > 90 && b > 90) {
                            data[idx] = Math.max(0, Math.min(255, Math.round((r - (1 - A) * 255) / A)));
                            data[idx+1] = Math.max(0, Math.min(255, Math.round((g - (1 - A) * 255) / A)));
                            data[idx+2] = Math.max(0, Math.min(255, Math.round((b - (1 - A) * 255) / A)));
                        }
                    } else {
                        data[idx+3] = 255; // Gövde içi tamamen mat kalır
                    }
                }
            }
            tempCtx.putImageData(imgData, 0, 0);
            
            ctx.drawImage(tempCanvas, destX, destY, destW, destH);
        }
    }

    function drawAll() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // --- A. ORİJİNAL CHEVRON LOGOLARI ---
        if (mode === 'iconKoyu' || mode === 'iconAcik') {
            ctx.save();
            const scale = 3.2; 
            ctx.translate(256 - (66.8 * scale), 256 - (50 * scale) - 20); 
            ctx.scale(scale, scale);
            ctx.translate(25, 10);
            ctx.transform(1, 0, -0.267949, 1, 0, 0);

            let grad1 = ctx.createLinearGradient(0, 15, 55, 65);
            grad1.addColorStop(0, '#1E3A8A');
            grad1.addColorStop(1, '#2563EB');
            ctx.fillStyle = grad1;
            drawChevron(ctx, path1_raw);
            ctx.fill();

            let grad2 = ctx.createLinearGradient(25, 65, 80, 15);
            grad2.addColorStop(0, '#2563EB');
            grad2.addColorStop(1, '#60A5FA');
            ctx.fillStyle = grad2;
            drawChevron(ctx, path2_raw);
            ctx.fill();

            ctx.save();
            ctx.shadowColor = '#60A5FA';
            ctx.shadowBlur = 10;
            ctx.fillStyle = '#60A5FA';
            drawChevron(ctx, path3_raw);
            ctx.fill();
            ctx.restore();
            ctx.restore();

        } else if (mode === 'fullKoyu' || mode === 'fullAcik') {
            ctx.save();
            const scale = 2.4; 
            ctx.translate(90, 200 - (50 * scale) - 22); 
            ctx.scale(scale, scale);
            ctx.translate(25, 10);
            ctx.transform(1, 0, -0.267949, 1, 0, 0);

            let grad1 = ctx.createLinearGradient(0, 15, 55, 65);
            grad1.addColorStop(0, '#1E3A8A');
            grad1.addColorStop(1, '#2563EB');
            ctx.fillStyle = grad1;
            drawChevron(ctx, path1_raw);
            ctx.fill();

            let grad2 = ctx.createLinearGradient(25, 65, 80, 15);
            grad2.addColorStop(0, '#2563EB');
            grad2.addColorStop(1, '#60A5FA');
            ctx.fillStyle = grad2;
            drawChevron(ctx, path2_raw);
            ctx.fill();

            ctx.save();
            ctx.shadowColor = '#60A5FA';
            ctx.shadowBlur = 10;
            ctx.fillStyle = '#60A5FA';
            drawChevron(ctx, path3_raw);
            ctx.fill();
            ctx.restore();
            ctx.restore();

            // Yazı
            ctx.save();
            ctx.translate(460, 200);
            ctx.transform(1, 0, -0.267949, 1, 0, 0);
            ctx.font = "italic 900 170px 'Roboto', sans-serif";
            ctx.textBaseline = "middle";

            ctx.fillStyle = isDarkBg ? "#FFFFFF" : "#111827"; 
            ctx.fillText("edu", 0, 0);

            let eduWidth = ctx.measureText("edu").width;
            ctx.fillStyle = "#1E3A8A"; 
            ctx.fillText("KN", eduWidth - 12, 0);
            ctx.restore();

        } else if (mode === 'textKoyu' || mode === 'textAcik') {
            ctx.save();
            ctx.font = "italic 900 190px 'Roboto', sans-serif";
            ctx.textBaseline = "middle";

            let eduWidth = ctx.measureText("edu").width;
            let knWidth = ctx.measureText("KN").width;
            let totalWidth = eduWidth + knWidth - 14;

            ctx.translate(600, 200);
            ctx.transform(1, 0, -0.267949, 1, 0, 0);

            ctx.fillStyle = isDarkBg ? "#FFFFFF" : "#111827"; 
            ctx.fillText("edu", -totalWidth / 2, 0);

            ctx.fillStyle = "#1E3A8A"; 
            ctx.fillText("KN", -totalWidth / 2 + eduWidth - 14, 0);
            ctx.restore();

        // --- B. MODERN 3D GÖRSEL LOGOLARI (SADECE google_auth varyasyonları) ---
        } else if (mode === 'modernIcon') {
            draw3DLogoIcon(ctx, 0, 0, 512, 512);

        } else if (mode === 'modernIconLight') {
            ctx.fillStyle = "#FFFFFF";
            ctx.fillRect(0, 0, 512, 512);
            draw3DLogoIcon(ctx, 0, 0, 512, 512);

        } else if (mode === 'modernFullKoyu' || mode === 'modernFullAcik') {
            const targetH = 345;
            const targetW = 345;
            const iconY = 200 - targetH / 2; // 27.5
            
            draw3DLogoIcon(ctx, 70, iconY, targetW, targetH);
            
            ctx.save();
            ctx.translate(445, 214);
            ctx.transform(1, 0, -0.267949, 1, 0, 0);

            ctx.font = "italic 900 160px 'Roboto', sans-serif";
            ctx.textBaseline = "middle";

            ctx.fillStyle = isDarkBg ? "#FFFFFF" : "#111827"; 
            ctx.fillText("edu", 0, 0);

            let eduWidth = ctx.measureText("edu").width;
            ctx.fillStyle = "#1E3A8A"; 
            ctx.fillText("KN", eduWidth - 12, 0);
            ctx.restore();
        }

        // Chrome Headless için hazırız class'ı ekle
        document.body.classList.add('ready');
    }
</script>

</body>
</html>
"@

$templateHtml | Out-File -FilePath "c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\scratch\logo_template.html" -Encoding utf8

# ----------------- 2. logo_exporter.html -----------------
$exporterHtml = @"
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>eduKN Orijinal ve Modern Logo Çıkarıcı Pro 🚀</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,900;1,900&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #05070c;
            --card-bg: rgba(255, 255, 255, 0.02);
            --border-color: rgba(255, 255, 255, 0.08);
            --primary-blue: #2563eb;
            --accent-blue: #60a5fa;
            --text-color: #f3f4f6;
        }
        body {
            background-color: var(--bg-color);
            color: var(--text-color);
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 40px 20px;
            display: flex;
            flex-direction: column;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            width: 100%;
            text-align: center;
        }
        h1 {
            font-size: 2.5rem;
            font-weight: 800;
            background: linear-gradient(135deg, #fff 30%, var(--accent-blue));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 5px;
        }
        p.subtitle {
            color: #9ca3af;
            font-size: 1.1rem;
            margin-bottom: 40px;
        }
        .section-title {
            font-size: 1.8rem;
            font-weight: 700;
            margin-top: 40px;
            margin-bottom: 20px;
            text-align: left;
            border-left: 5px solid var(--accent-blue);
            padding-left: 15px;
            color: #e5e7eb;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
            gap: 25px;
            margin-bottom: 45px;
        }
        .card {
            background: var(--card-bg);
            border: none;
            border-radius: 20px;
            padding: 25px;
            backdrop-filter: blur(10px);
            display: flex;
            flex-direction: column;
            align-items: center;
            box-shadow: 0 10px 30px rgba(0,0,0,0.5);
            transition: transform 0.2s ease, box-shadow 0.2s ease;
        }
        .card:hover {
            transform: translateY(-3px);
            box-shadow: 0 15px 40px rgba(96, 165, 250, 0.15);
        }
        .card h2 {
            font-size: 1.2rem;
            margin-top: 0;
            margin-bottom: 15px;
            color: #d1d5db;
        }
        .canvas-container {
            border-radius: 12px;
            padding: 15px;
            margin-bottom: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            width: 100%;
            box-sizing: border-box;
            border: none;
        }
        .koyu-tema {
            background: #0B0F19; 
            box-shadow: inset 0 2px 8px rgba(0,0,0,0.6);
        }
        .acik-tema {
            background: #FFFFFF; 
            box-shadow: inset 0 2px 8px rgba(0,0,0,0.1);
        }
        canvas, img {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
        }
        .btn-group {
            display: flex;
            gap: 10px;
            width: 100%;
        }
        .btn {
            background: linear-gradient(135deg, var(--primary-blue), #1d4ed8);
            color: white;
            border: none;
            padding: 12px 20px;
            font-size: 0.9rem;
            font-weight: 600;
            border-radius: 10px;
            cursor: pointer;
            transition: all 0.2s ease;
            box-shadow: 0 4px 12px rgba(37, 99, 235, 0.3);
            display: inline-flex;
            align-items: center;
            gap: 8px;
            flex: 1;
            justify-content: center;
            text-decoration: none;
        }
        .btn-svg {
            background: linear-gradient(135deg, #10b981, #059669);
            box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
        }
        .btn:hover {
            transform: scale(1.02);
            opacity: 0.95;
        }
    </style>
</head>
<body>

<div class="container">
    <h1>eduKN Orijinal ve Modern Logo Çıkarıcı Pro 🚀</h1>
    <p class="subtitle">Orijinal logolarınız aynen korundu! Çok beğendiğiniz o 3D modern logolarınız da transparan olarak eklendi.</p>

    <!-- KOYU TEMA SETİ -->
    <div class="section-title">A. Orijinal Koyu Tema Seti (Şeffaf Arka Plan - Orijinal Chevron Simgesi)</div>
    <div class="grid">
        <div class="card">
            <h2>1. Orijinal İkon (Koyu Tema)</h2>
            <div class="canvas-container koyu-tema">
                <canvas id="iconKoyu" width="512" height="512"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('iconKoyu', 'logo_icon_dark.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('iconKoyu', 'logo_icon_dark.svg')">SVG</button>
            </div>
        </div>

        <div class="card">
            <h2>2. Orijinal Tam Logo (Koyu Tema)</h2>
            <div class="canvas-container koyu-tema">
                <canvas id="fullKoyu" width="1200" height="400"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('fullKoyu', 'logo_full_dark.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('fullKoyu', 'logo_full_dark.svg')">SVG</button>
            </div>
        </div>

        <div class="card">
            <h2>3. Sadece eduKN Yazısı (Koyu Tema)</h2>
            <div class="canvas-container koyu-tema">
                <canvas id="textKoyu" width="1200" height="400"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('textKoyu', 'logo_text_dark.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('textKoyu', 'logo_text_dark.svg')">SVG</button>
            </div>
        </div>
    </div>

    <!-- BEYAZ ZEMİN AÇIK TEMA SETİ -->
    <div class="section-title">B. Beyaz Zemin Açık Tema Seti (Şeffaf Arka Plan - Orijinal Chevron Simgesi)</div>
    <div class="grid">
        <div class="card">
            <h2>4. Orijinal İkon (Beyaz Zemin)</h2>
            <div class="canvas-container acik-tema">
                <canvas id="iconAcik" width="512" height="512"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('iconAcik', 'logo_icon_light.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('iconAcik', 'logo_icon_light.svg')">SVG</button>
            </div>
        </div>

        <div class="card">
            <h2>5. Orijinal Tam Logo (Beyaz Zemin)</h2>
            <div class="canvas-container acik-tema">
                <canvas id="fullAcik" width="1200" height="400"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('fullAcik', 'logo_full_light.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('fullAcik', 'logo_full_light.svg')">SVG</button>
            </div>
        </div>

        <div class="card">
            <h2>6. Sadece eduKN Yazısı (Beyaz Zemin)</h2>
            <div class="canvas-container acik-tema">
                <canvas id="textAcik" width="1200" height="400"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('textAcik', 'logo_text_light.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('textAcik', 'logo_text_light.svg')">SVG</button>
            </div>
        </div>
    </div>

    <!-- ÇOK BEĞENİLEN 3D MODERN SET -->
    <div class="section-title">C. Çok Beğendiğiniz 3D Modern Set (Orijinal Yüksek Kalite Şeffaf)</div>
    <div class="grid">
        <div class="card">
            <h2>7. Beğendiğiniz Modern Kare İkon (3D)</h2>
            <div class="canvas-container acik-tema">
                <canvas id="modernIcon" width="512" height="512"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('modernIcon', 'google_auth_logo.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('modernIcon', 'google_auth_logo.svg')">SVG</button>
            </div>
        </div>

        <div class="card">
            <h2>8. Beğendiğiniz Modern Tam Logo (Koyu Tema)</h2>
            <div class="canvas-container koyu-tema">
                <canvas id="modernFullKoyu" width="1200" height="400"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('modernFullKoyu', 'google_auth_full_logo.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('modernFullKoyu', 'google_auth_full_logo.svg')">SVG</button>
            </div>
        </div>

        <div class="card">
            <h2>9. Beğendiğiniz Modern Tam Logo (Açık Tema)</h2>
            <div class="canvas-container acik-tema">
                <canvas id="modernFullAcik" width="1200" height="400"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('modernFullAcik', 'google_auth_full_logo_light.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('modernFullAcik', 'google_auth_full_logo_light.svg')">SVG</button>
            </div>
        </div>

        <div class="card">
            <h2>10. Beğendiğiniz Modern Kare İkon (3D - Beyaz Zemin)</h2>
            <div class="canvas-container acik-tema">
                <canvas id="modernIconLight" width="512" height="512"></canvas>
            </div>
            <div class="btn-group">
                <button class="btn" onclick="downloadCanvas('modernIconLight', 'google_auth_logo_light.png')">PNG</button>
                <button class="btn btn-svg" onclick="downloadSVG('modernIconLight', 'google_auth_logo_light.svg')">SVG</button>
            </div>
        </div>
    </div>
</div>

<script>
    // 1. Orijinal Chevron Koordinatları (Orijinal logolar için)
    const path1_raw = [[0, 15], [35, 15], [55, 40], [35, 65], [0, 65], [20, 40]];
    const path2_raw = [[25, 15], [60, 15], [80, 40], [60, 65], [25, 65], [45, 40]];
    const path3_raw = [[50, 15], [85, 15], [105, 40], [85, 65], [50, 65], [70, 40]];

    function drawChevron(ctx, points) {
        ctx.beginPath();
        ctx.moveTo(points[0][0], points[0][1]);
        for (let i = 1; i < points.length; i++) ctx.lineTo(points[i][0], points[i][1]);
        ctx.closePath();
    }

    // Base64 görseli yükle
    const img = new Image();
    img.src = "data:image/png;base64,$base64"; 

    img.onload = function() {
        initAll();
    };

    function draw3DLogoIcon(ctx, destX, destY, destW, destH) {
        if (img.complete && img.naturalWidth !== 0) {
            const tempCanvas = document.createElement('canvas');
            tempCanvas.width = img.width;
            tempCanvas.height = img.height;
            const tempCtx = tempCanvas.getContext('2d');
            tempCtx.drawImage(img, 0, 0);
            
            const imgData = tempCtx.getImageData(0, 0, tempCanvas.width, tempCanvas.height);
            const data = imgData.data;
            
            const centerX = img.width / 2;
            const centerY = img.height / 2;
            
            for (let y = 0; y < img.height; y++) {
                for (let x = 0; x < img.width; x++) {
                    const idx = (y * img.width + x) * 4;
                    let r = data[idx];
                    let g = data[idx+1];
                    let b = data[idx+2];
                    let brightness = (r + g + b) / 3;
                    
                    // 1. Dış dairesel gri halka/gölge temizliği (dist > 145 ve nötr renkler için)
                    let dx = x - centerX;
                    let dy = y - centerY;
                    let dist = Math.sqrt(dx*dx + dy*dy);
                    
                    if (dist > 145) {
                        let maxDiff = Math.max(Math.abs(r - g), Math.abs(g - b), Math.abs(r - b));
                        if (maxDiff < 40 && brightness > 100) {
                            data[idx+3] = 0; // Tamamen transparan
                            continue;
                        }
                    }
                    
                    // 2. Açık mavi/cyan tüylü gölge kalıntılarını temizle (dist > 125 ve r > 160 açık parıltı)
                    if (dist > 125) {
                        if (r > 160 && b > 180 && g > 180) {
                            data[idx+3] = 0; // Tamamen transparan yap
                            continue;
                        }
                    }
                    
                    // 3. GELİŞMİŞ PÜRÜZSÜZLEŞTİRİCİ V2 (Siyah Nokta Korumalı)
                    let distToWhite = Math.sqrt((255-r)*(255-r) + (255-g)*(255-g) + (255-b)*(255-b));
                    let maxDiff = Math.max(r, g, b) - Math.min(r, g, b);
                    let effDist = distToWhite + maxDiff * 1.5;
                    
                    let thresholdMin = 45;
                    let thresholdMax = 190;
                    
                    if (effDist < thresholdMin) {
                        data[idx+3] = 0; // Tamamen transparan arka plan
                    } else if (effDist < thresholdMax) {
                        // Kenar yumuşatma (Yumuşak kenar anti-aliasing)
                        let A = (effDist - thresholdMin) / (thresholdMax - thresholdMin);
                        data[idx+3] = Math.round(A * 255);
                        
                        // Sadece parlak ve renkli pikselleri unmultiply yap (Koyu gölgelerin siyaha düşmesini önler)
                        if (A > 0.05 && maxDiff > 30 && r > 90 && g > 90 && b > 90) {
                            data[idx] = Math.max(0, Math.min(255, Math.round((r - (1 - A) * 255) / A)));
                            data[idx+1] = Math.max(0, Math.min(255, Math.round((g - (1 - A) * 255) / A)));
                            data[idx+2] = Math.max(0, Math.min(255, Math.round((b - (1 - A) * 255) / A)));
                        }
                    } else {
                        data[idx+3] = 255; // Gövde içi tamamen mat kalır
                    }
                }
            }
            tempCtx.putImageData(imgData, 0, 0);
            
            ctx.drawImage(tempCanvas, destX, destY, destW, destH);
        }
    }

    function drawIconCanvas(canvasId) {
        const canvas = document.getElementById(canvasId);
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        ctx.save();
        const scale = 3.2; 
        ctx.translate(256 - (66.8 * scale), 256 - (50 * scale) - 20); 
        ctx.scale(scale, scale);
        ctx.translate(25, 10);
        ctx.transform(1, 0, -0.267949, 1, 0, 0);

        let grad1 = ctx.createLinearGradient(0, 15, 55, 65);
        grad1.addColorStop(0, '#1E3A8A'); grad1.addColorStop(1, '#2563EB');
        ctx.fillStyle = grad1; drawChevron(ctx, path1_raw); ctx.fill();

        let grad2 = ctx.createLinearGradient(25, 65, 80, 15);
        grad2.addColorStop(0, '#2563EB'); grad2.addColorStop(1, '#60A5FA');
        ctx.fillStyle = grad2; drawChevron(ctx, path2_raw); ctx.fill();

        ctx.save(); ctx.shadowColor = '#60A5FA'; ctx.shadowBlur = 10; ctx.fillStyle = '#60A5FA'; drawChevron(ctx, path3_raw); ctx.fill(); ctx.restore();
        ctx.restore();
    }

    function drawFullLogoCanvas(canvasId, isDarkBg) {
        const canvas = document.getElementById(canvasId);
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        ctx.save();
        const scale = 2.4; 
        ctx.translate(90, 200 - (50 * scale) - 22); 
        ctx.scale(scale, scale);
        ctx.translate(25, 10);
        ctx.transform(1, 0, -0.267949, 1, 0, 0);

        let grad1 = ctx.createLinearGradient(0, 15, 55, 65);
        grad1.addColorStop(0, '#1E3A8A'); grad1.addColorStop(1, '#2563EB');
        ctx.fillStyle = grad1; drawChevron(ctx, path1_raw); ctx.fill();

        let grad2 = ctx.createLinearGradient(25, 65, 80, 15);
        grad2.addColorStop(0, '#2563EB'); grad2.addColorStop(1, '#60A5FA');
        ctx.fillStyle = grad2; drawChevron(ctx, path2_raw); ctx.fill();

        ctx.save(); ctx.shadowColor = '#60A5FA'; ctx.shadowBlur = 10; ctx.fillStyle = '#60A5FA'; drawChevron(ctx, path3_raw); ctx.fill(); ctx.restore();
        ctx.restore();

        ctx.save();
        ctx.translate(460, 200); ctx.transform(1, 0, -0.267949, 1, 0, 0);
        ctx.font = "italic 900 170px 'Roboto', sans-serif"; ctx.textBaseline = "middle";
        ctx.fillStyle = isDarkBg ? "#FFFFFF" : "#111827"; ctx.fillText("edu", 0, 0);
        let eduWidth = ctx.measureText("edu").width;
        ctx.fillStyle = "#1E3A8A"; ctx.fillText("KN", eduWidth - 12, 0);
        ctx.restore();
    }

    function drawTextOnlyCanvas(canvasId, isDarkBg) {
        const canvas = document.getElementById(canvasId);
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.save();
        ctx.font = "italic 900 190px 'Roboto', sans-serif"; ctx.textBaseline = "middle";
        let eduWidth = ctx.measureText("edu").width;
        let knWidth = ctx.measureText("KN").width;
        let totalWidth = eduWidth + knWidth - 14; 
        ctx.translate(600, 200); ctx.transform(1, 0, -0.267949, 1, 0, 0);
        ctx.fillStyle = isDarkBg ? "#FFFFFF" : "#111827"; ctx.fillText("edu", -totalWidth / 2, 0);
        ctx.fillStyle = "#1E3A8A"; ctx.fillText("KN", -totalWidth / 2 + eduWidth - 14, 0);
        ctx.restore();
    }

    // Modern 3D Çizimleri
    function drawModernIconCanvas() {
        const canvas = document.getElementById('modernIcon');
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        draw3DLogoIcon(ctx, 0, 0, 512, 512);
    }

    function drawModernIconLightCanvas() {
        const canvas = document.getElementById('modernIconLight');
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = "#FFFFFF";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        draw3DLogoIcon(ctx, 0, 0, 512, 512);
    }

    function drawModernFullCanvas(canvasId, isDarkBg) {
        const canvas = document.getElementById(canvasId);
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        const targetH = 345;
        const targetW = 345;
        const iconY = 200 - targetH / 2;
        
        draw3DLogoIcon(ctx, 70, iconY, targetW, targetH);
        
        ctx.save();
        ctx.translate(445, 214);
        ctx.transform(1, 0, -0.267949, 1, 0, 0);
        ctx.font = "italic 900 160px 'Roboto', sans-serif"; ctx.textBaseline = "middle";
        ctx.fillStyle = isDarkBg ? "#FFFFFF" : "#111827"; ctx.fillText("edu", 0, 0);
        let eduWidth = ctx.measureText("edu").width;
        ctx.fillStyle = "#1E3A8A"; ctx.fillText("KN", eduWidth - 12, 0);
        ctx.restore();
    }

    function downloadSVG(canvasId, filename) {
        const canvas = document.getElementById(canvasId);
        const base64Png = canvas.toDataURL('image/png');
        
        let width = canvas.width;
        let height = canvas.height;
        
        const svgContent = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \${width} \${height}" width="\${width}" height="\${height}"><image href="\${base64Png}" x="0" y="0" width="\${width}" height="\${height}"/></svg>`;
        
        const blob = new Blob([svgContent], {type: 'image/svg+xml;charset=utf-8'});
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url; a.download = filename; document.body.appendChild(a); a.click(); document.body.removeChild(a); URL.revokeObjectURL(url);
    }

    function initAll() {
        // Orijinal logolar çiziliyor
        drawIconCanvas('iconKoyu'); drawFullLogoCanvas('fullKoyu', true); drawTextOnlyCanvas('textKoyu', true);
        drawIconCanvas('iconAcik'); drawFullLogoCanvas('fullAcik', false); drawTextOnlyCanvas('textAcik', false);
        
        // Modern 3D logolar çiziliyor
        drawModernIconCanvas();
        drawModernIconLightCanvas();
        drawModernFullCanvas('modernFullKoyu', true);
        drawModernFullCanvas('modernFullAcik', false);
    }

    function downloadCanvas(canvasId, filename) {
        const canvas = document.getElementById(canvasId);
        const url = canvas.toDataURL('image/png');
        const a = document.createElement('a');
        a.href = url; a.download = filename; document.body.appendChild(a); a.click(); document.body.removeChild(a);
    }
</script>

</body>
</html>
"@

$exporterHtml | Out-File -FilePath "c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\scratch\logo_exporter.html" -Encoding utf8

Write-Host "logo_template.html and logo_exporter.html successfully regenerated with embedded Base64 3D logo icon!" -ForegroundColor Green
