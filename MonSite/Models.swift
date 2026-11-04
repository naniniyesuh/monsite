import Foundation
import Security

// MARK: - Önem derecesi ve kategori

enum Severity: String, Codable, CaseIterable, Comparable, Sendable {
    case critical, error, warning, info

    var rank: Int {
        switch self {
        case .critical: return 0
        case .error: return 1
        case .warning: return 2
        case .info: return 3
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }

    var title: String {
        switch self {
        case .critical: return "Kritik"
        case .error: return "Hata"
        case .warning: return "Uyarı"
        case .info: return "Bilgi"
        }
    }

    var systemImage: String {
        switch self {
        case .critical: return "xmark.octagon.fill"
        case .error: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

enum IssueCategory: String, Codable, CaseIterable, Sendable {
    case availability, content, resource, performance, security, certificate, accessibility, seo

    var title: String {
        switch self {
        case .accessibility: return "Erişilebilirlik (WCAG)"
        case .seo: return "SEO"
        case .availability: return "Erişim"
        case .content: return "İçerik / bütünlük"
        case .resource: return "Kaynaklar"
        case .performance: return "Performans"
        case .security: return "Güvenlik"
        case .certificate: return "Sertifika"
        }
    }

    var systemImage: String {
        switch self {
        case .accessibility: return "figure.wave"
        case .seo: return "magnifyingglass"
        case .availability: return "network"
        case .content: return "doc.text"
        case .resource: return "photo.on.rectangle"
        case .performance: return "speedometer"
        case .security: return "shield.lefthalf.filled"
        case .certificate: return "lock.shield"
        }
    }
}

struct Issue: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    let severity: Severity
    let category: IssueCategory
    let title: String
    let detail: String
    let url: String
}

// MARK: - Kaynak türleri

enum ResourceKind: String, Codable, CaseIterable, Sendable {
    case image, script, stylesheet, font, media, document, frame, link, other

    var title: String {
        switch self {
        case .image: return "Resim"
        case .script: return "Script"
        case .stylesheet: return "CSS"
        case .font: return "Font"
        case .media: return "Medya"
        case .document: return "Dosya"
        case .frame: return "iframe"
        case .link: return "Bağlantı"
        case .other: return "Diğer"
        }
    }

    /// Cümle içinde kullanmak için ("Yüklenemeyen resim")
    var noun: String {
        switch self {
        case .image: return "resim"
        case .script: return "script"
        case .stylesheet: return "CSS dosyası"
        case .font: return "font"
        case .media: return "medya dosyası"
        case .document: return "dosya"
        case .frame: return "iframe"
        case .link: return "bağlantı"
        case .other: return "kaynak"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .script: return "curlybraces"
        case .stylesheet: return "paintbrush"
        case .font: return "textformat"
        case .media: return "play.rectangle"
        case .document: return "doc"
        case .frame: return "rectangle.on.rectangle"
        case .link: return "link"
        case .other: return "questionmark.square"
        }
    }
}

// MARK: - Zamanlama

struct TimingBreakdown: Codable, Hashable, Sendable {
    var dnsMs: Double?
    var connectMs: Double?
    var tlsMs: Double?
    var ttfbMs: Double?
    var downloadMs: Double?
    var redirectCount: Int = 0
    var tlsVersion: String?
    var httpProtocol: String?
}

extension TimingBreakdown {
    init?(metrics: URLSessionTaskMetrics?) {
        guard let metrics, let t = metrics.transactionMetrics.last else { return nil }
        func ms(_ a: Date?, _ b: Date?) -> Double? {
            guard let a, let b else { return nil }
            return b.timeIntervalSince(a) * 1000
        }
        self.init()
        dnsMs = ms(t.domainLookupStartDate, t.domainLookupEndDate)
        connectMs = ms(t.connectStartDate, t.connectEndDate)
        tlsMs = ms(t.secureConnectionStartDate, t.secureConnectionEndDate)
        ttfbMs = ms(t.requestStartDate, t.responseStartDate)
        downloadMs = ms(t.responseStartDate, t.responseEndDate)
        redirectCount = metrics.redirectCount
        httpProtocol = t.networkProtocolName
        if let v = t.negotiatedTLSProtocolVersion {
            switch v.rawValue {
            case 0x0304: tlsVersion = "TLS 1.3"
            case 0x0303: tlsVersion = "TLS 1.2"
            case 0x0302: tlsVersion = "TLS 1.1"
            case 0x0301: tlsVersion = "TLS 1.0"
            default: tlsVersion = "Bilinmiyor"
            }
        }
    }
}

// MARK: - Sonuçlar

struct PageResult: Identifiable, Codable, Hashable, Sendable {
    var id: String { url }
    let url: String
    let finalURL: String
    let depth: Int
    let statusCode: Int?
    let durationMs: Double
    let timing: TimingBreakdown?
    let bytes: Int
    let title: String?
    let contentType: String?
    let isHTML: Bool
    let error: String?
    let linkCount: Int
    let resourceCount: Int
    var issues: [Issue]
    // 1.1 ile eklenenler (eski raporlarda yok)
    var metaDescription: String?
    var canonical: String?
    var wordCount: Int?
    var contentEncoding: String?
}

struct ResourceResult: Identifiable, Codable, Hashable, Sendable {
    var id: String { url }
    let url: String
    let kind: ResourceKind
    let external: Bool
    let statusCode: Int?
    let durationMs: Double
    let bytes: Int?
    let contentType: String?
    let error: String?
    let corrupt: Bool
    let foundOn: [String]
    var contentEncoding: String?
    var cacheControl: String?
    var hasExpires: Bool?

    var servedHTMLInstead: Bool {
        guard ([ResourceKind.image, .script, .stylesheet, .font] as [ResourceKind]).contains(kind) else { return false }
        return contentType?.lowercased().contains("text/html") ?? false
    }

    var isBroken: Bool {
        error != nil || (statusCode ?? 0) >= 400 || corrupt || servedHTMLInstead
    }
}

struct CertificateInfo: Codable, Sendable {
    let host: String
    let subject: String?
    let issuer: String?
    let chain: [String]
    let notBefore: Date?
    let notAfter: Date?
    let trusted: Bool
    let trustError: String?
    let fetchError: String?
    var keyDescription: String?
    var keyBits: Int?
    var keyIsRSA: Bool?

    var daysRemaining: Int? {
        guard let notAfter else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: notAfter).day
    }
}

struct ScanReport: Codable, Sendable {
    let startURL: String
    let finalURL: String
    let startedAt: Date
    let finishedAt: Date
    let cancelled: Bool
    let unscannedLinkCount: Int
    let pages: [PageResult]
    let resources: [ResourceResult]
    let certificate: CertificateInfo?
    let issues: [Issue]

    var host: String { URL(string: finalURL)?.host ?? startURL }
    var durationSec: Double { finishedAt.timeIntervalSince(startedAt) }

    func count(_ s: Severity) -> Int { issues.filter { $0.severity == s }.count }

    var brokenResources: [ResourceResult] { resources.filter(\.isBroken) }

    var averagePageMs: Double {
        let ok = pages.filter { $0.error == nil }
        guard !ok.isEmpty else { return 0 }
        return ok.map(\.durationMs).reduce(0, +) / Double(ok.count)
    }

    var slowestPages: [PageResult] {
        pages.filter { $0.error == nil }.sorted { $0.durationMs > $1.durationMs }
    }

    /// 0–100 arası genel sağlık puanı.
    /// 0–100 arası genel sağlık puanı: alan puanlarının ağırlıklı ortalaması.
    /// Kritik bir sorun varsa puan 59'u geçmez.
    var score: Int {
        let total = ScoreArea.allCases.reduce(0.0) { $0 + Double(areaScore($1)) * $1.weight }
        var result = Int(total.rounded())
        if count(.critical) > 0 { result = min(result, 59) }
        return max(0, min(100, result))
    }

    /// Bir alanın 0–100 puanı. Aynı başlıklı sorunlar (ör. 40 sayfada "alt metni yok")
    /// bir kez sayılır, tekrar sayısı cezayı en fazla iki katına çıkarır.
    func areaScore(_ area: ScoreArea) -> Int {
        var groups: [String: (Severity, Int)] = [:]
        for i in issues where area.categories.contains(i.category) {
            let k = "\(i.severity.rawValue)|\(i.title)"
            groups[k] = (i.severity, (groups[k]?.1 ?? 0) + 1)
        }
        var penalty = 0.0
        for (sev, n) in groups.values {
            let w: Double
            switch sev {
            case .critical: w = 30
            case .error: w = 12
            case .warning: w = 5
            case .info: w = 1
            }
            penalty += w * min(1 + Double(n - 1) * 0.1, 2)
        }
        return max(0, Int((100 - penalty).rounded()))
    }

    var grade: String {
        switch score {
        case 90...: return "A"
        case 80..<90: return "B"
        case 65..<80: return "C"
        case 50..<65: return "D"
        default: return "F"
        }
    }

    var verdict: String {
        switch score {
        case 90...: return "Mükemmel durumda"
        case 80..<90: return "İyi, küçük iyileştirmeler var"
        case 65..<80: return "Dikkat gerektiren sorunlar var"
        case 50..<65: return "Ciddi sorunlar var"
        default: return "Acil müdahale gerekiyor"
        }
    }

    var slowestResources: [ResourceResult] {
        resources.filter { $0.error == nil && !$0.external }.sorted { $0.durationMs > $1.durationMs }
    }
}

// MARK: - Puan alanları

enum ScoreArea: String, CaseIterable, Identifiable, Sendable {
    case links, performance, accessibility, seo, security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .links: return "Bağlantılar"
        case .performance: return "Performans"
        case .accessibility: return "Erişilebilirlik"
        case .seo: return "SEO"
        case .security: return "Güvenlik"
        }
    }

    var categories: Set<IssueCategory> {
        switch self {
        case .links: return [.availability, .resource, .content]
        case .performance: return [.performance]
        case .accessibility: return [.accessibility]
        case .seo: return [.seo]
        case .security: return [.security, .certificate]
        }
    }

    var weight: Double {
        switch self {
        case .links: return 0.25
        case .security: return 0.25
        case .performance: return 0.20
        case .accessibility: return 0.15
        case .seo: return 0.15
        }
    }
}

// MARK: - Yapılandırma

struct ScanConfig: Codable, Hashable, Sendable {
    var maxPages = 50
    var maxDepth = 3
    var concurrency = 4
    var timeout: Double = 20
    var checkExternalLinks = true
    var probeSensitivePaths = false
    var slowPageMs = 3000
    var respectRobots = true
    var useSitemap = true
    /// İzlemede ana sayfada bulunması gereken metin (boşsa kontrol edilmez).
    var requiredText: String?

    init() {}

    enum CodingKeys: String, CodingKey {
        case maxPages, maxDepth, concurrency, timeout, checkExternalLinks, probeSensitivePaths,
             slowPageMs, respectRobots, useSitemap, requiredText
    }

    /// Eski sürümde kaydedilmiş ayarlar da okunabilsin diye eksik alanlar varsayılana düşer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScanConfig()
        maxPages = try c.decodeIfPresent(Int.self, forKey: .maxPages) ?? d.maxPages
        maxDepth = try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? d.maxDepth
        concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency) ?? d.concurrency
        timeout = try c.decodeIfPresent(Double.self, forKey: .timeout) ?? d.timeout
        checkExternalLinks = try c.decodeIfPresent(Bool.self, forKey: .checkExternalLinks) ?? d.checkExternalLinks
        probeSensitivePaths = try c.decodeIfPresent(Bool.self, forKey: .probeSensitivePaths) ?? d.probeSensitivePaths
        slowPageMs = try c.decodeIfPresent(Int.self, forKey: .slowPageMs) ?? d.slowPageMs
        respectRobots = try c.decodeIfPresent(Bool.self, forKey: .respectRobots) ?? d.respectRobots
        useSitemap = try c.decodeIfPresent(Bool.self, forKey: .useSitemap) ?? d.useSitemap
        requiredText = try c.decodeIfPresent(String.self, forKey: .requiredText)
    }
}

// MARK: - Biçimlendirme yardımcıları

func formatMs(_ ms: Double) -> String {
    if ms < 1000 { return "\(Int(ms.rounded())) ms" }
    return String(format: "%.2f sn", ms / 1000)
}

func formatBytes(_ b: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
}

/// Kullanıcının yazdığı adresi tam URL'ye çevirir ("ornek.com" → "https://ornek.com/").
func normalizeSiteURL(_ text: String) -> URL? {
    var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    let lower = s.lowercased()
    if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { s = "https://" + s }
    guard var c = URLComponents(string: s), let host = c.host,
          host.contains(".") || host == "localhost" else { return nil }
    if c.path.isEmpty { c.path = "/" }
    return c.url
}

func shortURL(_ s: String) -> String {
    var r = s
    for p in ["https://", "http://"] where r.hasPrefix(p) { r.removeFirst(p.count) }
    return r
}

extension URL {
    /// Aynı site kontrolü için "www." olmadan, küçük harf host.
    var siteHost: String {
        (host ?? "").lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    /// Ziyaret edilmiş sayfa anahtarı (şema ve fragment yok sayılır).
    var visitKey: String {
        guard let c = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return absoluteString }
        var path = c.percentEncodedPath
        if path.isEmpty { path = "/" }
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        let q = c.percentEncodedQuery.map { "?\($0)" } ?? ""
        let port = c.port.map { ":\($0)" } ?? ""
        return siteHost + port + path + q
    }

    var withoutFragment: URL {
        guard var c = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }
        c.fragment = nil
        return c.url ?? self
    }

    var siteRoot: URL? {
        guard let scheme, let host else { return nil }
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.port = port
        return c.url
    }
}
