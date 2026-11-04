import Foundation
import Security

/// TLS el sıkışmasında sunucunun sertifika zincirini yakalar.
private final class TrustCaptureDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: SecTrust?

    var trust: SecTrust? {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let t = challenge.protectionSpace.serverTrust {
            lock.lock(); captured = t; lock.unlock()
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

enum CertificateChecker {

    static func check(host: String, port: Int?, timeout: TimeInterval) async -> CertificateInfo {
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.port = port
        c.path = "/"
        guard let url = c.url else {
            return CertificateInfo(host: host, subject: nil, issuer: nil, chain: [], notBefore: nil, notAfter: nil,
                                   trusted: false, trustError: nil, fetchError: "Geçersiz adres")
        }

        let delegate = TrustCaptureDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "HEAD"
        req.setValue(HTTPFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        var fetchError: String?
        do { _ = try await session.data(for: req) } catch { fetchError = HTTPFetcher.describe(error) }

        guard let trust = delegate.trust else {
            return CertificateInfo(host: host, subject: nil, issuer: nil, chain: [], notBefore: nil, notAfter: nil,
                                   trusted: false, trustError: nil, fetchError: fetchError ?? "Sertifika alınamadı")
        }

        var cfError: CFError?
        let trusted = SecTrustEvaluateWithError(trust, &cfError)
        let trustError = cfError.map { ($0 as Error).localizedDescription }

        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        let names = chain.map { (SecCertificateCopySubjectSummary($0) as String?) ?? "?" }
        var notBefore: Date?
        var notAfter: Date?
        if let leaf = chain.first,
           let validity = DERValidity.parse(SecCertificateCopyData(leaf) as Data) {
            notBefore = validity.notBefore
            notAfter = validity.notAfter
        }

        var keyDescription: String?
        var keyBits: Int?
        var keyIsRSA: Bool?
        if let leaf = chain.first, let key = SecCertificateCopyKey(leaf),
           let attrs = SecKeyCopyAttributes(key) as? [String: Any] {
            keyBits = (attrs[kSecAttrKeySizeInBits as String] as? NSNumber)?.intValue
            let type = attrs[kSecAttrKeyType as String] as? String
            keyIsRSA = type == (kSecAttrKeyTypeRSA as String)
            let name = keyIsRSA == true ? "RSA" : (type == (kSecAttrKeyTypeECSECPrimeRandom as String) ? "ECDSA" : "Diğer")
            keyDescription = keyBits.map { "\(name) \($0) bit" } ?? name
        }

        var info = CertificateInfo(host: host,
                               subject: names.first,
                               issuer: names.count > 1 ? names[1] : nil,
                               chain: names,
                               notBefore: notBefore,
                               notAfter: notAfter,
                               trusted: trusted,
                               trustError: trusted ? nil : trustError,
                               fetchError: trusted ? nil : fetchError)
        info.keyDescription = keyDescription
        info.keyBits = keyBits
        info.keyIsRSA = keyIsRSA
        return info
    }

    static func issues(for cert: CertificateInfo) -> [Issue] {
        let u = "https://\(cert.host)/"
        var issues: [Issue] = []
        func add(_ s: Severity, _ t: String, _ d: String) {
            issues.append(Issue(severity: s, category: .certificate, title: t, detail: d, url: u))
        }
        if cert.chain.isEmpty {
            add(.critical, "SSL sertifikası okunamadı", cert.fetchError ?? "HTTPS bağlantısı kurulamadı")
            return issues
        }
        if !cert.trusted {
            add(.critical, "Sertifika güvenilir değil", cert.trustError ?? cert.fetchError ?? "Zincir doğrulanamadı")
        }
        let df = DateFormatter()
        df.dateStyle = .long
        df.locale = Locale(identifier: "tr_TR")
        if let days = cert.daysRemaining, let end = cert.notAfter {
            let endText = df.string(from: end)
            if days < 0 {
                add(.critical, "Sertifikanın süresi dolmuş", "\(endText) tarihinde sona erdi (\(-days) gün önce)")
            } else if days < 14 {
                add(.error, "Sertifika çok yakında sona eriyor", "\(days) gün kaldı — bitiş: \(endText)")
            } else if days < 30 {
                add(.warning, "Sertifika yakında sona eriyor", "\(days) gün kaldı — bitiş: \(endText)")
            } else {
                add(.info, "Sertifika geçerli", "\(days) gün kaldı — bitiş: \(endText)")
            }
        }
        if cert.keyIsRSA == true, let bits = cert.keyBits, bits < 2048 {
            add(.error, "Zayıf sertifika anahtarı", "RSA \(bits) bit; en az 2048 bit olmalı.")
        }
        if let start = cert.notBefore, let end = cert.notAfter,
           end.timeIntervalSince(start) > 398 * 86_400 {
            add(.info, "Sertifika süresi çok uzun", "Geçerlilik süresi 398 günü aşıyor; tarayıcılar bu sertifikaları reddedebilir.")
        }
        if let start = cert.notBefore, start > Date() {
            add(.critical, "Sertifika henüz geçerli değil", "Başlangıç: \(df.string(from: start))")
        }
        return issues
    }
}

/// X.509 sertifikasından geçerlilik tarihlerini okuyan küçük DER ayrıştırıcı.
/// (iOS'ta sertifika tarihleri için herkese açık bir API yoktur.)
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
        var el = read(b, &k)                       // [0] version veya serialNumber
        if el?.tag == 0xA0 { el = read(b, &k) }    // serialNumber
        guard el != nil,
              read(b, &k) != nil,                  // signature algorithm
              read(b, &k) != nil,                  // issuer
              let validity = read(b, &k), validity.tag == 0x30 else { return nil }
        var v = validity.start
        guard let nb = read(b, &v), let na = read(b, &v),
              let d1 = time(b, nb), let d2 = time(b, na) else { return nil }
        return (d1, d2)
    }

    private static func time(_ b: [UInt8], _ t: TLV) -> Date? {
        let s = String(decoding: b[t.start..<(t.start + t.length)], as: UTF8.self)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        switch t.tag {
        case 0x17: // UTCTime: YYMMDDHHMMSSZ
            f.dateFormat = "yyMMddHHmmss'Z'"
            f.twoDigitStartDate = Date(timeIntervalSince1970: -631_152_000) // 1950
        case 0x18: // GeneralizedTime: YYYYMMDDHHMMSSZ
            f.dateFormat = "yyyyMMddHHmmss'Z'"
        default:
            return nil
        }
        return f.date(from: s)
    }
}
