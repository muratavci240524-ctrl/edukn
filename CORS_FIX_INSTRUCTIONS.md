# Firebase Storage CORS Hatası Çözümü

Bilgisayarınızda `gsutil` aracı yüklü olmadığı için komut çalışmadı. En kolay çözüm, Google'ın kendi online terminalini (Cloud Shell) kullanmaktır.

Lütfen aşağıdaki adımları sırasıyla uygulayın:

1.  **Google Cloud Console'u Açın:**
    Aşağıdaki linke tıklayarak projenizin Storage sayfasına gidin:
    [https://console.cloud.google.com/storage/browser?project=edukn-23036](https://console.cloud.google.com/storage/browser?project=edukn-23036)

2.  **Cloud Shell'i Başlatın:**
    Sayfanın sağ üst köşesindeki **Terminal ikonuna** ( >_ simgesi) tıklayın. Sayfanın altında bir terminal penceresi açılacaktır.

3.  **Ayar Dosyasını Oluşturun:**
    Açılan terminale şu komutu yapıştırın ve Enter'a basın:
    ```bash
    nano cors.json
    ```

4.  **İçeriği Yapıştırın:**
    Açılan editör ekranına aşağıdaki parantezli kısmı tamamen kopyalayıp yapıştırın:
    ```json
    [
      {
        "origin": ["*"],
        "method": ["GET", "PUT", "POST", "DELETE", "HEAD", "OPTIONS"],
        "responseHeader": ["*"],
        "maxAgeSeconds": 3600
      }
    ]
    ```

5.  **Kaydedin:**
    *   `Ctrl + O` tuşlarına basın, sonra `Enter`'a basın (Kaydetmek için).
    *   `Ctrl + X` tuşlarına basın (Çıkmak için).

6.  **Komutu Çalıştırın:**
    Şimdi terminale şu komutu yapıştırın ve Enter'a basın:
    ```bash
    gsutil cors set cors.json gs://edukn-23036.firebasestorage.app
    ```

Bu işlemden sonra "Setting CORS on..." gibi bir mesaj göreceksiniz. İşlem tamamlanmış demektir. Uygulamaya dönüp tekrar dosya yüklemeyi deneyebilirsiniz.
