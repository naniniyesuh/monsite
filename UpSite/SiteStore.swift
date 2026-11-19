import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Uygulamanın durumu: siteler sunucudan gelir, değişiklikler sunucuya gönderilir.
@MainActor
final class SiteStore: ObservableObject {
    static let shared = SiteStore()

    @Published private(set) var sites: [Site] = []
    @Published private(set) var lastCronAt: Date?
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
            (sites, lastCronAt) = DemoData.state()
            loadedOnce = true
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-UpSiteOpenSite"), i + 1 < args.count { openSiteId = args[i + 1] }
        }
        Prefs.shared.onServerSettingsChange = { [weak self] in self?.scheduleDeviceSync() }
    }

    var downSites: [Site] { sites.filter { $0.displayStatus == .down } }
    var upCount: Int { sites.filter { $0.displayStatus == .up }.count }
    var nextCheck: Date? { sites.compactMap(\.nextCheck).filter { $0 > Date().addingTimeInterval(-60) }.min() }

    /// Sunucu kontrolleri gecikiyor mu (son tur 35 dakikadan eski)?
    var serverLate: Bool {
        guard !demo, let lastCronAt else { return false }
        return Date().timeIntervalSince(lastCronAt) > 35 * 60
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
            lastCronAt = s.lastCronAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            lastRefresh = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Site işlemleri

    func add(url: String, name: String, interval: Int, notifyDown: Bool, notifyUp: Bool, trackCert: Bool) async throws -> Site {
        let site: Site
        if demo {
            site = DemoData.newSite(url: url, name: name, interval: interval)
        } else {
            site = try await api.addSite(url: url, name: name, interval: interval, notifyDown: notifyDown, notifyUp: notifyUp)
        }
        sites.append(site)
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

    // MARK: Veri

    func exportFile() -> URL? {
        let file = SiteListFile(sites: sites.map { .init(url: $0.url, name: $0.name, intervalMin: $0.intervalMin, notifyDown: $0.notifyDown, notifyUp: $0.notifyUp) })
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(file) else { return nil }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UpSite-siteler-\(df.string(from: Date())).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// İçe aktarır; (eklenen, atlanan) sayısını döndürür.
    func importFile(_ url: URL) async -> (added: Int, skipped: Int) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return (0, 0) }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let file = try? dec.decode(SiteListFile.self, from: data) else { return (0, 0) }
        var added = 0, skipped = 0
        let existing = Set(sites.map { $0.url.lowercased() })
        for e in file.sites {
            if existing.contains(e.url.lowercased()) { skipped += 1; continue }
            do {
                _ = try await add(url: e.url, name: e.name ?? "", interval: e.intervalMin ?? 15,
                                  notifyDown: e.notifyDown ?? true, notifyUp: e.notifyUp ?? true, trackCert: true)
                added += 1
            } catch {
                skipped += 1
            }
        }
        await refresh()
        return (added, skipped)
    }

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
