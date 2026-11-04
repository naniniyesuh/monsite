import Foundation
import ImageIO

struct PageOutcome: @unchecked Sendable {
    let page: PageResult
    let links: [URL]
    let resources: [FoundResource]
    let response: HTTPURLResponse?
    let finalURL: URL?
}

enum PageProcessor {
    static func process(url: URL, depth: Int, fetcher: HTTPFetcher, config: ScanConfig) async -> PageOutcome? {
        let r = await fetcher.fetchWithRetry(url)
        if r.cancelled { return nil }

        let ct = r.header("Content-Type")
        let code = r.statusCode ?? 0
        var isHTML = false
        if let data = r.data {
            if let ct { isHTML = ct.lowercased().contains("html") }
            else {
                let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
                isHTML = head.contains("<html") || head.contains("<!doctype html")
            }
        }

        var html: String?
        var extracted: ExtractedHTML?
        var facts: PageFacts?
        let final = r.finalURL ?? url
        if isHTML, code < 400, let data = r.data {
            let body = HTMLExtractor.decodeBody(data, contentType: ct)
            html = body
            extracted = HTMLExtractor.extract(html: body, baseURL: final)
            facts = PageInspector.inspect(html: body, url: final)
        }

        var issues = PageAnalyzer.analyze(url: url, finalURL: final, fetch: r,
                                          isHTML: isHTML, html: html, extracted: extracted, config: config)
        if let facts, let html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues += PageInspector.issues(facts, url: url, isHome: depth == 0, xRobotsTag: r.header("X-Robots-Tag"))
        }
        // İzleme: ana sayfada beklenen metin var mı?
        if depth == 0, let needle = config.requiredText?.trimmingCharacters(in: .whitespacesAndNewlines), !needle.isEmpty {
            let found = html?.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            if !found {
                issues.append(Issue(severity: .critical, category: .availability, title: "Beklenen içerik bulunamadı",
                                    detail: "Ana sayfada “\(needle)” metni yok. Sayfa açılıyor ama içerik değişmiş veya hata sayfası gösteriliyor olabilir.",
                                    url: url.absoluteString))
            }
        }
        let page = PageResult(
            url: url.absoluteString,
            finalURL: (r.finalURL ?? url).absoluteString,
            depth: depth,
            statusCode: r.statusCode,
            durationMs: r.durationMs,
            timing: r.timing,
            bytes: r.data?.count ?? 0,
            title: extracted?.title,
            contentType: ct,
            isHTML: isHTML,
            error: r.error,
            linkCount: extracted?.links.count ?? 0,
            resourceCount: extracted?.resources.count ?? 0,
            issues: issues,
            metaDescription: facts?.metaDescription,
            canonical: facts?.canonical?.absoluteString,
            wordCount: facts?.wordCount,
            contentEncoding: r.header("Content-Encoding"))
        return PageOutcome(page: page,
                           links: extracted?.links ?? [],
                           resources: extracted?.resources ?? [],
                           response: r.response,
                           finalURL: r.finalURL)
    }
}

enum PageAnalyzer {
    static let errorSignatures: [(String, String)] = [
        ("<b>Fatal error</b>", "PHP ölümcül hata"),
        ("<b>Parse error</b>", "PHP söz dizimi hatası"),
        ("<b>Warning</b>:", "PHP uyarı çıktısı"),
        ("<b>Notice</b>:", "PHP bildirim çıktısı"),
        ("<b>Deprecated</b>:", "PHP eskimiş fonksiyon uyarısı"),
        ("Traceback (most recent call last)", "Python hata izi"),
        ("You have an error in your SQL syntax", "SQL söz dizimi hatası"),
        ("SQLSTATE[", "Veritabanı hatası"),
        ("Error establishing a database connection", "WordPress veritabanı bağlantı hatası"),
        ("There has been a critical error on this website", "WordPress kritik hata"),
        ("Server Error in '/' Application", "ASP.NET sunucu hatası"),
        ("Whitelabel Error Page", "Spring Boot hata sayfası"),
        ("Uncaught exception", "Yakalanmamış istisna"),
        ("Stack trace:", "Hata izi (stack trace)")
    ]

    static func analyze(url: URL, finalURL: URL, fetch: FetchResult, isHTML: Bool,
                        html: String?, extracted: ExtractedHTML?, config: ScanConfig) -> [Issue] {
        var issues: [Issue] = []
        let u = url.absoluteString
        func add(_ s: Severity, _ c: IssueCategory, _ t: String, _ d: String = "") {
            issues.append(Issue(severity: s, category: c, title: t, detail: d, url: u))
        }

        if let err = fetch.error {
            add(.critical, .availability, "Sayfa açılamadı", err)
            return issues
        }
        guard let code = fetch.statusCode else { return issues }
        let reason = HTTPURLResponse.localizedString(forStatusCode: code)
        if code >= 500 {
            add(.critical, .availability, "Sunucu hatası (HTTP \(code))", reason)
        } else if code >= 400 {
            add(.error, .availability, "Sayfa açılmıyor (HTTP \(code))", reason)
        }

        if let t = fetch.timing {
            if t.redirectCount >= 3 {
                add(.warning, .performance, "Çok fazla yönlendirme", "\(t.redirectCount) yönlendirme → \(finalURL.absoluteString)")
            }
            if let ttfb = t.ttfbMs, ttfb > 1500 {
                add(.warning, .performance, "Sunucu yanıtı yavaş (TTFB)", "İlk bayt \(formatMs(ttfb)) sonra geldi")
            }
        }
        if fetch.durationMs > Double(config.slowPageMs) {
            add(.warning, .performance, "Yavaş sayfa", "HTML \(formatMs(fetch.durationMs)) içinde yüklendi")
        }
        let bytes = fetch.data?.count ?? 0
        if isHTML && bytes > 2_000_000 {
            add(.warning, .performance, "HTML çok büyük", formatBytes(bytes))
        }

        guard code < 400, isHTML else { return issues }
        guard let html, let ex = extracted else { return issues }

        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, .content, "Sayfa boş", "Sunucu boş içerik döndürdü")
            return issues
        }
        if !ex.hasClosingHTML {
            add(.warning, .content, "Sayfa eksik yüklenmiş olabilir", "</html> kapanış etiketi bulunamadı")
        }
        if let sig = errorSignatures.first(where: { html.contains($0.0) }) {
            add(.error, .content, "Sayfada sunucu hata çıktısı var", "\(sig.1) — “\(sig.0)” ifadesi bulundu")
        }
        if html.range(of: "<title>Index of /", options: .caseInsensitive) != nil {
            add(.warning, .security, "Dizin listeleme açık", "Sunucu klasör içeriğini listeliyor")
        }

        let activeKinds: Set<ResourceKind> = [.script, .stylesheet, .frame]
        if finalURL.scheme == "https" {
            let insecure = ex.resources.filter { $0.url.scheme == "http" }
            let active = insecure.filter { activeKinds.contains($0.kind) }
            let passive = insecure.filter { !activeKinds.contains($0.kind) }
            if !active.isEmpty {
                add(.error, .security, "Aktif karışık içerik",
                    "HTTPS sayfada HTTP üzerinden \(active.count) script/CSS/iframe: " +
                    active.prefix(3).map(\.url.absoluteString).joined(separator: ", "))
            }
            if !passive.isEmpty {
                add(.warning, .security, "Pasif karışık içerik",
                    "HTTP üzerinden \(passive.count) resim/medya yükleniyor")
            }
            let insecureForms = ex.formActions.filter { $0.scheme == "http" }
            if !insecureForms.isEmpty {
                add(.critical, .security, "Form şifresiz HTTP'ye gönderiliyor",
                    insecureForms.prefix(3).map(\.absoluteString).joined(separator: ", "))
            }
        } else if ex.hasPasswordField {
            add(.critical, .security, "Şifre alanı şifrelenmemiş sayfada", "Parolalar HTTP üzerinden açık metin gönderilir")
        }
        return issues
    }
}

// MARK: - Kaynak (resim, script, css, dosya, dış bağlantı) kontrolü

struct ResourceRef: Sendable {
    let url: URL
    var kind: ResourceKind
    let external: Bool
    var foundOn: Set<String>
}

enum ResourceChecker {
    private static let fullDownloadKinds: Set<ResourceKind> = [.image, .script, .stylesheet, .font]

    struct Outcome: Sendable {
        let result: ResourceResult
        /// İndirilen CSS dosyasının içinde bulunan font, resim ve @import adresleri
        let cssResources: [FoundResource]
    }

    static func check(_ ref: ResourceRef, fetcher: HTTPFetcher) async -> Outcome? {
        let downloadFully = fullDownloadKinds.contains(ref.kind) && !ref.external
        var r: FetchResult
        if downloadFully {
            r = await fetcher.fetchWithRetry(ref.url)
        } else {
            r = await fetcher.fetch(ref.url, method: "HEAD")
            if r.cancelled { return nil }
            // Bazı sunucular HEAD isteğini desteklemez; kısa bir GET ile tekrar dene.
            if r.error != nil || (r.statusCode ?? 0) >= 400 {
                let g = await fetcher.fetchPrefix(ref.url, maxBytes: 2048)
                if !g.cancelled { r = g }
            }
        }
        if r.cancelled { return nil }

        var bytes: Int?
        if downloadFully {
            bytes = r.data?.count
        } else {
            let len = r.response?.expectedContentLength ?? -1
            bytes = len > 0 ? Int(len) : nil
        }

        let ct = r.header("Content-Type")
        let ok = (r.statusCode ?? 0) < 400 && r.error == nil
        var corrupt = false
        if ref.kind == .image, downloadFully, ok, let data = r.data,
           let lct = ct?.lowercased(),
           ["png", "jpeg", "jpg", "gif", "webp", "heic"].contains(where: { lct.contains($0) }) {
            corrupt = !imageDecodes(data)
        }

        var css: [FoundResource] = []
        if ref.kind == .stylesheet, downloadFully, ok, let data = r.data,
           !(ct?.lowercased().contains("html") ?? false) {
            let text = String(decoding: data, as: UTF8.self)
            css = HTMLExtractor.cssResources(text, base: r.finalURL ?? ref.url)
        }

        var result = ResourceResult(
            url: ref.url.absoluteString,
            kind: ref.kind,
            external: ref.external,
            statusCode: r.statusCode,
            durationMs: r.durationMs,
            bytes: bytes,
            contentType: ct,
            error: r.error,
            corrupt: corrupt,
            foundOn: ref.foundOn.sorted())
        result.contentEncoding = r.header("Content-Encoding")
        result.cacheControl = r.header("Cache-Control")
        result.hasExpires = r.header("Expires") != nil
        return Outcome(result: result, cssResources: css)
    }

    /// Resmin gerçekten açılabildiğini ImageIO ile doğrular (UIKit gerektirmez).
    static func imageDecodes(_ data: Data) -> Bool {
        guard !data.isEmpty, let src = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(src) > 0 else { return false }
        return CGImageSourceCreateImageAtIndex(src, 0, nil) != nil
    }

    static func issues(for res: [ResourceResult]) -> [Issue] {
        var issues: [Issue] = []
        let heavyKinds: Set<ResourceKind> = [.image, .script, .stylesheet, .font]
        for r in res {
            let usedIn = r.foundOn.count == 1
                ? "Sayfa: \(shortURL(r.foundOn[0]))"
                : "\(r.foundOn.count) sayfada kullanılıyor"
            func add(_ s: Severity, _ c: IssueCategory, _ t: String, _ d: String) {
                issues.append(Issue(severity: s, category: c, title: t, detail: "\(d) · \(usedIn)", url: r.url))
            }

            if let e = r.error {
                if r.external { add(.warning, .resource, "Dış bağlantıya ulaşılamıyor", e) }
                else { add(.error, .resource, "Yüklenemeyen \(r.kind.noun)", e) }
                continue
            }
            if let c = r.statusCode, c >= 400 {
                let reason = HTTPURLResponse.localizedString(forStatusCode: c)
                if r.external {
                    // 403/429 çoğu zaman bot korumasıdır.
                    let sev: Severity = (c == 403 || c == 429 || c == 999) ? .info : .warning
                    add(sev, .resource, "Kırık dış bağlantı (HTTP \(c))", reason)
                } else {
                    add(.error, .resource, r.kind == .link || r.kind == .document
                        ? "Kırık bağlantı (HTTP \(c))"
                        : "Yüklenemeyen \(r.kind.noun) (HTTP \(c))", reason)
                }
                continue
            }
            if r.corrupt {
                add(.error, .resource, "Bozuk resim dosyası", "Dosya indirildi ama resim olarak açılamadı")
                continue
            }
            if r.servedHTMLInstead {
                add(.error, .resource, "\(r.kind.title) yerine HTML döndü", "Sunucu muhtemelen bir hata/404 sayfası gönderiyor")
                continue
            }
            if !r.external && heavyKinds.contains(r.kind) && r.durationMs > 2000 {
                add(.warning, .performance, "Yavaş yüklenen \(r.kind.noun)", formatMs(r.durationMs))
            }
            if let b = r.bytes {
                if r.kind == .image && b > 1_000_000 {
                    add(.warning, .performance, "Büyük resim dosyası", "\(formatBytes(b)) — sıkıştırma/WebP önerilir")
                } else if (r.kind == .script || r.kind == .stylesheet) && b > 1_000_000 {
                    add(.warning, .performance, "Büyük \(r.kind.noun)", formatBytes(b))
                }
            }
        }
        return issues
    }
}
