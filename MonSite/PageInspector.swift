import Foundation

/// Bir HTML sayfasından erişilebilirlik, SEO ve performans kontrolleri için toplanan bilgiler.
struct PageFacts: Sendable {
    var title: String?
    var metaDescription: String?
    var canonical: URL?
    var noIndex = false
    var hasOGTitle = false
    var hasOGImage = false
    var viewport: String?
    var hasLang = false
    var metaRefresh: String?

    var headings: [(level: Int, text: String)] = []
    var imagesTotal = 0
    var imagesWithoutAlt: [String] = []
    var imagesWithoutSize = 0
    var linksWithoutName: [String] = []
    var genericLinks: [String] = []
    var buttonsWithoutName = 0
    var unlabeledFields: [String] = []
    var iframesWithoutTitle = 0
    var duplicateIDs: [String] = []
    var positiveTabindex = 0
    var autoplayMedia = 0
    var brokenFragments: [String] = []
    var blockingHeadScripts = 0
    var externalScriptsWithoutSRI: [String] = []
    var wordCount = 0
}

enum PageInspector {
    private static func re(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }

    private static let commentRE = re("<!--[\\s\\S]*?-->")
    private static let scriptBlockRE = re("<script\\b[^>]*>[\\s\\S]*?</script>")
    private static let styleBlockRE = re("<style\\b[^>]*>[\\s\\S]*?</style>")
    private static let tagRE = re("<[^>]+>")
    private static let headRE = re("<head\\b[^>]*>([\\s\\S]*?)</head>")
    private static let titleRE = re("<title[^>]*>([\\s\\S]*?)</title>")
    private static let htmlTagRE = re("<html\\b([^>]*)>")
    private static let metaRE = re("<meta\\b([^>]*)>")
    private static let linkTagRE = re("<link\\b([^>]*)>")
    private static let imgRE = re("<img\\b([^>]*)>")
    private static let anchorRE = re("<a\\b([^>]*)>([\\s\\S]*?)</a>")
    private static let buttonRE = re("<button\\b([^>]*)>([\\s\\S]*?)</button>")
    private static let fieldRE = re("<(input|select|textarea)\\b([^>]*)>")
    private static let labelRE = re("<label\\b([^>]*)>([\\s\\S]*?)</label>")
    private static let iframeRE = re("<iframe\\b([^>]*)>")
    private static let mediaRE = re("<(video|audio)\\b([^>]*)>")
    private static let headingRE = re("<h([1-6])\\b[^>]*>([\\s\\S]*?)</h\\1\\s*>")
    private static let idRE = re("<[a-z][a-z0-9-]*\\b[^>]*?\\sid\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")
    private static let nameAnchorRE = re("<a\\b[^>]*?\\sname\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")
    private static let tabindexRE = re("\\stabindex\\s*=\\s*[\"']?(\\d+)")
    private static let scriptTagRE = re("<script\\b([^>]*)>")
    private static let altInsideRE = re("<img\\b[^>]*\\salt\\s*=\\s*(?:\"([^\"]+)\"|'([^']+)')")
    private static let svgTitleRE = re("<svg\\b[\\s\\S]*?<title[^>]*>\\s*\\S[\\s\\S]*?</title>")

    private static let genericTexts: Set<String> = [
        "tıklayın", "buraya tıklayın", "tıkla", "buraya", "devamı", "devamını oku", "daha fazla",
        "detay", "detaylar", "incele", "click here", "here", "read more", "more", "link", "learn more"
    ]

    static func text(_ s: String) -> String {
        let noTags = tagRE.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        return HTMLExtractor.decodeEntities(noTags)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func sub(_ ns: NSString, _ m: NSTextCheckingResult, _ i: Int) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : ns.substring(with: r)
    }

    private static func nonEmpty(_ s: String?) -> Bool {
        !(s?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func inspect(html raw: String, url: URL) -> PageFacts {
        var f = PageFacts()
        let noComments = commentRE.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        // Script ve style içerikleri metin/etiket kontrollerine karışmasın.
        var html = scriptBlockRE.stringByReplacingMatches(in: noComments, range: NSRange(noComments.startIndex..., in: noComments), withTemplate: "<script></script>")
        html = styleBlockRE.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)
        let attrs = HTMLExtractor.attributes

        if let m = titleRE.firstMatch(in: html, range: full) {
            let t = text(sub(ns, m, 1))
            f.title = t.isEmpty ? nil : t
        }
        if let m = htmlTagRE.firstMatch(in: html, range: full) {
            f.hasLang = nonEmpty(attrs(sub(ns, m, 1))["lang"])
        }

        for m in metaRE.matches(in: html, range: full) {
            let a = attrs(sub(ns, m, 1))
            let name = a["name"]?.lowercased()
            let prop = a["property"]?.lowercased()
            let content = HTMLExtractor.decodeEntities(a["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "description": f.metaDescription = content
            case "viewport": f.viewport = content
            case "robots": if content.lowercased().contains("noindex") { f.noIndex = true }
            default: break
            }
            if prop == "og:title", !content.isEmpty { f.hasOGTitle = true }
            if prop == "og:image", !content.isEmpty { f.hasOGImage = true }
            if a["http-equiv"]?.lowercased() == "refresh" { f.metaRefresh = content }
        }
        for m in linkTagRE.matches(in: html, range: full) {
            let a = attrs(sub(ns, m, 1))
            if a["rel"]?.lowercased().split(separator: " ").contains("canonical") == true, let h = a["href"] {
                f.canonical = HTMLExtractor.resolve(h, base: url)
            }
        }

        // Görseller
        for m in imgRE.matches(in: html, range: full) {
            let a = attrs(sub(ns, m, 1))
            f.imagesTotal += 1
            let hidden = a["aria-hidden"]?.lowercased() == "true" || ["presentation", "none"].contains(a["role"]?.lowercased() ?? "")
            if a["alt"] == nil && !hidden && !nonEmpty(a["aria-label"]) && !nonEmpty(a["aria-labelledby"]) {
                f.imagesWithoutAlt.append(a["src"] ?? a["data-src"] ?? "img")
            }
            if a["width"] == nil || a["height"] == nil { f.imagesWithoutSize += 1 }
        }

        // id'ler (yinelenenler ve #bağlantı hedefleri için)
        var idCounts: [String: Int] = [:]
        for m in idRE.matches(in: html, range: full) {
            let v = sub(ns, m, 1).isEmpty ? sub(ns, m, 2) : sub(ns, m, 1)
            if !v.isEmpty { idCounts[v, default: 0] += 1 }
        }
        f.duplicateIDs = idCounts.filter { $0.value > 1 }.map(\.key).sorted()
        var targets = Set(idCounts.keys)
        for m in nameAnchorRE.matches(in: html, range: full) {
            let v = sub(ns, m, 1).isEmpty ? sub(ns, m, 2) : sub(ns, m, 1)
            if !v.isEmpty { targets.insert(v) }
        }

        func accessibleName(attrs a: [String: String], inner: String) -> Bool {
            if nonEmpty(a["aria-label"]) || nonEmpty(a["aria-labelledby"]) || nonEmpty(a["title"]) { return true }
            if !text(inner).isEmpty { return true }
            let ins = inner as NSString
            let r = NSRange(location: 0, length: ins.length)
            return altInsideRE.firstMatch(in: inner, range: r) != nil || svgTitleRE.firstMatch(in: inner, range: r) != nil
        }

        // Bağlantılar
        var fragmentSet = Set<String>()
        for m in anchorRE.matches(in: html, range: full) {
            let a = attrs(sub(ns, m, 1))
            guard let href = a["href"] else { continue }
            let inner = sub(ns, m, 2)
            if a["aria-hidden"]?.lowercased() != "true" && !accessibleName(attrs: a, inner: inner) {
                f.linksWithoutName.append(href)
            }
            let t = text(inner).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .…»›>"))
            if genericTexts.contains(t) { f.genericLinks.append(t) }
            let h = href.trimmingCharacters(in: .whitespaces)
            if h.hasPrefix("#"), h.count > 1, !h.hasPrefix("#!"), !h.hasPrefix("#/") {
                let frag = String(h.dropFirst()).removingPercentEncoding ?? String(h.dropFirst())
                if frag.lowercased() != "top", !targets.contains(frag), fragmentSet.insert(frag).inserted {
                    f.brokenFragments.append(h)
                }
            }
        }

        // Düğmeler
        for m in buttonRE.matches(in: html, range: full) {
            let a = attrs(sub(ns, m, 1))
            if !accessibleName(attrs: a, inner: sub(ns, m, 2)) { f.buttonsWithoutName += 1 }
        }

        // Form alanları ve etiketler
        var labelFor = Set<String>()
        var labelRanges: [NSRange] = []
        for m in labelRE.matches(in: html, range: full) {
            if let id = attrs(sub(ns, m, 1))["for"], !id.isEmpty { labelFor.insert(id) }
            labelRanges.append(m.range)
        }
        for m in fieldRE.matches(in: html, range: full) {
            let tag = sub(ns, m, 1).lowercased()
            let a = attrs(sub(ns, m, 2))
            let type = a["type"]?.lowercased() ?? "text"
            if tag == "input" {
                if ["hidden", "submit", "button", "reset"].contains(type) { continue }
                if type == "image" {
                    if !nonEmpty(a["alt"]) && !nonEmpty(a["aria-label"]) { f.unlabeledFields.append("image") }
                    continue
                }
            }
            if a["aria-hidden"]?.lowercased() == "true" { continue }
            let labeled = nonEmpty(a["aria-label"]) || nonEmpty(a["aria-labelledby"]) || nonEmpty(a["title"])
                || (a["id"].map { labelFor.contains($0) } ?? false)
                || labelRanges.contains { NSLocationInRange(m.range.location, $0) }
            if !labeled { f.unlabeledFields.append(a["name"] ?? a["id"] ?? tag) }
        }

        for m in iframeRE.matches(in: html, range: full) {
            let a = attrs(sub(ns, m, 1))
            if !nonEmpty(a["title"]) && !nonEmpty(a["aria-label"]) && a["aria-hidden"]?.lowercased() != "true" {
                f.iframesWithoutTitle += 1
            }
        }
        for m in mediaRE.matches(in: html, range: full) {
            let a = attrs(sub(ns, m, 2))
            if a["autoplay"] != nil && a["muted"] == nil { f.autoplayMedia += 1 }
        }
        for m in tabindexRE.matches(in: html, range: full) {
            if let v = Int(sub(ns, m, 1)), v > 0 { f.positiveTabindex += 1 }
        }
        for m in headingRE.matches(in: html, range: full) {
            f.headings.append((Int(sub(ns, m, 1)) ?? 1, text(sub(ns, m, 2))))
        }

        // Script'ler: orijinal (yorumsuz) HTML üzerinde, çünkü yukarıda içerikleri silindi.
        let sns = noComments as NSString
        let sfull = NSRange(location: 0, length: sns.length)
        if let head = headRE.firstMatch(in: noComments, range: sfull) {
            let headHTML = sub(sns, head, 1)
            let hns = headHTML as NSString
            for m in scriptTagRE.matches(in: headHTML, range: NSRange(location: 0, length: hns.length)) {
                let a = attrs(sub(hns, m, 1))
                let type = a["type"]?.lowercased() ?? ""
                if a["src"] != nil && a["async"] == nil && a["defer"] == nil && type != "module" {
                    f.blockingHeadScripts += 1
                }
            }
        }
        let host = url.siteHost
        for m in scriptTagRE.matches(in: noComments, range: sfull) {
            let a = attrs(sub(sns, m, 1))
            if let src = a["src"], let u = HTMLExtractor.resolve(src, base: url), u.siteHost != host, a["integrity"] == nil {
                f.externalScriptsWithoutSRI.append(u.host ?? u.absoluteString)
            }
        }

        if let bodyStart = html.range(of: "<body", options: .caseInsensitive) {
            f.wordCount = text(String(html[bodyStart.lowerBound...])).split(separator: " ").count
        } else {
            f.wordCount = text(html).split(separator: " ").count
        }
        return f
    }

    // MARK: - Kurallar

    static func issues(_ f: PageFacts, url: URL, isHome: Bool, xRobotsTag: String?) -> [Issue] {
        var issues: [Issue] = []
        let u = url.absoluteString
        func add(_ s: Severity, _ c: IssueCategory, _ t: String, _ d: String) {
            issues.append(Issue(severity: s, category: c, title: t, detail: d, url: u))
        }
        func examples(_ list: [String]) -> String {
            let uniq = Array(NSOrderedSet(array: list)) as? [String] ?? list
            let shown = uniq.prefix(3).map { shortURL($0) }.joined(separator: ", ")
            return uniq.count > 3 ? "\(shown) …" : shown
        }

        // Erişilebilirlik (WCAG 2.2 A/AA alt kümesi)
        if !f.imagesWithoutAlt.isEmpty {
            add(.error, .accessibility, "Alt metni olmayan görseller",
                "\(f.imagesWithoutAlt.count)/\(f.imagesTotal) görselde alt özniteliği yok (WCAG 1.1.1): \(examples(f.imagesWithoutAlt))")
        }
        if !f.linksWithoutName.isEmpty {
            add(.error, .accessibility, "Metni olmayan bağlantılar",
                "\(f.linksWithoutName.count) bağlantının ekran okuyucuya okunacak adı yok (WCAG 2.4.4): \(examples(f.linksWithoutName))")
        }
        if f.buttonsWithoutName > 0 {
            add(.error, .accessibility, "Adı olmayan düğmeler", "\(f.buttonsWithoutName) düğmede metin veya aria-label yok (WCAG 4.1.2)")
        }
        if !f.unlabeledFields.isEmpty {
            add(.error, .accessibility, "Etiketi olmayan form alanları",
                "\(f.unlabeledFields.count) alan bir <label> veya aria-label ile ilişkilendirilmemiş (WCAG 1.3.1, 3.3.2): \(examples(f.unlabeledFields))")
        }
        if !f.hasLang {
            add(.warning, .accessibility, "Sayfa dili belirtilmemiş", "<html lang=\"tr\"> gibi bir dil özniteliği yok (WCAG 3.1.1)")
        }
        if let vp = f.viewport?.lowercased().replacingOccurrences(of: " ", with: "") {
            let noScale = vp.contains("user-scalable=no") || vp.contains("user-scalable=0")
            var maxScaleLow = false
            if let r = vp.range(of: "maximum-scale=") {
                let num = vp[r.upperBound...].prefix { "0123456789.".contains($0) }
                if let v = Double(num), v < 2 { maxScaleLow = true }
            }
            if noScale || maxScaleLow {
                add(.error, .accessibility, "Yakınlaştırma engellenmiş", "Viewport ayarı kullanıcının yakınlaştırmasını engelliyor (WCAG 1.4.4)")
            }
        }
        if f.iframesWithoutTitle > 0 {
            add(.warning, .accessibility, "Başlığı olmayan iframe'ler", "\(f.iframesWithoutTitle) iframe'de title özniteliği yok (WCAG 4.1.2)")
        }
        let levels = f.headings.map(\.level)
        if !levels.contains(1) {
            add(.warning, .accessibility, "Sayfada h1 başlığı yok", "Ana başlık (h1) sayfa yapısını ve SEO'yu güçlendirir (WCAG 1.3.1)")
        } else if levels.filter({ $0 == 1 }).count > 1 {
            add(.info, .accessibility, "Birden fazla h1 başlığı", "\(levels.filter { $0 == 1 }.count) adet h1 var")
        }
        if let jump = zip(levels, levels.dropFirst()).first(where: { $1 > $0 + 1 }) {
            add(.warning, .accessibility, "Başlık seviyesi atlanıyor", "h\(jump.0) sonrasında h\(jump.1) geliyor (WCAG 1.3.1)")
        }
        let emptyHeadings = f.headings.filter { $0.text.isEmpty }.count
        if emptyHeadings > 0 {
            add(.warning, .accessibility, "Boş başlıklar", "\(emptyHeadings) başlık etiketinin içi boş")
        }
        if !f.duplicateIDs.isEmpty {
            add(.warning, .accessibility, "Yinelenen id değerleri",
                "\(f.duplicateIDs.count) id birden fazla kullanılıyor; etiket ve ARIA ilişkileri bozulabilir: \(f.duplicateIDs.prefix(3).joined(separator: ", "))")
        }
        if f.positiveTabindex > 0 {
            add(.warning, .accessibility, "Pozitif tabindex kullanımı", "\(f.positiveTabindex) öğe klavye gezinme sırasını değiştiriyor (WCAG 2.4.3)")
        }
        if f.autoplayMedia > 0 {
            add(.warning, .accessibility, "Sesli otomatik oynatılan medya", "\(f.autoplayMedia) video/ses sessize alınmadan otomatik oynuyor (WCAG 1.4.2)")
        }
        if let r = f.metaRefresh, !r.isEmpty {
            add(.warning, .accessibility, "Otomatik sayfa yenileme/yönlendirme", "meta refresh: \(r) (WCAG 2.2.1)")
        }
        if !f.genericLinks.isEmpty {
            add(.info, .accessibility, "Anlamsız bağlantı metinleri",
                "\(f.genericLinks.count) bağlantı “\(Array(Set(f.genericLinks)).prefix(3).joined(separator: "”, “"))” gibi bağlamdan bağımsız metin kullanıyor (WCAG 2.4.4)")
        }
        if !f.brokenFragments.isEmpty {
            add(.warning, .content, "Hedefi olmayan sayfa içi bağlantılar",
                "\(f.brokenFragments.count) #bağlantının hedefi sayfada yok: \(f.brokenFragments.prefix(3).joined(separator: ", "))")
        }

        // SEO
        if f.title == nil {
            add(.error, .seo, "Sayfa başlığı yok", "<title> etiketi eksik veya boş")
        } else if let t = f.title {
            if t.count > 65 { add(.info, .seo, "Sayfa başlığı uzun", "\(t.count) karakter; arama sonuçlarında kesilebilir (öneri ≤ 60)") }
            else if t.count < 10 { add(.info, .seo, "Sayfa başlığı çok kısa", "“\(t)”") }
        }
        if let d = f.metaDescription, !d.isEmpty {
            if d.count > 170 { add(.info, .seo, "Meta açıklama uzun", "\(d.count) karakter (öneri 70–160)") }
            else if d.count < 50 { add(.info, .seo, "Meta açıklama kısa", "\(d.count) karakter (öneri 70–160)") }
        } else {
            add(.warning, .seo, "Meta açıklama yok", "Arama sonuçlarındaki açıklama metni tanımlanmamış")
        }
        let xNoIndex = xRobotsTag?.lowercased().contains("noindex") ?? false
        if f.noIndex || xNoIndex {
            add(isHome ? .error : .info, .seo, "Sayfa arama motorlarından gizlenmiş (noindex)",
                xNoIndex ? "X-Robots-Tag başlığı: \(xRobotsTag ?? "")" : "<meta name=\"robots\" content=\"noindex\">")
        }
        if let c = f.canonical {
            if c.siteHost != url.siteHost {
                add(.warning, .seo, "Canonical başka bir alan adını gösteriyor", c.absoluteString)
            }
        } else {
            add(.info, .seo, "Canonical etiketi yok", "<link rel=\"canonical\"> yinelenen içerik sorunlarını önler")
        }
        if f.viewport == nil {
            add(.warning, .seo, "Mobil viewport etiketi yok", "<meta name=\"viewport\"> eksik; sayfa mobilde küçük görünür")
        }
        if !f.hasOGTitle || !f.hasOGImage {
            add(.info, .seo, "Sosyal medya önizleme etiketleri eksik",
                "Eksik: " + [f.hasOGTitle ? nil : "og:title", f.hasOGImage ? nil : "og:image"].compactMap { $0 }.joined(separator: ", "))
        }
        if f.wordCount < 50 && !isHome {
            add(.info, .seo, "Sayfada çok az metin var", "\(f.wordCount) kelime")
        }

        // Performans
        if f.blockingHeadScripts > 0 {
            add(.info, .performance, "Oluşturmayı engelleyen script'ler", "<head> içinde async/defer olmadan \(f.blockingHeadScripts) script yükleniyor")
        }
        if f.imagesWithoutSize > 0 && f.imagesTotal > 0 {
            add(.info, .performance, "Boyutu belirtilmemiş görseller", "\(f.imagesWithoutSize) görselde width/height yok; yüklenirken sayfa kayabilir (CLS)")
        }

        // Güvenlik
        if !f.externalScriptsWithoutSRI.isEmpty {
            let hosts = Array(Set(f.externalScriptsWithoutSRI)).sorted()
            add(.info, .security, "Dış script'lerde bütünlük (SRI) kontrolü yok",
                "\(f.externalScriptsWithoutSRI.count) script integrity özniteliği olmadan yükleniyor: \(hosts.prefix(3).joined(separator: ", "))")
        }
        return issues
    }
}
