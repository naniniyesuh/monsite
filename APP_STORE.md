# UpSite 2.0 — App Store yayın rehberi

UpSite, App Store'daki MonSite uygulamasının yeni sürümüdür (aynı bundle ID: `studio.alpp.monsite`). Bu dosyada gönderim adımları, App Store Connect'e yapıştırılacak metinler, gizlilik ve yaş derecelendirmesi cevapları, inceleme notu ve ekran görüntüleri var.

Projede hazır olanlar:

- Sürüm 2.0 (3), yalnızca iPhone, iOS 16.0+
- Yeni simge (logo A), 1024×1024, saydamlık yok
- Push Notifications yetkisi (`aps-environment`); arşivlerken Xcode üretim ortamına çevirir
- Gizlilik manifesti: "Diğer kullanıcı içeriği" ve "Cihaz kimliği" — kimliğe bağlı değil, takip yok, yalnızca uygulama işlevi
- Şifreleme beyanı (`ITSAppUsesNonExemptEncryption = NO`)
- Sunucu: `https://upsite-api.alpp.workers.dev` (Cloudflare Workers + D1, kurulum: `server/KURULUM.md`)
- Destek ve gizlilik sayfaları: https://alpp.studio/upsite/ ve https://alpp.studio/upsite/privacy/

---

## 1. Gönderim adımları

### Derleme

1. `git pull`, sonra Xcode'da `UpSite.xcodeproj`'u açın.
2. Üstteki cihaz menüsünden **Any iOS Device (arm64)** seçin.
3. **Product → Archive**. Bitince Organizer açılır.
4. **Distribute App** → **App Store Connect** → **Distribute**.
5. 10–30 dakika sonra derleme App Store Connect'te görünür (e-posta gelir).

### App Store Connect

1. https://appstoreconnect.apple.com → **Uygulamalar** → MonSite.
2. Sol üstte iOS uygulaması yanındaki **+** → yeni sürüm: `2.0`.
   - 1.0 hâlâ incelemedeyse önce onu sürüm sayfasından **Bu Sürümü Kaldır** (Remove from Review) ile geri çekin. Onaylandıysa doğrudan 2.0 oluşturun.
3. **Sürüm 2.0 sayfası** (Türkçe ve İngilizce için ayrı ayrı):
   - Ekran görüntülerini değiştirin (bölüm 6).
   - **Bu sürümdeki yenilikler**, tanıtım metni, açıklama, anahtar kelimeler, destek URL'si: bölüm 2.
   - **Derleme**: 2.0 (3)'ü seçin.
   - **App Review bilgileri**: bölüm 5'teki notu yapıştırın; "Giriş gerekli" kutusu boş.
4. **Uygulama Bilgileri** (sol menü):
   - **Ad**: `UpSite` (alınmışsa `UpSite: Uptime Monitor`), **Alt başlık**: bölüm 2. Ad ve alt başlık yalnızca yeni sürüm "Gönderime Hazırlanıyor" durumundayken değişebilir.
   - **Gizlilik politikası URL'si**: `https://alpp.studio/upsite/privacy/` (her iki dilde).
   - **Kategori**: birincil **Geliştirici Araçları**, ikincil **Yardımcı Uygulamalar**.
   - **Yaş derecelendirmesi**: bölüm 3.
5. **Uygulama Gizliliği** (sol menü): bölüm 4'e göre yeniden doldurup **Yayımla**.
6. Sürüm sayfasında **İncelemeye Gönder**.

İnceleme genellikle 1–3 gün sürer. Onaydan sonra eski `alpp.studio/monsite/` sayfaları UpSite'a yönlendirilebilir.

### Sonraki sürümler

Her yüklemede **Build** artmalı (Xcode → UpSite hedefi → General → Build: 4, 5 …). Yeni özellik içeren sürümlerde **Version** da artmalı (2.1 …).

---

## 2. Mağaza metinleri

### Türkçe

**Ad** (30)
```
UpSite
```

**Alt başlık** (30)
```
Site kesinti ve SSL takibi
```

**Tanıtım metni** (170)
```
Siteniz erişilemez olduğu anda bildirim alın. UpSite kontrolleri sunucuda yapar; telefonunuz kilitli olsa da kesintileri kaçırmazsınız.
```

**Bu sürümdeki yenilikler**
```
MonSite artık UpSite!

• Yeni ad, yeni simge, koyu ve sade tasarım
• Siteleriniz 15 dakikadan 1 güne kadar seçtiğiniz sıklıkta, saat başına hizalı olarak kontrol edilir
• Kontroller UpSite sunucusunda yapılır; uygulama kapalıyken bile kesinti ve düzelme bildirimleri gelir
• Sertifikalar sekmesi: bitiş tarihleri, yenilenen sertifikalar ve bitişe yaklaşınca hatırlatma
• Yanlış alarm koruması, sessiz saatler, site listesini dışa/içe aktarma
• Türkçe ve İngilizce

Sayfa hızı ve güvenlik denetimi özellikleri bu sürümde kaldırıldı.
```

**Açıklama**
```
UpSite, web siteleriniz için sade ve güvenilir bir erişilebilirlik (uptime) takipçisidir. Sitelerinizi ekleyin, kontrol sıklığını seçin; siteniz erişilemez olduğunda UpSite size hemen haber versin.

TELEFONUNUZ KİLİTLİYKEN DE ÇALIŞIR
Kontroller telefonunuzda değil UpSite sunucusunda yapılır. Uygulamayı kapatsanız da, telefonunuz kilitli olsa da kesinti bildirimleri gelir.

SİZİN SEÇTİĞİNİZ SIKLIK
• 15 dakika, 30 dakika, 1 saat, 6 saat, 12 saat veya 1 gün
• Kontroller saat başına hizalıdır: 15 dakikada bir :00, :15, :30, :45'te
• Siteyi eklediğiniz anda ilk kontrol yapılır

NET KURAL
• Yönlendirmeler izlenir; son yanıt 200–299 ise site erişilebilirdir
• Hata kodu, zaman aşımı, DNS ve güvenli bağlantı hataları ayrı ayrı gösterilir

BİLDİRİMLER
• Site erişilemez olduğunda bildirim
• İsterseniz tekrar erişilebildiğinde de bildirim ve kesinti süresi
• Yanlış alarm koruması: kesinti bildirilmeden önce tekrar deneme
• Sessiz saatler: gece gelen bildirimler sessizce Bildirim Merkezi'ne düşer

GEÇMİŞ
• Her site için son 7 günün kontrol çubukları ve erişilebilirlik yüzdesi
• Kesinti ve düzelme olayları

SERTİFİKALAR
• Tüm sitelerinizin SSL sertifikası bitiş tarihleri tek listede
• Sertifikayı yenilediğinizde tek dokunuşla yeniden kontrol edin, "Yenilendi" etiketiyle hemen görün
• Bitişe seçtiğiniz gün sayısı kala hatırlatma

GİZLİLİK
Hesap açmanız gerekmez. Ad, e-posta ya da telefon numarası istenmez; reklam ve takip yoktur. Sunucuda yalnızca izlediğiniz adresler, kontrol sonuçları ve bildirim kaydı tutulur; tümünü uygulamadan tek dokunuşla silebilirsiniz.

Cihaz başına en fazla 50 site eklenebilir.
```

**Anahtar kelimeler** (100, virgülle, boşluksuz)
```
uptime,izleme,web sitesi,kesinti,ssl,sertifika,sunucu,erişilebilirlik,bildirim,monitor,down,site
```

**Destek URL'si**
```
https://alpp.studio/upsite/
```

**Pazarlama URL'si** (isteğe bağlı)
```
https://alpp.studio/
```

### English (U.S.)

**Name**
```
UpSite
```

**Subtitle**
```
Website uptime & SSL monitor
```

**Promotional text**
```
Get notified the moment your site goes down. UpSite runs checks on its server, so you won't miss downtime even when your phone is locked.
```

**What's New**
```
MonSite is now UpSite!

• New name, new icon, a dark and clean design
• Sites are checked at the interval you choose, from 15 minutes to 1 day, aligned to the hour
• Checks run on the UpSite server, so down and recovery alerts arrive even when the app is closed
• Certificates tab: expiry dates, renewed certificates and reminders before expiry
• False alarm protection, quiet hours, site list export and import
• Turkish and English

Page speed and security audit features were removed in this version.
```

**Description**
```
UpSite is a simple, reliable uptime monitor for your websites. Add your sites, pick a check interval, and UpSite tells you right away when a site goes down.

WORKS WHILE YOUR PHONE IS LOCKED
Checks run on the UpSite server, not on your phone. You get downtime alerts even when the app is closed or your phone is locked.

YOUR INTERVAL
• 15 minutes, 30 minutes, 1 hour, 6 hours, 12 hours or 1 day
• Checks are aligned to the hour: every 15 minutes means :00, :15, :30, :45
• The first check runs as soon as you add a site

A CLEAR RULE
• Redirects are followed; a site is up if the final response is 200–299
• Error codes, timeouts, DNS and secure connection failures are shown separately

NOTIFICATIONS
• Alert when a site goes down
• Optional alert when it's back up, with the downtime duration
• False alarm protection: retries before reporting downtime
• Quiet hours: alerts at night arrive silently in Notification Center

HISTORY
• Last 7 days of checks and uptime percentage for each site
• Down and recovery events

CERTIFICATES
• SSL certificate expiry dates for all your sites in one list
• Recheck with one tap after renewing and see the "Renewed" badge right away
• Reminders the number of days you choose before expiry

PRIVACY
No account needed. No name, email or phone number, no ads, no tracking. The server stores only the addresses you monitor, check results and your notification registration, and you can delete all of it from the app with one tap.

Up to 50 sites per device.
```

**Keywords**
```
uptime,monitor,website,downtime,ssl,certificate,server,status,alert,ping,web,checker,down,site
```

**Support URL** / **Marketing URL**: same as above.

---

## 3. Yaş derecelendirmesi

Bütün içerik sorularına (şiddet, cinsellik, kumar, uyuşturucu, korku vb.) **Hiç / Yok** cevabını verin.

| Soru | Cevap |
|---|---|
| Sınırsız web erişimi | Hayır. Uygulama web sayfası göstermez; yalnızca sitelerin yanıt kodunu ve sertifikasını kontrol eder. |
| Kullanıcı tarafından oluşturulan içerik | Hayır |
| Mesajlaşma ve sohbet | Hayır |
| Reklam | Hayır |
| Ebeveyn denetimi / yaş doğrulama | Hayır |

Sonuç: **4+**

---

## 4. Uygulama gizliliği (App Privacy)

1.0'daki "Veri Toplanmıyor" artık doğru değil; sunucuda veri tutuluyor. Şöyle doldurun:

- "Bu uygulamadan veri topluyor musunuz?" → **Evet**
- İşaretlenecek veri türleri:
  - **Kullanıcı İçeriği → Diğer Kullanıcı İçeriği** (izlenen site adresleri ve adları)
  - **Tanımlayıcılar → Cihaz Kimliği** (uygulamanın ürettiği anonim kimlik ve bildirim anahtarı)
- Her biri için:
  - Kullanım amacı: **Uygulama İşlevselliği** (yalnızca bu)
  - Kullanıcının kimliğine bağlı mı? **Hayır**
  - Takip için kullanılıyor mu? **Hayır**

Sonuç etiketi: **Kimliğinizle İlişkilendirilmeyen Veriler** — Kullanıcı İçeriği, Tanımlayıcılar.

Bu cevaplar projedeki `PrivacyInfo.xcprivacy` ile aynıdır.

---

## 5. App Review notu

İngilizce yazın. **Sign-in required** kutusunu boş bırakın.

```
UpSite (formerly MonSite) is an uptime monitor for website owners. No account or sign-in is required.

How it works:
Sites are checked by our own backend (Cloudflare Workers) at the interval the user chooses, aligned to the hour. When a site goes down or comes back up, the backend sends an Apple push notification. This lets alerts arrive while the app is closed. The app doesn't use any background modes.

How to test:
1. Allow notifications when asked (the prompt appears after adding the first site).
2. On the "Sites" tab, tap + and add any site, e.g. example.com. The first check runs immediately and the result appears within a few seconds.
3. Open the site to see its status, the last 7 days of checks, and notification toggles. "Check now" runs a check on demand.
4. Settings → "Send test notification" sends a push through the backend.
5. The "Certificates" tab shows SSL certificate expiry dates. These are checked directly from the device when the app opens; tap refresh to recheck.

To see a site go down, add an address that returns an error, e.g. httpbin.org/status/503.

Push notifications are used only for the user's own site alerts; there is no marketing content.

Data: The backend stores an anonymous random device ID, the monitored site addresses, check results and the push token. There is no account and no personal information. Settings → "Delete all my data" removes everything from the server.

Contact: help@alpp.studio
```

---

## 6. Ekran görüntüleri

**iPhone 6.9"** (1320 × 2868). Uygulama yalnızca iPhone'u desteklediği için iPad görüntüsü gerekmiyor. 1.0'ın ekran görüntülerini silip bunları yükleyin.

Görüntüler demo verisiyle simülatörde otomatik çekiliyor: GitHub → Actions → **Screenshots** → Run workflow. Sonuç `screenshots` dalına konur: https://github.com/naniniyesuh/monsite/tree/screenshots

| Sıra | Türkçe | English |
|---|---|---|
| 1 | `tr-01-siteler.png` | `en-01-siteler.png` |
| 2 | `tr-02-ayrinti.png` | `en-02-ayrinti.png` |
| 3 | `tr-03-sertifikalar.png` | `en-03-sertifikalar.png` |
| 4 | `tr-04-ayarlar.png` | `en-04-ayarlar.png` |

---

## 7. Olası inceleme soruları

- **Ad çakışması:** "UpSite" alınmışsa ad alanı hata verir. `UpSite: Uptime Monitor` deneyin; ana ekrandaki ad yine "UpSite" kalır.
- **Sunucuya erişim:** İnceleme sırasında sunucu çalışıyor olmalı. Cloudflare panelinde Worker'ı durdurmayın.
- **Özellik kaldırma:** 1.0'daki tarama özellikleri kaldırıldı; "Bu sürümdeki yenilikler" metni bunu açıkça söylüyor.
- **Bildirim izni:** İzin ilk site eklendiğinde isteniyor, uygulama açılır açılmaz değil. Apple bu davranışı tercih ediyor.
