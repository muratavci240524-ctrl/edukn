import math
from PIL import Image, ImageDraw, ImageFont, ImageChops

def transform_point(x, y, scale_x, scale_y, skew_factor, trans_x, trans_y):
    # 1. Scale
    xs = x * scale_x
    ys = y * scale_y
    
    # 2. Translate (koddaki translate(25, 10))
    xt = xs + 25 * scale_x
    yt = ys + 10 * scale_y
    
    # 3. SkewX (tan(-15 deg) = -0.267949)
    # x_skewed = x + y * factor
    # y_skewed = y
    # Skew merkezini şeklin ortası (y=40) civarı almak veya koddaki gibi sol üstten eğmek:
    x_skew = xt + yt * skew_factor
    y_skew = yt
    
    # 4. Genel merkeze hizalama (tuvalin ortasına taşımak için)
    return (x_skew + trans_x, y_skew + trans_y)

def draw_gradient_polygon(draw, points, color1, color2):
    # Çokgenin bounding box'ını bul
    min_x = min(p[0] for p in points)
    max_x = max(p[0] for p in points)
    min_y = min(p[1] for p in points)
    max_y = max(p[1] for p in points)
    
    # Çokgen maskesi oluştur
    mask = Image.new("L", (2048, 2048), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.polygon(points, fill=255)
    
    # Gradyan resmi oluştur
    grad = Image.new("RGBA", (2048, 2048))
    grad_draw = ImageDraw.Draw(grad)
    
    # Linear gradient hesapla (topLeft to bottomRight veya bottomLeft to topRight)
    for y in range(int(min_y), int(max_y) + 1):
        if y < 0 or y >= 2048: continue
        for x in range(int(min_x), int(max_x) + 1):
            if x < 0 or x >= 2048: continue
            
            # Normalizasyon faktörü (0 ile 1 arası)
            # Top-Left to Bottom-Right için basit bir projeksiyon
            t = ((x - min_x) / (max_x - min_x + 1) + (y - min_y) / (max_y - min_y + 1)) / 2.0
            t = max(0.0, min(1.0, t))
            
            # Renk interpolasyonu
            r = int(color1[0] + (color2[0] - color1[0]) * t)
            g = int(color1[1] + (color2[1] - color1[1]) * t)
            b = int(color1[2] + (color2[2] - color1[2]) * t)
            a = int(color1[3] + (color2[3] - color1[3]) * t)
            
            grad.putpixel((x, y), (r, g, b, a))
            
    # Maske ile gradyanı birleştir
    return grad, mask

def generate_logo():
    # Supersampling için 2048x2048 boyutunda çiziyoruz, sonra 512x512'ye küçülteceğiz
    canvas_size = 2048
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0)) # Şeffaf arka plan
    
    # Ölçeklendirme faktörleri (Orijinal koddaki 120x100 boyutunu tuvale yaymak için)
    scale_x = 12.0
    scale_y = 12.0
    skew_factor = -0.267949 # tan(-15)
    
    # Şekli merkeze almak için öteleme (trans_x, trans_y)
    trans_x = 650
    trans_y = 600
    
    # Orijinal koddaki koordinat yolları
    path1_raw = [(0, 15), (35, 15), (55, 40), (35, 65), (0, 65), (20, 40)]
    path2_raw = [(25, 15), (60, 15), (80, 40), (60, 65), (25, 65), (45, 40)]
    path3_raw = [(50, 15), (85, 15), (105, 40), (85, 65), (50, 65), (70, 40)]
    
    # Noktaları dönüştür
    p1 = [transform_point(x, y, scale_x, scale_y, skew_factor, trans_x, trans_y) for x, y in path1_raw]
    p2 = [transform_point(x, y, scale_x, scale_y, skew_factor, trans_x, trans_y) for x, y in path2_raw]
    p3 = [transform_point(x, y, scale_x, scale_y, skew_factor, trans_x, trans_y) for x, y in path3_raw]
    
    # 1. Parça Gradyan Renkleri
    color1_start = (0x1E, 0x3A, 0x8A, 255) # Koyu Mavi
    color1_end = (0x25, 0x63, 0xEB, 255)   # Mavi
    grad1, mask1 = draw_gradient_polygon(None, p1, color1_start, color1_end)
    img = Image.alpha_composite(img, grad1)
    
    # 2. Parça Gradyan Renkleri
    color2_start = (0x25, 0x63, 0xEB, 255) # Mavi
    color2_end = (0x60, 0xA5, 0xFA, 255)   # Açık Mavi
    grad2, mask2 = draw_gradient_polygon(None, p2, color2_start, color2_end)
    img = Image.alpha_composite(img, grad2)
    
    # 3. Parça Renkleri (Neon Parlama Efektli Açık Mavi)
    color3 = (0x60, 0xA5, 0xFA, 255)
    
    # Neon parlaması için: Önce daha geniş ve yarı şeffaf bir katman çizip bulanıklaştırıyoruz
    glow_img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    glow_draw.polygon(p3, fill=(0x60, 0xA5, 0xFA, 128))
    
    # Basit bir kutu bulanıklığı (box blur) uygulayarak parlama efekti verelim
    from PIL import ImageFilter
    glow_blurred = glow_img.filter(ImageFilter.GaussianBlur(radius=25))
    img = Image.alpha_composite(img, glow_blurred)
    
    # Üstüne asıl parlak parçayı çizelim
    final_draw = ImageDraw.Draw(img)
    final_draw.polygon(p3, fill=color3)
    
    # 512x512'ye küçült (Pürüzsüz kenarlar için)
    square_logo = img.resize((512, 512), resample=Image.Resampling.LANCZOS)
    
    # Google onay ekranı için beyaz arka planlı dairesel bir buton hazırlayalım (Önerilen tarz)
    google_btn = Image.new("RGBA", (512, 512), (255, 255, 255, 255))
    # Ortasına logoyu yerleştir (Biraz küçülterek)
    logo_small = square_logo.resize((360, 360), resample=Image.Resampling.LANCZOS)
    google_btn.paste(logo_small, (76, 76), logo_small)
    google_btn.save("c:/Users/user/Desktop/eduKN/edukn/edukn21.11.2025/edukn/assets/images/google_auth_logo.png", "PNG")
    
    print("Sadece ikon olan logo başarıyla oluşturuldu!")
    
    # --- TAM LOGO OLUŞTURMA (eduKN Yazısı İle Birlikte) ---
    # Genişlik: 1200, Yükseklik: 400 boyutunda şeffaf arka plan
    full_img = Image.new("RGBA", (2400, 800), (0, 0, 0, 0))
    
    # Sol tarafa İkonu Çiz
    scale_x_full = 8.0
    scale_y_full = 8.0
    trans_x_full = 150
    trans_y_full = 200
    
    p1_f = [transform_point(x, y, scale_x_full, scale_y_full, skew_factor, trans_x_full, trans_y_full) for x, y in path1_raw]
    p2_f = [transform_point(x, y, scale_x_full, scale_y_full, skew_factor, trans_x_full, trans_y_full) for x, y in path2_raw]
    p3_f = [transform_point(x, y, scale_x_full, scale_y_full, skew_factor, trans_x_full, trans_y_full) for x, y in path3_raw]
    
    grad1_f, _ = draw_gradient_polygon(None, p1_f, color1_start, color1_end)
    full_img = Image.alpha_composite(full_img, grad1_f)
    
    grad2_f, _ = draw_gradient_polygon(None, p2_f, color2_start, color2_end)
    full_img = Image.alpha_composite(full_img, grad2_f)
    
    glow_f = Image.new("RGBA", (2400, 800), (0, 0, 0, 0))
    glow_draw_f = ImageDraw.Draw(glow_f)
    glow_draw_f.polygon(p3_f, fill=(0x60, 0xA5, 0xFA, 128))
    glow_blurred_f = glow_f.filter(ImageFilter.GaussianBlur(radius=15))
    full_img = Image.alpha_composite(full_img, glow_blurred_f)
    
    final_draw_f = ImageDraw.Draw(full_img)
    final_draw_f.polygon(p3_f, fill=color3)
    
    # Sağ tarafa Yazıyı Yaz (eduKN)
    # Sistemde yüklü olabilecek kalın yazı tiplerini deneyelim (Roboto, Arial, Trebuchet, Segoe UI)
    font_paths = [
        "C:\\Windows\\Fonts\\arialbd.ttf",   # Arial Bold
        "C:\\Windows\\Fonts\\segoeuib.ttf",  # Segoe UI Bold
        "C:\\Windows\\Fonts\\trebucbd.ttf",  # Trebuchet MS Bold
        "C:\\Windows\\Fonts\\impact.ttf"     # Impact (ekstra kalın)
    ]
    
    font = None
    for path in font_paths:
        try:
            font = ImageFont.truetype(path, 340) # Çok büyük çizip küçülteceğiz
            break
        except:
            continue
            
    if font is None:
        font = ImageFont.load_default()
        
    # 'edu' yazısı (koyu lacivert / siyah - beyaz arka planda gözüksün diye)
    # Koddaki edu: Colors.white, KN: Color(0xFF60A5FA) idi.
    # Beyaz arka planda kullanmak için edu: #1E3A8A (koyu lacivert) yapıyoruz.
    edu_color = (0x11, 0x18, 0x27, 255) # Çok koyu gri/siyah tonu
    kn_color = (0x60, 0xA5, 0xFA, 255)   # Açık mavi
    
    # Yazıyı -15 derece eğmek için geçici bir tuvale yazıp skew uygulayacağız
    text_canvas = Image.new("RGBA", (2000, 500), (0, 0, 0, 0))
    text_draw = ImageDraw.Draw(text_canvas)
    
    # 'edu' yazısı
    text_draw.text((0, 50), "edu", fill=edu_color, font=font)
    
    # 'edu'nun bittiği yeri ölçüp yanına 'KN' yazalım
    edu_width = text_draw.textlength("edu", font=font)
    text_draw.text((edu_width - 25, 50), "KN", fill=kn_color, font=font) # -25 harfleri sıkıştırmak için
    
    # Yazıyı eğelim (Skew)
    # Pillow transform matrisi: (a, b, c, d, e, f)
    # x' = a*x + b*y + c
    # y' = d*x + e*y + f
    # SkewX için: x' = x + y * factor, y' = y
    # Pillow'da bu transform inverse olarak çalışır, bu yüzden factor'ün tersini veya düzünü denemeliyiz
    # Eğim koddaki gibi -15 derece (sola doğru yatık gibi ama sağa yatırmak için)
    skewed_text = text_canvas.transform(
        (2000, 500),
        Image.Transform.AFFINE,
        (1.0, -0.267949, 0.0, 0.0, 1.0, 0.0),
        resample=Image.Resampling.LANCZOS
    )
    
    # Eğrilmiş yazıyı ana resme yapıştır
    full_img.paste(skewed_text, (1100, 180), skewed_text)
    
    # Resmi kırpıp 1024x341 boyutuna getirelim (3:1 oranı)
    # Orijinal 2400x800'ü 1200x400'e küçültelim
    final_full = full_img.resize((1200, 400), resample=Image.Resampling.LANCZOS)
    
    # Temiz bir beyaz arka plana yapıştırarak kaydedelim
    white_bg = Image.new("RGBA", (1200, 400), (255, 255, 255, 255))
    white_bg.paste(final_full, (0, 0), final_full)
    white_bg.save("c:/Users/user/Desktop/eduKN/edukn/edukn21.11.2025/edukn/assets/images/google_auth_full_logo.png", "PNG")
    
    print("Yazılı tam logo başarıyla oluşturuldu!")

if __name__ == "__main__":
    generate_logo()
