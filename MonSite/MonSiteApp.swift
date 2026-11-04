import SwiftUI
import UserNotifications

@main
struct MonSiteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = MonitorStore.shared
    @State private var tab = LaunchOptions.startOnMonitors ? 1 : 0

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                ContentView()
                    .tabItem { Label("Tarama", systemImage: "magnifyingglass") }
                    .tag(0)
                MonitorsView()
                    .tabItem { Label("İzleme", systemImage: "clock.arrow.2.circlepath") }
                    .badge(store.monitors.filter { $0.latest?.diff?.hasRegressions == true }.count)
                    .tag(1)
            }
            .environmentObject(store)
            .task {
                LaunchOptions.applyDemoMonitor(store)
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

/// Otomatik ekran görüntüsü ve test için başlangıç argümanları (normal kullanımda etkisizdir).
///   -MonSiteAutoScan <adres>      Açılışta taramayı başlatır
///   -MonSiteDemoMonitor <adres>   Bu adres için izleme ekler ve iki kez kontrol eder
///   -MonSiteMonitorsTab           İzleme sekmesiyle açılır
enum LaunchOptions {
    private static let args = ProcessInfo.processInfo.arguments

    private static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var autoScanURL: String? { value(after: "-MonSiteAutoScan") }
    static var startOnMonitors: Bool { args.contains("-MonSiteMonitorsTab") }

    @MainActor
    static func applyDemoMonitor(_ store: MonitorStore) {
        guard let raw = value(after: "-MonSiteDemoMonitor"), let url = normalizeSiteURL(raw) else { return }
        if store.monitors.contains(where: { $0.urlString == url.absoluteString }) { return }
        var m = Monitor(name: url.host ?? raw, urlString: url.absoluteString, intervalMinutes: 60)
        m.notifyOnChange = false
        m.config.maxPages = 15
        m.config.maxDepth = 1
        store.add(m)
        store.runNow(m.id)
        Task {
            // İkinci kontrol: fark ekranı için
            while store.runningID != nil || !store.queue.isEmpty { try? await Task.sleep(nanoseconds: 500_000_000) }
            store.runNow(m.id)
        }
    }
}
