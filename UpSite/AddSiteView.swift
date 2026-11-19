import SwiftUI

struct AddSiteView: View {
    @EnvironmentObject private var store: SiteStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var interval = CheckInterval.m15
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
                    AlignmentHint(interval: interval).themedRow()
                } header: {
                    SectionLabel(text: L.s("add.interval"))
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
            .onAppear { urlFocused = true }
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                _ = try await store.add(url: url, name: name, interval: interval.rawValue,
                                        notifyDown: notifyDown, notifyUp: notifyUp, trackCert: trackCert)
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
    @State private var interval = CheckInterval.m15

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.s("add.name"), text: $name).themedRow()
                    Text(site.url).foregroundStyle(Theme.text3).themedRow()
                } header: { SectionLabel(text: L.s("add.site")) }
                Section {
                    IntervalPicker(selection: $interval).themedRow()
                    AlignmentHint(interval: interval).themedRow()
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
                                               interval: interval.rawValue == site.intervalMin ? nil : interval.rawValue)
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                name = site.name
                interval = CheckInterval(rawValue: site.intervalMin) ?? .m15
            }
        }
    }
}

struct IntervalPicker: View {
    @Binding var selection: CheckInterval

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(CheckInterval.allCases) { it in
                let on = it == selection
                Button { selection = it } label: {
                    Text(it.short)
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

/// "Saat başına hizalı" açıklaması ve örnek saatler.
struct AlignmentHint: View {
    let interval: CheckInterval

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock").foregroundStyle(Theme.text3)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.s("add.aligned")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(L.s("add.alignedExample", examples)).font(.footnote).foregroundStyle(Theme.text2)
            }
        }
        .padding(.vertical, 4)
    }

    private var examples: String {
        let step = min(interval.rawValue, 60)
        let now = Date()
        let cal = Calendar.current
        let m = cal.component(.minute, from: now) + cal.component(.hour, from: now) * 60
        let first = (m / step + 1) * step
        let start = cal.startOfDay(for: now)
        return (0..<4).map { i in
            let d = start.addingTimeInterval(Double((first + i * interval.rawValue) * 60))
            return d.formatted(date: .omitted, time: .shortened)
        }.joined(separator: ", ") + "…"
    }
}
