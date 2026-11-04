import Foundation
import SwiftUI

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var config = ScanConfig()

    @Published private(set) var isRunning = false
    @Published private(set) var phase = ""
    @Published private(set) var stage = 0
    @Published private(set) var currentURL = ""
    @Published private(set) var startedAt: Date?

    static let stages = ["Sayfalar", "Kaynaklar", "Güvenlik", "Sertifika"]
    @Published private(set) var scannedPages = 0
    @Published private(set) var resourcesDone = 0
    @Published private(set) var resourcesTotal = 0
    @Published private(set) var log: [String] = []
    @Published var report: ScanReport?
    @Published var showReport = false
    @Published var inputError: String?

    private var task: Task<Void, Never>?

    func normalizedURL() -> URL? { normalizeSiteURL(urlText) }

    func start() {
        guard !isRunning else { return }
        guard let url = normalizedURL() else {
            inputError = "Geçerli bir adres girin (ör. ornek.com)"
            return
        }
        inputError = nil
        report = nil
        log = []
        scannedPages = 0
        resourcesDone = 0
        resourcesTotal = 0
        isRunning = true
        stage = 0
        currentURL = ""
        startedAt = Date()
        append("Başlatıldı: \(url.absoluteString)")

        let crawler = SiteCrawler(startURL: url, config: config)
        task = Task {
            let result = await crawler.run { [weak self] event in
                await self?.handle(event)
            }
            self.report = result
            self.isRunning = false
            self.showReport = true
        }
    }

    func cancel() {
        task?.cancel()
        append("İptal ediliyor…")
    }

    private func handle(_ e: ScanEvent) {
        switch e {
        case .phase(let p):
            phase = p
            switch p {
            case "Sayfalar taranıyor": stage = 0
            case "Kaynaklar kontrol ediliyor": stage = 1
            case "Güvenlik kontrolleri": stage = 2
            case "Sertifika kontrol ediliyor": stage = 3
            default: stage = 4
            }
            append("— \(p)")
            resourcesDone = 0
            resourcesTotal = 0
        case let .page(url, status, ms, scanned):
            scannedPages = scanned
            currentURL = url
            append("\(status.map { "\($0)" } ?? "ERR")  \(formatMs(ms))  \(shortURL(url))")
        case let .resources(done, total):
            resourcesDone = done
            resourcesTotal = total
        case .log(let s):
            append(s)
        }
    }

    private func append(_ s: String) {
        log.append(s)
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}
