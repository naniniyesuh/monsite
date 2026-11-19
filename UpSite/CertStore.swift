import Foundation
import Security
import CryptoKit
import UserNotifications

/// Sertifikaları telefondan kontrol eder (uygulama açıldığında ve istendiğinde)
/// ve bitiş tarihinden önce yerel uyarı kurar.
@MainActor
final class CertStore: ObservableObject {
    static let shared = CertStore()

    @Published private(set) var records: [String: CertRecord] = [:]
    @Published private(set) var checking: Set<String> = []
    @Published private(set) var lastCheckAll: Date?

    private let key = "certRecords"
    private let demo = ProcessInfo.processInfo.arguments.contains("-UpSiteDemo")

    private init() {
        if demo {
            records = DemoData.certs()
        } else if let data = UserDefaults.standard.data(forKey: key),
                  let list = try? JSONDecoder().decode([CertRecord].self, from: data) {
            records = Dictionary(uniqueKeysWithValues: list.map { ($0.host, $0) })
        }
        Prefs.shared.onCertSettingsChange = { [weak self] in self?.scheduleReminders() }
    }

    private func save() {
        guard !demo, let data = try? JSONEncoder().encode(Array(records.values)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        records = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Takip edilen siteler için benzersiz alan adları
    func trackedHosts(_ sites: [Site]) -> [String] {
        var seen = Set<String>()
        return sites.filter { $0.isHTTPS && !Prefs.shared.certExcluded.contains($0.id) }
            .map(\.host).filter { seen.insert($0).inserted }
    }

    func checkAll(_ sites: [Site]) async {
        if demo { return }
        let hosts = trackedHosts(sites)
        await withTaskGroup(of: Void.self) { group in
            var it = hosts.makeIterator()
            for _ in 0..<min(4, hosts.count) {
                if let h = it.next() { group.addTask { await self.check(h) } }
            }
            while await group.next() != nil {
                if let h = it.next() { group.addTask { await self.check(h) } }
            }
        }
        lastCheckAll = Date()
        // Artık takip edilmeyen alan adlarını temizle
        let keep = Set(hosts)
        records = records.filter { keep.contains($0.key) }
        save()
        scheduleReminders()
    }

    func check(_ host: String) async {
        if demo { return }
        checking.insert(host)
        defer { checking.remove(host) }
        let fetched = await CertificateProbe.fetch(host: host)
        let old = records[host]
        var rec = CertRecord(host: host, notAfter: fetched.notAfter, notBefore: fetched.notBefore, issuer: fetched.issuer,
                             fingerprint: fetched.fingerprint, trusted: fetched.trusted, error: fetched.error,
                             checkedAt: Date(), changedAt: old?.changedAt, previousNotAfter: old?.previousNotAfter)
        if let oldFP = old?.fingerprint, let newFP = fetched.fingerprint, oldFP != newFP {
            rec.changedAt = Date()
            rec.previousNotAfter = old?.notAfter
        }
        // Okunamadıysa son bilinen tarihleri göster
        if fetched.fingerprint == nil, let old {
            rec.notAfter = old.notAfter; rec.notBefore = old.notBefore; rec.issuer = old.issuer; rec.fingerprint = old.fingerprint
        }
        records[host] = rec
        save()
    }

    /// Her sertifika için "bitişe N gün kala" yerel bildirimi (sabah 10:00).
    func scheduleReminders() {
        let center = UNUserNotificationCenter.current()
        let current = Set(records.keys.map { "cert.\($0)" })
        // Aynı kimlikle eklenen istek eskisinin yerine geçer; artık takip edilmeyenleri ayrıca sil.
        center.getPendingNotificationRequests { reqs in
            let stale = reqs.map(\.identifier).filter { $0.hasPrefix("cert.") && !current.contains($0) }
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        }
        let threshold = Prefs.shared.certThresholdDays
        for r in records.values {
            guard let end = r.notAfter,
                  let fire = Calendar.current.date(byAdding: .day, value: -threshold, to: end) else {
                center.removePendingNotificationRequests(withIdentifiers: ["cert.\(r.host)"])
                continue
            }
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: fire)
            comps.hour = 10
            guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else {
                center.removePendingNotificationRequests(withIdentifiers: ["cert.\(r.host)"])
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = L.s("cert.reminder.title", r.host)
            content.body = L.s("cert.reminder.body", threshold, end.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: L.locale)))
            content.sound = .default
            content.threadIdentifier = "certs"
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "cert.\(r.host)", content: content, trigger: trigger))
        }
    }
}

/// TLS el sıkışmasında sunucu sertifikasını okur.
enum CertificateProbe {
    struct Result {
        var notAfter: Date?
        var notBefore: Date?
        var issuer: String?
        var fingerprint: String?
        var trusted: Bool
        var error: String?
    }

    private final class Capture: NSObject, URLSessionDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: SecTrust?
        var trust: SecTrust? { lock.lock(); defer { lock.unlock() }; return stored }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let t = challenge.protectionSpace.serverTrust {
                lock.lock(); stored = t; lock.unlock()
            }
            completionHandler(.performDefaultHandling, nil)
        }
    }

    static func fetch(host: String) async -> Result {
        guard let url = URL(string: "https://\(host)/") else { return Result(trusted: false, error: L.s("cert.error.address")) }
        let capture = Capture()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config, delegate: capture, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        req.httpMethod = "HEAD"
        req.setValue("UpSite-iOS/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        var requestError: Error?
        do { _ = try await session.data(for: req) } catch { requestError = error }

        guard let trust = capture.trust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return Result(trusted: false, error: describe(requestError))
        }
        var cfErr: CFError?
        let trusted = SecTrustEvaluateWithError(trust, &cfErr)
        let der = SecCertificateCopyData(leaf) as Data
        let validity = DERValidity.parse(der)
        let fp = SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined()
        let issuer = chain.count > 1 ? (SecCertificateCopySubjectSummary(chain[1]) as String?) : nil
        return Result(notAfter: validity?.notAfter, notBefore: validity?.notBefore, issuer: issuer, fingerprint: fp,
                      trusted: trusted, error: trusted ? nil : (cfErr.map { ($0 as Error).localizedDescription } ?? L.s("cert.error.untrusted")))
    }

    private static func describe(_ e: Error?) -> String {
        guard let e = e as? URLError else { return L.s("cert.error.read") }
        switch e.code {
        case .timedOut: return L.s("cert.error.timeout")
        case .cannotFindHost, .dnsLookupFailed: return L.s("cert.error.dns")
        case .notConnectedToInternet: return L.s("error.offline")
        default: return L.s("cert.error.read")
        }
    }
}

/// X.509 sertifikasından geçerlilik tarihlerini okuyan küçük DER ayrıştırıcı.
enum DERValidity {
    private struct TLV { let tag: UInt8; let start: Int; let length: Int }

    private static func read(_ b: [UInt8], _ i: inout Int) -> TLV? {
        guard i < b.count else { return nil }
        let tag = b[i]; i += 1
        guard i < b.count else { return nil }
        var len = Int(b[i]); i += 1
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n > 0, n <= 4, i + n <= b.count else { return nil }
            len = 0
            for _ in 0..<n { len = (len << 8) | Int(b[i]); i += 1 }
        }
        guard len >= 0, i + len <= b.count else { return nil }
        let tlv = TLV(tag: tag, start: i, length: len)
        i += len
        return tlv
    }

    static func parse(_ data: Data) -> (notBefore: Date, notAfter: Date)? {
        let b = [UInt8](data)
        var i = 0
        guard let cert = read(b, &i), cert.tag == 0x30 else { return nil }
        var j = cert.start
        guard let tbs = read(b, &j), tbs.tag == 0x30 else { return nil }
        var k = tbs.start
        var el = read(b, &k)
        if el?.tag == 0xA0 { el = read(b, &k) }
        guard el != nil, read(b, &k) != nil, read(b, &k) != nil,
              let validity = read(b, &k), validity.tag == 0x30 else { return nil }
        var v = validity.start
        guard let nb = read(b, &v), let na = read(b, &v), let d1 = time(b, nb), let d2 = time(b, na) else { return nil }
        return (d1, d2)
    }

    private static func time(_ b: [UInt8], _ t: TLV) -> Date? {
        let s = String(decoding: b[t.start..<(t.start + t.length)], as: UTF8.self)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        switch t.tag {
        case 0x17:
            f.dateFormat = "yyMMddHHmmss'Z'"
            f.twoDigitStartDate = Date(timeIntervalSince1970: -631_152_000)
        case 0x18:
            f.dateFormat = "yyyyMMddHHmmss'Z'"
        default:
            return nil
        }
        return f.date(from: s)
    }
}
