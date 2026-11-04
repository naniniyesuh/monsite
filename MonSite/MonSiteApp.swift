import SwiftUI
import UserNotifications

@main
struct MonSiteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = MonitorStore.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("Tarama", systemImage: "magnifyingglass") }
                MonitorsView()
                    .tabItem { Label("İzleme", systemImage: "clock.arrow.2.circlepath") }
                    .badge(store.monitors.filter { $0.latest?.diff?.hasRegressions == true }.count)
            }
            .environmentObject(store)
            .task { await ForegroundScheduler.loop() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { BackgroundScheduler.schedule() }
        }
        .backgroundTask(.appRefresh(BackgroundScheduler.refreshID)) {
            await BackgroundScheduler.handleRefresh()
        }
    }
}
