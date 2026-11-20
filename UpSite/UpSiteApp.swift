import SwiftUI
import UIKit
@preconcurrency import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in SiteStore.shared.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Bildirim kaydı başarısız: \(error.localizedDescription)")
    }

    // Uygulama açıkken de bildirim göster
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
        Task { @MainActor in await SiteStore.shared.refresh() }
    }

    // Bildirime dokunulunca ilgili siteyi aç
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let siteId = info["siteId"] as? String
        let isCert = response.notification.request.identifier.hasPrefix("cert.")
        Task { @MainActor in
            if isCert { RootRouter.shared.tab = .certificates }
            else if let siteId {
                RootRouter.shared.tab = .sites
                SiteStore.shared.openSiteId = siteId
            }
            await SiteStore.shared.refresh()
        }
        completionHandler()
    }
}

@MainActor
final class RootRouter: ObservableObject {
    static let shared = RootRouter()
    enum Tab: Hashable { case sites, certificates, settings }
    @Published var tab: Tab = .sites

    init() {
        // Ekran görüntüleri için: -UpSiteTab certs|settings
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-UpSiteTab"), i + 1 < args.count {
            switch args[i + 1] {
            case "certs": tab = .certificates
            case "settings": tab = .settings
            default: tab = .sites
            }
        }
    }
}

@main
struct UpSiteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SiteStore.shared
    @StateObject private var certs = CertStore.shared
    @StateObject private var prefs = Prefs.shared
    @StateObject private var router = RootRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(certs)
                .environmentObject(prefs)
                .environmentObject(router)
                .preferredColorScheme(prefs.colorScheme)
                .tint(Theme.accent)
                .id(prefs.language)
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await store.refreshNotificationStatus()
                await store.refresh()
                await store.syncDevice()
                await certs.checkAll(store.sites)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var router: RootRouter
    @EnvironmentObject private var store: SiteStore

    var body: some View {
        // TabView her zaman yerinde kalır; güncelleme ekranı üstüne kapanır.
        tabs.overlay {
            if store.updateRequired { UpdateRequiredView() }
        }
    }

    private var tabs: some View {
        TabView(selection: $router.tab) {
            SitesView()
                .tabItem { Label(L.s("tab.sites"), systemImage: "waveform.path.ecg") }
                .tag(RootRouter.Tab.sites)
            CertificatesView()
                .tabItem { Label(L.s("tab.certs"), systemImage: "checkmark.shield") }
                .tag(RootRouter.Tab.certificates)
            SettingsView()
                .tabItem { Label(L.s("tab.settings"), systemImage: "gearshape") }
                .tag(RootRouter.Tab.settings)
        }
        .toolbarBackground(Theme.tabBar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

/// Sunucu daha yeni bir sürüm istediğinde uygulamanın tamamını kaplayan ekran.
struct UpdateRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            LogoMark(size: 88)
            Text(L.s("update.title"))
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(L.s("update.body"))
                .font(.body)
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L.s("update.button")) { openURL(AppInfo.appStoreURL) }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}
