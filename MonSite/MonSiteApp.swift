import SwiftUI
import UIKit
import UserNotifications

@main
struct MonSiteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = MonitorStore.shared
    @StateObject private var demo = DemoDirector.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Gezinme çubuğundaki "Geri" düğmesi, uyarılar ve sistem kontrolleri de marka rengini kullansın.
        UIView.appearance().tintColor = UIColor(named: "AccentColor")
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $demo.tab) {
                ContentView()
                    .tabItem { Label("Tarama", systemImage: "magnifyingglass") }
                    .tag(0)
                MonitorsView()
                    .tabItem { Label("İzleme", systemImage: "clock.arrow.2.circlepath") }
                    .badge(store.monitors.filter { $0.latest?.diff?.hasRegressions == true }.count)
                    .tag(1)
            }
            .environmentObject(store)
            .tint(Color.brand)
            .task {
                LaunchOptions.applyDemoMonitor(store)
                demo.startIfNeeded(store: store)
                await ForegroundScheduler.loop()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { BackgroundScheduler.schedule() }
        }
        .backgroundTask(.appRefresh(BackgroundScheduler.refreshID)) {
            await BackgroundScheduler.handleRefresh()
        }
    }
}

/// Otomatik ekran görüntüsü, tanıtım videosu ve test için başlangıç argümanları.
/// Normal kullanımda (argüman verilmeden açıldığında) hiçbir etkisi yoktur.
///   -MonSitePrefill <adres>       Adres kutusunu doldurur
///   -MonSiteAutoScan <adres>      Açılışta taramayı başlatır
///   -MonSiteSlowDemo              Ağ isteklerini yavaşlatır (ilerleme ekranı görünsün diye)
///   -MonSiteOpenArea <alan>       Rapor gelince bir alanın sorunlarını açar (links, performance, accessibility, seo, security)
///   -MonSiteDemoMonitor <adres>   Bu adres için izleme ekler ve birkaç kez kontrol eder
///   -MonSiteMonitorsTab           İzleme sekmesiyle açılır
///   -MonSiteOpenMonitor           İzleme kontrolleri bitince ilk izlemenin ayrıntısını açar
///   -MonSiteDemoTour <adres>      Tanıtım videosu: adres yazılır, taranır, rapor ve izleme gösterilir
enum LaunchOptions {
    private static let args = ProcessInfo.processInfo.arguments

    private static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var tourURL: String? { value(after: "-MonSiteDemoTour") }
    static var prefillURL: String? { value(after: "-MonSitePrefill") }
    static var autoScanURL: String? { value(after: "-MonSiteAutoScan") ?? tourURL }
    static var startOnMonitors: Bool { args.contains("-MonSiteMonitorsTab") }
    static var openMonitor: Bool { args.contains("-MonSiteOpenMonitor") }
    static var openArea: ScoreArea? {
        if let v = value(after: "-MonSiteOpenArea") { return ScoreArea(rawValue: v) }
        return tourURL != nil ? .accessibility : nil
    }
    static var demoMonitorURL: String? { value(after: "-MonSiteDemoMonitor") ?? tourURL }

    @MainActor
    static func applyDemoMonitor(_ store: MonitorStore) {
        guard let raw = demoMonitorURL, let url = normalizeSiteURL(raw) else { return }
        if store.monitors.contains(where: { $0.urlString == url.absoluteString }) { return }
        var m = Monitor(name: url.host ?? raw, urlString: url.absoluteString, intervalMinutes: 60)
        m.notifyOnChange = false
        m.config.maxPages = 15
        m.config.maxDepth = 1
        store.add(m)
        let runs = tourURL != nil ? 2 : 4
        Task {
            // Eğilim grafiği ve fark ekranı için birkaç kontrol arka arkaya
            for _ in 0..<runs {
                store.runNow(m.id)
                try? await Task.sleep(nanoseconds: 300_000_000)
                while store.runningID != nil || !store.queue.isEmpty {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            DemoDirector.shared.monitorsReady = true
        }
    }
}

/// Ekran görüntüsü ve tanıtım videosu için ekranlar arasında otomatik gezinir.
@MainActor
final class DemoDirector: ObservableObject {
    static let shared = DemoDirector()

    @Published var tab = LaunchOptions.startOnMonitors ? 1 : 0
    @Published var area: ScoreArea?
    @Published var showMonitor = false
    @Published var reportReady = false
    @Published var monitorsReady = false

    private var started = false

    func startIfNeeded(store: MonitorStore) {
        guard !started else { return }
        started = true
        let isTour = LaunchOptions.tourURL != nil
        guard isTour || LaunchOptions.openArea != nil || LaunchOptions.openMonitor else { return }
        Task {
            if let a = LaunchOptions.openArea, LaunchOptions.autoScanURL != nil {
                await wait { self.reportReady }
                await pause(isTour ? 4.5 : 1.5)
                area = a
                if isTour {
                    await pause(4.5)
                    area = nil
                    await pause(1.5)
                }
            }
            if isTour {
                tab = 1
            }
            if LaunchOptions.openMonitor || isTour {
                await wait { self.monitorsReady }
                await pause(isTour ? 2.5 : 1)
                showMonitor = true
            }
        }
    }

    private func wait(_ cond: @escaping () -> Bool) async {
        while !cond() { try? await Task.sleep(nanoseconds: 200_000_000) }
    }

    private func pause(_ sec: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(sec * 1_000_000_000))
    }
}
