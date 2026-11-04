import Foundation

struct FetchResult: @unchecked Sendable {
    var data: Data?
    var response: HTTPURLResponse?
    var durationMs: Double
    var timing: TimingBreakdown?
    var error: String?
    var finalURL: URL?
    var cancelled = false

    var statusCode: Int? { response?.statusCode }
    func header(_ name: String) -> String? { response?.value(forHTTPHeaderField: name) }
}

/// Her istek için ağ zamanlama metriklerini toplar.
final class MetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLSessionTaskMetrics?

    var metrics: URLSessionTaskMetrics? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock(); stored = metrics; lock.unlock()
    }
}

final class HTTPFetcher: @unchecked Sendable {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 MonSite/1.0"

    let session: URLSession
    let timeout: TimeInterval

    init(timeout: TimeInterval) {
        self.timeout = timeout
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout * 3
        c.httpMaximumConnectionsPerHost = 6
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.urlCache = nil
        c.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept-Language": "tr-TR,tr;q=0.9,en;q=0.8"
        ]
        session = URLSession(configuration: c)
    }

    /// Yalnızca ekran görüntüsü/tanıtım videosu için: istekleri yavaşlatır.
    static let demoDelayNs: UInt64 = ProcessInfo.processInfo.arguments.contains("-MonSiteSlowDemo")
        || ProcessInfo.processInfo.arguments.contains("-MonSiteDemoTour") ? 260_000_000 : 0

    private func request(_ url: URL, method: String, headers: [String: String]) -> URLRequest {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }

    /// Tam istek: gövdenin tamamını indirir.
    func fetch(_ url: URL, method: String = "GET", headers: [String: String] = [:]) async -> FetchResult {
        if Self.demoDelayNs > 0 { try? await Task.sleep(nanoseconds: Self.demoDelayNs) }
        let req = request(url, method: method, headers: headers)
        let delegate = MetricsDelegate()
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, resp) = try await session.data(for: req, delegate: delegate)
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            return FetchResult(data: data, response: resp as? HTTPURLResponse, durationMs: ms,
                               timing: TimingBreakdown(metrics: delegate.metrics), error: nil, finalURL: resp.url)
        } catch {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            return FetchResult(data: nil, response: nil, durationMs: ms,
                               timing: TimingBreakdown(metrics: delegate.metrics),
                               error: Self.describe(error), finalURL: nil,
                               cancelled: Self.isCancellation(error))
        }
    }

    /// Geçici hatalarda (zaman aşımı, bağlantı kopması, 429/502/503/504) bir kez daha dener.
    /// İzlemede tek seferlik ağ aksaklıklarının "site çöktü" diye raporlanmasını önler.
    func fetchWithRetry(_ url: URL, method: String = "GET") async -> FetchResult {
        var r = await fetch(url, method: method)
        guard !r.cancelled else { return r }
        let transientCodes: Set<Int> = [429, 502, 503, 504]
        let permanentError = r.error.map { $0.contains("DNS") || $0.contains("Sertifika") || $0.contains("yönlendirme") } ?? false
        if (r.error != nil && !permanentError) || transientCodes.contains(r.statusCode ?? 0) {
            var wait = 1.5
            if r.statusCode == 429, let ra = r.header("Retry-After"), let sec = Double(ra) { wait = min(max(sec, 1), 5) }
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if Task.isCancelled { return r }
            let second = await fetch(url, method: method)
            if !second.cancelled { r = second }
        }
        return r
    }

    /// Sadece ilk `maxBytes` baytı okur (büyük dosyaları indirmeden kontrol etmek için).
    func fetchPrefix(_ url: URL, maxBytes: Int = 16_384) async -> FetchResult {
        if Self.demoDelayNs > 0 { try? await Task.sleep(nanoseconds: Self.demoDelayNs) }
        let req = request(url, method: "GET", headers: [:])
        let delegate = MetricsDelegate()
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (bytes, resp) = try await session.bytes(for: req, delegate: delegate)
            var data = Data()
            data.reserveCapacity(min(maxBytes, 16_384))
            for try await b in bytes {
                data.append(b)
                if data.count >= maxBytes { break }
            }
            bytes.task.cancel()
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            return FetchResult(data: data, response: resp as? HTTPURLResponse, durationMs: ms,
                               timing: TimingBreakdown(metrics: delegate.metrics), error: nil, finalURL: resp.url)
        } catch {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            return FetchResult(data: nil, response: nil, durationMs: ms, timing: nil,
                               error: Self.describe(error), finalURL: nil,
                               cancelled: Self.isCancellation(error))
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }

    static func describe(_ error: Error) -> String {
        guard let e = error as? URLError else { return error.localizedDescription }
        switch e.code {
        case .timedOut: return "Zaman aşımı"
        case .cannotFindHost, .dnsLookupFailed: return "Sunucu bulunamadı (DNS)"
        case .cannotConnectToHost: return "Sunucuya bağlanılamadı"
        case .networkConnectionLost: return "Bağlantı koptu"
        case .notConnectedToInternet: return "İnternet bağlantısı yok"
        case .secureConnectionFailed: return "Güvenli bağlantı (TLS) kurulamadı"
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "Sertifika hatası: \(e.localizedDescription)"
        case .httpTooManyRedirects: return "Çok fazla yönlendirme (döngü olabilir)"
        case .badServerResponse: return "Geçersiz sunucu yanıtı"
        case .zeroByteResource: return "Boş yanıt"
        case .cancelled: return "İptal edildi"
        default: return e.localizedDescription
        }
    }
}

/// Elemanları en fazla `limit` eşzamanlı görevle işler, sonuçları giriş sırasıyla döndürür.
func concurrentMap<T, R>(_ items: [T],
                         limit: Int,
                         _ transform: @escaping @Sendable (T) async -> R,
                         onEach: (Int, R) async -> Void = { _, _ in }) async -> [R] {
    guard !items.isEmpty else { return [] }
    var results = [R?](repeating: nil, count: items.count)
    await withTaskGroup(of: (Int, R).self) { group in
        var next = 0
        for _ in 0..<min(max(limit, 1), items.count) {
            let i = next, item = items[i]
            group.addTask { (i, await transform(item)) }
            next += 1
        }
        var done = 0
        while let pair = await group.next() {
            results[pair.0] = pair.1
            done += 1
            await onEach(done, pair.1)
            if next < items.count && !Task.isCancelled {
                let i = next, item = items[i]
                group.addTask { (i, await transform(item)) }
                next += 1
            }
        }
    }
    return results.compactMap { $0 }
}
