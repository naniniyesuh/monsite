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
    case availability, content, resource, performance, security, certificate

    var title: String {
        switch self {
        case .availability: return "Erişilebilirlik"
        case .content: return "İçerik / bütünlük"
        case .resource: return "Kaynaklar"
        case .performance: return "Performans"
        case .security: return "Güvenlik"
        case .certificate: return "Sertifika"
        }
    }

    var systemImage: String {
        switch self {
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
    var score: Int {
        let penalty = min(Double(count(.critical)) * 15, 60)
            + min(Double(count(.error)) * 4, 30)
            + min(Double(count(.warning)) * 1, 15)
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

// MARK: - Yapılandırma

struct ScanConfig: Codable, Hashable, Sendable {
    var maxPages = 50
    var maxDepth = 3
    var concurrency = 4
    var timeout: Double = 20
    var checkExternalLinks = true
    var probeSensitivePaths = false
    var slowPageMs = 3000
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
