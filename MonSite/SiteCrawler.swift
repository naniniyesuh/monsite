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
        var mainResponse: HTTPURLResponse?
        var mainURL = startURL
        var level: [URL] = [startURL]
        var depth = 0
        var unscanned = 0

        func register(_ url: URL, _ kind: ResourceKind, external: Bool, on page: String) {
            let key = url.absoluteString
            if var existing = resources[key] {
                existing.foundOn.insert(page)
                resources[key] = existing
            } else {
                resources[key] = ResourceRef(url: url, kind: kind, external: external, foundOn: [page])
            }
        }

        // 1) Sayfaları katman katman (BFS) tara
        await progress(.phase("Sayfalar taranıyor"))
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
                        if let kind = HTMLExtractor.fileKind(for: link) {
                            register(link, kind, external: false, on: o.page.url)
                        } else if visited.insert(link.visitKey).inserted {
                            next.append(link)
                        }
                    } else if config.checkExternalLinks {
                        register(link, .link, external: true, on: o.page.url)
                    }
                }
            }
            level = next
            depth += 1
        }

        // Taranmış sayfalar kaynak listesine bir daha girmesin
        let pageKeys = Set(pages.map { URL(string: $0.url)?.visitKey ?? $0.url })
        let refs = resources.values.filter { $0.external || !pageKeys.contains($0.url.visitKey) }

        // 2) Resim, script, CSS, dosya ve bağlantıları kontrol et
        var resourceResults: [ResourceResult] = []
        if !Task.isCancelled && !refs.isEmpty {
            await progress(.phase("Kaynaklar kontrol ediliyor"))
            let total = refs.count
            let checked: [ResourceResult?] = await concurrentMap(Array(refs), limit: config.concurrency * 2, { ref in
                await ResourceChecker.check(ref, fetcher: fetcher)
            }, onEach: { done, _ in
                await progress(.resources(done: done, total: total))
            })
            resourceResults = checked.compactMap { $0 }
        }

        // 3) Güvenlik
        var siteIssues: [Issue] = []
        if !Task.isCancelled {
            await progress(.phase("Güvenlik kontrolleri"))
            if let resp = mainResponse {
                siteIssues += SecurityChecker.headerIssues(response: resp, url: mainURL)
            }
            siteIssues += await SecurityChecker.schemeIssues(finalURL: mainURL, fetcher: fetcher)
            if config.probeSensitivePaths, let root = mainURL.siteRoot {
                await progress(.log("Hassas dosyalar aranıyor…"))
                siteIssues += await SecurityChecker.probeSensitivePaths(root: root, fetcher: fetcher) { done, total in
                    await progress(.resources(done: done, total: total))
                }
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
}
