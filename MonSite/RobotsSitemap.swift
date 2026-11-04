import Foundation

/// robots.txt kuralları (Google'ın yorumladığı şekilde: en uzun eşleşen kural kazanır, * ve $ desteklenir).
struct RobotsRules: Sendable {
    var found = false
    var allow: [String] = []
    var disallow: [String] = []
    var sitemaps: [URL] = []

    var blocksEverything: Bool {
        disallow.contains("/") && !allow.contains(where: { $0 == "/" || $0 == "/*" })
    }

    static func parse(_ text: String, base: URL) -> RobotsRules {
        struct Group { var agents: [String] = []; var allow: [String] = []; var disallow: [String] = [] }
        var rules = RobotsRules()
        rules.found = true
        var groups: [Group] = []
        var current = Group()
        var lastWasAgent = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "user-agent":
                if !lastWasAgent && !current.agents.isEmpty {
                    groups.append(current)
                    current = Group()
                }
                current.agents.append(value.lowercased())
                lastWasAgent = true
            case "allow":
                current.allow.append(value)
                lastWasAgent = false
            case "disallow":
                if !value.isEmpty { current.disallow.append(value) }
                lastWasAgent = false
            case "sitemap":
                if let u = URL(string: value, relativeTo: base)?.absoluteURL { rules.sitemaps.append(u) }
            default:
                break
            }
        }
        if !current.agents.isEmpty { groups.append(current) }

        let chosen = groups.first { $0.agents.contains { $0.contains("monsite") } }
            ?? groups.first { $0.agents.contains("*") }
        rules.allow = chosen?.allow ?? []
        rules.disallow = chosen?.disallow ?? []
        return rules
    }

    func isAllowed(_ url: URL) -> Bool {
        guard found else { return true }
        var path = url.path.isEmpty ? "/" : url.path
        if let q = url.query { path += "?" + q }
        var best: (length: Int, allow: Bool)?
        for p in disallow where Self.matches(p, path) {
            if best == nil || p.count > best!.length { best = (p.count, false) }
        }
        for p in allow where !p.isEmpty && Self.matches(p, path) {
            if best == nil || p.count >= best!.length { best = (p.count, true) }
        }
        return best?.allow ?? true
    }

    private static func matches(_ pattern: String, _ path: String) -> Bool {
        if !pattern.contains("*") && !pattern.hasSuffix("$") { return path.hasPrefix(pattern) }
        var re = "^"
        for ch in pattern {
            switch ch {
            case "*": re += ".*"
            case "$": re += "$"
            default: re += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        return path.range(of: re, options: .regularExpression) != nil
    }
}

enum SitemapLoader {
    private static let locRE = try! NSRegularExpression(pattern: "<loc>\\s*([^<]+?)\\s*</loc>", options: [.caseInsensitive])

    struct Result: Sendable {
        var found = false
        var pageURLs: [URL] = []
        var sitemapCount = 0
        var brokenSitemaps: [String] = []
    }

    /// Sitemap'leri (sitemap index dahil, en fazla 6 dosya) okuyup sayfa adreslerini döndürür.
    static func load(_ candidates: [URL], declared: Bool, fetcher: HTTPFetcher, maxURLs: Int = 2000) async -> Result {
        var result = Result()
        var queue = candidates
        var visited = Set<String>()
        var pages: [URL] = []
        var seenPages = Set<String>()

        while !queue.isEmpty && result.sitemapCount < 6 && !Task.isCancelled {
            let url = queue.removeFirst()
            guard visited.insert(url.absoluteString).inserted else { continue }
            let r = await fetcher.fetchWithRetry(url)
            guard r.error == nil, let code = r.statusCode, code < 400, let data = r.data else {
                // Varsayılan /sitemap.xml yoksa bu bir hata değil; ama robots.txt'de bildirilen
                // veya sitemap index içinde listelenen bir dosya açılmıyorsa raporlanır.
                if declared || !candidates.contains(url) {
                    result.brokenSitemaps.append(url.absoluteString)
                }
                continue
            }
            let text = String(decoding: data, as: UTF8.self)
            guard text.range(of: "<urlset", options: .caseInsensitive) != nil
                    || text.range(of: "<sitemapindex", options: .caseInsensitive) != nil else { continue }
            result.found = true
            result.sitemapCount += 1
            let isIndex = text.range(of: "<sitemapindex", options: .caseInsensitive) != nil
            let ns = text as NSString
            for m in locRE.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = HTMLExtractor.decodeEntities(ns.substring(with: m.range(at: 1)))
                guard let u = URL(string: raw.trimmingCharacters(in: .whitespaces)) else { continue }
                if isIndex {
                    if !u.path.lowercased().hasSuffix(".gz") { queue.append(u) }
                } else if pages.count < maxURLs, seenPages.insert(u.visitKey).inserted {
                    pages.append(u.withoutFragment)
                }
            }
        }
        result.pageURLs = pages
        return result
    }
}
