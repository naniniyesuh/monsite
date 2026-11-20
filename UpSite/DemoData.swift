import Foundation

/// Yalnızca `-UpSiteDemo` başlangıç argümanıyla kullanılır (ekran görüntüleri ve tanıtım videosu).
enum DemoData {
    private static func ms(_ d: Date) -> Double { d.timeIntervalSince1970 * 1000 }

    private static var lastTick: Date {
        let now = Date()
        let m = Calendar.current.component(.minute, from: now)
        return Calendar.current.date(byAdding: .minute, value: -(m % 15), to: now)
            .flatMap { Calendar.current.date(bySetting: .second, value: 0, of: $0) } ?? now
    }

    private static func recent(_ interval: Int, downAt: Set<Int> = [], code: Int = 200) -> [[Double]] {
        (0..<24).map { i in
            let at = lastTick.addingTimeInterval(-Double(i * interval * 60))
            return [ms(at), downAt.contains(i) ? Double(code) : 200]
        }
    }

    private static func site(_ id: String, _ url: String, _ name: String, _ interval: Int, status: String, sinceH: Double,
                             recent r: [[Double]], paused: Bool = false, code: Int = 200, pkg: String = "p1") -> Site {
        Site(id: id, packageId: pkg, url: url, name: name, intervalMin: interval, notifyDown: true, notifyUp: true, paused: paused,
             status: status, statusSince: ms(Date().addingTimeInterval(-sinceH * 3600)), lastCode: code, lastError: nil,
             lastCheckAt: paused ? nil : ms(lastTick), nextCheckAt: paused ? nil : ms(lastTick.addingTimeInterval(Double(interval * 60))),
             recent: paused ? [] : r, createdAt: ms(Date().addingTimeInterval(-20 * 86_400)))
    }

    static func state() -> ([SitePackage], [Site], Date?) {
        let created = Date().addingTimeInterval(-30 * 86_400).timeIntervalSince1970 * 1000
        let packages = [
            SitePackage(id: "p1", name: L.current == .tr ? "Sitelerim" : "My sites", key: "7K2PQ9XAMH4D", isOwner: true, members: 1, retries: 2, timeoutS: 15, createdAt: created),
            SitePackage(id: "p2", name: L.current == .tr ? "Web ekibi" : "Web team", key: "R8VN3CWE6TJB", isOwner: false, members: 5, retries: 2, timeoutS: 15, createdAt: created),
        ]
        let sites = [
            site("d1", "https://shop.example.com/", "shop.example.com", 2, status: "down", sinceH: 0.25, recent: recent(2, downAt: [0, 1], code: 503), code: 503, pkg: "p2"),
            site("d2", "https://alpp.studio/", "alpp.studio", 15, status: "up", sinceH: 74, recent: recent(15)),
            site("d3", "https://alpp.studio/upsite/", "alpp.studio/upsite", 60, status: "up", sinceH: 290, recent: recent(60)),
            site("d4", "https://api.example.com/", "api.example.com", 5, status: "up", sinceH: 20, recent: recent(5, downAt: [9, 10]), pkg: "p2"),
            site("d5", "https://example.com/", "example.com", 30, status: "up", sinceH: 220, recent: recent(30), pkg: "p2"),
            site("d6", "https://docs.example.org/", "docs.example.org", 3, status: "up", sinceH: 400, recent: [], paused: true, pkg: "p2"),
        ]
        return (packages, sites, lastTick)
    }

    static func newSite(url: String, name: String, interval: Int, packageId: String?) -> Site {
        let u = url.hasPrefix("http") ? url : "https://\(url)/"
        let host = URL(string: u)?.host ?? url
        return site(UUID().uuidString, u, name.isEmpty ? host : name, interval, status: "unknown", sinceH: 0, recent: [], pkg: packageId ?? "p1")
    }

    static func history(for s: Site) -> SiteHistory {
        let n = 7 * 24 * 60 / max(s.intervalMin, 15)
        let checks: [[Double]] = (0..<min(n, 672)).map { i in
            let at = lastTick.addingTimeInterval(-Double(i * s.intervalMin * 60))
            let down = s.id == "d1" ? i < 2 : (s.id == "d4" ? (i == 9 || i == 10) : (s.id == "d2" && (i == 300 || i == 301)))
            return [ms(at), down ? 503 : 200]
        }
        var events: [SiteHistory.Event] = []
        if s.id == "d1" {
            events = [.init(at: ms(lastTick.addingTimeInterval(-900)), kind: "down", code: 503, error: "http")]
        } else if s.id == "d2" {
            events = [
                .init(at: ms(Date().addingTimeInterval(-74 * 3600)), kind: "up", code: 200, error: nil),
                .init(at: ms(Date().addingTimeInterval(-74.5 * 3600)), kind: "down", code: 503, error: "http"),
            ]
        } else if s.id == "d4" {
            events = [
                .init(at: ms(Date().addingTimeInterval(-20 * 3600)), kind: "up", code: 200, error: nil),
                .init(at: ms(Date().addingTimeInterval(-20.5 * 3600)), kind: "down", code: nil, error: "timeout"),
            ]
        }
        return SiteHistory(checks: checks, events: events)
    }

    static func certs() -> [String: CertRecord] {
        let now = Date()
        func rec(_ host: String, _ days: Int, _ issuer: String, changed: Bool = false) -> CertRecord {
            CertRecord(host: host, notAfter: Calendar.current.date(byAdding: .day, value: days, to: now),
                       notBefore: Calendar.current.date(byAdding: .day, value: days - 90, to: now), issuer: issuer,
                       fingerprint: host, trusted: true, error: nil, checkedAt: now.addingTimeInterval(-40),
                       changedAt: changed ? now.addingTimeInterval(-120) : nil,
                       previousNotAfter: changed ? Calendar.current.date(byAdding: .day, value: 3, to: now) : nil)
        }
        let list = [
            rec("api.example.com", 9, "R11"),
            rec("alpp.studio", 89, "YR1", changed: true),
            rec("shop.example.com", 41, "E7"),
            rec("example.com", 46, "DigiCert Global G3"),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.host, $0) })
    }
}
