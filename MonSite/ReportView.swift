import SwiftUI
import UIKit

// MARK: - Rapor ana ekranı

struct ReportView: View {
    let report: ScanReport
    @State private var jsonURL: URL?
    @State private var area: ScoreArea?

    var body: some View {
        List {
            Section {
                ScoreHeader(report: report)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                AreaScoresRow(report: report) { area = $0 }
                    .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
            }

            Section {
                MetricGrid(report: report)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if report.cancelled {
                Section {
                    Label("Tarama iptal edildi — sonuçlar kısmi.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(Severity.allCases, id: \.self) { s in
                    let list = report.issues.filter { $0.severity == s }
                    NavigationLink {
                        IssuesView(title: s.title, issues: list)
                    } label: {
                        RowLabel(icon: s.systemImage, tint: SeverityIcon(severity: s).color, title: s.title) {
                            CountBadge(count: list.count, tint: SeverityIcon(severity: s).color)
                        }
                    }
                    .disabled(list.isEmpty)
                }
            } header: {
                SectionTitle("Sorunlar", trailing: "\(report.issues.count) bulgu")
            }

            Section {
                ForEach(IssueCategory.allCases, id: \.self) { c in
                    let all = report.issues.filter { $0.category == c }
                    let problems = all.filter { $0.severity <= .warning }
                    let worst = problems.map(\.severity).min()
                    NavigationLink {
                        IssuesView(title: c.title, issues: all)
                    } label: {
                        RowLabel(icon: c.systemImage, tint: .accentColor, title: c.title) {
                            if let worst {
                                CountBadge(count: problems.count, tint: SeverityIcon(severity: worst).color)
                            } else {
                                Label("Sorunsuz", systemImage: "checkmark")
                                    .labelStyle(.iconOnly)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            } header: {
                SectionTitle("Kategoriler")
            }

            Section {
                CertificateSection(cert: report.certificate)
            } header: {
                SectionTitle("SSL sertifikası")
            }

            let pages = Array(report.slowestPages.prefix(5))
            if !pages.isEmpty {
                Section {
                    let maxMs = pages.first?.durationMs ?? 1
                    ForEach(pages) { p in
                        NavigationLink {
                            PageDetailView(page: p, report: report)
                        } label: {
                            DurationBar(title: shortURL(p.url), subtitle: p.title, ms: p.durationMs, maxMs: maxMs)
                        }
                    }
                } header: {
                    SectionTitle("En yavaş sayfalar")
                }
            }

            let slowRes = Array(report.slowestResources.prefix(10))
            if !slowRes.isEmpty {
                Section {
                    let maxMs = slowRes.first?.durationMs ?? 1
                    ForEach(slowRes) { r in
                        DurationBar(title: shortURL(r.url),
                                    subtitle: [r.kind.title, r.bytes.map(formatBytes)].compactMap { $0 }.joined(separator: " · "),
                                    ms: r.durationMs, maxMs: maxMs)
                    }
                } header: {
                    SectionTitle("En yavaş yüklenen parçalar")
                }
            }

            Section {
                NavigationLink {
                    PagesListView(report: report)
                } label: {
                    RowLabel(icon: "doc.on.doc", tint: .accentColor, title: "Tüm sayfalar") {
                        Text("\(report.pages.count)").foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    ResourcesListView(report: report)
                } label: {
                    RowLabel(icon: "square.stack.3d.up", tint: .accentColor, title: "Tüm kaynaklar") {
                        Text("\(report.resources.count)").foregroundStyle(.secondary)
                    }
                }
            } header: {
                SectionTitle("Ayrıntılar")
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(isPresented: Binding(get: { area != nil }, set: { if !$0 { area = nil } })) {
            if let area {
                IssuesView(title: area.title, issues: report.issues.filter { area.categories.contains($0.category) })
            }
        }
        .navigationTitle(report.host)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ShareLink("Metin rapor", item: ReportExporter.text(report))
                    if let jsonURL {
                        ShareLink("JSON dosyası", item: jsonURL)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            if jsonURL == nil { jsonURL = ReportExporter.jsonFile(report) }
        }
    }
}

// MARK: - Puan başlığı

private struct AreaScoresRow: View {
    let report: ScanReport
    let onSelect: (ScoreArea) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(ScoreArea.allCases) { a in
                Button { onSelect(a) } label: {
                    VStack(spacing: 6) {
                        ScoreRing(score: report.areaScore(a), grade: "", size: 46, lineWidth: 5)
                        Text(a.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(a.title) puanı \(report.areaScore(a))")
            }
        }
    }
}

struct ScoreRing: View {
    let score: Int
    let grade: String
    var size: CGFloat = 96
    var lineWidth: CGFloat = 10

    static func color(for score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 65..<80: return .yellow
        case 50..<65: return .orange
        default: return .red
        }
    }

    var body: some View {
        let c = Self.color(for: score)
        ZStack {
            Circle().stroke(c.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(c, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded).monospacedDigit())
                if size >= 80 {
                    Text(grade)
                        .font(.system(size: size * 0.14, weight: .semibold, design: .rounded))
                        .foregroundStyle(c)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sağlık puanı \(score), not \(grade)")
    }
}

private struct ScoreHeader: View {
    let report: ScanReport

    var body: some View {
        HStack(spacing: 18) {
            ScoreRing(score: report.score, grade: report.grade)
            VStack(alignment: .leading, spacing: 6) {
                Text("Sağlık puanı")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(report.verdict)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Label(report.host, systemImage: "globe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(report.finishedAt.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.1f", report.durationSec)) sn")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MetricGrid: View {
    let report: ScanReport

    var body: some View {
        let problems = report.count(.critical) + report.count(.error)
        let certDays = report.certificate?.daysRemaining
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            MetricTile(icon: "doc.text.magnifyingglass", label: "Taranan sayfa",
                       value: "\(report.pages.count)", tint: .accentColor)
            MetricTile(icon: "exclamationmark.octagon", label: "Kritik + hata",
                       value: "\(problems)", tint: problems > 0 ? .red : .green)
            MetricTile(icon: "timer", label: "Ort. yükleme",
                       value: formatMs(report.averagePageMs),
                       tint: report.averagePageMs > 3000 ? .orange : .green)
            MetricTile(icon: "photo.badge.exclamationmark", label: "Bozuk kaynak",
                       value: "\(report.brokenResources.count)",
                       tint: report.brokenResources.isEmpty ? .green : .red)
            MetricTile(icon: "exclamationmark.triangle", label: "Uyarı",
                       value: "\(report.count(.warning))",
                       tint: report.count(.warning) > 0 ? .orange : .green)
            MetricTile(icon: "lock.shield", label: "Sertifika",
                       value: certDays.map { $0 < 0 ? "Dolmuş" : "\($0) gün" } ?? "—",
                       tint: certColor(certDays))
        }
    }

    private func certColor(_ d: Int?) -> Color {
        guard let d else { return .secondary }
        if d < 14 { return .red }
        if d < 30 { return .orange }
        return .green
    }
}

private struct MetricTile: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Liste yardımcıları

struct SectionTitle: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing { Text(trailing).textCase(nil) }
        }
    }
}

struct RowLabel<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
            Spacer()
            trailing()
        }
    }
}

struct CountBadge: View {
    let count: Int
    let tint: Color

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(count == 0 ? Color.secondary : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((count == 0 ? Color.secondary : tint).opacity(0.13), in: Capsule())
    }
}

// MARK: - Sertifika

private struct CertificateSection: View {
    let cert: CertificateInfo?

    var body: some View {
        if let cert {
            if cert.chain.isEmpty {
                Label(cert.fetchError ?? "Sertifika okunamadı", systemImage: "lock.slash")
                    .foregroundStyle(.red)
            } else {
                Label(cert.trusted ? "Güvenilir" : "Güvenilir değil",
                      systemImage: cert.trusted ? "lock.fill" : "lock.open.fill")
                    .foregroundStyle(cert.trusted ? .green : .red)
                if let e = cert.trustError {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
                if let s = cert.subject { LabeledContent("Sahibi", value: s) }
                if let i = cert.issuer { LabeledContent("Veren", value: i) }
                if let k = cert.keyDescription { LabeledContent("Anahtar", value: k) }
                if let d = cert.notBefore { LabeledContent("Başlangıç", value: d.formatted(date: .long, time: .omitted)) }
                if let d = cert.notAfter { LabeledContent("Bitiş", value: d.formatted(date: .long, time: .omitted)) }
                if let days = cert.daysRemaining {
                    LabeledContent("Kalan", value: days < 0 ? "Süresi dolmuş" : "\(days) gün")
                }
                if cert.chain.count > 1 {
                    DisclosureGroup("Zincir (\(cert.chain.count))") {
                        ForEach(Array(cert.chain.enumerated()), id: \.offset) { i, name in
                            Text("\(i + 1). \(name)").font(.caption)
                        }
                    }
                }
            }
        } else {
            Text("Kontrol edilmedi").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sorun listesi

struct IssuesView: View {
    let title: String
    let issues: [Issue]
    @State private var query = ""
    @State private var category: IssueCategory?
    @State private var grouped: Bool

    init(title: String, issues: [Issue], grouped: Bool = true) {
        self.title = title
        self.issues = issues
        _grouped = State(initialValue: grouped)
    }

    private struct IssueGroup: Identifiable {
        let id: String
        let severity: Severity
        let category: IssueCategory
        let title: String
        let issues: [Issue]
    }

    private var filtered: [Issue] {
        issues.filter { i in
            (category == nil || i.category == category) &&
            (query.isEmpty || i.title.localizedCaseInsensitiveContains(query)
                || i.detail.localizedCaseInsensitiveContains(query)
                || i.url.localizedCaseInsensitiveContains(query))
        }
    }

    private var groups: [IssueGroup] {
        let dict = Dictionary(grouping: filtered) { "\($0.severity.rawValue)|\($0.category.rawValue)|\($0.title)" }
        return dict.map { k, v in IssueGroup(id: k, severity: v[0].severity, category: v[0].category, title: v[0].title, issues: v) }
            .sorted { ($0.severity.rank, -$0.issues.count, $0.title) < ($1.severity.rank, -$1.issues.count, $1.title) }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                Label("Sorun yok", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
            if grouped {
                ForEach(groups) { g in
                    if g.issues.count == 1 {
                        IssueRow(issue: g.issues[0])
                    } else {
                        NavigationLink {
                            IssuesView(title: g.title, issues: g.issues, grouped: false)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                SeverityIcon(severity: g.severity)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(g.title).font(.subheadline.weight(.semibold))
                                    Text("\(g.category.title) · \(g.issues.count) yerde")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                CountBadge(count: g.issues.count, tint: SeverityIcon(severity: g.severity).color)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else {
                ForEach(filtered) { IssueRow(issue: $0) }
            }
        }
        .searchable(text: $query, prompt: "Ara")
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Toggle(isOn: $grouped) {
                        Label("Aynı sorunları grupla", systemImage: "square.stack.3d.up")
                    }
                    Picker("Kategori", selection: $category) {
                        Text("Tüm kategoriler").tag(IssueCategory?.none)
                        ForEach(IssueCategory.allCases, id: \.self) { c in
                            Text(c.title).tag(IssueCategory?.some(c))
                        }
                    }
                } label: {
                    Image(systemName: category == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }
}

struct IssueRow: View {
    let issue: Issue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SeverityIcon(severity: issue.severity)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.subheadline.weight(.semibold))
                if !issue.detail.isEmpty {
                    Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                }
                Text(shortURL(issue.url))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button { UIPasteboard.general.string = issue.url } label: {
                Label("Adresi kopyala", systemImage: "doc.on.doc")
            }
            if let u = URL(string: issue.url) {
                Link(destination: u) { Label("Safari'de aç", systemImage: "safari") }
            }
        }
    }
}

struct SeverityIcon: View {
    let severity: Severity

    var color: Color {
        switch severity {
        case .critical: return .purple
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    var body: some View {
        Image(systemName: severity.systemImage).foregroundStyle(color)
    }
}

// MARK: - Süre çubuğu

struct DurationBar: View {
    let title: String
    let subtitle: String?
    let ms: Double
    let maxMs: Double

    private var color: Color {
        if ms < 1000 { return .green }
        if ms < 3000 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Text(formatMs(ms)).font(.subheadline.monospacedDigit()).foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(color)
                        .frame(width: max(4, g.size.width * CGFloat(min(ms / max(maxMs, 1), 1))))
                }
            }
            .frame(height: 6)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sayfalar

struct PagesListView: View {
    let report: ScanReport
    @State private var query = ""
    @State private var sort = 0

    private var pages: [PageResult] {
        let base = report.pages.filter { query.isEmpty || $0.url.localizedCaseInsensitiveContains(query) || ($0.title ?? "").localizedCaseInsensitiveContains(query) }
        switch sort {
        case 1: return base.sorted { $0.durationMs > $1.durationMs }
        case 2: return base.sorted { $0.issues.count > $1.issues.count }
        default: return base
        }
    }

    var body: some View {
        List {
            Picker("Sırala", selection: $sort) {
                Text("Tarama sırası").tag(0)
                Text("En yavaş").tag(1)
                Text("En çok sorun").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            ForEach(pages) { p in
                NavigationLink {
                    PageDetailView(page: p, report: report)
                } label: {
                    HStack(spacing: 10) {
                        StatusBadge(code: p.statusCode, failed: p.error != nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title ?? shortURL(p.url)).font(.subheadline).lineLimit(1)
                            Text(shortURL(p.url)).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatMs(p.durationMs)).font(.caption.monospacedDigit())
                            let n = p.issues.filter { $0.severity <= .warning }.count
                            if n > 0 {
                                Text("\(n) sorun").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Adres veya başlık")
        .navigationTitle("Sayfalar")
    }
}

struct StatusBadge: View {
    let code: Int?
    let failed: Bool

    var body: some View {
        let c = code ?? 0
        let color: Color = failed || c >= 500 ? .red : c >= 400 ? .orange : c >= 300 ? .blue : .green
        Text(failed ? "ERR" : code.map { "\($0)" } ?? "—")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct PageDetailView: View {
    let page: PageResult
    let report: ScanReport

    private var pageResources: [ResourceResult] {
        report.resources
            .filter { $0.foundOn.contains(page.url) }
            .sorted { ($0.isBroken ? 0 : 1, -$0.durationMs) < ($1.isBroken ? 0 : 1, -$1.durationMs) }
    }

    var body: some View {
        List {
            Section("Genel") {
                LabeledContent("Durum") {
                    StatusBadge(code: page.statusCode, failed: page.error != nil)
                }
                if let e = page.error { Text(e).foregroundStyle(.red) }
                if let t = page.title { LabeledContent("Başlık", value: t) }
                LabeledContent("Derinlik", value: "\(page.depth)")
                LabeledContent("Boyut", value: formatBytes(page.bytes))
                if let ct = page.contentType { LabeledContent("Tür", value: ct) }
                LabeledContent("Bağlantı / kaynak", value: "\(page.linkCount) / \(page.resourceCount)")
                if page.finalURL != page.url {
                    LabeledContent("Yönlendirildi", value: shortURL(page.finalURL))
                }
                if let u = URL(string: page.url) {
                    Link(destination: u) { Label("Safari'de aç", systemImage: "safari") }
                }
            }

            Section("Zamanlama") {
                LabeledContent("Toplam", value: formatMs(page.durationMs))
                if let t = page.timing {
                    if let v = t.dnsMs { LabeledContent("DNS", value: formatMs(v)) }
                    if let v = t.connectMs { LabeledContent("Bağlantı", value: formatMs(v)) }
                    if let v = t.tlsMs { LabeledContent("TLS el sıkışma", value: formatMs(v)) }
                    if let v = t.ttfbMs { LabeledContent("İlk bayt (TTFB)", value: formatMs(v)) }
                    if let v = t.downloadMs { LabeledContent("İndirme", value: formatMs(v)) }
                    if t.redirectCount > 0 { LabeledContent("Yönlendirme", value: "\(t.redirectCount)") }
                    if let p = t.httpProtocol { LabeledContent("Protokol", value: p) }
                    if let v = t.tlsVersion { LabeledContent("TLS", value: v) }
                }
            }

            Section("Sorunlar (\(page.issues.count))") {
                if page.issues.isEmpty {
                    Label("Sorun yok", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                ForEach(page.issues) { IssueRow(issue: $0) }
            }

            let res = pageResources
            if !res.isEmpty {
                let maxMs = res.map(\.durationMs).max() ?? 1
                Section("Kaynaklar (\(res.count))") {
                    ForEach(res) { ResourceRow(resource: $0, maxMs: maxMs) }
                }
            }
        }
        .navigationTitle(shortURL(page.url))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Kaynaklar

struct ResourcesListView: View {
    let report: ScanReport
    @State private var filter = 0
    @State private var query = ""

    private var items: [ResourceResult] {
        let base: [ResourceResult]
        switch filter {
        case 1: base = report.resources.filter(\.isBroken)
        case 2: base = report.slowestResources
        case 3: base = report.resources.filter(\.external)
        default: base = report.resources
        }
        return query.isEmpty ? base : base.filter { $0.url.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let list = items
        let maxMs = list.map(\.durationMs).max() ?? 1
        List {
            Picker("Filtre", selection: $filter) {
                Text("Tümü").tag(0)
                Text("Bozuk").tag(1)
                Text("Yavaş").tag(2)
                Text("Dış").tag(3)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            ForEach(list) { ResourceRow(resource: $0, maxMs: maxMs) }
        }
        .searchable(text: $query, prompt: "Adres")
        .navigationTitle("Kaynaklar")
    }
}

struct ResourceRow: View {
    let resource: ResourceResult
    let maxMs: Double

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: resource.kind.systemImage)
                .foregroundStyle(resource.isBroken ? .red : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    StatusBadge(code: resource.statusCode, failed: resource.error != nil)
                    Text(resource.kind.title + (resource.external ? " · dış" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                    if let b = resource.bytes {
                        Text(formatBytes(b)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DurationBar(title: shortURL(resource.url), subtitle: resource.error, ms: resource.durationMs, maxMs: maxMs)
            }
        }
        .contextMenu {
            Button { UIPasteboard.general.string = resource.url } label: {
                Label("Adresi kopyala", systemImage: "doc.on.doc")
            }
            if let u = URL(string: resource.url) {
                Link(destination: u) { Label("Safari'de aç", systemImage: "safari") }
            }
        }
    }
}
