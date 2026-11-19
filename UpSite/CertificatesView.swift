import SwiftUI

struct CertificatesView: View {
    @EnvironmentObject private var store: SiteStore
    @EnvironmentObject private var certs: CertStore
    @EnvironmentObject private var prefs: Prefs
    @State private var filter = 0

    private var rows: [CertRecord] {
        let hosts = certs.trackedHosts(store.sites)
        let all = hosts.map { certs.records[$0] ?? CertRecord(host: $0, trusted: false, checkedAt: .distantPast) }
        let sorted = all.sorted { ($0.daysLeft ?? Int.max) < ($1.daysLeft ?? Int.max) }
        switch filter {
        case 1: return sorted.filter { ($0.daysLeft ?? Int.max) <= prefs.certThresholdDays }
        case 2: return sorted.filter(\.recentlyChanged)
        default: return sorted
        }
    }

    private var expiringSoon: [CertRecord] {
        certs.trackedHosts(store.sites).compactMap { certs.records[$0] }
            .filter { ($0.daysLeft ?? Int.max) <= prefs.certThresholdDays }
            .sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $filter) {
                        Text(L.s("certs.filter.all")).tag(0)
                        Text(L.s("certs.filter.soon")).tag(1)
                        Text(L.s("certs.filter.changed")).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if let first = expiringSoon.first, filter == 0 {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warn)
                            Text(expiringSoon.count == 1
                                 ? L.s("certs.banner.one", first.host, max(0, first.daysLeft ?? 0))
                                 : L.s("certs.banner.many", expiringSoon.count, prefs.certThresholdDays))
                                .font(.subheadline)
                                .foregroundStyle(Theme.warn)
                        }
                        .listRowBackground(Theme.warnBg)
                    }
                }

                if rows.isEmpty {
                    Section {
                        Text(store.sites.isEmpty ? L.s("certs.empty") : L.s("certs.emptyFilter"))
                            .font(.subheadline).foregroundStyle(Theme.text3).themedRow()
                    }
                } else {
                    Section {
                        ForEach(rows) { r in CertRow(record: r) }
                    } footer: {
                        Text(L.s("certs.footer"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .themedList()
            .navigationTitle(L.s("tab.certs"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await certs.checkAll(store.sites) }
                    } label: {
                        if !certs.checking.isEmpty { ProgressView() }
                        else { Label(L.s("certs.refreshAll"), systemImage: "arrow.clockwise").labelStyle(.titleAndIcon) }
                    }
                    .disabled(!certs.checking.isEmpty)
                }
            }
            .refreshable { await certs.checkAll(store.sites) }
        }
    }
}

private struct CertRow: View {
    let record: CertRecord
    @EnvironmentObject private var certs: CertStore
    @EnvironmentObject private var prefs: Prefs

    var body: some View {
        let busy = certs.checking.contains(record.host)
        HStack(spacing: 12) {
            DaysPill(days: record.daysLeft, threshold: prefs.certThresholdDays, failed: record.notAfter == nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.host).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if record.recentlyChanged {
                        Text(L.s("certs.renewed"))
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.accentFill, in: Capsule())
                    }
                }
                Text(line1).font(.footnote).foregroundStyle(record.error != nil && record.notAfter == nil ? Theme.down : Theme.text2).lineLimit(2)
                if !line2.isEmpty { Text(line2).font(.caption).foregroundStyle(Theme.text3) }
            }
            Spacer(minLength: 0)
            Button {
                Task { await certs.check(record.host); certs.scheduleReminders() }
            } label: {
                if busy { ProgressView() } else { Image(systemName: "arrow.clockwise").font(.body.weight(.semibold)) }
            }
            .buttonStyle(.borderless)
            .frame(width: 44, height: 44)
            .disabled(busy)
            .accessibilityLabel(L.s("certs.refreshOne", record.host))
        }
        .padding(.vertical, 2)
        .themedRow()
    }

    private var line1: String {
        if let end = record.notAfter {
            let date = end.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: L.locale))
            return [L.s("certs.expires", date), record.issuer].compactMap { $0 }.joined(separator: " · ")
        }
        return record.error ?? L.s("certs.notChecked")
    }

    private var line2: String {
        if record.checkedAt == .distantPast { return "" }
        var s = L.s("certs.checked", SiteText.relative(record.checkedAt))
        if record.recentlyChanged, let prev = record.previousNotAfter {
            s = L.s("certs.newCert", prev.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: L.locale))) + " · " + s
        }
        if !record.trusted && record.notAfter != nil { s = L.s("certs.untrusted") + " · " + s }
        return s
    }
}

private struct DaysPill: View {
    let days: Int?
    let threshold: Int
    let failed: Bool

    var body: some View {
        let (bg, fg): (Color, Color) = {
            guard let d = days else { return (Theme.pausedBg, Theme.paused) }
            if d < 0 { return (Theme.downBg, Theme.down) }
            if d <= threshold { return (Theme.warnBg, Theme.warn) }
            return (Theme.upBg, Theme.up)
        }()
        VStack(spacing: 0) {
            if let d = days {
                Text("\(d)").font(.headline.weight(.heavy)).monospacedDigit()
                Text(L.s("certs.days")).font(.caption2.weight(.semibold))
            } else {
                Image(systemName: failed ? "questionmark" : "ellipsis").font(.headline)
            }
        }
        .foregroundStyle(fg)
        .frame(width: 56, height: 50)
        .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days.map { L.s("certs.daysA11y", $0) } ?? L.s("certs.notChecked"))
    }
}
