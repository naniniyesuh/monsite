import SwiftUI

struct SitesView: View {
    @EnvironmentObject private var store: SiteStore
    @State private var showAdd = false
    @State private var path: [String] = []

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

                if store.sites.isEmpty && store.loadedOnce {
                    Section { EmptySites { showAdd = true } }
                        .listRowBackground(Color.clear)
                }

                if !store.downSites.isEmpty {
                    Section {
                        ForEach(store.downSites) { site in
                            NavigationLink(value: site.id) { SiteRow(site: site, showBars: true) }
                                .themedRow()
                        }
                    } header: {
                        SectionLabel(text: L.s("sites.attention"))
                    }
                }

                let others = store.sites.filter { $0.displayStatus != .down }
                if !others.isEmpty {
                    Section {
                        ForEach(others) { site in
                            NavigationLink(value: site.id) { SiteRow(site: site, showBars: false) }
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
                    } header: {
                        SectionLabel(text: L.s("sites.all"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .themedList()
            .navigationTitle(L.s("tab.sites"))
            .navigationDestination(for: String.self) { id in SiteDetailView(siteId: id) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
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
            .sheet(isPresented: $showAdd) { AddSiteView() }
            .task { if !store.loadedOnce { await store.refresh() } }
            .onAppear {
                if let id = store.openSiteId { path = [id]; store.openSiteId = nil }
            }
            .onChange(of: store.openSiteId) { id in
                if let id { path = [id]; store.openSiteId = nil }
            }
        }
    }
}

private struct SummaryCard: View {
    @EnvironmentObject private var store: SiteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                metric("\(store.upCount)", L.s("summary.up"), Theme.up)
                metric("\(store.downSites.count)", L.s("summary.down"), store.downSites.isEmpty ? Theme.text : Theme.down)
                metric(store.nextCheck.map { $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L.locale)) } ?? "—", L.s("summary.next"), Theme.text)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.divider))

            if let last = store.lastCronAt {
                HStack(spacing: 6) {
                    Circle().fill(store.serverLate ? Theme.warn : Theme.up).frame(width: 7, height: 7)
                    Text(L.s("summary.server", last.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L.locale))))
                        .font(.caption)
                        .foregroundStyle(Theme.text3)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
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

    var body: some View {
        HStack(alignment: showBars ? .top : .center, spacing: 12) {
            StatusBadge(status: site.displayStatus)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(site.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 8)
                    if showBars {
                        Text(site.codeText).font(.footnote.weight(.bold)).foregroundStyle(Theme.down)
                    }
                }
                Text(SiteText.meta(site))
                    .font(.footnote)
                    .foregroundStyle(site.displayStatus == .down ? Theme.down : Theme.text3)
                    .lineLimit(2)
                if showBars {
                    UptimeBars(values: site.recentOK).padding(.top, 4)
                }
            }
            if !showBars {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(site.codeText)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(site.displayStatus == .up ? Theme.up : Theme.text3)
                    Text(CheckInterval.label(site.intervalMin)).font(.caption).foregroundStyle(Theme.text3)
                }
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

    static func duration(from: Date, to: Date = Date()) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.maximumUnitCount = 2
        f.allowedUnits = [.day, .hour, .minute]
        var cal = Calendar.current
        cal.locale = L.locale
        f.calendar = cal
        return f.string(from: max(60, to.timeIntervalSince(from))) ?? ""
    }

    static func meta(_ s: Site) -> String {
        switch s.displayStatus {
        case .paused: return L.s("site.paused")
        case .unknown: return L.s("site.waiting")
        case .down:
            let t = s.since.map { $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L.locale)) } ?? "—"
            return L.s("site.downSince", t, s.since.map { duration(from: $0) } ?? "")
        case .up:
            if let since = s.since { return L.s("site.upFor", duration(from: since)) }
            return L.s("site.up")
        }
    }
}

private struct EmptySites: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            LogoMark(size: 64)
            Text(L.s("empty.title")).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            Text(L.s("empty.body")).font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            Button(L.s("sites.add"), action: add).buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
