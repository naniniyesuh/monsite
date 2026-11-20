import SwiftUI

struct AddSiteView: View {
    /// Açılırken seçili paket (nil: ilk paket)
    var packageId: String? = nil
    @EnvironmentObject private var store: SiteStore
    @State private var selectedPackage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var interval = CheckInterval.defaultValue
    @State private var notifyDown = true
    @State private var notifyUp = true
    @State private var trackCert = true
    @State private var saving = false
    @State private var error: String?
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.s("add.address")).font(.caption).foregroundStyle(Theme.text3)
                        TextField("example.com", text: $url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                            .submitLabel(.done)
                            .focused($urlFocused)
                    }
                    .themedRow()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.s("add.name")).font(.caption).foregroundStyle(Theme.text3)
                        TextField(L.s("add.namePlaceholder"), text: $name)
                    }
                    .themedRow()
                } header: {
                    SectionLabel(text: L.s("add.site"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let error { Text(error).foregroundStyle(Theme.down) }
                        Text(L.s("add.rule"))
                    }
                }

                Section {
                    IntervalPicker(selection: $interval).themedRow()
                } header: {
                    SectionLabel(text: L.s("add.interval"))
                }

                if store.packages.count > 1 {
                    Section {
                        Picker(L.s("add.package"), selection: $selectedPackage) {
                            ForEach(store.packages) { p in
                                Text(p.members > 1 ? "\(p.name) · \(L.s("package.membersShort", p.members))" : p.name).tag(Optional(p.id))
                            }
                        }
                        .themedRow()
                    } header: {
                        SectionLabel(text: L.s("add.package"))
                    } footer: {
                        if (store.package(selectedPackage)?.members ?? 1) > 1 { Text(L.s("add.packageShared")) }
                    }
                }

                Section {
                    Toggle(L.s("notify.down"), isOn: $notifyDown).themedRow()
                    Toggle(L.s("notify.up"), isOn: $notifyUp).themedRow()
                    Toggle(isOn: $trackCert) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.s("add.trackCert"))
                            Text(L.s("add.trackCert.hint")).font(.footnote).foregroundStyle(Theme.text3)
                        }
                    }
                    .themedRow()
                } header: {
                    SectionLabel(text: L.s("detail.notifications"))
                } footer: {
                    Text(L.s("add.serverNote"))
                }
                .tint(Theme.barUp)
            }
            .themedList()
            .navigationTitle(L.s("sites.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.s("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button(L.s("action.add")) { save() }
                            .fontWeight(.bold)
                            .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear {
                selectedPackage = packageId ?? store.packages.first?.id
                // Ekran görüntüleri için: -UpSiteAddInterval 3
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-UpSiteAddInterval"), i + 1 < args.count, let m = Int(args[i + 1]) {
                    url = "example.com"
                    interval = CheckInterval.clamp(m)
                } else {
                    urlFocused = true
                }
            }
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                _ = try await store.add(url: url, name: name, interval: interval,
                                        notifyDown: notifyDown, notifyUp: notifyUp, trackCert: trackCert,
                                        packageId: selectedPackage ?? store.packages.first?.id)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}

struct EditSiteView: View {
    let site: Site
    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var interval = CheckInterval.defaultValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.s("add.name"), text: $name).themedRow()
                    Text(site.url).foregroundStyle(Theme.text3).themedRow()
                } header: { SectionLabel(text: L.s("add.site")) }
                Section {
                    IntervalPicker(selection: $interval).themedRow()
                } header: { SectionLabel(text: L.s("add.interval")) }
            }
            .themedList()
            .navigationTitle(L.s("edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.s("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("action.save")) {
                        Task {
                            await store.update(site, name: name == site.name ? nil : name,
                                               interval: interval == site.intervalMin ? nil : interval)
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                name = site.name
                interval = CheckInterval.clamp(site.intervalMin)
            }
        }
    }
}

struct IntervalPicker: View {
    @Binding var selection: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(CheckInterval.presets, id: \.self) { m in
                let on = m == selection
                Button { selection = m } label: {
                    Text(CheckInterval.label(m))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(on ? .white : Theme.text)
                        .background(on ? Theme.accentFill : Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.accentFill : Theme.border))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}
