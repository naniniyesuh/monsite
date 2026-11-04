# MonSite — App Store yayın rehberi

Bu dosya, MonSite'ı App Store'a göndermek için gereken her şeyi içerir: kontrol listesi, App Store Connect'e yapıştırılacak metinler, gizlilik ve yaş derecelendirmesi cevapları, inceleme notu ve ekran görüntüsü planı.

Projede hazır olanlar:

- Bundle ID `studio.alpp.monsite`, sürüm 1.0 (1)
- 1024×1024 uygulama simgesi (saydamlık yok)
- Gizlilik manifesti (`PrivacyInfo.xcprivacy`): veri toplama yok, takip yok
- Şifreleme beyanı (`ITSAppUsesNonExemptEncryption = NO`); her yüklemede export compliance sorusu çıkmaz
- Arka plan yenileme (`fetch`) ve görev kimliği `studio.alpp.monsite.refresh`
- Hassas dosya taraması varsayılan olarak kapalı; açarken site sahipliği onayı isteniyor
- Hakkında ekranı: gizlilik politikası ve destek bağlantıları
- Gizlilik ve destek sayfaları: https://alpp.studio/monsite/ (ayrı `alpp.studio` deposunda)
- GitHub Actions derlemesi: her push'ta Xcode 16.4 ile derleniyor

---

## 1. Kontrol listesi

### Bir kez yapılacaklar

- [ ] **Apple Developer Program üyeliği** (yıllık 99 USD). MANDIRAKE için zaten varsa bu adımı atlayın.
- [ ] **alpp.studio sitesinin yayında olduğunu kontrol edin.** MonSite sayfaları ayrı `alpp.studio` deposunda. Şu adresler açılmalı:
  - https://alpp.studio/monsite/
  - https://alpp.studio/monsite/privacy/
- [ ] **Bundle ID'yi kaydedin.** Xcode → MonSite hedefi → **Signing & Capabilities** → Team'i seçin, **Automatically manage signing** açık kalsın. Xcode, `studio.alpp.monsite` kimliğini geliştirici hesabınıza kendisi kaydeder.

### App Store Connect

- [ ] https://appstoreconnect.apple.com → **Uygulamalar** → **+** → **Yeni Uygulama**
  - Platform: iOS
  - Ad: `MonSite` (alınmışsa `MonSite: Site İzleme`)
  - Birincil dil: Türkçe
  - Bundle ID: `studio.alpp.monsite`
  - SKU: `monsite-ios-1`
  - Kullanıcı erişimi: Tam erişim
- [ ] **Uygulama Bilgileri**
  - Kategori: birincil **Geliştirici Araçları**, ikincil **Yardımcı Uygulamalar**
  - Gizlilik politikası URL'si: `https://alpp.studio/monsite/privacy/`
  - İngilizce yerelleştirme ekleyin (sağ üstteki dil menüsü → İngilizce (ABD)). Bölüm 2'deki İngilizce metinleri kullanın.
- [ ] **Yaş derecelendirmesi**: bölüm 3'teki cevaplar → 4+
- [ ] **Uygulama Gizliliği** → **Veri Toplanmıyor** (bölüm 4)
- [ ] **Fiyatlandırma ve Erişilebilirlik**: Ücretsiz, tüm ülkeler
- [ ] **1.0 sürüm sayfası**: bölüm 2'deki metinler, bölüm 6'daki ekran görüntüleri, bölüm 5'teki inceleme notu
  - Telif hakkı: `2026 <adınız soyadınız>`

### Derleme ve gönderme

- [ ] Xcode'da üstteki cihaz menüsünden **Any iOS Device (arm64)** seçin.
- [ ] **Product → Archive**. Bittiğinde Organizer penceresi açılır.
- [ ] **Distribute App** → **App Store Connect** → **Distribute**.
- [ ] 10–30 dakika sonra derleme App Store Connect → **TestFlight** sekmesinde görünür.
- [ ] Kendi telefonunuzda TestFlight ile deneyin: tarama, izleme ekleme, bildirim, Hakkında ekranındaki bağlantılar.
- [ ] Sürüm sayfasında **Derleme** bölümünden bu derlemeyi seçin → **İncelemeye Gönder**.

İnceleme genellikle 1–3 gün sürer.

### Sonraki sürümler

Her yüklemede `CURRENT_PROJECT_VERSION` (derleme numarası) artmalı. Xcode → MonSite hedefi → **General** → **Build** alanını 2, 3 … diye artırın. Yeni özellik içeren sürümlerde **Version** değerini de artırın (1.1, 1.2 …).

---

## 2. Mağaza metinleri

### Türkçe

**Ad** (30 karakter sınırı)
```
MonSite
```

**Alt başlık** (30 karakter sınırı)
```
Site sağlığı, hız, SSL takibi
```

**Tanıtım metni** (170 karakter sınırı; inceleme gerektirmeden değiştirilebilir)
```
Sitenizi tek dokunuşla tarayın: kırık bağlantılar, yavaş sayfalar, güvenlik eksikleri ve SSL bitiş tarihi tek raporda. Düzenli izlemeyle değişiklikleri kaçırmayın.
```

**Açıklama**
```
MonSite, web sitenizi baştan sona gezer ve sağlığını tek bir raporda gösterir: bağlantılar, performans, erişilebilirlik, SEO, güvenlik ve SSL. Adresi yazın, taramayı başlatın; gerisini MonSite halleder.

KIRIK BAĞLANTI VE KAYNAKLAR
• Sitedeki tüm sayfaları sırayla açar, 404 ve sunucu hatalarını bulur
• Yüklenemeyen resim, script, CSS, font ve dosyaları listeler
• Açılamayan bozuk resimleri ve hata sayfası döndüren adresleri yakalar
• Dış bağlantıların hâlâ çalışıp çalışmadığını kontrol eder
• Sitemap ve robots.txt'yi okur, CSS içindeki font ve resimleri de kontrol eder

PERFORMANS
• Her sayfa için DNS, bağlantı, TLS, ilk bayt ve indirme süreleri
• En yavaş sayfalar ve en yavaş yüklenen parçalar
• Sıkıştırma, önbellek, HTTP/2, oluşturmayı engelleyen script'ler
• Aşırı büyük resimler ve sayfa ağırlığı

ERİŞİLEBİLİRLİK (WCAG)
• Alt metni olmayan görseller, adı olmayan bağlantı ve düğmeler
• Etiketi olmayan form alanları, sayfa dili, başlık yapısı
• Yakınlaştırmanın engellenmesi, başlıksız iframe'ler ve daha fazlası

SEO
• Başlık ve meta açıklama kontrolleri, yinelenen başlıklar
• Canonical, noindex, mobil uyum, sosyal medya etiketleri
• Sitemap, robots.txt, yetim sayfalar ve soft 404

GÜVENLİK
• HTTPS kullanımı ve HTTP'den HTTPS'e yönlendirme
• HSTS, CSP, clickjacking koruması gibi güvenlik başlıkları
• Çerez güvenlik ayarları, karışık içerik, şifresiz gönderilen formlar
• CSP ve HSTS kalitesi, dış script'lerde bütünlük (SRI) kontrolü
• Sunucu sürüm bilgisi sızıntıları, security.txt
• İsteğe bağlı: herkese açık kalmış .git, .env ve yedek dosyaları

SSL SERTİFİKASI
• Güvenilirlik, sertifikayı veren kuruluş, başlangıç ve bitiş tarihi
• Bitişe kaç gün kaldığı; süre yaklaşınca uyarı
• Anahtar türü ve uzunluğu

SAĞLIK PUANI
• Genel puan ve A–F not, ayrıca beş alanın her biri için ayrı puan
• Sorunlar önem derecesine ve kategoriye göre gruplanır

ZAMANLANMIŞ İZLEME
• Sitelerinizi dakikalık, saatlik veya günlük aralıklarla izleyin
• Her kontrol bir öncekiyle karşılaştırılır: yeni ve çözülen sorunlar, bozulan ve düzelen kaynaklar, yavaşlayan sayfalar, sertifika yenilenmesi
• Çalışırlık yüzdesi, ortalama yanıt süresi ve son kesinti
• Ana sayfada beklenen bir metin yoksa kesinti olarak algılama
• Değişiklik olunca bildirim
• Puan, yükleme süresi ve sorun sayısı için eğilim grafikleri

GİZLİLİK
MonSite hiçbir kişisel veri toplamaz. Hesap gerekmez, reklam ve takip yoktur. Tüm sonuçlar yalnızca cihazınızda saklanır.

Raporları metin veya JSON olarak paylaşabilirsiniz.

Not: Arka plandaki kontrollerin zamanını iOS belirler; uygulama açıkken kontroller seçtiğiniz sıklıkta yapılır. Taramaları yalnızca size ait veya test izniniz olan sitelerde yapın.
```

**Anahtar kelimeler** (100 karakter sınırı, virgülle, boşluksuz)
```
web,site,denetim,izleme,ssl,sertifika,kırık link,hız,güvenlik,uptime,seo,wcag,erişilebilirlik
```

**Destek URL'si**
```
https://alpp.studio/monsite/
```

**Pazarlama URL'si** (isteğe bağlı)
```
https://alpp.studio/
```

### English (U.S.)

**Name**
```
MonSite
```

**Subtitle**
```
Website health, speed and SSL
```

**Promotional text**
```
Scan your site in one tap: broken links, slow pages, security gaps and SSL expiry in a single report. Schedule checks and get notified when something changes.
```

**Description**
```
MonSite crawls your website from top to bottom and shows its health in a single report: links, performance, accessibility, SEO, security and SSL. Type the address, start the scan, and MonSite does the rest.

BROKEN LINKS AND RESOURCES
• Opens every page on the site and finds 404s and server errors
• Lists images, scripts, CSS, fonts and files that fail to load
• Catches corrupt images and addresses that return an error page instead
• Checks whether external links still work
• Reads sitemap and robots.txt, and checks fonts and images referenced in CSS

PERFORMANCE
• DNS, connect, TLS, time-to-first-byte and download times for every page
• Slowest pages and slowest-loading resources
• Compression, caching, HTTP/2 and render-blocking scripts
• Oversized images and page weight

ACCESSIBILITY (WCAG)
• Images without alt text, links and buttons without names
• Unlabeled form fields, page language, heading structure
• Disabled zoom, untitled iframes and more

SEO
• Title and meta description checks, duplicate titles
• Canonical, noindex, mobile viewport, social preview tags
• Sitemap, robots.txt, orphan pages and soft 404s

SECURITY
• HTTPS usage and HTTP-to-HTTPS redirects
• Security headers such as HSTS, CSP and clickjacking protection
• Cookie flags, mixed content and forms submitted over plain HTTP
• CSP and HSTS quality, Subresource Integrity for external scripts
• Server version disclosure, security.txt
• Optional: publicly exposed .git, .env and backup files

SSL CERTIFICATE
• Trust status, issuer, start and expiry dates
• Days remaining, with a warning as expiry approaches
• Key type and size

HEALTH SCORE
• An overall score and A–F grade, plus a separate score for each of five areas
• Issues grouped by severity and category

SCHEDULED MONITORING
• Monitor your sites every minute, hour or day
• Every check is compared with the previous one: new and resolved issues, newly broken and fixed resources, slower pages, certificate renewals
• Uptime percentage, average response time and last downtime
• Detects downtime when expected text is missing from the home page
• Notifications when something changes
• Trend charts for score, load time and issue count

PRIVACY
MonSite collects no personal data. No account, no ads, no tracking. All results are stored only on your device.

Share reports as text or JSON.

Note: iOS decides when background checks run; while the app is open, checks run at the interval you choose. Only scan sites you own or are authorized to test.
```

**Keywords**
```
website,monitor,uptime,ssl,certificate,broken link,checker,speed,security,seo,wcag,accessibility
```

**Support URL** / **Marketing URL**: same as above.

---

## 3. Yaş derecelendirmesi

Bütün içerik sorularına (şiddet, cinsellik, kumar, uyuşturucu, korku vb.) **Hiç / Yok** cevabını verin.

| Soru | Cevap |
|---|---|
| Sınırsız web erişimi | Hayır. Uygulama web sayfası göstermez; yalnızca HTTP isteği gönderip yanıtı analiz eder. Bağlantılar Safari'de açılır. |
| Kullanıcı tarafından oluşturulan içerik | Hayır |
| Mesajlaşma ve sohbet | Hayır |
| Reklam | Hayır |
| Ebeveyn denetimi / yaş doğrulama | Hayır |

Sonuç: **4+**

---

## 4. Uygulama gizliliği (App Privacy)

- "Bu uygulamadan veri topluyor musunuz?" → **Hayır, bu uygulamadan veri toplamıyoruz**
- Sonuç etiketi: **Veri Toplanmıyor**

Gerekçe: Tarama sonuçları ve ayarlar yalnızca cihazda saklanıyor. Uygulamada analitik, reklam veya crash raporlama SDK'sı yok. Ağ istekleri yalnızca kullanıcının girdiği sitelere gidiyor.

---

## 5. App Review notu (Review Notes)

İngilizce yazın. **Sign-in required** kutusunu boş bırakın.

```
MonSite is a website auditing and monitoring tool for site owners and developers. No account or sign-in is required.

How to test:
1. On the "Tarama" (Scan) tab, enter any website address (e.g. apple.com or example.com) and tap "Taramayı başlat" (Start scan).
2. The report shows a health score, broken links/resources, load times, security headers and the SSL certificate.
3. On the "İzleme" (Monitoring) tab, tap + to add a site and choose an interval. The first check runs immediately. Tap "Şimdi kontrol et" (Check now) again to create a second run; the run detail shows differences from the previous check.

About NSAllowsArbitraryLoads:
The app audits websites the user enters, which may still use plain HTTP. Auditing a site requires connecting to it over HTTP, for example to check whether HTTP redirects to HTTPS or to report that the site does not use HTTPS. The app never displays web content; it only sends requests and analyzes the responses.

About background fetch:
BGAppRefreshTask is used to run lightweight scheduled checks for the user's monitored sites and to post a local notification if the results changed. No remote server is involved.

About the optional sensitive file check:
It is off by default and requires the user to confirm they manage the site. It only requests a short list of well-known public paths (such as /.git/HEAD or /.env) to warn site owners about files exposed by misconfiguration. No exploitation or authentication attempts are made.

All data stays on the device. The app collects no personal data.
Contact: help@alpp.studio
```

---

## 6. Ekran görüntüleri

**Gerekli boyut**

- **iPhone 6.9"**: 1320 × 2868. Uygulama yalnızca iPhone'u desteklediği için iPad görüntüsü gerekmiyor.

Hazır görüntüler ve App Review için tanıtım videosu, her `v1.1` push'unda GitHub Actions tarafından simülatörde otomatik çekilip `screenshots` dalına konuyor: https://github.com/naniniyesuh/monsite/tree/screenshots

**Elle almak isterseniz**

Simülatörde uygulamayı çalıştırın, ekranı hazırlayın ve **⌘S** tuşuna basın. Görüntü masaüstüne doğru boyutta kaydedilir.

Durum çubuğunu temizlemek için (saat 9:41, tam pil) Terminal'e şunu yazın:
```
xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
```

**Önerilen sıra**

1. Rapor ekranı: puan halkası ve ölçüm kartları. Puanı iyi çıkan bir site seçin.
2. Kategoriler ve sorun listesi
3. Sayfa ayrıntısı: zamanlama (DNS, TLS, TTFB)
4. İzleme listesi: birkaç site eklenmiş halde
5. Kontrol farkları: çözülen sorunlar ve hızlanan sayfalar

Görüntülerin üstüne başlık eklemek isterseniz önerilen kısa başlıklar:

1. Sitenizin sağlığı tek bakışta
2. Kırık bağlantıları anında bulun
3. Her sayfanın hızını ölçün
4. Sitelerinizi düzenli izleyin
5. Neyin değiştiğini görün

---

## 7. Olası inceleme soruları

- **Ad çakışması:** "MonSite" adı App Store'da alınmışsa yeni uygulama oluştururken hata alırsınız. `MonSite: Site İzleme` gibi bir ad deneyin. Ana ekrandaki ad yine "MonSite" kalır.
- **Arka plan kullanımı:** İnceleme ekibi `fetch` modunun ne için kullanıldığını sorabilir. İnceleme notu bunu açıklıyor.
- **"Güvenlik tarayıcısı" algısı:** Hassas dosya taraması varsayılan olarak kapalı, açarken onay isteniyor ve yalnızca bilinen herkese açık yollara bakıyor. İnceleme notu bunu da açıklıyor. Ret gelirse bu özelliği 1.0'dan çıkarıp sonraki sürüme bırakmak en hızlı çözüm.
- **Simge çözünürlüğü:** Mevcut simge düşük çözünürlüklü bir görselden büyütüldü. Yüksek çözünürlüklü logo varsa göndermeden önce değiştirmek iyi olur.
