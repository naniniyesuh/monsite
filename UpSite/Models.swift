import Foundation

enum SiteStatus: String, Codable {
    case unknown, up, down, paused
}

/// Sunucudan gelen site durumu.
struct Site: Identifiable, Codable, Hashable {
    var id: String
    var url: String
    var name: String
    var intervalMin: Int
    var notifyDown: Bool
    var notifyUp: Bool
    var paused: Bool
    var status: String
    var statusSince: Double?
    var lastCode: Int?
    var lastError: String?
    var lastCheckAt: Double?
    var nextCheckAt: Double?
    /// En yeni başta: [zaman(ms), kod]; kod -1 = bağlantı kurulamadı
    var recent: [[Double]]
    var createdAt: Double

    var displayStatus: SiteStatus {
        if paused { return .paused }
        return SiteStatus(rawValue: status) ?? .unknown
    }

    var host: String { URL(string: url)?.host ?? url }
    var isHTTPS: Bool { url.lowercased().hasPrefix("https://") }

    var since: Date? { statusSince.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var lastCheck: Date? { lastCheckAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var nextCheck: Date? { nextCheckAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

    /// Çubuklar için eskiden yeniye sonuçlar
    var recentOK: [Bool?] {
        recent.reversed().map { pair in
            guard pair.count > 1 else { return nil }
            let c = Int(pair[1])
            return c >= 200 && c < 300
        }
    }

    var codeText: String {
        if paused { return "—" }
        if let c = lastCode, c > 0 { return "\(c)" }
        if displayStatus == .down { return L.s("code.noResponse") }
        return "—"
    }
}

struct SiteState: Codable {
    var serverTime: Double
    var lastCronAt: Double?
    var sites: [Site]
}

struct SiteHistory: Codable {
    struct Event: Codable, Hashable {
        var at: Double
        var kind: String
        var code: Int?
        var error: String?
        var date: Date { Date(timeIntervalSince1970: at / 1000) }
    }
    /// [zaman(ms), kod]
    var checks: [[Double]]
    var events: [Event]

    var okValues: [Bool?] {
        checks.reversed().map { p in
            guard p.count > 1 else { return nil }
            let c = Int(p[1]); return c >= 200 && c < 300
        }
    }

    var uptimePercent: Double? {
        let v = okValues.compactMap { $0 }
        guard !v.isEmpty else { return nil }
        return Double(v.filter { $0 }.count) / Double(v.count) * 100
    }
}

/// Kontrol sıklığı (dakika). Hazır seçenekler ve 1–60 dakika arası özel değer.
enum CheckInterval {
    static let presets = [1, 5, 10, 15, 30, 60]
    static let range = 1...60
    static let defaultValue = 15

    static func clamp(_ minutes: Int) -> Int { min(max(minutes, range.lowerBound), range.upperBound) }

    static func label(_ minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            return minutes == 60 ? L.s("interval.1h") : L.s("interval.hours", minutes / 60)
        }
        return L.s("interval.min", minutes)
    }

    /// Şu andan sonraki ilk `count` planlı kontrol (her saat başında yeniden :00'dan sayılır).
    static func upcoming(_ minutes: Int, count: Int, from now: Date = Date()) -> [Date] {
        let step = clamp(minutes)
        let cal = Calendar.current
        guard var t = cal.date(bySetting: .second, value: 0, of: now) else { return [] }
        var out: [Date] = []
        for _ in 0..<(24 * 60) where out.count < count {
            t = t.addingTimeInterval(60)
            if (cal.component(.minute, from: t) % 60) % step == 0 { out.append(t) }
        }
        return out
    }
}

/// Dışa / içe aktarma dosyası
struct SiteListFile: Codable {
    struct Entry: Codable {
        var url: String
        var name: String?
        var intervalMin: Int?
        var notifyDown: Bool?
        var notifyUp: Bool?
    }
    var app = "UpSite"
    var version = 1
    var exportedAt: Date = Date()
    var sites: [Entry]
}

/// Telefonda yapılan sertifika kontrolünün sonucu.
struct CertRecord: Codable, Identifiable, Hashable {
    var id: String { host }
    var host: String
    var notAfter: Date?
    var notBefore: Date?
    var issuer: String?
    var fingerprint: String?
    var trusted: Bool
    var error: String?
    var checkedAt: Date
    /// Sertifika değiştiyse (parmak izi farklı) bu tarih
    var changedAt: Date?
    var previousNotAfter: Date?

    var daysLeft: Int? {
        guard let notAfter else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                               to: Calendar.current.startOfDay(for: notAfter)).day
    }

    /// Son 7 gün içinde yenilendi mi
    var recentlyChanged: Bool {
        guard let changedAt else { return false }
        return Date().timeIntervalSince(changedAt) < 7 * 86_400
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, tr, en
    var id: String { rawValue }
}
