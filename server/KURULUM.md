# UpSite sunucusu — kurulum

Sunucu Cloudflare'in ücretsiz planında çalışır. Kurulum bir kez yapılır, sonrası GitHub Actions'tan tek tıkla güncellenir. Toplam süre yaklaşık 20 dakika.

## 1. Cloudflare hesabı

1. https://dash.cloudflare.com/sign-up adresinden ücretsiz hesap açın (kart istenmez).
2. Sol menüden **Workers & Pages**'e girin. İlk girişte bir `workers.dev` alt alan adı seçmeniz istenir (ör. `alpp`). Sunucu adresi `https://upsite-api.<alt-alan>.workers.dev` olur.
3. **Account ID**: Workers & Pages sayfasının sağ tarafında yazar. Kopyalayın.
4. **API token**: Sağ üstte profil → **My Profile** → **API Tokens** → **Create Token** → **Edit Cloudflare Workers** şablonunu seçin.
   - **Permissions** bölümüne **Account → D1 → Edit** satırını ekleyin.
   - Account Resources: kendi hesabınız. Zone Resources: **All zones** kalabilir.
   - **Continue to summary** → **Create Token**. Token yalnızca bir kez gösterilir, kopyalayın.

## 2. Apple bildirim anahtarı (APNs)

1. https://developer.apple.com/account/resources/authkeys/list → **+**
2. Ad: `UpSite Push`, **Apple Push Notifications service (APNs)** kutusunu işaretleyin → Continue → Register.
3. **Download** ile `.p8` dosyasını indirin (yalnızca bir kez indirilebilir, güvenli bir yerde saklayın).
4. Sayfadaki **Key ID**'yi (10 karakter) not edin.
5. **Team ID**: https://developer.apple.com/account → Membership details.
6. Identifiers → `studio.alpp.monsite` → **Push Notifications** kutusunu işaretleyip kaydedin (Xcode'da Signing & Capabilities açılınca kendisi de yapar).

## 3. GitHub secrets

`naniniyesuh/monsite` deposu → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Şu beş secret'ı ekleyin:

| Ad | Değer |
|---|---|
| `CLOUDFLARE_API_TOKEN` | 1.4'teki token |
| `CLOUDFLARE_ACCOUNT_ID` | 1.3'teki Account ID |
| `APNS_KEY` | `.p8` dosyasının tüm içeriği (`-----BEGIN PRIVATE KEY-----` satırları dahil) |
| `APNS_KEY_ID` | 2.4'teki Key ID |
| `APNS_TEAM_ID` | 2.5'teki Team ID |

`INTERNAL_KEY` gerekmez; iş akışı kendisi rastgele üretir.

## 4. Yayına alma

1. Depo → **Actions** → **Server** → **Run workflow**.
2. Dal: `main`, **deploy** kutusunu işaretleyin → **Run workflow**.
3. İş bittiğinde özet sayfasında sunucu adresi ve `/v1/health` yanıtı görünür.

İş akışı veritabanını oluşturur, tabloları kurar, secret'ları yükler ve Worker'ı yayınlar. Sonraki güncellemelerde aynı düğmeyi kullanmanız yeterli; veriler korunur.

## 5. Uygulamaya adresi yazma

Sunucu adresini bana iletin, `UPSITE_API_BASE` ayarını güncelleyeyim. Kendiniz yapmak isterseniz: Xcode → UpSite hedefi → **Build Settings** → `UPSITE_API_BASE` → `https://upsite-api.<alt-alan>.workers.dev`.

## 6. Deneme

1. Uygulamayı telefona Xcode ile kurun, bildirim iznini verin.
2. Ayarlar → **Test bildirimi gönder**. Birkaç saniye içinde bildirim gelmeli.
3. Bir site ekleyin; ilk kontrol hemen yapılır.

Xcode'dan kurulan (Debug) sürüm Apple'ın test bildirim sunucusunu, App Store sürümü gerçek sunucuyu kullanır; sunucu ikisini de destekler.

## Ücretsiz plan sınırları

- Cihaz başına en fazla 50 site, toplam 500 cihaz (`wrangler.toml` içinden değiştirilebilir).
- Günlük 100.000 istek: 15 dakikalık sıklıkta yaklaşık 1.000 siteye yeter.
- Sınır aşılırsa Cloudflare o günün kalan kontrollerini durdurur, ücret çıkarmaz.
