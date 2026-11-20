import SwiftUI

enum SitesRoute: Hashable {
    case site(String)
    case package(String)
}

struct SitesView: View {
    @EnvironmentObject private var store: SiteStore
    @State private var addTo: AddTarget?
    @State private var joining = false
    @State private var path: [SitesRoute] = []

    /// Site ekleme sayfasının hangi pakete açılacağı
    struct AddTarget: Identifiable { let id = UUID(); let packageId: String? }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !store.sites.isEmpty {
                    Section {
                        SummaryCard()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                if let err = store.lastError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.warn)
                            .themedRow()
                    }
                } else if store.serverLate {
                    Section {
                        Label(L.s("server.late"), systemImage: "clock.badge.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(Theme.warn)
                            .themedRow()
                    }
                }

                if store.sites.isEmpty && store.packages.isEmpty && store.loadedOnce {
                    Section { EmptySites(add: { addTo = AddTarget(packageId: nil) }, join: { joining = true }) }
                        .listRowBackground(Color.clear)
                }

                if !store.downSites.isEmpty {
                    Section {
                        ForEach(store.downSites) { site in
                            NavigationLink(value: SitesRoute.site(site.id)) {
                                SiteRow(site: site, showBars: true, packageName: store.packages.count > 1 ? store.package(site.packageId)?.name : nil)
                            }
                            .themedRow()
                        }
                    } header: {
                        SectionLabel(text: L.s("sites.attention"))
                    }
                }

                ForEach(store.packages) { pkg in
                    let list = store.sites(in: pkg).filter { $0.displayStatus != .down }
                    let total = store.sites(in: pkg).count
                    Section {
                        ForEach(list) { site in
                            NavigationLink(value: SitesRoute.site(site.id)) { SiteRow(site: site, showBars: false) }
                                .themedRow()
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await store.delete(site) }
                                    } label: { Label(L.s("action.delete"), systemImage: "trash") }
                                    Button {
                                        Task { await store.update(site, paused: !site.paused) }
                                    } label: {
                                        Label(site.paused ? L.s("action.resume") : L.s("action.pause"),
                                              systemImage: site.paused ? "play.fill" : "pause.fill")
                                    }
                                    .tint(Theme.warn)
                                }
                        }
                        if total == 0 {
                            Button { addTo = AddTarget(packageId: pkg.id) } label: {
                                Label(L.s("sites.emptyPackage"), systemImage: "plus.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.accent)
                            }
                            .themedRow()
                        }
                    } header: {
                        PackageHeader(pkg: pkg, downCount: total - list.count)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .themedList()
            .navigationTitle(L.s("tab.sites"))
            .navigationDestination(for: SitesRoute.self) { route in
                switch route {
                case .site(let id): SiteDetailView(siteId: id)
                case .package(let id): PackageView(packageId: id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addTo = AddTarget(packageId: nil) } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Theme.accentFill, in: Circle())
                    }
                    .accessibilityLabel(L.s("sites.add"))
                }
            }
            .refreshable { await store.refresh() }
            .sheet(item: $addTo) { t in AddSiteView(packageId: t.packageId) }
            .sheet(isPresented: $joining) { JoinPackageView() }
            .task { if !store.loadedOnce { await store.refresh() } }
            .onAppear {
                // Ekran görüntüleri için: -UpSiteAdd
                if ProcessInfo.processInfo.arguments.contains("-UpSiteAdd") { addTo = AddTarget(packageId: nil) }
                if let id = store.openSiteId { path = [.site(id)]; store.openSiteId = nil }
            }
            .onChange(of: store.openSiteId) { id in
                if let id { path = [.site(id)]; store.openSiteId = nil }
            }
        }
    }
}

/// Paket bölüm başlığı: ad ve üye sayısı; dokununca paket sayfası açılır.
private struct PackageHeader: View {
    let pkg: SitePackage
    let downCount: Int

    var body: some View {
        NavigationLink(value: SitesRoute.package(pkg.id)) {
            HStack(spacing: 6) {
                Text(pkg.name.uppercased(with: L.locale))
                    .font(.footnote.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
                if pkg.members > 1 {
                    Label("\(pkg.members)", systemImage: "person.2.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.chevron)
            }
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel(L.s("package.a11y", pkg.name, pkg.members))
    }
}

private struct SummaryCard: View {
    @EnvironmentObject private var store: SiteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                metric("\(store.upCount)", L.s("summary.up"), Theme.up)
                metric("\(store.downSites.count)", L.s("summary.down"), store.downSites.isEmpty ? Theme.text : Theme.down)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.divider))

            if let last = store.lastCronAt {
                Text(L.s("summary.lastCheck", last.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L.locale))))
                    .font(.caption)
                    .foregroundStyle(store.serverLate ? Theme.warn : Theme.text3)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func metric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.heavy)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(Theme.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SiteRow: View {
    let site: Site
    let showBars: Bool
    var packageName: String? = nil

    var body: some View {
        HStack(alignment: showBars ? .top : .center, spacing: 12) {
            StatusLight(status: site.displayStatus)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(site.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 8)
                    if showBars {
                        Text(site.codeText).font(.footnote.weight(.bold)).foregroundStyle(Theme.down)
                    }
                }
                Text([packageName, SiteText.meta(site)].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(site.displayStatus == .down ? Theme.down : Theme.text3)
                    .lineLimit(2)
                if showBars {
                    UptimeBars(values: site.recentOK).padding(.top, 4)
                }
            }
            if !showBars {
                Text(CheckInterval.label(site.intervalMin)).font(.caption).foregroundStyle(Theme.text3)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

enum SiteText {
    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = L.locale
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    /// "3 gündür", "20 saattir", "15 dakikadır" / "for 3 days" … (en büyük birim)
    static func span(from: Date, to: Date = Date()) -> String {
        let mins = max(1, Int(to.timeIntervalSince(from) / 60))
        if mins >= 1440 { let d = mins / 1440; return d == 1 ? L.s("span.day1") : L.s("span.days", d) }
        if mins >= 60 { let h = mins / 60; return h == 1 ? L.s("span.hour1") : L.s("span.hours", h) }
        return mins == 1 ? L.s("span.minute1") : L.s("span.minutes", mins)
    }

    static func meta(_ s: Site) -> String {
        switch s.displayStatus {
        case .paused: return L.s("site.paused")
        case .unknown: return L.s("site.waiting")
        case .down:
            return s.since.map { L.s("site.downFor", span(from: $0)) } ?? L.s("status.down")
        case .up:
            if let since = s.since { return L.s("site.upFor", span(from: since)) }
            return L.s("site.up")
        }
    }
}

private struct EmptySites: View {
    let add: () -> Void
    let join: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            LogoMark(size: 64)
            Text(L.s("empty.title")).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            Text(L.s("empty.body")).font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            Button(L.s("sites.add"), action: add).buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
            Button(L.s("package.join"), action: join)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
