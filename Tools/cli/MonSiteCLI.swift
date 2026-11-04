import Foundation

// Uygulamanın tarama motorunu komut satırında çalıştırır (CI'da doğrulama için).
// Kullanım:
//   monsite-cli --selftest
//   monsite-cli https://ornek.com [--pages 30] [--depth 2]

@main
struct MonSiteCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--selftest" {
            exit(selfTest() ? 0 : 1)
        }
        var config = ScanConfig()
        config.maxPages = 30
        config.maxDepth = 2
        config.checkExternalLinks = true
        if let i = args.firstIndex(of: "--pages"), i + 1 < args.count, let v = Int(args[i + 1]) {
            config.maxPages = v; args.removeSubrange(i...(i + 1))
        }
        if let i = args.firstIndex(of: "--depth"), i + 1 < args.count, let v = Int(args[i + 1]) {
            config.maxDepth = v; args.removeSubrange(i...(i + 1))
        }
        var failures = 0
        for a in args {
            guard let url = normalizeSiteURL(a) else { print("Geçersiz adres: \(a)"); failures += 1; continue }
            let report = await SiteCrawler(startURL: url, config: config).run { e in
                if case .phase(let p) = e { print("  … \(p)") }
            }
            printReport(report)
            if report.pages.isEmpty { failures += 1 }
        }
        exit(failures == 0 ? 0 : 1)
    }

    static func printReport(_ r: ScanReport) {
        print("\n================ \(r.finalURL) ================")
        print(String(format: "Süre %.1f sn · %d sayfa · %d kaynak · puan %d (%@)",
                     r.durationSec, r.pages.count, r.resources.count, r.score, r.grade))
        print(ScoreArea.allCases.map { "\($0.title) \(r.areaScore($0))" }.joined(separator: " · "))
        if let c = r.certificate {
            print("Sertifika: \(c.trusted ? "güvenilir" : "GÜVENİLMEZ") · \(c.issuer ?? "-") · \(c.daysRemaining.map { "\($0) gün" } ?? "-") · \(c.keyDescription ?? "-")")
        }
        print("İlk sayfa: \(r.pages.first.map { "\($0.statusCode ?? 0) \(formatMs($0.durationMs)) \($0.timing?.httpProtocol ?? "?") \($0.timing?.tlsVersion ?? "")" } ?? "-")")
        let groups = Dictionary(grouping: r.issues, by: { "\($0.severity.title)|\($0.category.title)|\($0.title)" })
        for (k, list) in groups.sorted(by: { a, b in
            let sa = a.value[0].severity, sb = b.value[0].severity
            return sa != sb ? sa < sb : a.key < b.key
        }) {
            let parts = k.split(separator: "|")
            print("  [\(parts[0])] \(parts[1]) — \(parts[2]) ×\(list.count)")
            print("      \(list[0].detail.prefix(160)) → \(shortURL(list[0].url).prefix(70))")
        }
    }

    // MARK: - Ayrıştırıcı testleri

    static func selfTest() -> Bool {
        var ok = true
        func check(_ cond: Bool, _ name: String) {
            print("\(cond ? "✓" : "✗") \(name)")
            if !cond { ok = false }
        }
        let base = URL(string: "https://ornek.com/blog/yazi")!

        // robots.txt
        let robots = RobotsRules.parse("""
        User-agent: Googlebot
        Disallow: /

        User-agent: *
        Disallow: /admin/
        Disallow: /*.pdf$
        Allow: /admin/public/
        Sitemap: https://ornek.com/sitemap.xml
        """, base: base)
        check(!robots.isAllowed(URL(string: "https://ornek.com/admin/ayarlar")!), "robots: /admin/ engelli")
        check(robots.isAllowed(URL(string: "https://ornek.com/admin/public/x")!), "robots: daha uzun Allow kazanır")
        check(!robots.isAllowed(URL(string: "https://ornek.com/dosya.pdf")!), "robots: *.pdf$ deseni")
        check(robots.isAllowed(URL(string: "https://ornek.com/dosya.pdf?x=1")!), "robots: $ son eşleşmesi")
        check(robots.isAllowed(URL(string: "https://ornek.com/")!), "robots: Googlebot grubu bize uygulanmaz")
        check(robots.sitemaps.count == 1, "robots: sitemap satırı")
        check(!robots.blocksEverything, "robots: tüm siteyi engellemiyor")

        // HTML bilgileri ve erişilebilirlik
        let html = """
        <!doctype html><html><head>
        <title>Ana sayfa</title>
        <meta name="viewport" content="width=device-width, maximum-scale=1">
        <script src="/app.js"></script><script src="https://cdn.example.net/lib.js"></script>
        <style>.hero{background:url('/img/hero.jpg')} @font-face{src:url(/f/a.woff2)}</style>
        </head><body>
        <!-- <img src="yorum.png"> -->
        <h1>Başlık</h1><h3>Alt</h3><h2></h2>
        <img src="a.png"><img src="b.png" alt=""><img src="c.png" alt="Logo" width="10" height="10">
        <a href="/x"><img src="ikon.svg"></a>
        <a href="/y" aria-label="Profil"><svg></svg></a>
        <a href="#yok">git</a><a href="#var">git</a><div id="var"></div><div id="var"></div>
        <a href="/z">buraya tıklayın</a>
        <label for="ad">Ad</label><input id="ad" name="ad">
        <label>E-posta <input name="eposta"></label>
        <input name="telefon" placeholder="Telefon"><input type="hidden" name="t">
        <button><svg></svg></button><button>Gönder</button>
        <iframe src="https://video.example/x"></iframe>
        <div tabindex="3">x</div>
        <script>var s = "<img src='js.png'>";</script>
        </body></html>
        """
        let f = PageInspector.inspect(html: html, url: base)
        check(f.title == "Ana sayfa", "başlık okunuyor")
        check(f.imagesWithoutAlt.count == 2, "alt'ı olmayan 2 görsel (yorum ve script içi sayılmaz) — bulunan \(f.imagesWithoutAlt.count)")
        check(f.linksWithoutName.count == 1, "adı olmayan 1 bağlantı — bulunan \(f.linksWithoutName.count)")
        check(f.buttonsWithoutName == 1, "adı olmayan 1 düğme")
        check(f.unlabeledFields == ["telefon"], "yalnızca telefon alanı etiketsiz — bulunan \(f.unlabeledFields)")
        check(f.brokenFragments == ["#yok"], "kırık sayfa içi bağlantı #yok")
        check(f.duplicateIDs == ["var"], "yinelenen id")
        check(f.iframesWithoutTitle == 1, "başlıksız iframe")
        check(f.positiveTabindex == 1, "pozitif tabindex")
        check(f.genericLinks.count == 1, "anlamsız bağlantı metni")
        check(f.blockingHeadScripts == 2, "head'de engelleyen 2 script")
        check(f.externalScriptsWithoutSRI.count == 1, "SRI'sız dış script")
        check(!f.hasLang, "lang eksik")
        check(f.headings.map(\.level) == [1, 3, 2], "başlık seviyeleri")
        let issues = PageInspector.issues(f, url: base, isHome: true, xRobotsTag: nil)
        check(issues.contains { $0.title == "Yakınlaştırma engellenmiş" }, "maximum-scale=1 yakınlaştırma engeli")
        check(issues.contains { $0.title == "Başlık seviyesi atlanıyor" }, "h1 → h3 atlaması")
        check(issues.contains { $0.title == "Meta açıklama yok" }, "meta açıklama eksik")

        let ex = HTMLExtractor.extract(html: html, baseURL: base)
        let urls = Set(ex.resources.map(\.url.absoluteString))
        check(urls.contains("https://ornek.com/img/hero.jpg"), "<style> içindeki arka plan resmi bulunuyor")
        check(ex.resources.contains { $0.url.absoluteString == "https://ornek.com/f/a.woff2" && $0.kind == .font }, "<style> içindeki font bulunuyor")
        check(!urls.contains("https://ornek.com/blog/yorum.png"), "yorum içindeki resim atlanıyor")

        let css = HTMLExtractor.cssResources("@import 'tema.css'; body{background:url(\"../i/bg.png\")} .x{src:url(data:abc)}",
                                             base: URL(string: "https://ornek.com/css/ana.css")!)
        check(css.map(\.url.absoluteString).sorted() == ["https://ornek.com/css/tema.css", "https://ornek.com/i/bg.png"], "CSS url() ve @import — bulunan \(css.map(\.url.absoluteString))")

        // Görsel doğrulama
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        check(ResourceChecker.imageDecodes(png), "geçerli PNG açılıyor")
        check(!ResourceChecker.imageDecodes(Data("<html>404</html>".utf8)), "HTML resim olarak açılmıyor")

        // Eski kayıtların okunması
        let old = #"{"maxPages":20,"maxDepth":1,"concurrency":4,"timeout":20,"checkExternalLinks":true,"probeSensitivePaths":true,"slowPageMs":3000}"#
        let decoded = try? JSONDecoder().decode(ScanConfig.self, from: Data(old.utf8))
        check(decoded?.maxPages == 20 && decoded?.respectRobots == true, "1.0 ayarları okunabiliyor")

        print(ok ? "Tüm testler geçti" : "TESTLER BAŞARISIZ")
        return ok
    }
}
