import SwiftUI

struct SiteDetailView: View {
    let siteId: String
    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @State private var history: SiteHistory?
    @State private var checking = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var pickingInterval = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let site = store.site(siteId) {
            content(site)
        } else {
            Text(L.s("site.deleted")).foregroundStyle(Theme.text3).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
        }
    }

    private func content(_ site: Site) -> some View {
        List {
            Section {
                // Adrese dokununca site tarayıcıda açılır (kesintiyi gözle görmek için).
                Button {
                    if let u = URL(string: site.url) { openURL(u) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(site.name).font(.title.weight(.heavy)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                        HStack(spacing: 4) {
                            Text(site.url).lineLimit(1).truncationMode(.middle)
                            Image(systemName: "arrow.up.right.square").font(.footnote.weight(.semibold))
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                        if store.packages.count > 1, let pkg = store.package(site.packageId) {
                            Label(pkg.name, systemImage: "square.stack.3d.up").font(.footnote).foregroundStyle(Theme.text3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L.s("detail.openHint"))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))

                StatusHero(site: site)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                HStack(spacing: 8) {
                    Button { pickingInterval = true } label: {
                        fact(CheckInterval.label(site.intervalMin), L.s("detail.interval"), editable: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L.s("detail.intervalHint"))
                    fact(site.lastCheck.map { $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L.locale)) } ?? "—", L.s("detail.last"))
                    fact(site.nextCheck.map { $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L.locale)) } ?? "—", L.s("detail.next"))
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(history?.uptimePercent.map { L.percent($0) } ?? "—")
                            .font(.title2.weight(.heavy)).foregroundStyle(Theme.text)
                        Spacer()
                        if let h = history {
                            let v = h.okValues.compactMap { $0 }
                            Text(L.s("detail.checks", v.count, v.filter { !$0 }.count))
                                .font(.footnote).foregroundStyle(Theme.text3)
                        }
                    }
                    UptimeBars(values: history?.okValues ?? site.recentOK, height: 28, count: 48)
                    HStack {
                        Text(L.s("detail.7daysAgo"))
                        Spacer()
                        Text(L.s("detail.now"))
                    }
                    .font(.caption).foregroundStyle(Theme.text3)
                }
                .padding(.vertical, 6)
                .themedRow()
            } header: {
                SectionLabel(text: L.s("detail.last7"))
            }

            if let events = history?.events, !events.isEmpty {
                Section {
                    ForEach(events, id: \.self) { e in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(e.kind == "down" ? Theme.down : Theme.up).frame(width: 10, height: 10).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(eventTitle(e)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text(e.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: L.locale))).font(.footnote).foregroundStyle(Theme.text3)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .themedRow()
                    }
                } header: {
                    SectionLabel(text: L.s("detail.events"))
                }
            }

            Section {
                Toggle(L.s("notify.down"), isOn: Binding(get: { site.notifyDown }, set: { v in Task { await store.update(site, notifyDown: v) } }))
                    .themedRow()
                Toggle(L.s("notify.up"), isOn: Binding(get: { site.notifyUp }, set: { v in Task { await store.update(site, notifyUp: v) } }))
                    .themedRow()
            } header: {
                SectionLabel(text: L.s("detail.notifications"))
            }
            .tint(Theme.barUp)

            Section {
                Button {
                    checking = true
                    Task {
                        await store.checkNow(site)
                        history = await store.history(site)
                        checking = false
                    }
                } label: {
                    HStack {
                        if checking { ProgressView().tint(.white) }
                        Text(checking ? L.s("detail.checking") : L.s("detail.checkNow"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(checking || site.paused)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Button(site.paused ? L.s("detail.resume") : L.s("detail.pause")) {
                    Task { await store.update(site, paused: !site.paused) }
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(site.paused ? Theme.accent : Theme.warn)
                .listRowBackground(Color.clear)

                Button(L.s("detail.delete"), role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.down)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .themedList()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L.s("action.edit")) { editing = true }
            }
        }
        .sheet(isPresented: $editing) { EditSiteView(site: site) }
        .sheet(isPresented: $pickingInterval) { IntervalSheet(site: site) }
        .confirmationDialog(L.s("detail.deleteConfirm", site.name), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L.s("action.delete"), role: .destructive) {
                Task { await store.delete(site); dismiss() }
            }
            Button(L.s("action.cancel"), role: .cancel) {}
        }
        .task(id: site.id) { history = await store.history(site) }
        .refreshable {
            await store.refresh()
            history = await store.history(site)
        }
    }

    private func fact(_ value: String, _ label: String, editable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(value).font(.headline).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                if editable { Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent) }
            }
            Text(label).font(.caption).foregroundStyle(Theme.text3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.divider))
        .accessibilityElement(children: .combine)
    }

    private func eventTitle(_ e: SiteHistory.Event) -> String {
        if e.kind == "up" { return L.s("event.up") }
        if let c = e.code { return L.s("event.downCode", c) }
        return L.s("event.down") + " · " + L.s("error.kind.\(e.error ?? "connect")")
    }
}

private struct StatusHero: View {
    let site: Site

    var body: some View {
        let st = site.displayStatus
        HStack(spacing: 14) {
            StatusBadge(status: st, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(st)).font(.title3.weight(.bold)).foregroundStyle(color(st))
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(border(st)))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let c = site.lastCode, c > 0 { parts.append("HTTP \(c)") }
        else if site.displayStatus == .down, let e = site.lastError { parts.append(L.s("error.kind.\(e)")) }
        parts.append(SiteText.meta(site))
        return parts.joined(separator: " · ")
    }

    private func title(_ s: SiteStatus) -> String {
        switch s {
        case .up: return L.s("status.up")
        case .down: return L.s("status.down")
        case .paused: return L.s("status.paused")
        case .unknown: return L.s("status.unknown")
        }
    }

    private func color(_ s: SiteStatus) -> Color {
        switch s {
        case .up: return Theme.up
        case .down: return Theme.down
        default: return Theme.text2
        }
    }

    private func border(_ s: SiteStatus) -> Color {
        switch s {
        case .up: return Theme.upBorder
        case .down: return Theme.downBorder
        default: return Theme.divider
        }
    }
}

/// Site ayrıntısında "Sıklık" kutusuna dokununca açılan kısa seçim.
struct IntervalSheet: View {
    let site: Site
    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @State private var interval = CheckInterval.defaultValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    IntervalPicker(selection: $interval).themedRow()
                } footer: {
                    if store.package(site.packageId)?.members ?? 1 > 1 { Text(L.s("detail.intervalShared")) }
                }
            }
            .themedList()
            .navigationTitle(L.s("add.interval"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.s("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("action.save")) {
                        Task {
                            if interval != site.intervalMin { await store.update(site, interval: interval) }
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear { interval = CheckInterval.clamp(site.intervalMin) }
        }
        .presentationDetents([.medium])
    }
}
