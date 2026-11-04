import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ScanViewModel()
    @FocusState private var urlFocused: Bool
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var showLog = false
    @State private var watchURL: String?
    @EnvironmentObject private var monitors: MonitorStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    inputCard
                    if vm.isRunning {
                        progressCard
                    } else if let r = vm.report {
                        lastReportCard(r)
                        watchButton(r)
                    } else {
                        featureGrid
                    }
                    settingsCard
                    if !vm.log.isEmpty { logCard }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                if let url = LaunchOptions.prefillURL, vm.urlText.isEmpty { vm.urlText = url }
                if let url = LaunchOptions.autoScanURL, vm.report == nil, !vm.isRunning {
                    if LaunchOptions.tourURL != nil {
                        // Tanıtım videosu: adres harf harf yazılır
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        vm.urlText = ""
                        for ch in url {
                            vm.urlText.append(ch)
                            try? await Task.sleep(nanoseconds: 110_000_000)
                        }
                        try? await Task.sleep(nanoseconds: 700_000_000)
                    } else {
                        vm.urlText = url
                    }
                    vm.start()
                }
            }
            .onChange(of: vm.showReport) { shown in
                if shown { DemoDirector.shared.reportReady = true }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: Binding(get: { watchURL.map(WatchTarget.init) }, set: { watchURL = $0?.url })) { t in
                MonitorEditView(prefillURL: t.url)
            }
            .navigationDestination(isPresented: $vm.showReport) {
                if let r = vm.report { ReportView(report: r) }
            }
        }
    }

    // MARK: Başlık

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("MonSite").font(.title2.weight(.bold))
                Text("Web sitesi sağlık ve güvenlik denetimi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Hakkında")
        }
        .padding(.top, 12)
        .sheet(isPresented: $showAbout) { AboutView() }
    }

    // MARK: Adres girişi

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                TextField("ornek.com", text: $vm.urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($urlFocused)
                    .onSubmit(startScan)
                    .disabled(vm.isRunning)
                if !vm.urlText.isEmpty && !vm.isRunning {
                    Button { vm.urlText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Temizle")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(urlFocused ? Color.brand : .clear, lineWidth: 1.5)
            )

            if let err = vm.inputError {
                Label(err, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if vm.isRunning {
                Button(role: .destructive) { vm.cancel() } label: {
                    Label("Taramayı durdur", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button(action: startScan) {
                    Label("Taramayı başlat", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .card()
    }

    private func startScan() {
        urlFocused = false
        vm.start()
    }

    // MARK: Boş durum

    private struct Feature: Identifiable {
        let icon: String
        let title: String
        let subtitle: String
        var id: String { title }
    }

    private var featureGrid: some View {
        let items = [
            Feature(icon: "link", title: "Bağlantılar", subtitle: "Kırık sayfa ve dosyalar"),
            Feature(icon: "speedometer", title: "Performans", subtitle: "Yükleme süreleri"),
            Feature(icon: "shield.lefthalf.filled", title: "Güvenlik", subtitle: "Başlıklar ve açıklar"),
            Feature(icon: "lock.shield", title: "SSL", subtitle: "Sertifika ve süresi")
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(items) { f in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: f.icon)
                        .font(.title3)
                        .foregroundStyle(Color.brand)
                        .frame(width: 36, height: 36)
                        .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    Text(f.title).font(.subheadline.weight(.semibold))
                    Text(f.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14)
            }
        }
    }

    // MARK: İlerleme

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            StageIndicator(stages: ScanViewModel.stages, current: vm.stage)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(vm.phase).font(.headline)
                }
                if vm.resourcesTotal > 0 {
                    ProgressView(value: Double(vm.resourcesDone), total: Double(vm.resourcesTotal))
                        .tint(Color.brand)
                    Text("\(vm.resourcesDone) / \(vm.resourcesTotal)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                Metric(value: "\(vm.scannedPages)", label: "Sayfa")
                Divider().frame(height: 32)
                Metric(value: "\(vm.resourcesTotal)", label: "Kaynak")
                Divider().frame(height: 32)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let sec = vm.startedAt.map { Int(ctx.date.timeIntervalSince($0)) } ?? 0
                    Metric(value: String(format: "%d:%02d", sec / 60, sec % 60), label: "Süre")
                }
            }

            if !vm.currentURL.isEmpty {
                Text(shortURL(vm.currentURL))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .card()
    }

    // MARK: Son rapor

    private func lastReportCard(_ r: ScanReport) -> some View {
        NavigationLink {
            ReportView(report: r)
        } label: {
            HStack(spacing: 14) {
                ScoreRing(score: r.score, grade: r.grade, size: 56, lineWidth: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.host).font(.headline).foregroundStyle(.primary)
                    Text(r.verdict).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(r.pages.count) sayfa · \(r.issues.filter { $0.severity <= .warning }.count) sorun")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func watchButton(_ r: ScanReport) -> some View {
        let watched = monitors.monitors.contains { URL(string: $0.urlString)?.visitKey == URL(string: r.startURL)?.visitKey }
        if !watched {
            Button {
                watchURL = r.startURL
            } label: {
                Label("Bu siteyi düzenli izle", systemImage: "clock.arrow.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: Ayarlar

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() }
            } label: {
                HStack {
                    Label("Tarama ayarları", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(vm.config.maxPages) sayfa · derinlik \(vm.config.maxDepth)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showSettings ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSettings {
                VStack(spacing: 0) {
                    SettingStepper(title: "En fazla sayfa", value: $vm.config.maxPages, range: 5...1000, step: 5) { "\($0)" }
                    SettingStepper(title: "Bağlantı derinliği", value: $vm.config.maxDepth, range: 0...10, step: 1) { "\($0)" }
                    SettingStepper(title: "Eşzamanlı istek", value: $vm.config.concurrency, range: 1...10, step: 1) { "\($0)" }
                    SettingStepper(title: "Yavaş sayfa eşiği", value: $vm.config.slowPageMs, range: 500...10000, step: 500) {
                        formatMs(Double($0))
                    }
                    Toggle("Dış bağlantıları kontrol et", isOn: $vm.config.checkExternalLinks)
                        .font(.subheadline)
                        .padding(.vertical, 10)
                    Divider()
                    Toggle("robots.txt kurallarına uy", isOn: $vm.config.respectRobots)
                        .font(.subheadline)
                        .padding(.vertical, 10)
                    Divider()
                    Toggle("Sitemap'teki sayfaları da tara", isOn: $vm.config.useSitemap)
                        .font(.subheadline)
                        .padding(.vertical, 10)
                    Divider()
                    ProbeToggle(isOn: $vm.config.probeSensitivePaths)
                        .font(.subheadline)
                        .padding(.vertical, 10)
                    Text("Hassas dosya taraması .git, .env ve yedek dosyaları gibi yaygın açıkları arar. Yalnızca size ait veya test izniniz olan sitelerde kullanın.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 8)
                .disabled(vm.isRunning)
                .transition(.opacity)
            }
        }
        .card()
    }

    // MARK: Kayıt

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLog.toggle() }
            } label: {
                HStack {
                    Label("Ayrıntılı kayıt", systemImage: "terminal")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showLog ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showLog { LogView(lines: vm.log) }
        }
        .card()
    }
}

// MARK: - Bileşenler

extension Color {
    /// Marka vurgu rengi (Assets → AccentColor). Sistemin varsayılan mavisine düşmemesi için
    /// her yerde doğrudan bu renk kullanılır.
    static let brand = Color("AccentColor")
}

/// Hassas dosya taramasını açmadan önce site sahipliğini onaylatır.
struct ProbeToggle: View {
    @Binding var isOn: Bool
    @State private var confirming = false

    var body: some View {
        Toggle("Hassas dosya taraması", isOn: Binding(
            get: { isOn },
            set: { newValue in
                if newValue { confirming = true } else { isOn = false }
            }))
            .font(.subheadline)
            .confirmationDialog("Hassas dosya taraması", isPresented: $confirming, titleVisibility: .visible) {
                Button("Bu siteyi yönetiyorum, aç") { isOn = true }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Bu tarama .git, .env ve yedek dosyaları gibi herkese açık kalmış hassas dosyaları arar. Yalnızca size ait veya test izniniz olan sitelerde kullanın.")
            }
    }
}

private struct WatchTarget: Identifiable {
    let url: String
    var id: String { url }
}

struct BrandMark: View {
    var size: CGFloat = 44

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

private struct Metric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StageIndicator: View {
    let stages: [String]
    let current: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.offset) { i, name in
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(i < current ? Color.brand : i == current ? Color.brand.opacity(0.15) : Color(.tertiarySystemFill))
                            .frame(width: 26, height: 26)
                        if i < current {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(i + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(i == current ? Color.brand : .secondary)
                        }
                    }
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(i <= current ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct SettingStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String

    var body: some View {
        VStack(spacing: 0) {
            Stepper(value: $value, in: range, step: step) {
                HStack {
                    Text(title).font(.subheadline)
                    Spacer()
                    Text(format(value))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            Divider()
        }
    }
}

private struct LogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(10)
            }
            .frame(height: 180)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .onChange(of: lines.count) { n in
                proxy.scrollTo(n - 1, anchor: .bottom)
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(MonitorStore.shared)
}
