import Foundation
import SwiftUI
import UIKit
@preconcurrency import UserNotifications

/// Uygulamanın durumu: siteler sunucudan gelir, değişiklikler sunucuya gönderilir.
@MainActor
final class SiteStore: ObservableObject {
    static let shared = SiteStore()

    @Published private(set) var sites: [Site] = []
    @Published private(set) var packages: [SitePackage] = []
    @Published private(set) var isAdmin = false
    @Published private(set) var lastCronAt: Date?
    /// Sunucunun bu cihaza son bildirim denemesi (zaman, "sent" ya da hata).
    @Published private(set) var lastPush: SiteState.PushInfo?
    /// Sunucunun istediği en düşük derleme; bunun altındaysa "Güncelleme gerekli" ekranı gösterilir.
    /// Çevrimdışı açılışta da geçerli olsun diye saklanır.
    @Published private(set) var minBuild = UserDefaults.standard.integer(forKey: "minBuild")
    var updateRequired: Bool { !demo && (Int(AppInfo.build) ?? 0) < minBuild }
    @Published private(set) var loading = false
    @Published private(set) var loadedOnce = false
    @Published var lastError: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var pushToken: String?
    @Published private(set) var notificationsAllowed: Bool?
    /// Bildirime dokunulunca açılacak site
    @Published var openSiteId: String?

    let api = APIClient.shared
    let demo = ProcessInfo.processInfo.arguments.contains("-UpSiteDemo")
    private var syncTask: Task<Void, Never>?

    private init() {
        if demo {
            (packages, sites, lastCronAt) = DemoData.state()
            loadedOnce = true
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-UpSiteOpenSite"), i + 1 < args.count { openSiteId = args[i + 1] }
        }
        Prefs.shared.onServerSettingsChange = { [weak self] in self?.scheduleDeviceSync() }
    }

    var downSites: [Site] { sites.filter { $0.displayStatus == .down } }
    var upCount: Int { sites.filter { $0.displayStatus == .up }.count }

    func sites(in pkg: SitePackage) -> [Site] { sites.filter { $0.packageId == pkg.id } }
    func package(_ id: String?) -> SitePackage? { packages.first { $0.id == id } }

    /// Sunucu kontrolleri gecikiyor mu (son tur 5 dakikadan eski)?
    var serverLate: Bool {
        guard !demo, let lastCronAt else { return false }
        return Date().timeIntervalSince(lastCronAt) > 5 * 60
    }

    func site(_ id: String) -> Site? { sites.first { $0.id == id } }

    // MARK: Yükleme

    func refresh() async {
        if demo { return }
        guard api.isConfigured else { lastError = APIError.notConfigured.errorDescription; loadedOnce = true; return }
        loading = true
        defer { loading = false; loadedOnce = true }
        do {
            let s = try await api.state()
            sites = s.sites
            packages = s.packages ?? []
            isAdmin = s.isAdmin ?? false
            lastCronAt = s.lastCronAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            lastPush = s.lastPush
            if let m = s.minBuild, m != minBuild {
                minBuild = m
                UserDefaults.standard.set(m, forKey: "minBuild")
            }
            lastRefresh = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Site işlemleri

    func add(url: String, name: String, interval: Int, notifyDown: Bool, notifyUp: Bool, trackCert: Bool, packageId: String?) async throws -> Site {
        let site: Site
        if demo {
            site = DemoData.newSite(url: url, name: name, interval: interval, packageId: packageId ?? packages.first?.id)
        } else {
            site = try await api.addSite(url: url, name: name, interval: interval, notifyDown: notifyDown, notifyUp: notifyUp, packageId: packageId)
        }
        sites.append(site)
        // İlk sitede sunucu kişisel paketi kendisi oluşturur; paket listesini tazele.
        if !demo && (site.packageId == nil || package(site.packageId) == nil) { await refresh() }
        if !trackCert { Prefs.shared.certExcluded.insert(site.id) }
        await requestNotificationPermissionIfNeeded()
        if !demo {
            // İlk kontrolün sonucunu birkaç saniye sonra getir.
            Task { try? await Task.sleep(nanoseconds: 4_000_000_000); await self.refresh() }
        }
        return site
    }

    func update(_ site: Site, name: String? = nil, interval: Int? = nil, notifyDown: Bool? = nil, notifyUp: Bool? = nil, paused: Bool? = nil) async {
        var f: [String: Any] = [:]
        if let name { f["name"] = name }
        if let interval { f["intervalMin"] = interval }
        if let notifyDown { f["notifyDown"] = notifyDown }
        if let notifyUp { f["notifyUp"] = notifyUp }
        if let paused { f["paused"] = paused }
        guard let i = sites.firstIndex(where: { $0.id == site.id }) else { return }
        if demo {
            if let name { sites[i].name = name }
            if let interval { sites[i].intervalMin = interval }
            if let notifyDown { sites[i].notifyDown = notifyDown }
            if let notifyUp { sites[i].notifyUp = notifyUp }
            if let paused { sites[i].paused = paused }
            return
        }
        do {
            var updated = try await api.updateSite(site.id, f)
            // PATCH yanıtında son sonuçlar yok; eldeki geçmişi koru.
            if updated.recent.isEmpty { updated.recent = sites[i].recent; updated.lastCheckAt = sites[i].lastCheckAt; updated.lastCode = sites[i].lastCode }
            if let j = sites.firstIndex(where: { $0.id == site.id }) { sites[j] = updated }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(_ site: Site) async {
        if !demo {
            do { try await api.deleteSite(site.id) } catch { lastError = error.localizedDescription; return }
        }
        sites.removeAll { $0.id == site.id }
        Prefs.shared.certExcluded.remove(site.id)
    }

    func checkNow(_ site: Site) async {
        if demo { return }
        do {
            let s = try await api.checkNow(site.id)
            if let i = sites.firstIndex(where: { $0.id == s.id }) { sites[i] = s }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func history(_ site: Site) async -> SiteHistory? {
        if demo { return DemoData.history(for: site) }
        return try? await api.history(site.id)
    }

    // MARK: Paketler

    func createPackage(name: String) async throws -> SitePackage {
        if demo {
            let p = SitePackage(id: UUID().uuidString, name: name, key: "DEMO7K2PQ9XA", isOwner: true, members: 1, retries: 2, timeoutS: 15, createdAt: Date().timeIntervalSince1970 * 1000)
            packages.append(p)
            return p
        }
        let p = try await api.createPackage(name: name)
        packages.append(p)
        return p
    }

    func joinPackage(key: String) async throws -> SitePackage {
        if demo { throw APIError.server(404, "invalid-key") }
        let p = try await api.joinPackage(key: key)
        await refresh()
        return p
    }

    func updatePackage(_ pkg: SitePackage, name: String? = nil, retries: Int? = nil, timeoutS: Int? = nil) async {
        var f: [String: Any] = [:]
        if let name { f["name"] = name }
        if let retries { f["retries"] = retries }
        if let timeoutS { f["timeoutS"] = timeoutS }
        guard let i = packages.firstIndex(where: { $0.id == pkg.id }) else { return }
        if demo {
            if let name { packages[i].name = name }
            if let retries { packages[i].retries = retries }
            if let timeoutS { packages[i].timeoutS = timeoutS }
            return
        }
        do {
            let p = try await api.updatePackage(pkg.id, f)
            if let j = packages.firstIndex(where: { $0.id == p.id }) { packages[j] = p }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func rotateKey(_ pkg: SitePackage) async throws {
        let p = try await api.rotateKey(pkg.id)
        if let i = packages.firstIndex(where: { $0.id == p.id }) { packages[i] = p }
    }

    /// Paketten ayrılır; sahibi "sil" derse paket herkes için silinir.
    func leave(_ pkg: SitePackage, delete: Bool) async throws {
        if !demo {
            if delete { try await api.deletePackage(pkg.id) } else { try await api.leavePackage(pkg.id) }
        }
        let gone = Set(sites(in: pkg).map(\.id))
        packages.removeAll { $0.id == pkg.id }
        sites.removeAll { gone.contains($0.id) }
    }

    func admin() async throws -> AdminState {
        try await api.admin()
    }

    // MARK: Veri

    func clearHistory() async -> Bool {
        if demo { return true }
        do { try await api.clearHistory(); await refresh(); return true } catch { lastError = error.localizedDescription; return false }
    }

    func deleteAllData() async -> Bool {
        if !demo {
            do { try await api.deleteDevice() } catch { lastError = error.localizedDescription; return false }
        }
        api.resetIdentity()
        sites = []
        packages = []
        isAdmin = false
        lastCronAt = nil
        CertStore.shared.clear()
        Prefs.shared.resetAll()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        if !demo { await syncDevice() }
        return true
    }

    // MARK: Bildirimler ve cihaz ayarları

    func refreshNotificationStatus() async {
        if demo { notificationsAllowed = true; pushToken = pushToken ?? "demo"; return }
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsAllowed = true
            UIApplication.shared.registerForRemoteNotifications()
        case .denied: notificationsAllowed = false
        default: notificationsAllowed = nil
        }
    }

    func requestNotificationPermissionIfNeeded() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        if s.authorizationStatus == .notDetermined {
            let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            notificationsAllowed = ok
            if ok { UIApplication.shared.registerForRemoteNotifications() }
        } else {
            await refreshNotificationStatus()
        }
    }

    func didRegister(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        pushToken = hex
        Task { await syncDevice() }
    }

    private func scheduleDeviceSync() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            await syncDevice()
        }
    }

    func syncDevice() async {
        if demo || !api.isConfigured { return }
        var f = Prefs.shared.serverFields
        if let pushToken {
            f["apnsToken"] = pushToken
            #if DEBUG
            f["apnsEnv"] = "sandbox"
            #else
            f["apnsEnv"] = "production"
            #endif
        }
        do { try await api.updateDevice(f) } catch { lastError = error.localizedDescription }
    }

    /// (başarılı mı, mesaj)
    func sendTestPush() async -> (Bool, String) {
        if demo { return (true, L.s("push.test.sent")) }
        await requestNotificationPermissionIfNeeded()
        if notificationsAllowed == false { return (false, L.s("push.denied")) }
        if pushToken == nil {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        guard pushToken != nil else { return (false, L.s("error.noToken")) }
        await syncDevice()
        do {
            let r = try await api.testPush()
            return r.outcome == "sent" ? (true, L.s("push.test.sent")) : (false, L.s("push.test.failed", r.reason ?? r.outcome))
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
