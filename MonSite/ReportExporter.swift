import Foundation

enum ReportExporter {

    static func text(_ r: ScanReport) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "tr_TR")
        df.dateStyle = .medium
        df.timeStyle = .short

        var s = "MonSite — Site denetim raporu\n"
        s += "Adres: \(r.startURL)\n"
        if r.finalURL != r.startURL { s += "Son adres: \(r.finalURL)\n" }
        s += "Tarih: \(df.string(from: r.startedAt)) · Süre: \(String(format: "%.1f", r.durationSec)) sn\n"
        if r.cancelled { s += "UYARI: Tarama iptal edildi, sonuçlar kısmi.\n" }
        s += "Taranan sayfa: \(r.pages.count) · Kontrol edilen kaynak: \(r.resources.count) · Bozuk kaynak: \(r.brokenResources.count)\n"
        s += "Kritik: \(r.count(.critical)) · Hata: \(r.count(.error)) · Uyarı: \(r.count(.warning)) · Bilgi: \(r.count(.info))\n"
        s += "Sağlık puanı: \(r.score)/100 (\(r.grade)) — \(r.verdict)\n"
        s += "Ortalama sayfa süresi: \(formatMs(r.averagePageMs))\n"

        s += "\n== SSL SERTİFİKASI ==\n"
        if let c = r.certificate {
            s += "Güvenilir: \(c.trusted ? "Evet" : "Hayır")\(c.trustError.map { " (\($0))" } ?? "")\n"
            if let v = c.subject { s += "Sahibi: \(v)\n" }
            if let v = c.issuer { s += "Veren: \(v)\n" }
            if let v = c.notBefore { s += "Başlangıç: \(df.string(from: v))\n" }
            if let v = c.notAfter { s += "Bitiş: \(df.string(from: v))\n" }
            if let d = c.daysRemaining { s += "Kalan gün: \(d)\n" }
            if c.chain.isEmpty, let e = c.fetchError { s += "Hata: \(e)\n" }
        } else {
            s += "Kontrol edilmedi\n"
        }

        s += "\n== SORUNLAR (\(r.issues.count)) ==\n"
        for i in r.issues {
            s += "[\(i.severity.title.uppercased(with: Locale(identifier: "tr_TR")))] [\(i.category.title)] \(i.title)"
            if !i.detail.isEmpty { s += " — \(i.detail)" }
            s += "\n    \(i.url)\n"
        }

        s += "\n== EN YAVAŞ SAYFALAR ==\n"
        for p in r.slowestPages.prefix(10) {
            s += "\(formatMs(p.durationMs).padding(toLength: 10, withPad: " ", startingAt: 0)) \(p.url)\n"
        }

        s += "\n== EN YAVAŞ PARÇALAR ==\n"
        for x in r.slowestResources.prefix(15) {
            s += "\(formatMs(x.durationMs).padding(toLength: 10, withPad: " ", startingAt: 0)) [\(x.kind.title)] \(x.url)\n"
        }

        if !r.brokenResources.isEmpty {
            s += "\n== BOZUK KAYNAKLAR ==\n"
            for x in r.brokenResources {
                let why: String
                if let e = x.error { why = e }
                else if let c = x.statusCode, c >= 400 { why = "HTTP \(c)" }
                else if x.corrupt { why = "bozuk dosya" }
                else { why = "\(x.kind.title) yerine HTML döndü" }
                s += "[\(x.kind.title)] \(why) — \(x.url)\n"
                for p in x.foundOn.prefix(3) { s += "    sayfa: \(p)\n" }
            }
        }

        s += "\n== SAYFALAR ==\n"
        for p in r.pages {
            let code = p.error != nil ? "ERR" : p.statusCode.map { "\($0)" } ?? "—"
            s += "\(code)  \(formatMs(p.durationMs).padding(toLength: 10, withPad: " ", startingAt: 0)) \(p.url)\n"
        }
        return s
    }

    static func jsonFile(_ r: ScanReport) -> URL? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(r) else { return nil }
        let name = "monsite-\(r.host)-\(Int(r.startedAt.timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
