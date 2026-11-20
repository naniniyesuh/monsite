import SwiftUI
import UIKit

/// Paket sayfası: anahtar, üyeler, ortak ayarlar ve ayrılma.
struct PackageView: View {
    let packageId: String
    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var copied = false
    @State private var confirm: Confirm?
    @State private var errorText: String?

    enum Confirm: Identifiable { case rotate, leave, delete; var id: Self { self } }

    var body: some View {
        if let pkg = store.package(packageId) {
            content(pkg)
        } else {
            Text(L.s("package.gone")).foregroundStyle(Theme.text3).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
        }
    }

    private func content(_ pkg: SitePackage) -> some View {
        List {
            Section {
                TextField(L.s("package.name"), text: $name)
                    .font(.title3.weight(.bold))
                    .submitLabel(.done)
                    .onSubmit { save(pkg) }
                    .themedRow()
                HStack {
                    Label(L.s("package.membersShort", pkg.members), systemImage: "person.2.fill")
                    Spacer()
                    Label(L.s("package.sitesShort", store.sites(in: pkg).count), systemImage: "globe")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
                .themedRow()
            } header: { SectionLabel(text: L.s("package.title")) }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(pkg.prettyKey)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = pkg.prettyKey
                            copied = true
                        } label: {
                            Label(copied ? L.s("package.copied") : L.s("package.copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        ShareLink(item: L.s("package.shareText", pkg.name, pkg.prettyKey)) {
                            Label(L.s("package.share"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .tint(Theme.accent)
                }
                .themedRow()
            } header: {
                SectionLabel(text: L.s("package.key"))
            } footer: {
                Text(L.s("package.keyFooter"))
            }

            Section {
                Stepper(value: Binding(get: { pkg.retries }, set: { v in Task { await store.updatePackage(pkg, retries: v) } }), in: 0...3) {
                    HStack { Text(L.s("falseAlarm.retries")); Spacer(); Text("\(pkg.retries)").foregroundStyle(Theme.text3).monospacedDigit() }
                }
                .themedRow()
                Picker(L.s("falseAlarm.timeout"), selection: Binding(get: { pkg.timeoutS }, set: { v in Task { await store.updatePackage(pkg, timeoutS: v) } })) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text(L.s("falseAlarm.seconds", $0)).tag($0) }
                }
                .themedRow()
            } header: {
                SectionLabel(text: L.s("set.falseAlarm"))
            } footer: {
                Text(L.s("falseAlarm.footer") + (pkg.members > 1 ? " " + L.s("package.sharedSetting") : ""))
            }

            Section {
                if pkg.isOwner && pkg.members > 1 {
                    Button(L.s("package.rotate")) { confirm = .rotate }.foregroundStyle(Theme.accent)
                }
                Button(L.s("package.leave")) { confirm = .leave }.foregroundStyle(Theme.warn)
                if pkg.isOwner && pkg.members > 1 {
                    Button(L.s("package.delete")) { confirm = .delete }.foregroundStyle(Theme.down)
                }
            } footer: {
                if let errorText { Text(errorText).foregroundStyle(Theme.down) }
            }
            .themedRows()
        }
        .listStyle(.insetGrouped)
        .themedList()
        .navigationTitle(pkg.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = pkg.name }
        .onDisappear { save(pkg) }
        .confirmationDialog(confirmTitle(pkg), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            switch confirm {
            case .rotate:
                Button(L.s("package.rotate")) { run { try await store.rotateKey(pkg) } }
            case .leave:
                Button(L.s("package.leave"), role: .destructive) { run { try await store.leave(pkg, delete: false); dismiss() } }
            case .delete:
                Button(L.s("package.delete"), role: .destructive) { run { try await store.leave(pkg, delete: true); dismiss() } }
            case .none:
                EmptyView()
            }
            Button(L.s("action.cancel"), role: .cancel) {}
        }
    }

    private func confirmTitle(_ pkg: SitePackage) -> String {
        switch confirm {
        case .rotate: return L.s("package.rotateConfirm")
        case .leave: return pkg.members > 1 ? L.s("package.leaveConfirm", pkg.name) : L.s("package.leaveLastConfirm", pkg.name)
        case .delete: return L.s("package.deleteConfirm", pkg.name, pkg.members)
        case .none: return ""
        }
    }

    private func save(_ pkg: SitePackage) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != pkg.name else { return }
        Task { await store.updatePackage(pkg, name: n) }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        Task {
            do { try await op(); errorText = nil } catch { errorText = error.localizedDescription }
        }
    }
}

/// Yeni paket oluşturma
struct CreatePackageView: View {
    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool
    var onCreated: (SitePackage) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.s("package.namePlaceholder"), text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(create)
                        .themedRow()
                } header: {
                    SectionLabel(text: L.s("package.name"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let error { Text(error).foregroundStyle(Theme.down) }
                        Text(L.s("package.createFooter"))
                    }
                }
            }
            .themedList()
            .navigationTitle(L.s("package.create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.s("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button(L.s("package.createButton"), action: create)
                            .fontWeight(.bold)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func create() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !saving else { return }
        saving = true
        Task {
            do {
                let p = try await store.createPackage(name: n)
                dismiss()
                onCreated(p)
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}

/// Anahtarla pakete katılma
struct JoinPackageView: View {
    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var joining = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("XXXX-XXXX-XXXX", text: Binding(get: { key }, set: { key = SitePackage.pretty($0) }))
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.join)
                        .onSubmit(join)
                        .themedRow()
                } header: {
                    SectionLabel(text: L.s("package.key"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let error { Text(error).foregroundStyle(Theme.down) }
                        Text(L.s("package.joinFooter"))
                    }
                }
            }
            .themedList()
            .navigationTitle(L.s("package.join"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.s("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if joining { ProgressView() } else {
                        Button(L.s("package.joinButton"), action: join)
                            .fontWeight(.bold)
                            .disabled(key.filter { $0.isLetter || $0.isNumber }.count < 8)
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func join() {
        guard !joining else { return }
        joining = true
        Task {
            do {
                _ = try await store.joinPackage(key: key)
                await store.requestNotificationPermissionIfNeeded()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            joining = false
        }
    }
}

// MARK: - Yönetici

/// Yalnızca yönetici cihazında görünür: paketler, siteleri ve haber akışı.
struct AdminView: View {
    @EnvironmentObject private var store: SiteStore
    @State private var data: AdminState?
    @State private var error: String?

    var body: some View {
        List {
            if let data {
                Section {
                    HStack(spacing: 0) {
                        metric("\(data.totals.packages)", L.s("admin.packages"), limit: data.limits.packages)
                        metric("\(data.totals.sites)", L.s("admin.sites"))
                        metric("\(data.totals.devices)", L.s("admin.devices"))
                    }
                    .listRowBackground(Theme.surface)
                } footer: {
                    Text(L.s("admin.limits", data.limits.sitesPerPackage, data.limits.members, data.limits.packagesPerDevice))
                }

                Section {
                    if data.log.isEmpty {
                        Text(L.s("admin.noNews")).foregroundStyle(Theme.text3)
                    }
                    ForEach(data.log, id: \.self) { e in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(e.kind)).foregroundStyle(color(e.kind)).frame(width: 22).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.s("admin.kind.\(e.kind)", e.text)).foregroundStyle(Theme.text)
                                Text(e.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: L.locale)))
                                    .font(.footnote).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                } header: { SectionLabel(text: L.s("admin.news")) }
                .themedRows()

                Section {
                    ForEach(data.packages) { p in
                        DisclosureGroup {
                            if p.sites.isEmpty { Text(L.s("admin.noSites")).font(.footnote).foregroundStyle(Theme.text3) }
                            ForEach(p.sites, id: \.self) { s in
                                HStack {
                                    Circle().fill(s.paused ? Theme.paused : (s.status == "down" ? Theme.down : Theme.up)).frame(width: 8, height: 8)
                                    Text(s.url.replacingOccurrences(of: "https://", with: "")).font(.footnote).foregroundStyle(Theme.text2).lineLimit(1)
                                    Spacer()
                                    Text(CheckInterval.label(s.intervalMin)).font(.caption).foregroundStyle(Theme.text3)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).foregroundStyle(Theme.text)
                                Text(L.s("admin.packageMeta", p.members, p.sites.count,
                                         Date(timeIntervalSince1970: p.createdAt / 1000).formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: L.locale))))
                                    .font(.footnote).foregroundStyle(Theme.text3)
                            }
                        }
                    }
                } header: { SectionLabel(text: L.s("admin.allPackages")) }
                .themedRows()
            } else if let error {
                Text(error).foregroundStyle(Theme.warn).themedRow()
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .themedList()
        .navigationTitle(L.s("admin.title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { data = try await store.admin(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func metric(_ value: String, _ label: String, limit: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.heavy)).monospacedDigit().foregroundStyle(Theme.text)
            Text(limit.map { "\(label) / \($0)" } ?? label).font(.caption).foregroundStyle(Theme.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "created": return "plus.square.fill"
        case "deleted": return "trash.fill"
        case "joined": return "person.badge.plus"
        default: return "shippingbox.fill"
        }
    }

    private func color(_ kind: String) -> Color {
        switch kind {
        case "created": return Theme.up
        case "deleted": return Theme.down
        default: return Theme.accent
        }
    }
}
