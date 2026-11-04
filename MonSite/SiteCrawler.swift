import Foundation

enum ScanEvent: Sendable {
    case phase(String)
    case page(url: String, status: Int?, ms: Double, scanned: Int)
    case resources(done: Int, total: Int)
    case log(String)
}

/// Siteyi gezen ve tüm kontrolleri sırayla yapan tarayıcı.
final class SiteCrawler {
    let startURL: URL
    let config: ScanConfig
    let fetcher: HTTPFetcher

    init(startURL: URL, config: ScanConfig) {
        self.startURL = startURL
        self.config = config
        self.fetcher = HTTPFetcher(timeout: config.timeout)
    }

    func run(progress: @escaping @Sendable (ScanEvent) async -> Void) async -> ScanReport {
        let startedAt = Date()
        let fetcher = self.fetcher
        let config = self.config

        var pages: [PageResult] = []
        var visited: Set<String> = [startURL.visitKey]
        var siteHosts: Set<String> = [startURL.siteHost]
        var resources: [String: ResourceRef] = [:]
        var linkedKeys = Set<String>()
        var mainResponse: HTTPURLResponse?
        var mainURL = startURL
        var siteIssues: [Issue] = []
        var unscanned = 0
        var robotsSkipped: [String] = []

        func register(_ url: URL, _ kind: ResourceKind, external: Bool, on page: String) {
            let key = url.absoluteString
            if var existing = resources[key] {
                existing.foundOn.insert(page)
                resources[key] = existing
            } else {
                resources[key] = ResourceRef(url: url, kind: kind, external: external, foundOn: [page])
            }
        }

        // 0) robots.txt ve sitemap
        var robots = RobotsRules()
        var sitemapSeeds: [URL] = []
        var sitemapKeys = Set<String>()
        if let root = startURL.siteRoot, !Task.isCancelled {
            await progress(.phase("robots.txt ve sitemap okunuyor"))
            if let robotsURL = URL(string: "/robots.txt", relativeTo: root)?.absoluteURL {
                let r = await fetcher.fetchWithRetry(robotsURL)
                let text = r.data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                if r.error == nil, r.statusCode == 200, !SecurityChecker.looksHTML(text) {
                    robots = RobotsRules.parse(text, base: r.finalURL ?? robotsURL)
                    if robots.blocksEverything {
                        siteIssues.append(Issue(severity: .warning, category: .seo, title: "robots.txt tüm siteyi engelliyor",
                                                detail: "“Disallow: /” kuralı arama motorlarının siteyi taramasını engelliyor.",
                                                url: robotsURL.absoluteString))
                    }
                } else {
                    siteIssues.append(Issue(severity: .info, category: .seo, title: "robots.txt yok",
                                            detail: "Arama motorlarına hangi bölümlerin taranacağını söyleyen robots.txt dosyası bulunamadı.",
                                            url: robotsURL.absoluteString))
                }
            }
            if config.useSitemap {
                let declared = !robots.sitemaps.isEmpty
                let candidates = declared ? robots.sitemaps
                    : [URL(string: "/sitemap.xml", relativeTo: root)?.absoluteURL].compactMap { $0 }
                let sm = await SitemapLoader.load(candidates, declared: declared, fetcher: fetcher)
                if sm.found {
                    sitemapSeeds = sm.pageURLs.filter { $0.siteHost == startURL.siteHost }
                    sitemapKeys = Set(sitemapSeeds.map(\.visitKey))
                    await progress(.log("Sitemap: \(sm.pageURLs.count) adres"))
                } else {
                    siteIssues.append(Issue(severity: .info, category: .seo, title: "Sitemap bulunamadı",
                                            detail: "sitemap.xml arama motorlarının tüm sayfaları bulmasına yardım eder.",
                                            url: candidates.first?.absoluteString ?? root.absoluteString))
                }
                for b in sm.brokenSitemaps {
                    siteIssues.append(Issue(severity: .warning, category: .seo, title: "Sitemap dosyası açılmıyor",
                                            detail: "Bildirilen sitemap adresi okunamadı.", url: b))
                }
            }
        }

        // 1) Sayfaları katman katman (BFS) tara
        await progress(.phase("Sayfalar taranıyor"))
        var level: [URL] = [startURL]
        var depth = 0
        while !level.isEmpty && !Task.isCancelled {
            let budget = config.maxPages - pages.count
            if budget <= 0 || depth > config.maxDepth {
                unscanned += level.count
                break
            }
            let batch = Array(level.prefix(budget))
            unscanned += level.count - batch.count
            let d = depth
            let already = pages.count

            let outcomes: [PageOutcome?] = await concurrentMap(batch, limit: config.concurrency, { url in
                await PageProcessor.process(url: url, depth: d, fetcher: fetcher, config: config)
            }, onEach: { done, outcome in
                if let p = outcome?.page {
                    await progress(.page(url: p.url, status: p.statusCode, ms: p.durationMs, scanned: already + done))
                }
            })

            var next: [URL] = []
            func enqueue(_ link: URL) {
                guard visited.insert(link.visitKey).inserted else { return }
                if config.respectRobots && !robots.isAllowed(link) {
                    robotsSkipped.append(link.absoluteString)
                    return
                }
                next.append(link)
            }

            for case let o? in outcomes {
                pages.append(o.page)

                // Ana sayfa başka bir host'a yönlendiriyorsa (ör. www.) onu da aynı site say.
                if pages.count == 1 {
                    mainResponse = o.response
                    if let f = o.finalURL {
                        mainURL = f
                        siteHosts.insert(f.siteHost)
                        visited.insert(f.visitKey)
                    }
                }

                for r in o.resources {
                    register(r.url, r.kind, external: !siteHosts.contains(r.url.siteHost), on: o.page.url)
                }
                for link in o.links {
                    if siteHosts.contains(link.siteHost) {
                        linkedKeys.insert(link.visitKey)
                        if let kind = HTMLExtractor.fileKind(for: link) {
                            register(link, kind, external: false, on: o.page.url)
                        } else {
                            enqueue(link)
                        }
                    } else if config.checkExternalLinks {
                        register(link, .link, external: true, on: o.page.url)
                    }
                }
            }
            // Bağlantı verilmemiş ama sitemap'te olan sayfalar ikinci katmanda taranır.
            if depth == 0 {
                for u in sitemapSeeds where siteHosts.contains(u.siteHost) && HTMLExtractor.fileKind(for: u) == nil {
                    enqueue(u)
                }
            }
            level = next
            depth += 1
        }

        // Taranmış sayfalar kaynak listesine bir daha girmesin
        let pageKeys = Set(pages.map { URL(string: $0.url)?.visitKey ?? $0.url })
        var refs = resources.values.filter { $0.external || !pageKeys.contains($0.url.visitKey) }

        // 2) Resim, script, CSS, dosya ve bağlantıları kontrol et (CSS içindeki font/resimler dahil)
        var resourceResults: [ResourceResult] = []
        var checkedKeys = Set<String>()
        var pass = 0
        if !Task.isCancelled && !refs.isEmpty {
            await progress(.phase("Kaynaklar kontrol ediliyor"))
        }
        while !refs.isEmpty && pass < 3 && !Task.isCancelled {
            pass += 1
            let batch = refs
            let total = batch.count
            checkedKeys.formUnion(batch.map(\.url.absoluteString))
            let checked: [ResourceChecker.Outcome?] = await concurrentMap(batch, limit: config.concurrency * 2, { ref in
                await ResourceChecker.check(ref, fetcher: fetcher)
            }, onEach: { done, _ in
                await progress(.resources(done: done, total: total))
            })
            var nested: [String: ResourceRef] = [:]
            for case let o? in checked {
                resourceResults.append(o.result)
                for r in o.cssResources where !checkedKeys.contains(r.url.absoluteString) {
                    let key = r.url.absoluteString
                    if var e = nested[key] {
                        e.foundOn.insert(o.result.url)
                        nested[key] = e
                    } else {
                        nested[key] = ResourceRef(url: r.url, kind: r.kind,
                                                  external: !siteHosts.contains(r.url.siteHost), foundOn: [o.result.url])
                    }
                }
            }
            refs = Array(nested.values)
        }

        // 3) Güvenlik
        if !Task.isCancelled {
            await progress(.phase("Güvenlik kontrolleri"))
            if let resp = mainResponse {
                siteIssues += SecurityChecker.headerIssues(response: resp, url: mainURL)
            }
            siteIssues += await SecurityChecker.schemeIssues(finalURL: mainURL, fetcher: fetcher)
            if let root = mainURL.siteRoot {
                if let i = await SecurityChecker.securityTxtIssue(root: root, fetcher: fetcher) { siteIssues.append(i) }
                if let i = await SecurityChecker.soft404Issue(root: root, fetcher: fetcher) { siteIssues.append(i) }
                if config.probeSensitivePaths {
                    await progress(.log("Hassas dosyalar aranıyor…"))
                    siteIssues += await SecurityChecker.probeSensitivePaths(root: root, fetcher: fetcher) { done, total in
                        await progress(.resources(done: done, total: total))
                    }
                }
            }
            if let t = pages.first?.timing, let v = t.tlsVersion, v == "TLS 1.0" || v == "TLS 1.1" {
                siteIssues.append(Issue(severity: .error, category: .security, title: "Eski TLS sürümü",
                                        detail: "Bağlantı \(v) ile kuruldu; TLS 1.2 veya 1.3 kullanılmalı.", url: mainURL.absoluteString))
            }
        }

        // 4) Sertifika
        var cert: CertificateInfo?
        if !Task.isCancelled, let host = mainURL.host {
            await progress(.phase("Sertifika kontrol ediliyor"))
            let info = await CertificateChecker.check(host: host,
                                                      port: mainURL.scheme == "https" ? mainURL.port : nil,
                                                      timeout: config.timeout)
            // HTTP-only sitede sertifika yoksa bu zaten "HTTPS kullanmıyor" olarak raporlandı.
            if !(mainURL.scheme == "http" && info.chain.isEmpty) {
                cert = info
                siteIssues += CertificateChecker.issues(for: info)
            }
        }

        // 5) Site geneli değerlendirmeler
        siteIssues += Self.siteWideIssues(pages: pages, resources: resourceResults, mainURL: mainURL,
                                          sitemapKeys: sitemapKeys, linkedKeys: linkedKeys)
        if !robotsSkipped.isEmpty {
            siteIssues.append(Issue(severity: .info, category: .availability, title: "robots.txt nedeniyle taranmayan sayfalar",
                                    detail: "\(robotsSkipped.count) adres robots.txt kuralları gereği atlandı. Ayarlardan bu kurala uymayı kapatabilirsiniz.",
                                    url: robotsSkipped[0]))
        }
        if unscanned > 0 {
            siteIssues.append(Issue(severity: .info, category: .availability,
                                    title: "Limit nedeniyle taranmayan sayfalar",
                                    detail: "\(unscanned) bağlantı sayfa/derinlik limitine takıldı. Ayarlardan limiti artırabilirsiniz.",
                                    url: mainURL.absoluteString))
        }

        let allIssues = (siteIssues + pages.flatMap(\.issues) + ResourceChecker.issues(for: resourceResults))
            .sorted { $0.severity != $1.severity ? $0.severity < $1.severity : $0.category.rawValue < $1.category.rawValue }

        await progress(.phase(Task.isCancelled ? "İptal edildi" : "Tamamlandı"))
        return ScanReport(startURL: startURL.absoluteString,
                          finalURL: mainURL.absoluteString,
                          startedAt: startedAt,
                          finishedAt: Date(),
                          cancelled: Task.isCancelled,
                          unscannedLinkCount: unscanned,
                          pages: pages,
                          resources: resourceResults.sorted { $0.url < $1.url },
                          certificate: cert,
                          issues: allIssues)
    }

    /// Birden çok sayfaya bakarak verilen kararlar: yinelenen başlıklar, sayfa ağırlığı, sıkıştırma, önbellek...
    static func siteWideIssues(pages: [PageResult], resources: [ResourceResult], mainURL: URL,
                               sitemapKeys: Set<String>, linkedKeys: Set<String>) -> [Issue] {
        var issues: [Issue] = []
        let okPages = pages.filter { $0.isHTML && $0.error == nil && ($0.statusCode ?? 0) < 300 }
        func examples(_ urls: [String]) -> String {
            let shown = urls.prefix(3).map(shortURL).joined(separator: ", ")
            return urls.count > 3 ? "\(shown) …" : shown
        }

        // Yinelenen başlık ve açıklamalar
        let byTitle = Dictionary(grouping: okPages.filter { $0.title != nil }, by: { $0.title! })
        for (title, group) in byTitle.filter({ $0.value.count > 1 }).sorted(by: { $0.value.count > $1.value.count }).prefix(10) {
            issues.append(Issue(severity: .warning, category: .seo, title: "Aynı başlığı kullanan sayfalar",
                                detail: "\(group.count) sayfa “\(title)” başlığını kullanıyor: \(examples(group.map(\.url)))",
                                url: group[0].url))
        }
        let byDesc = Dictionary(grouping: okPages.filter { !($0.metaDescription ?? "").isEmpty }, by: { $0.metaDescription! })
        for (_, group) in byDesc.filter({ $0.value.count > 1 }).sorted(by: { $0.value.count > $1.value.count }).prefix(10) {
            issues.append(Issue(severity: .info, category: .seo, title: "Aynı meta açıklamayı kullanan sayfalar",
                                detail: "\(group.count) sayfa aynı açıklamayı kullanıyor: \(examples(group.map(\.url)))",
                                url: group[0].url))
        }

        // Sitemap'te olup hiçbir sayfadan bağlantı verilmeyenler
        let homeKey = mainURL.visitKey
        let orphans = okPages.filter {
            let k = URL(string: $0.url)?.visitKey ?? $0.url
            return k != homeKey && sitemapKeys.contains(k) && !linkedKeys.contains(k)
        }
        if !orphans.isEmpty {
            issues.append(Issue(severity: .info, category: .seo, title: "Bağlantı verilmeyen (yetim) sayfalar",
                                detail: "\(orphans.count) sayfa sitemap'te var ama taranan hiçbir sayfadan bağlantı almıyor: \(examples(orphans.map(\.url)))",
                                url: orphans[0].url))
        }

        // Sayfa ağırlığı ve istek sayısı
        var bytesByPage: [String: (bytes: Int, count: Int)] = [:]
        for r in resources where r.kind != .link && r.kind != .document && r.error == nil {
            for p in r.foundOn {
                var e = bytesByPage[p] ?? (0, 0)
                e.bytes += r.bytes ?? 0
                e.count += 1
                bytesByPage[p] = e
            }
        }
        var heavy: [String] = []
        var manyRequests: [String] = []
        for p in okPages {
            let e = bytesByPage[p.url] ?? (0, 0)
            if e.bytes + p.bytes > 3_000_000 { heavy.append(p.url) }
            if e.count > 80 { manyRequests.append(p.url) }
        }
        if !heavy.isEmpty {
            issues.append(Issue(severity: .warning, category: .performance, title: "Sayfa ağırlığı yüksek",
                                detail: "\(heavy.count) sayfanın HTML, resim, script ve CSS toplamı 3 MB'ı aşıyor: \(examples(heavy))",
                                url: heavy[0]))
        }
        if !manyRequests.isEmpty {
            issues.append(Issue(severity: .info, category: .performance, title: "Çok fazla kaynak isteği",
                                detail: "\(manyRequests.count) sayfa 80'den fazla dosya yüklüyor: \(examples(manyRequests))",
                                url: manyRequests[0]))
        }

        // Sıkıştırma
        let textKinds: Set<ResourceKind> = [.script, .stylesheet]
        var uncompressed = resources.filter { r in
            !r.external && r.error == nil && (r.statusCode ?? 0) < 300 && (r.bytes ?? 0) > 1400
                && (textKinds.contains(r.kind) || (r.contentType?.contains("svg") ?? false))
                && (r.contentEncoding ?? "").isEmpty
        }.map(\.url)
        uncompressed += okPages.filter { $0.bytes > 1400 && ($0.contentEncoding ?? "").isEmpty }.map(\.url)
        if !uncompressed.isEmpty {
            issues.append(Issue(severity: .warning, category: .performance, title: "Sıkıştırılmadan gönderilen dosyalar",
                                detail: "\(uncompressed.count) HTML/CSS/JS dosyası gzip veya brotli olmadan gönderiliyor; boyut genelde %60–80 küçülür: \(examples(uncompressed))",
                                url: uncompressed[0]))
        }

        // Önbellek
        let staticKinds: Set<ResourceKind> = [.image, .script, .stylesheet, .font]
        let uncached = resources.filter { r in
            guard !r.external, r.error == nil, (r.statusCode ?? 0) < 300, staticKinds.contains(r.kind) else { return false }
            let cc = r.cacheControl?.lowercased() ?? ""
            if cc.contains("no-store") { return true }
            return !cc.contains("max-age") && !(r.hasExpires ?? false)
        }.map(\.url)
        if !uncached.isEmpty {
            issues.append(Issue(severity: .warning, category: .performance, title: "Önbellek süresi tanımlanmamış dosyalar",
                                detail: "\(uncached.count) resim/CSS/JS/font dosyasında Cache-Control max-age veya Expires yok; tarayıcı her ziyarette dosyayı sunucuya yeniden sorar: \(examples(uncached))",
                                url: uncached[0]))
        }

        // Protokol
        if let proto = pages.first?.timing?.httpProtocol?.lowercased(), proto == "http/1.1" || proto == "http/1.0" {
            issues.append(Issue(severity: .info, category: .performance, title: "HTTP/2 kullanılmıyor",
                                detail: "Sunucu \(proto.uppercased()) ile yanıt veriyor; HTTP/2 veya HTTP/3 birçok dosyayı paralel ve daha hızlı yükler.",
                                url: mainURL.absoluteString))
        }

        // Ana sayfanın yönlendirme zinciri
        if let first = pages.first, let t = first.timing, t.redirectCount >= 2 {
            issues.append(Issue(severity: .info, category: .performance, title: "Ana sayfada yönlendirme zinciri",
                                detail: "Ana sayfaya ulaşmak için \(t.redirectCount) yönlendirme gerekiyor; her biri yüklemeyi geciktirir.",
                                url: first.url))
        }
        return issues
    }
}
