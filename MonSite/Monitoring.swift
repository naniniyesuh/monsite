import Foundation

// MARK: - İzleme modeli

struct Monitor: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var urlString: String
    var intervalMinutes: Int
    var enabled = true
    var notifyOnChange = true
    var config = ScanConfig()
    var createdAt = Date()
    var lastRunAt: Date?
    /// En yeni başta, en fazla `MonitorStore.maxRuns` kayıt.
    var runs: [MonitorRun] = []

    var url: URL? { URL(string: urlString) }
    var latest: MonitorRun? { runs.first }

    var nextRunAt: Date {
        guard let lastRunAt else { return createdAt }
        return lastRunAt.addingTimeInterval(Double(intervalMinutes) * 60)
    }

    var isDue: Bool { enabled && nextRunAt <= Date() }

    var intervalText: String { MonitorInterval.title(for: intervalMinutes) }
}

struct MonitorRun: Identifiable, Codable, Hashable {
    var id = UUID()
    let date: Date
    let durationSec: Double
    let quick: Bool
    let score: Int
    let grade: String
    let pageCount: Int
    let problemCount: Int
    let brokenCount: Int
    let avgMs: Double
    let certDays: Int?
    let reportFile: String
    let diff: ScanDiff?
    // 1.1: çalışırlık (uptime) istatistikleri için ana sayfa durumu
    var homeOK: Bool?
    var homeMs: Double?
    var homeTTFBMs: Double?
}

/// Son kontrollerden hesaplanan çalışırlık özeti.
struct UptimeStats {
    let checks: Int
    let up: Int
    let avgMs: Double
    let avgTTFBMs: Double?
    let lastDown: Date?
    let since: Date?

    var percent: Double { checks == 0 ? 0 : Double(up) / Double(checks) * 100 }

    init?(runs: [MonitorRun], limit: Int = 100) {
        let list = runs.prefix(limit).filter { $0.homeOK != nil }
        guard !list.isEmpty else { return nil }
        checks = list.count
        up = list.filter { $0.homeOK == true }.count
        let ok = list.filter { $0.homeOK == true }
        let ms = ok.compactMap(\.homeMs)
        avgMs = ms.isEmpty ? 0 : ms.reduce(0, +) / Double(ms.count)
        let tt = ok.compactMap(\.homeTTFBMs)
        avgTTFBMs = tt.isEmpty ? nil : tt.reduce(0, +) / Double(tt.count)
        lastDown = list.first { $0.homeOK == false }?.date
        since = list.last?.date
    }
}

enum MonitorInterval {
    static let presets: [Int] = [1, 5, 15, 30, 60, 180, 360, 720, 1440, 10080]

    static func title(for minutes: Int) -> String {
        switch minutes {
        case 1: return "Her dakika"
        case 10080: return "Haftada bir"
        case 1440: return "Günde bir"
        case 60: return "Saatte bir"
        case let m where m % 1440 == 0: return "\(m / 1440) günde bir"
        case let m where m % 60 == 0: return "\(m / 60) saatte bir"
        default: return "\(minutes) dakikada bir"
        }
    }
}

// MARK: - Fark (diff)

struct ScanDiff: Codable, Hashable {
    struct IssueChange: Codable, Hashable, Identifiable {
        var id: String { key }
        let key: String
        let severity: Severity
        let category: IssueCategory
        let title: String
        let detail: String
        let url: String
    }

    struct StatusChange: Codable, Hashable, Identifiable {
        var id: String { url }
        let url: String
        let oldText: String
        let newText: String
        let worse: Bool
    }

    struct TimingChange: Codable, Hashable, Identifiable {
        var id: String { url }
        let url: String
        let oldMs: Double
        let newMs: Double
    }

    var previousRunDate: Date
    var oldScore: Int
    var newScore: Int
    var oldAvgMs: Double
    var newAvgMs: Double
    var oldPageCount: Int
    var newPageCount: Int
    var newIssues: [IssueChange] = []
    var resolvedIssues: [IssueChange] = []
    var addedPages: [String] = []
    var removedPages: [String] = []
    var statusChanges: [StatusChange] = []
    var newlyBroken: [String] = []
    var fixedResources: [String] = []
    var slowerPages: [TimingChange] = []
    var fasterPages: [TimingChange] = []
    var certChanges: [String] = []

    var scoreDelta: Int { newScore - oldScore }

    /// Önemli (bilgi seviyesi dışındaki) yeni sorunlar
    var newProblems: [IssueChange] { newIssues.filter { $0.severity <= .warning } }
    var resolvedProblems: [IssueChange] { resolvedIssues.filter { $0.severity <= .warning } }

    var hasChanges: Bool {
        !newProblems.isEmpty || !resolvedProblems.isEmpty || !addedPages.isEmpty || !removedPages.isEmpty
            || !statusChanges.isEmpty || !newlyBroken.isEmpty || !fixedResources.isEmpty
            || !slowerPages.isEmpty || !fasterPages.isEmpty || !certChanges.isEmpty || scoreDelta != 0
    }

    var hasRegressions: Bool {
        !newProblems.isEmpty || !newlyBroken.isEmpty || statusChanges.contains(where: \.worse)
            || scoreDelta < 0 || !slowerPages.isEmpty
    }

    var summary: String {
        var parts: [String] = []
        if !newProblems.isEmpty { parts.append("\(newProblems.count) yeni sorun") }
        if !resolvedProblems.isEmpty { parts.append("\(resolvedProblems.count) çözüldü") }
        if !newlyBroken.isEmpty { parts.append("\(newlyBroken.count) kaynak bozuldu") }
        if !fixedResources.isEmpty { parts.append("\(fixedResources.count) kaynak düzeldi") }
        let worse = statusChanges.filter(\.worse).count
        if worse > 0 { parts.append("\(worse) sayfa erişilemez oldu") }
        if !slowerPages.isEmpty { parts.append("\(slowerPages.count) sayfa yavaşladı") }
        if !addedPages.isEmpty { parts.append("\(addedPages.count) yeni sayfa") }
        if !removedPages.isEmpty { parts.append("\(removedPages.count) sayfa kayboldu") }
        if !certChanges.isEmpty { parts.append("sertifika değişti") }
        if scoreDelta != 0 { parts.append("puan \(scoreDelta > 0 ? "+" : "−")\(abs(scoreDelta))") }
        return parts.isEmpty ? "Değişiklik yok" : parts.joined(separator: " · ")
    }
}

enum DiffEngine {
    static func key(_ i: Issue) -> String {
        "\(i.severity.rawValue)|\(i.category.rawValue)|\(i.title)|\(i.url)"
    }

    private static func change(_ i: Issue) -> ScanDiff.IssueChange {
        .init(key: key(i), severity: i.severity, category: i.category, title: i.title, detail: i.detail, url: i.url)
    }

    private static func pageKey(_ s: String) -> String { URL(string: s)?.visitKey ?? s }

    private static func statusText(_ p: PageResult) -> String {
        if let e = p.error { return e }
        return p.statusCode.map { "HTTP \($0)" } ?? "—"
    }

    private static func isOK(_ p: PageResult) -> Bool {
        p.error == nil && (p.statusCode ?? 0) < 400
    }

    static func diff(old: ScanReport, new: ScanReport, previousRunDate: Date) -> ScanDiff {
        var d = ScanDiff(previousRunDate: previousRunDate,
                         oldScore: old.score, newScore: new.score,
                         oldAvgMs: old.averagePageMs, newAvgMs: new.averagePageMs,
                         oldPageCount: old.pages.count, newPageCount: new.pages.count)

        // Sorunlar
        let oldIssues = Dictionary(old.issues.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        let newIssues = Dictionary(new.issues.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        d.newIssues = newIssues.filter { oldIssues[$0.key] == nil }.values
            .sorted { $0.severity < $1.severity }.map(change)
        d.resolvedIssues = oldIssues.filter { newIssues[$0.key] == nil }.values
            .sorted { $0.severity < $1.severity }.map(change)

        // Sayfalar
        let oldPages = Dictionary(old.pages.map { (pageKey($0.url), $0) }, uniquingKeysWith: { a, _ in a })
        let newPages = Dictionary(new.pages.map { (pageKey($0.url), $0) }, uniquingKeysWith: { a, _ in a })
        // Sayfa limiti dolduysa "kaybolan/eklenen" sayfalar sadece tarama sırasından kaynaklanabilir.
        let limitHit = old.unscannedLinkCount > 0 || new.unscannedLinkCount > 0
        if !limitHit {
            d.addedPages = newPages.filter { oldPages[$0.key] == nil }.map { $0.value.url }.sorted()
            d.removedPages = oldPages.filter { newPages[$0.key] == nil }.map { $0.value.url }.sorted()
        }

        for (k, np) in newPages {
            guard let op = oldPages[k] else { continue }
            let os = statusText(op), ns = statusText(np)
            if os != ns {
                d.statusChanges.append(.init(url: np.url, oldText: os, newText: ns, worse: isOK(op) && !isOK(np)))
            }
            if isOK(op) && isOK(np) {
                let delta = np.durationMs - op.durationMs
                if np.durationMs > op.durationMs * 1.5 && delta > 500 {
                    d.slowerPages.append(.init(url: np.url, oldMs: op.durationMs, newMs: np.durationMs))
                } else if op.durationMs > np.durationMs * 1.5 && -delta > 500 {
                    d.fasterPages.append(.init(url: np.url, oldMs: op.durationMs, newMs: np.durationMs))
                }
            }
        }
        d.statusChanges.sort { ($0.worse ? 0 : 1, $0.url) < ($1.worse ? 0 : 1, $1.url) }
        d.slowerPages.sort { ($0.newMs - $0.oldMs) > ($1.newMs - $1.oldMs) }
        d.fasterPages.sort { ($0.oldMs - $0.newMs) > ($1.oldMs - $1.newMs) }

        // Kaynaklar
        let oldBroken = Set(old.brokenResources.map(\.url))
        let newBroken = Set(new.brokenResources.map(\.url))
        let newAll = Set(new.resources.map(\.url))
        d.newlyBroken = newBroken.subtracting(oldBroken).sorted()
        // Sadece hâlâ kontrol edilen ve artık bozuk olmayanlar "düzeldi" sayılır.
        d.fixedResources = oldBroken.subtracting(newBroken).filter { newAll.contains($0) }.sorted()

        // Sertifika
        if let oc = old.certificate, let nc = new.certificate {
            let df = DateFormatter()
            df.locale = Locale(identifier: "tr_TR")
            df.dateStyle = .medium
            if let a = oc.notAfter, let b = nc.notAfter, abs(a.timeIntervalSince(b)) > 60 {
                d.certChanges.append(b > a
                    ? "Sertifika yenilendi — yeni bitiş: \(df.string(from: b))"
                    : "Sertifika değişti — bitiş: \(df.string(from: b))")
            }
            if oc.trusted != nc.trusted {
                d.certChanges.append(nc.trusted ? "Sertifika tekrar güvenilir" : "Sertifika artık güvenilir değil")
            }
            if oc.issuer != nc.issuer, let ni = nc.issuer {
                d.certChanges.append("Sertifikayı veren değişti: \(oc.issuer ?? "—") → \(ni)")
            }
        }
        return d
    }
}

// MARK: - JSON kodlama

enum ReportCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
