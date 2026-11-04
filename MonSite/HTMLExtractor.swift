import Foundation

struct FoundResource: Hashable, Sendable {
    let url: URL
    let kind: ResourceKind
}

struct ExtractedHTML: Sendable {
    var title: String?
    var links: [URL] = []
    var resources: [FoundResource] = []
    var formActions: [URL] = []
    var hasPasswordField = false
    var hasViewport = false
    var hasLang = false
    var hasClosingHTML = false
    var metaRobotsNoIndex = false
}

/// Bağımlılıksız, düzenli ifade tabanlı hafif HTML ayrıştırıcı.
/// JavaScript ile sonradan eklenen içerikleri göremez.
enum HTMLExtractor {
    private static let commentRE = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->")
    private static let tagRE = try! NSRegularExpression(
        pattern: "<(a|link|script|img|iframe|source|video|audio|track|embed|object|form|input|meta|html|base)\\b([^>]*)>",
        options: [.caseInsensitive])
    private static let attrRE = try! NSRegularExpression(
        pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))")
    private static let titleRE = try! NSRegularExpression(
        pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive])

    private static let documentExtensions: Set<String> = [
        "pdf", "zip", "rar", "7z", "gz", "tar", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "csv", "txt", "xml", "json", "dmg", "exe", "apk", "ipa", "mp3", "mp4", "mov", "avi",
        "webm", "wav", "ogg"
    ]
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "svg", "ico", "bmp", "avif", "heic"
    ]

    /// Bağlantı bir HTML sayfası değil de indirilebilir dosya ise türünü döndürür.
    static func fileKind(for url: URL) -> ResourceKind? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if documentExtensions.contains(ext) { return ["mp3", "mp4", "mov", "avi", "webm", "wav", "ogg"].contains(ext) ? .media : .document }
        if ext == "css" { return .stylesheet }
        if ext == "js" { return .script }
        return nil
    }

    static func extract(html raw: String, baseURL: URL) -> ExtractedHTML {
        var out = ExtractedHTML()
        out.hasClosingHTML = raw.range(of: "</html>", options: .caseInsensitive) != nil

        let html = commentRE.stringByReplacingMatches(
            in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)

        if let m = titleRE.firstMatch(in: html, range: full) {
            let t = decodeEntities(ns.substring(with: m.range(at: 1)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            out.title = t.isEmpty ? nil : t
        }

        var base = baseURL
        var seenLinks = Set<String>()
        var seenRes = Set<FoundResource>()

        func addLink(_ raw: String?) {
            guard let raw, let u = resolve(raw, base: base) else { return }
            if seenLinks.insert(u.absoluteString).inserted { out.links.append(u) }
        }
        func addRes(_ raw: String?, _ kind: ResourceKind) {
            guard let raw, let u = resolve(raw, base: base) else { return }
            let r = FoundResource(url: u, kind: kind)
            if seenRes.insert(r).inserted { out.resources.append(r) }
        }
        func addSrcset(_ raw: String?, _ kind: ResourceKind) {
            guard let raw else { return }
            for part in raw.split(separator: ",") {
                let candidate = part.trimmingCharacters(in: .whitespaces)
                    .split(separator: " ").first.map(String.init)
                addRes(candidate, kind)
            }
        }

        for m in tagRE.matches(in: html, range: full) {
            let tag = ns.substring(with: m.range(at: 1)).lowercased()
            let a = attributes(ns.substring(with: m.range(at: 2)))
            switch tag {
            case "base":
                if let h = a["href"], let u = resolve(h, base: baseURL) { base = u }
            case "html":
                if let l = a["lang"], !l.isEmpty { out.hasLang = true }
            case "meta":
                let name = a["name"]?.lowercased()
                if name == "viewport" { out.hasViewport = true }
                if name == "robots", a["content"]?.lowercased().contains("noindex") == true { out.metaRobotsNoIndex = true }
            case "a":
                addLink(a["href"])
            case "link":
                let rel = a["rel"]?.lowercased() ?? ""
                if rel.contains("stylesheet") { addRes(a["href"], .stylesheet) }
                else if rel.contains("icon") { addRes(a["href"], .image) }
                else if rel.contains("manifest") { addRes(a["href"], .other) }
                else if rel.contains("preload") || rel.contains("modulepreload") {
                    switch a["as"]?.lowercased() {
                    case "font": addRes(a["href"], .font)
                    case "style": addRes(a["href"], .stylesheet)
                    case "script": addRes(a["href"], .script)
                    case "image": addRes(a["href"], .image)
                    default: if rel.contains("modulepreload") { addRes(a["href"], .script) }
                    }
                }
            case "script":
                addRes(a["src"], .script)
            case "img":
                addRes(a["src"], .image)
                addSrcset(a["srcset"], .image)
            case "iframe":
                addRes(a["src"], .frame)
            case "source":
                addRes(a["src"], .media)
                addSrcset(a["srcset"], .image)
            case "video":
                addRes(a["src"], .media)
                addRes(a["poster"], .image)
            case "audio", "track", "embed":
                addRes(a["src"], .media)
            case "object":
                addRes(a["data"], .media)
            case "form":
                if let action = a["action"], let u = resolve(action, base: base) {
                    out.formActions.append(u)
                } else {
                    out.formActions.append(base)
                }
            case "input":
                if a["type"]?.lowercased() == "password" { out.hasPasswordField = true }
            default:
                break
            }
        }
        return out
    }

    private static func attributes(_ s: String) -> [String: String] {
        var dict: [String: String] = [:]
        let ns = s as NSString
        for m in attrRE.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            var value = ""
            for i in 2...4 where m.range(at: i).location != NSNotFound {
                value = ns.substring(with: m.range(at: i))
                break
            }
            if dict[name] == nil { dict[name] = value }
        }
        return dict
    }

    private static let encodeSet = CharacterSet.urlFragmentAllowed.union(CharacterSet(charactersIn: "#%"))

    static func resolve(_ raw: String, base: URL) -> URL? {
        let s = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let l = s.lowercased()
        for skip in ["#", "mailto:", "tel:", "javascript:", "data:", "sms:", "blob:", "about:", "whatsapp:", "geo:"]
            where l.hasPrefix(skip) { return nil }
        let url = URL(string: s, relativeTo: base)
            ?? s.addingPercentEncoding(withAllowedCharacters: encodeSet).flatMap { URL(string: $0, relativeTo: base) }
        guard let abs = url?.absoluteURL,
              let scheme = abs.scheme?.lowercased(), scheme == "http" || scheme == "https",
              abs.host != nil else { return nil }
        return abs.withoutFragment
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var r = s
        let named = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#x2F;": "/", "&#47;": "/"]
        for (k, v) in named { r = r.replacingOccurrences(of: k, with: v) }
        if r.contains("&#"),
           let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = r as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: r, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let isHex = ns.substring(with: m.range(at: 1)) == "x"
                let num = ns.substring(with: m.range(at: 2))
                if let v = UInt32(num, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(v) {
                    result.unicodeScalars.append(scalar)
                } else {
                    result += ns.substring(with: m.range)
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            r = result
        }
        return r
    }

    /// Content-Type'taki karakter kümesine göre gövdeyi çözer (Türkçe kodlamalar dahil).
    static func decodeBody(_ data: Data, contentType: String?) -> String {
        let ct = contentType?.lowercased() ?? ""
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        let hint = ct + " " + head
        if hint.contains("iso-8859-9") || hint.contains("windows-1254") {
            let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.isoLatin5.rawValue)))
            if let s = String(data: data, encoding: enc) { return s }
        }
        if hint.contains("iso-8859-1") || hint.contains("windows-1252"),
           let s = String(data: data, encoding: .windowsCP1252) { return s }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
