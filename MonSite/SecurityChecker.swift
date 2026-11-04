import Foundation

enum SecurityChecker {

    // MARK: Güvenlik başlıkları ve çerezler

    static func headerIssues(response: HTTPURLResponse, url: URL) -> [Issue] {
        var issues: [Issue] = []
        let u = url.absoluteString
        func add(_ s: Severity, _ t: String, _ d: String) {
            issues.append(Issue(severity: s, category: .security, title: t, detail: d, url: u))
        }
        func h(_ name: String) -> String? { response.value(forHTTPHeaderField: name) }
        let https = url.scheme == "https"

        if https && h("Strict-Transport-Security") == nil {
            add(.warning, "HSTS başlığı yok", "Strict-Transport-Security, tarayıcıyı her zaman HTTPS kullanmaya zorlar.")
        }
        let csp = h("Content-Security-Policy")
        if csp == nil {
            add(.warning, "Content-Security-Policy (CSP) yok", "XSS saldırılarına karşı önemli bir savunma katmanı eksik.")
        }
        if h("X-Frame-Options") == nil && !(csp?.lowercased().contains("frame-ancestors") ?? false) {
            add(.warning, "Clickjacking koruması yok", "X-Frame-Options veya CSP frame-ancestors tanımlı değil; site başka sitelere gömülebilir.")
        }
        if h("X-Content-Type-Options")?.lowercased() != "nosniff" {
            add(.info, "X-Content-Type-Options: nosniff yok", "Tarayıcının MIME türü tahmin etmesi engellenmiyor.")
        }
        if h("Referrer-Policy") == nil {
            add(.info, "Referrer-Policy yok", "Dış sitelere gönderilen yönlendiren (referrer) bilgisi sınırlanmamış.")
        }
        if let server = h("Server"), server.rangeOfCharacter(from: .decimalDigits) != nil {
            add(.info, "Sunucu sürüm bilgisi açık", "Server: \(server) — saldırganlara hangi yamaların eksik olduğunu gösterebilir.")
        }
        if let p = h("X-Powered-By") {
            add(.info, "Teknoloji bilgisi açık", "X-Powered-By: \(p)")
        }
        if let v = h("X-AspNet-Version") {
            add(.info, "ASP.NET sürümü açık", "X-AspNet-Version: \(v)")
        }
        if h("Access-Control-Allow-Origin") == "*" {
            add(.info, "CORS herkese açık", "Access-Control-Allow-Origin: * — her site bu yanıtları okuyabilir.")
        }

        var fields: [String: String] = [:]
        for (k, v) in response.allHeaderFields {
            if let k = k as? String, let v = v as? String { fields[k] = v }
        }
        for c in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            var missing: [String] = []
            if https && !c.isSecure { missing.append("Secure") }
            if !c.isHTTPOnly { missing.append("HttpOnly") }
            if c.sameSitePolicy == nil { missing.append("SameSite") }
            if !missing.isEmpty {
                add(.warning, "Çerez güvenlik bayrakları eksik: \(c.name)", "Eksik: " + missing.joined(separator: ", "))
            }
        }
        return issues
    }

    // MARK: HTTP ↔ HTTPS

    static func schemeIssues(finalURL: URL, fetcher: HTTPFetcher) async -> [Issue] {
        guard let host = finalURL.host else { return [] }
        var issues: [Issue] = []
        func add(_ s: Severity, _ t: String, _ d: String, _ u: String) {
            issues.append(Issue(severity: s, category: .security, title: t, detail: d, url: u))
        }
        var c = URLComponents()
        c.host = host
        if finalURL.scheme == "http" {
            c.scheme = "https"
            guard let httpsURL = c.url else { return [] }
            let r = await fetcher.fetchPrefix(httpsURL, maxBytes: 1024)
            if r.error == nil, (r.statusCode ?? 999) < 400 {
                add(.error, "HTTP'den HTTPS'e yönlendirme yok",
                    "Site HTTPS destekliyor ama ziyaretçiler şifresiz HTTP sürümünde kalıyor.", finalURL.absoluteString)
            } else {
                add(.critical, "Site HTTPS kullanmıyor",
                    "Tüm trafik şifresiz iletiliyor. \(r.error ?? "")", finalURL.absoluteString)
            }
        } else {
            c.scheme = "http"
            guard let httpURL = c.url else { return [] }
            let r = await fetcher.fetchPrefix(httpURL, maxBytes: 1024)
            if r.error == nil, r.finalURL?.scheme == "http", (r.statusCode ?? 999) < 400 {
                add(.warning, "HTTP sürümü HTTPS'e yönlendirmiyor",
                    "\(httpURL.absoluteString) adresi şifresiz olarak açılıyor.", httpURL.absoluteString)
            }
        }
        return issues
    }

    // MARK: Herkese açık hassas dosyalar

    struct Probe: @unchecked Sendable {
        let path: String
        let severity: Severity
        let title: String
        let detail: String
        let test: (Data, String) -> Bool
    }

    static func looksHTML(_ s: String) -> Bool {
        let l = s.prefix(1024).lowercased()
        return l.contains("<html") || l.contains("<!doctype") || l.contains("<head") || l.contains("<body")
    }

    static func matches(_ pattern: String, _ s: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static let probes: [Probe] = {
        var p: [Probe] = [
            Probe(path: "/.git/HEAD", severity: .critical, title: "Git deposu herkese açık",
                  detail: "Sitenin kaynak kodu ve geçmişi indirilebilir.") { _, s in
                s.hasPrefix("ref: refs/") || SecurityChecker.matches("^[0-9a-f]{40}\\s*$", s)
            },
            Probe(path: "/.git/config", severity: .critical, title: "Git yapılandırması açık",
                  detail: "Depo adresi ve olası erişim bilgileri görünüyor.") { _, s in
                s.contains("[core]") && !SecurityChecker.looksHTML(s)
            },
            Probe(path: "/.env", severity: .critical, title: ".env dosyası erişilebilir",
                  detail: "Veritabanı şifreleri ve API anahtarları sızabilir.") { _, s in
                !SecurityChecker.looksHTML(s) && SecurityChecker.matches("^\\s*[A-Z][A-Z0-9_]*\\s*=", s)
            },
            Probe(path: "/.DS_Store", severity: .warning, title: ".DS_Store dosyası açık",
                  detail: "Sunucudaki dosya/klasör adları ortaya çıkıyor.") { d, _ in
                d.count > 8 && Array(Array(d.prefix(8)).suffix(4)) == Array("Bud1".utf8)
            },
            Probe(path: "/.htpasswd", severity: .critical, title: ".htpasswd dosyası açık",
                  detail: "Kullanıcı adları ve parola özetleri indirilebilir.") { _, s in
                !SecurityChecker.looksHTML(s) && SecurityChecker.matches("^[^:\\s<]+:\\S+$", s)
            },
            Probe(path: "/phpinfo.php", severity: .warning, title: "phpinfo sayfası açık",
                  detail: "Sunucu yapılandırmasının tamamı görünüyor.") { _, s in
                s.contains("PHP Version") && s.contains("phpinfo")
            },
            Probe(path: "/info.php", severity: .warning, title: "phpinfo sayfası açık (info.php)",
                  detail: "Sunucu yapılandırmasının tamamı görünüyor.") { _, s in
                s.contains("PHP Version") && s.contains("phpinfo")
            },
            Probe(path: "/server-status", severity: .warning, title: "Apache server-status açık",
                  detail: "Anlık istekler ve ziyaretçi IP'leri görünebilir.") { _, s in
                s.contains("Apache Server Status")
            },
            Probe(path: "/.vscode/sftp.json", severity: .critical, title: "SFTP yapılandırması açık",
                  detail: "Sunucu erişim bilgileri sızabilir.") { _, s in
                !SecurityChecker.looksHTML(s) && s.contains("\"host\"")
            },
            Probe(path: "/wp-json/wp/v2/users", severity: .warning, title: "WordPress kullanıcıları listelenebiliyor",
                  detail: "Yönetici kullanıcı adları kaba kuvvet saldırısını kolaylaştırır.") { _, s in
                s.hasPrefix("[") && s.contains("\"slug\"")
            }
        ]
        for path in ["/wp-config.php.bak", "/wp-config.php~", "/wp-config.old", "/config.php.bak", "/configuration.php.bak"] {
            p.append(Probe(path: path, severity: .critical, title: "Yapılandırma yedeği açık (\(path))",
                           detail: "PHP kaynak kodu ve veritabanı şifresi okunabilir.") { _, s in s.contains("<?php") })
        }
        for path in ["/backup.sql", "/dump.sql", "/db.sql", "/database.sql"] {
            p.append(Probe(path: path, severity: .critical, title: "Veritabanı yedeği açık (\(path))",
                           detail: "Tüm veritabanı indirilebilir.") { _, s in
                !SecurityChecker.looksHTML(s) && (s.contains("CREATE TABLE") || s.contains("INSERT INTO"))
            })
        }
        for path in ["/backup.zip", "/site.zip", "/www.zip", "/backup.tar.gz"] {
            p.append(Probe(path: path, severity: .critical, title: "Site yedeği açık (\(path))",
                           detail: "Sitenin tüm dosyaları indirilebilir.") { d, _ in
                let b = Array(d.prefix(4))
                return b == [0x50, 0x4B, 0x03, 0x04] || Array(b.prefix(2)) == [0x1F, 0x8B]
            })
        }
        for path in ["/uploads/", "/images/", "/files/", "/backup/", "/wp-content/uploads/"] {
            p.append(Probe(path: path, severity: .warning, title: "Dizin listeleme açık (\(path))",
                           detail: "Klasördeki tüm dosyalar listeleniyor.") { _, s in
                s.range(of: "<title>Index of", options: .caseInsensitive) != nil
            })
        }
        return p
    }()

    static func probeSensitivePaths(root: URL, fetcher: HTTPFetcher,
                                    onEach: (Int, Int) async -> Void) async -> [Issue] {
        let list = probes
        let found: [Issue?] = await concurrentMap(list, limit: 4, { probe in
            guard let url = URL(string: probe.path, relativeTo: root)?.absoluteURL else { return nil }
            let r = await fetcher.fetchPrefix(url, maxBytes: 16_384)
            guard r.error == nil, let code = r.statusCode, code == 200 || code == 206,
                  let data = r.data, !data.isEmpty else { return nil }
            // Yönlendirme sonrası farklı bir sayfaya düşüldüyse yok say (ör. ana sayfaya yönlendirme).
            if let f = r.finalURL, f.path != url.path { return nil }
            let text = String(decoding: data, as: UTF8.self)
            guard probe.test(data, text) else { return nil }
            return Issue(severity: probe.severity, category: .security, title: probe.title,
                         detail: probe.detail, url: url.absoluteString)
        }, onEach: { done, _ in await onEach(done, list.count) })
        return found.compactMap { $0 }
    }
}
