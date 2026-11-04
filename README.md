# MonSite (iOS)

Bir web sitesi adresi alır, siteyi gezip aşağıdakileri kontrol eder ve rapor olarak gösterir.

| Kontrol | Ne yapılıyor |
|---|---|
| Sayfa erişimi | Aynı sitedeki tüm bağlantılar BFS ile gezilir (sayfa/derinlik limiti ayarlanabilir). 4xx/5xx, DNS, zaman aşımı, TLS hataları. |
| Sayfa bütünlüğü | Boş sayfa, eksik `</html>`, eksik `<title>`, viewport/lang, sayfada PHP/SQL/ASP.NET/Python hata çıktısı. |
| Kaynaklar | Resim, script, CSS, font, iframe, medya, PDF/zip vb. dosyalar ve dış bağlantılar. 404, bozuk resim (açılamayan dosya), resim/CSS yerine HTML dönmesi, büyük dosyalar. |
| Süreler | Her sayfa için DNS / bağlantı / TLS / TTFB / indirme; en yavaş sayfalar ve en yavaş parçalar listesi. |
| Güvenlik | HTTPS kullanımı ve HTTP→HTTPS yönlendirmesi, HSTS, CSP, clickjacking, nosniff, Referrer-Policy, sürüm sızıntısı (Server, X-Powered-By), çerez bayrakları (Secure/HttpOnly/SameSite), karışık içerik, HTTP'ye giden formlar, dizin listeleme. |
| Hassas dosyalar (isteğe bağlı) | `.git`, `.env`, `.htpasswd`, `phpinfo`, `server-status`, config/SQL/zip yedekleri, WordPress kullanıcı listesi. İçerik imzasıyla doğrulanır, yanlış pozitif azdır. |
| Sertifika | Güvenilirlik, sahibi, veren, başlangıç/bitiş tarihi, kalan gün, zincir. |

Rapor metin veya JSON olarak paylaşılabilir.

## Zamanlanmış izleme

**İzleme** sekmesinden bir site ekleyip sıklık seçersiniz: her dakika, 5/15/30 dakika, 1/3/6/12 saat, günde veya haftada bir. Her kontrolün raporu cihazda saklanır (izleme başına son 100 kontrol). Her kontrol, aynı türdeki bir önceki kontrolle karşılaştırılır:

- Yeni çıkan ve çözülen sorunlar
- Durumu değişen sayfalar (ör. 200 → 404)
- Yeni bozulan ve düzelen kaynaklar
- %50'den ve 500 ms'den fazla yavaşlayan veya hızlanan sayfalar
- Eklenen ve kaybolan sayfalar (sayfa limiti dolmadıysa)
- Sertifika yenilenmesi veya değişmesi, sağlık puanı değişimi

Değişiklik varsa bildirim gönderilir. İzleme ekranında puan, yükleme süresi ve sorun sayısı için eğilim grafiği bulunur.

**Zamanlama nasıl çalışır:**
- Uygulama açıkken: zamanı gelen izlemeler 20 saniyede bir kontrol edilir ve tam tarama yapılır.
- Arka planda: iOS'tan uygulama yenileme (`BGAppRefreshTask`) istenir. Zamanı iOS belirler, genellikle en sık 15 dakikada bir. Süre kısıtlı olduğu için hızlı kontrol yapılır: en fazla 10 sayfa, derinlik 1, dış bağlantı ve hassas dosya taraması yok. Hızlı kontroller yalnızca hızlı kontrollerle, tam kontroller yalnızca tam kontrollerle karşılaştırılır.
- Kesin dakika aralığında 7/24 izleme gerekiyorsa bunu bir sunucu tarafı servis yapmalıdır; iOS buna izin vermez.

Arka plan yenilemesini simülatörde denemek için Xcode'da uygulamayı duraklatıp hata ayıklayıcıya şunu yazın:
`e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"studio.alpp.monsite.refresh"]`


## Kurulum

1. `MonSite.xcodeproj` dosyasını Xcode 15 veya üstüyle açın.
2. **Signing & Capabilities** sekmesinde kendi Team'inizi seçin. Gerekirse Bundle Identifier'ı değiştirin (`studio.alpp.monsite`).
3. iPhone'unuzu veya simülatörü seçip çalıştırın. Minimum iOS 16.

`Info.plist` içinde `NSAllowsArbitraryLoads` açıktır; HTTP siteleri ve HTTP→HTTPS kontrolü için gereklidir.

## Sınırlar

- HTML düzenli ifadelerle ayrıştırılır. JavaScript ile sonradan oluşturulan bağlantılar ve içerikler (SPA'lar) görülmez.
- CSS içindeki `url(...)` kaynakları takip edilmez.
- Güvenlik kontrolleri pasif ve yüzeyseldir; bir sızma testinin yerini tutmaz.
- Hassas dosya taramasını yalnızca size ait veya izinli olduğunuz sitelerde kullanın.

## App Store

Yayın adımları, mağaza metinleri ve inceleme notu için [APP_STORE.md](APP_STORE.md) dosyasına bakın.
