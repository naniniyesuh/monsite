import SwiftUI

struct AddSiteView: View {
    @EnvironmentObject private var store: SiteStore
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
            .onAppear {
                // Ekran görüntüleri için: -UpSiteAddInterval 4
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
    @State private var custom = false
    @FocusState private var fieldFocused: Bool

    private var isCustom: Bool { custom || !CheckInterval.presets.contains(selection) }

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(CheckInterval.presets, id: \.self) { m in
                    chip(CheckInterval.label(m), on: !isCustom && m == selection) {
                        custom = false
                        fieldFocused = false
                        selection = m
                    }
                }
                chip(L.s("interval.custom"), on: isCustom) {
                    custom = true
                    fieldFocused = true
                }
            }
            if isCustom {
                HStack(spacing: 12) {
                    Text(L.s("interval.every")).foregroundStyle(Theme.text2)
                    TextField("4", value: Binding(get: { selection },
                                                   set: { selection = CheckInterval.clamp($0) }), format: .number)
                        .keyboardType(.numberPad)
                        .focused($fieldFocused)
                        .multilineTextAlignment(.center)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .frame(width: 56, height: 36)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
                    Text(L.s("interval.minutes")).foregroundStyle(Theme.text2)
                    Spacer(minLength: 0)
                    Stepper("", value: $selection, in: CheckInterval.range).labelsHidden()
                }
                Text(L.s("interval.customHint")).font(.footnote).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .onAppear { custom = !CheckInterval.presets.contains(selection) }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(on ? .white : Theme.text)
                .background(on ? Theme.accentFill : Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.accentFill : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// "Saat başına hizalı" açıklaması ve örnek saatler.
struct AlignmentHint: View {
    let interval: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock").foregroundStyle(Theme.text3)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.s("add.aligned")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(L.s("add.alignedExample", examples)).font(.footnote).foregroundStyle(Theme.text2)
                if 60 % CheckInterval.clamp(interval) != 0 {
                    Text(L.s("add.alignedUneven")).font(.footnote).foregroundStyle(Theme.text3)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var examples: String {
        CheckInterval.upcoming(interval, count: 4)
            .map { $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L.locale)) }
            .joined(separator: ", ") + "…"
    }
}
