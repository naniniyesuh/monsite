import SwiftUI
import StoreKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: SiteStore
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @State private var alert: (title: String, message: String)?
    @State private var confirmClear = false
    @State private var confirmDeleteAll = false
    @State private var importing = false
    @State private var testing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { LanguageView() } label: {
                        SettingLabel(L.s("set.language"), "globe", .blue, value: languageName)
                    }
                    NavigationLink { AppearanceView() } label: {
                        SettingLabel(L.s("set.appearance"), "moon.fill", .gray, value: appearanceName)
                    }
                } header: { SectionLabel(text: L.s("set.general")) }
                .themedRows()

                Section {
                    NavigationLink { FalseAlarmView() } label: {
                        SettingLabel(L.s("set.falseAlarm"), "checkmark.shield.fill", .green,
                                     value: L.s("set.falseAlarm.value", prefs.retries, prefs.timeoutS))
                    }
                    NavigationLink { ServerStatusView() } label: {
                        SettingLabel(L.s("set.server"), "server.rack", .gray, value: serverValue)
                    }
                } header: { SectionLabel(text: L.s("set.checks")) } footer: { Text(L.s("set.falseAlarm.footer")) }
                .themedRows()

                Section {
                    NavigationLink { QuietHoursView() } label: {
                        SettingLabel(L.s("set.quiet"), "moon.zzz.fill", .orange,
                                     value: prefs.quietEnabled ? "\(prefs.quietStart)–\(prefs.quietEnd)" : L.s("set.off"))
                    }
                    NavigationLink { CertThresholdView() } label: {
                        SettingLabel(L.s("set.certWarning"), "calendar.badge.exclamationmark", .indigo,
                                     value: L.s("set.certWarning.value", prefs.certThresholdDays))
                    }
                    Button {
                        testing = true
                        Task {
                            let (ok, msg) = await store.sendTestPush()
                            alert = (ok ? L.s("push.test.title") : L.s("push.test.failTitle"), msg)
                            testing = false
                        }
                    } label: {
                        HStack {
                            SettingLabel(L.s("set.testPush"), "paperplane.fill", .blue)
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing)
                    if store.notificationsAllowed == false {
                        Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: {
                            Label(L.s("set.notificationsOff"), systemImage: "bell.slash").foregroundStyle(Theme.warn)
                        }
                    }
                } header: { SectionLabel(text: L.s("set.notifications")) }
                .themedRows()

                Section {
                    if let url = store.exportFile(), !store.sites.isEmpty {
                        ShareLink(item: url) { SettingLabel(L.s("set.export"), "square.and.arrow.up", .teal) }
                    }
                    Button { importing = true } label: { SettingLabel(L.s("set.import"), "square.and.arrow.down", .teal) }
                    Button { confirmClear = true } label: { SettingLabel(L.s("set.clearHistory"), "trash", .red, danger: true) }
                    Button { confirmDeleteAll = true } label: { SettingLabel(L.s("set.deleteAll"), "person.crop.circle.badge.xmark", .red, danger: true) }
                } header: { SectionLabel(text: L.s("set.data")) } footer: { Text(L.s("set.data.footer")) }
                .themedRows()

                Section {
                    NavigationLink { FeedbackView() } label: { SettingLabel(L.s("set.feedback"), "bubble.left.and.exclamationmark.bubble.right.fill", .indigo) }
                    Button { requestReview() } label: { SettingLabel(L.s("set.rate"), "star.fill", .orange) }
                    Button { openURL(AppInfo.supportURL) } label: { SettingLabel(L.s("set.help"), "questionmark.circle.fill", .gray, external: true) }
                } header: { SectionLabel(text: L.s("set.support")) }
                .themedRows()

                Section {
                    Button { openURL(AppInfo.privacyURL) } label: { SettingLabel(L.s("set.privacy"), "lock.fill", .gray, external: true) }
                } header: { SectionLabel(text: L.s("set.legal")) }
                .themedRows()

                Section {
                    VStack(spacing: 6) {
                        LogoMark(size: 40)
                        Text("UpSite \(AppInfo.version) (\(AppInfo.build)) · alpp.studio").font(.footnote).foregroundStyle(Theme.text3)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .themedList()
            .navigationTitle(L.s("tab.settings"))
            .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
                Button(L.s("action.ok"), role: .cancel) {}
            } message: { Text(alert?.message ?? "") }
            .confirmationDialog(L.s("set.clearHistory.confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(L.s("set.clearHistory"), role: .destructive) {
                    Task { if await store.clearHistory() { alert = (L.s("set.clearHistory"), L.s("set.done")) } }
                }
                Button(L.s("action.cancel"), role: .cancel) {}
            }
            .confirmationDialog(L.s("set.deleteAll.confirm"), isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button(L.s("set.deleteAll"), role: .destructive) {
                    Task { if await store.deleteAllData() { alert = (L.s("set.deleteAll"), L.s("set.deleteAll.done")) } }
                }
                Button(L.s("action.cancel"), role: .cancel) {}
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case let .success(url) = result else { return }
                Task {
                    let r = await store.importFile(url)
                    alert = (L.s("set.import"), L.s("set.import.result", r.added, r.skipped))
                }
            }
        }
    }

    private var languageName: String {
        switch prefs.language {
        case .system: return L.s("lang.system")
        case .tr: return "Türkçe"
        case .en: return "English"
        }
    }

    private var appearanceName: String {
        switch prefs.appearance {
        case .dark: return L.s("appearance.dark")
        case .light: return L.s("appearance.light")
        case .system: return L.s("appearance.system")
        }
    }

    private var serverValue: String {
        if !store.api.isConfigured && !store.demo { return L.s("server.notConfigured") }
        if store.lastError != nil { return L.s("server.unreachable") }
        if let t = store.lastCronAt { return L.s("server.ok", t.formatted(date: .omitted, time: .shortened)) }
        return "—"
    }
}

struct SettingLabel: View {
    let title: String
    let icon: String
    let tile: Color
    var value: String? = nil
    var danger = false
    var external = false

    init(_ title: String, _ icon: String, _ tile: Color, value: String? = nil, danger: Bool = false, external: Bool = false) {
        self.title = title; self.icon = icon; self.tile = tile; self.value = value; self.danger = danger; self.external = external
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tile.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).foregroundStyle(danger ? Theme.down : Theme.text)
            Spacer(minLength: 8)
            if let value { Text(value).foregroundStyle(Theme.text3).lineLimit(1) }
            if external { Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.chevron) }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func themedRows() -> some View { listRowBackground(Theme.surface).listRowSeparatorTint(Theme.divider) }
}

// MARK: - Alt sayfalar

struct LanguageView: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        List {
            Section {
                choice(L.s("lang.system"), .system)
                choice("Türkçe", .tr)
                choice("English", .en)
            } footer: { Text(L.s("lang.footer")) }
            .themedRows()
        }
        .listStyle(.insetGrouped).themedList().navigationTitle(L.s("set.language"))
    }
    private func choice(_ title: String, _ v: AppLanguage) -> some View {
        Button { prefs.language = v } label: {
            HStack { Text(title).foregroundStyle(Theme.text); Spacer(); if prefs.language == v { Image(systemName: "checkmark").foregroundStyle(Theme.accent) } }
        }
    }
}

struct AppearanceView: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        List {
            Section {
                choice(L.s("appearance.dark"), .dark)
                choice(L.s("appearance.light"), .light)
                choice(L.s("appearance.system"), .system)
            }
            .themedRows()
        }
        .listStyle(.insetGrouped).themedList().navigationTitle(L.s("set.appearance"))
    }
    private func choice(_ title: String, _ v: Appearance) -> some View {
        Button { prefs.appearance = v } label: {
            HStack { Text(title).foregroundStyle(Theme.text); Spacer(); if prefs.appearance == v { Image(systemName: "checkmark").foregroundStyle(Theme.accent) } }
        }
    }
}

struct FalseAlarmView: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        List {
            Section {
                Stepper(value: $prefs.retries, in: 0...3) {
                    HStack { Text(L.s("falseAlarm.retries")); Spacer(); Text("\(prefs.retries)").foregroundStyle(Theme.text3).monospacedDigit() }
                }
                Picker(L.s("falseAlarm.timeout"), selection: $prefs.timeoutS) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text(L.s("falseAlarm.seconds", $0)).tag($0) }
                }
            } footer: { Text(L.s("falseAlarm.footer")) }
            .themedRows()
        }
        .listStyle(.insetGrouped).themedList().navigationTitle(L.s("set.falseAlarm"))
    }
}

struct QuietHoursView: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        List {
            Section {
                Toggle(L.s("quiet.enable"), isOn: $prefs.quietEnabled).tint(Theme.barUp)
                if prefs.quietEnabled {
                    DatePicker(L.s("quiet.start"), selection: Binding(get: { .fromHHMM(prefs.quietStart) }, set: { prefs.quietStart = $0.hhmm }),
                               displayedComponents: .hourAndMinute)
                    DatePicker(L.s("quiet.end"), selection: Binding(get: { .fromHHMM(prefs.quietEnd) }, set: { prefs.quietEnd = $0.hhmm }),
                               displayedComponents: .hourAndMinute)
                }
            } footer: { Text(L.s("quiet.footer")) }
            .themedRows()
        }
        .listStyle(.insetGrouped).themedList().navigationTitle(L.s("set.quiet"))
    }
}

struct CertThresholdView: View {
    @EnvironmentObject private var prefs: Prefs
    var body: some View {
        List {
            Section {
                ForEach([7, 14, 21, 30], id: \.self) { d in
                    Button { prefs.certThresholdDays = d } label: {
                        HStack {
                            Text(L.s("set.certWarning.value", d)).foregroundStyle(Theme.text)
                            Spacer()
                            if prefs.certThresholdDays == d { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
            } footer: { Text(L.s("certWarning.footer")) }
            .themedRows()
        }
        .listStyle(.insetGrouped).themedList().navigationTitle(L.s("set.certWarning"))
    }
}

struct ServerStatusView: View {
    @EnvironmentObject private var store: SiteStore
    var body: some View {
        List {
            Section {
                row(L.s("server.address"), store.api.baseURL?.host ?? L.s("server.notConfigured"))
                row(L.s("server.lastRun"), store.lastCronAt.map { SiteText.relative($0) } ?? "—")
                row(L.s("server.lastRefresh"), store.lastRefresh.map { SiteText.relative($0) } ?? "—")
                row(L.s("server.push"), store.pushToken == nil ? L.s("server.push.none") : L.s("server.push.ok"))
                if let e = store.lastError { Text(e).font(.footnote).foregroundStyle(Theme.warn) }
            } footer: { Text(L.s("server.footer")) }
            .themedRows()
            Section {
                Button(L.s("server.refresh")) { Task { await store.refresh() } }
            }
            .themedRows()
        }
        .listStyle(.insetGrouped).themedList().navigationTitle(L.s("set.server"))
        .refreshable { await store.refresh() }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Theme.text); Spacer(); Text(v).foregroundStyle(Theme.text3).multilineTextAlignment(.trailing) }
    }
}
