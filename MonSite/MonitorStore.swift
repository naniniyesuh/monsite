import Foundation
import BackgroundTasks
import UserNotifications
import SwiftUI

@MainActor
final class MonitorStore: ObservableObject {
    static let shared = MonitorStore()
    static let maxRuns = 100

    @Published private(set) var monitors: [Monitor] = []
    @Published private(set) var runningID: UUID?
    @Published private(set) var queue: [UUID] = []

    private let baseDir: URL
    private let reportsDir: URL
    private var isBatchRunning = false
    private var currentTask: Task<Void, Never>?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = support.appendingPathComponent("MonSite", isDirectory: true)
        reportsDir = baseDir.appendingPathComponent("reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Kalıcılık

    private var monitorsFile: URL { baseDir.appendingPathComponent("monitors.json") }

    private func load() {
        guard let data = try? Data(contentsOf: monitorsFile),
              let list = try? ReportCodec.decoder.decode([Monitor].self, from: data) else { return }
        monitors = list
    }

    private func save() {
        guard let data = try? ReportCodec.encoder.encode(monitors) else { return }
        try? data.write(to: monitorsFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func monitor(_ id: UUID) -> Monitor? { monitors.first { $0.id == id } }

    func add(_ m: Monitor) {
        monitors.append(m)
        save()
        if m.notifyOnChange { Notifier.requestAuthorization() }
        BackgroundScheduler.schedule()
    }

    func update(_ m: Monitor) {
        guard let i = monitors.firstIndex(where: { $0.id == m.id }) else { return }
        monitors[i] = m
        save()
        if m.notifyOnChange { Notifier.requestAuthorization() }
        BackgroundScheduler.schedule()
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard var m = monitor(id) else { return }
        m.enabled = enabled
        update(m)
    }

    func delete(_ id: UUID) {
        monitors.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: reportsDir.appendingPathComponent(id.uuidString, isDirectory: true))
        save()
    }

    func clearHistory(_ id: UUID) {
        guard var m = monitor(id) else { return }
        m.runs = []
        m.lastRunAt = nil
        try? FileManager.default.removeItem(at: reportsDir.appendingPathComponent(id.uuidString, isDirectory: true))
        update(m)
    }

    func report(for run: MonitorRun) -> ScanReport? {
        let url = reportsDir.appendingPathComponent(run.reportFile)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? ReportCodec.decoder.decode(ScanReport.self, from: data)
    }

    /// Bir sonraki planlı çalışma (arka plan isteği için).
    var nextDueDate: Date? {
        monitors.filter(\.enabled).map(\.nextRunAt).min()
    }

    // MARK: Çalıştırma

    /// Elle tetiklenen tam kontrol.
    func runNow(_ id: UUID) {
        guard runningID != id, !queue.contains(id) else { return }
        queue.append(id)
        if !isBatchRunning {
            currentTask = Task { await drainQueue(quick: false) }
        }
    }

    /// Zamanı gelen tüm izlemeleri sırayla çalıştırır.
    func runDue(quick: Bool) async {
        for m in monitors where m.isDue && !queue.contains(m.id) && runningID != m.id {
            queue.append(m.id)
        }
        guard !isBatchRunning else { return }
        await drainQueue(quick: quick)
    }

    private func drainQueue(quick: Bool) async {
        isBatchRunning = true
        defer {
            isBatchRunning = false
            runningID = nil
        }
        while !queue.isEmpty && !Task.isCancelled {
            let id = queue.removeFirst()
            guard let m = monitor(id) else { continue }
            runningID = id
            await execute(m, quick: quick)
        }
        BackgroundScheduler.schedule()
    }

    private func execute(_ m: Monitor, quick: Bool) async {
        guard let url = m.url else { return }
        let config = quick ? Self.quickConfig(from: m.config) : m.config
        let crawler = SiteCrawler(startURL: url, config: config)
        let report = await crawler.run { _ in }
        guard !report.cancelled else { return }

        // Önceki aynı türden (hızlı/tam) çalışmayla karşılaştır.
        var diff: ScanDiff?
        if let prev = m.runs.first(where: { $0.quick == quick }), let old = self.report(for: prev) {
            diff = DiffEngine.diff(old: old, new: report, previousRunDate: prev.date)
        }

        let runID = UUID()
        let relPath = "\(m.id.uuidString)/\(runID.uuidString).json"
        let fileURL = reportsDir.appendingPathComponent(relPath)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? ReportCodec.encoder.encode(report) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }

        var run = MonitorRun(
            id: runID,
            date: report.finishedAt,
            durationSec: report.durationSec,
            quick: quick,
            score: report.score,
            grade: report.grade,
            pageCount: report.pages.count,
            problemCount: report.count(.critical) + report.count(.error) + report.count(.warning),
            brokenCount: report.brokenResources.count,
            avgMs: report.averagePageMs,
            certDays: report.certificate?.daysRemaining,
            reportFile: relPath,
            diff: diff)
        if let home = report.pages.first {
            run.homeOK = home.error == nil && (home.statusCode ?? 0) < 400
                && !report.issues.contains { $0.title == "Beklenen içerik bulunamadı" }
            run.homeMs = home.durationMs
            run.homeTTFBMs = home.timing?.ttfbMs
        } else {
            run.homeOK = false
        }

        // Kayıt sırasında izleme silinmiş/değişmiş olabilir; güncel halini al.
        guard var current = monitor(m.id) else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        current.runs.insert(run, at: 0)
        current.lastRunAt = Date()
        if current.runs.count > Self.maxRuns {
            for old in current.runs[Self.maxRuns...] {
                try? FileManager.default.removeItem(at: reportsDir.appendingPathComponent(old.reportFile))
            }
            current.runs = Array(current.runs.prefix(Self.maxRuns))
        }
        if let i = monitors.firstIndex(where: { $0.id == m.id }) { monitors[i] = current }
        save()

        if current.notifyOnChange, let diff, diff.hasChanges {
            Notifier.post(monitor: current, run: run, diff: diff)
        }
    }

    static func quickConfig(from c: ScanConfig) -> ScanConfig {
        var q = c
        q.maxPages = min(c.maxPages, 10)
        q.maxDepth = min(c.maxDepth, 1)
        q.timeout = 10
        q.checkExternalLinks = false
        q.probeSensitivePaths = false
        return q
    }
}

// MARK: - Uygulama açıkken zamanlayıcı

@MainActor
enum ForegroundScheduler {
    /// Uygulama ön plandayken her 20 saniyede zamanı gelen izlemeleri kontrol eder.
    static func loop() async {
        while !Task.isCancelled {
            await MonitorStore.shared.runDue(quick: false)
            try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
        }
    }
}

// MARK: - Arka plan

enum BackgroundScheduler {
    static let refreshID = "studio.alpp.monsite.refresh"

    /// iOS'tan bir sonraki arka plan çalışmasını ister. iOS zamanı kendisi belirler (genelde ≥15 dk).
    @MainActor
    static func schedule() {
        guard let next = MonitorStore.shared.nextDueDate else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = max(next, Date().addingTimeInterval(15 * 60))
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Arka plan penceresi kısa olduğu için hızlı kontrol yapılır.
    @MainActor
    static func handleRefresh() async {
        await MonitorStore.shared.runDue(quick: true)
        schedule()
    }
}

// MARK: - Bildirimler

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(monitor: Monitor, run: MonitorRun, diff: ScanDiff) {
        let content = UNMutableNotificationContent()
        content.title = diff.hasRegressions ? "\(monitor.name): sorun tespit edildi" : "\(monitor.name): değişiklik"
        content.body = "\(diff.summary)\nPuan: \(run.score) (\(run.grade))"
        content.sound = diff.hasRegressions ? .default : nil
        content.threadIdentifier = monitor.id.uuidString
        content.userInfo = ["monitorID": monitor.id.uuidString]
        let req = UNNotificationRequest(identifier: run.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

/// Uygulama açıkken de bildirim banner'ı gösterilsin.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
