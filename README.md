# MonSite (iOS)

Bir web sitesi adresi alır, siteyi gezer; bağlantıları, performansı, erişilebilirliği, SEO'yu, güvenliği ve SSL sertifikasını denetleyip rapor olarak gösterir. Siteleri zamanlanmış olarak izleyip her kontrolü bir öncekiyle karşılaştırır.

Kurumsal denetim araçlarının (Siteimprove, Lighthouse, UptimeRobot, Mozilla Observatory, SSL Labs gibi) telefonda, JavaScript çalıştırmadan güvenilir şekilde yapılabilen kontrollerini içerir.

## Puanlama

Rapor beş alanda ayrı puan verir: **Bağlantılar, Performans, Erişilebilirlik, SEO, Güvenlik**. Genel puan bunların ağırlıklı ortalamasıdır (%25, %20, %15, %15, %25). Kritik bir sorun varsa genel puan 59'u geçmez. Aynı sorun birçok sayfada tekrarlanıyorsa bir kez sayılır, tekrar sayısı cezayı en fazla iki katına çıkarır.

## Kontroller

| Alan | Ne kontrol ediliyor |
|---|---|
| Tarama kapsamı | Sitedeki bağlantılar sırayla gezilir (sayfa/derinlik limiti ayarlanabilir). `sitemap.xml` (sitemap index dahil) okunup bağlantı verilmeyen sayfalar da taranır. `robots.txt` kurallarına uyulur (kapatılabilir). Geçici ağ hatalarında ve 429/502/503/504 yanıtlarında bir kez daha denenir. |
| Bağlantılar ve kaynaklar | 4xx/5xx, DNS, zaman aşımı, TLS hataları. Resim, script, CSS, font, iframe, medya, PDF/zip ve dış bağlantılar. CSS dosyalarının içindeki `url()` ve `@import` kaynakları, `<style>` blokları ve `style=""` öznitelikleri. Bozuk resimler, resim/CSS/JS yerine HTML dönmesi, hedefi olmayan `#sayfa-içi` bağlantılar. |
| Sayfa bütünlüğü | Boş sayfa, eksik `</html>`, sayfada PHP/SQL/ASP.NET/Python/WordPress hata çıktısı, dizin listeleme. |
| Erişilebilirlik (WCAG 2.2 alt kümesi) | Alt metni olmayan görseller (1.1.1), adı olmayan bağlantı ve düğmeler (2.4.4, 4.1.2), etiketi olmayan form alanları (1.3.1, 3.3.2), sayfa dili (3.1.1), yakınlaştırmanın engellenmesi (1.4.4), h1 eksikliği ve atlanan başlık seviyeleri (1.3.1), başlıksız iframe'ler, yinelenen id'ler, pozitif tabindex (2.4.3), sesli otomatik oynatma (1.4.2), meta refresh (2.2.1), "buraya tıklayın" gibi anlamsız bağlantı metinleri. Renk kontrastı sayfa çizilmeden ölçülemediği için yoktur. |
| SEO | Başlık ve meta açıklama (eksik, kısa, uzun, sayfalar arasında yinelenen), canonical, noindex (meta ve `X-Robots-Tag`), mobil viewport, Open Graph etiketleri, az içerikli sayfalar, `robots.txt` ve sitemap varlığı, sitemap'te olup bağlantı almayan (yetim) sayfalar, soft 404 (olmayan sayfanın 200 dönmesi). |
| Performans | Sayfa başına DNS / bağlantı / TLS / ilk bayt / indirme süreleri, en yavaş sayfa ve parçalar. Sıkıştırılmadan (gzip/brotli olmadan) gönderilen HTML/CSS/JS, önbellek süresi tanımlanmamış statik dosyalar, HTTP/2 kullanılmaması, `<head>` içinde oluşturmayı engelleyen script'ler, boyutu belirtilmemiş görseller (CLS), büyük resimler, 3 MB'ı aşan sayfa ağırlığı, çok fazla istek, yönlendirme zincirleri. |
| Güvenlik | HTTPS ve HTTP→HTTPS yönlendirmesi, HSTS (ve süresi), CSP (ve `unsafe-inline`/`unsafe-eval`/joker zayıflıkları), clickjacking koruması, nosniff, Referrer-Policy, Permissions-Policy, sürüm sızıntısı, çerez bayrakları, CORS, karışık içerik, HTTP'ye giden formlar, dış script'lerde SRI, eski TLS sürümleri, `security.txt`. |
| Hassas dosyalar (isteğe bağlı, varsayılan kapalı) | `.git`, `.env`, `.htpasswd`, `phpinfo`, `server-status`, config/SQL/zip yedekleri, WordPress kullanıcı listesi. İçerik imzasıyla doğrulanır. |
| Sertifika | Güvenilirlik, sahibi, veren, başlangıç/bitiş, kalan gün, anahtar türü ve uzunluğu (RSA < 2048 bit hata), 398 günü aşan geçerlilik süresi, zincir. |

Rapor metin veya JSON olarak paylaşılabilir.

## Zamanlanmış izleme

**İzleme** sekmesinden bir site ekleyip sıklık seçersiniz: her dakika, 5/15/30 dakika, 1/3/6/12 saat, günde veya haftada bir. Her kontrolün raporu cihazda saklanır (izleme başına son 100 kontrol). Her kontrol, aynı türdeki bir önceki kontrolle karşılaştırılır:

- Yeni çıkan ve çözülen sorunlar
- Durumu değişen sayfalar (ör. 200 → 404)
- Yeni bozulan ve düzelen kaynaklar
- %50'den ve 500 ms'den fazla yavaşlayan veya hızlanan sayfalar
- Eklenen ve kaybolan sayfalar (sayfa limiti dolmadıysa)
- Sertifika yenilenmesi veya değişmesi, sağlık puanı değişimi

**Çalışırlık (uptime):** Her kontrolde ana sayfanın açılıp açılmadığı kaydedilir; izleme ekranında çalışırlık yüzdesi, ortalama yanıt süresi, ortalama ilk bayt süresi ve son kesinti gösterilir. İsteğe bağlı **beklenen içerik** ayarıyla, ana sayfada belirli bir metin yoksa (ör. sayfa açılıyor ama hata mesajı gösteriyor) site çalışmıyor sayılır.

Değişiklik varsa bildirim gönderilir. İzleme ekranında puan, yükleme süresi ve sorun sayısı için eğilim grafiği bulunur.

**Zamanlama nasıl çalışır:**
- Uygulama açıkken: zamanı gelen izlemeler 20 saniyede bir kontrol edilir ve tam tarama yapılır.
- Arka planda: iOS'tan uygulama yenileme (`BGAppRefreshTask`) istenir. Zamanı iOS belirler, genellikle en sık 15 dakikada bir. Süre kısıtlı olduğu için hızlı kontrol yapılır: en fazla 10 sayfa, derinlik 1, dış bağlantı ve hassas dosya taraması yok. Hızlı kontroller yalnızca hızlı kontrollerle, tam kontroller yalnızca tam kontrollerle karşılaştırılır.
- Kesin dakika aralığında 7/24 izleme gerekiyorsa bunu bir sunucu tarafı servis yapmalıdır; iOS buna izin vermez.

Arka plan yenilemesini simülatörde denemek için Xcode'da uygulamayı duraklatıp hata ayıklayıcıya şunu yazın:
`e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"studio.alpp.monsite.refresh"]`

## Kurulum

1. `MonSite.xcodeproj` dosyasını Xcode 15 veya üstüyle açın.
2. **Signing & Capabilities** sekmesinde kendi Team'inizi seçin.
3. iPhone'unuzu veya simülatörü seçip çalıştırın. Minimum iOS 16.

`Info.plist` içinde `NSAllowsArbitraryLoads` açıktır; HTTP siteleri ve HTTP→HTTPS kontrolü için gereklidir.

## Doğrulama (CI)

Her push'ta GitHub Actions:

1. Uygulamayı Xcode 16.4 ile derler.
2. Tarama motorunu `Tools/cli` altındaki komut satırı aracıyla derler ve ayrıştırıcı testlerini çalıştırır (`monsite-cli --selftest`).
3. Gerçek sitelerde tarama yapıp sonuçları kayda geçirir. Elle çalıştırırken taranacak siteleri **Actions → Build → Run workflow** ekranından değiştirebilirsiniz.

`Screenshots` iş akışı uygulamayı iPhone 16 Pro Max simülatöründe açar, gerçek bir tarama yapar ve ekran görüntülerini `screenshots` dalına koyar. Test amaçlı başlangıç argümanları (`-MonSiteAutoScan`, `-MonSiteDemoMonitor`, `-MonSiteMonitorsTab`) `MonSiteApp.swift` içinde açıklanmıştır; normal kullanımda etkisizdir.

## Sınırlar

- HTML düzenli ifadelerle ayrıştırılır. JavaScript ile sonradan oluşturulan bağlantılar ve içerikler (SPA'lar) görülmez.
- Renk kontrastı, odak görünürlüğü gibi sayfanın çizilmesini gerektiren erişilebilirlik kontrolleri yoktur.
- Güvenlik kontrolleri pasif ve yüzeyseldir; bir sızma testinin yerini tutmaz.
- Hassas dosya taramasını yalnızca size ait veya izinli olduğunuz sitelerde kullanın.

## App Store

Yayın adımları, mağaza metinleri ve inceleme notu için [APP_STORE.md](APP_STORE.md) dosyasına bakın.
