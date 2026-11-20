import Foundation
import Security

/// Cihaza özel anonim kimlik: hesap açılmaz, kimlik Anahtar Zinciri'nde saklanır.
enum DeviceCredentials {
    private static let service = "studio.alpp.upsite.device"

    struct Value: Codable { let id: String; let secret: String }

    static func load() -> Value? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    static func create() -> Value {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let secret = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let v = Value(id: UUID().uuidString.lowercased(), secret: secret)
        save(v)
        return v
    }

    static func save(_ v: Value) {
        delete()
        guard let data = try? JSONEncoder().encode(v) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                kSecValueData as String: data]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
    }
}

enum APIError: LocalizedError {
    case notConfigured
    case offline
    case server(Int, String?)
    case decoding

    var code: String? {
        if case let .server(_, c) = self { return c }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L.s("error.notConfigured")
        case .offline: return L.s("error.offline")
        case .decoding: return L.s("error.generic")
        case let .server(status, code):
            switch code {
            case "invalid-url": return L.s("error.invalidURL")
            case "duplicate": return L.s("error.duplicate")
            case "site-limit": return L.s("error.siteLimit")
            case "capacity": return L.s("error.capacity")
            case "no-token": return L.s("error.noToken")
            case "push-not-configured": return L.s("error.pushNotConfigured")
            case "invalid-key": return L.s("error.invalidKey")
            case "already-member": return L.s("error.alreadyMember")
            case "package-limit": return L.s("error.packageLimit")
            case "member-limit": return L.s("error.memberLimit")
            case "not-owner": return L.s("error.notOwner")
            default: return L.s("error.server", status)
            }
        }
    }
}

/// UpSite sunucusu ile konuşan istemci.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    let baseURL: URL?
    private let session: URLSession
    private var credentials: DeviceCredentials.Value?
    private var registered = false
    private let lock = NSLock()

    init() {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "UpSiteAPIBase") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        baseURL = raw.hasPrefix("https://") && !raw.contains("YOUR-SUBDOMAIN") ? URL(string: raw) : nil
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: c)
    }

    var isConfigured: Bool { baseURL != nil }

    private func creds() -> DeviceCredentials.Value {
        lock.lock(); defer { lock.unlock() }
        if let credentials { return credentials }
        let v = DeviceCredentials.load() ?? DeviceCredentials.create()
        credentials = v
        return v
    }

    func resetIdentity() {
        lock.lock()
        DeviceCredentials.delete()
        credentials = nil
        registered = false
        lock.unlock()
    }

    private func ensureRegistered() async throws {
        if registered { return }
        let c = creds()
        let _: EmptyResponse = try await send("POST", "/v1/register", body: ["deviceId": c.id, "secret": c.secret], auth: false)
        registered = true
    }

    private struct EmptyResponse: Decodable {}

    func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil, auth: Bool = true, retried: Bool = false) async throws -> T {
        guard let baseURL else { throw APIError.notConfigured }
        if auth { try await ensureRegistered() }
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path) else { throw APIError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("UpSite-iOS/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if auth {
            let c = creds()
            req.setValue("Bearer \(c.id).\(c.secret)", forHTTPHeaderField: "Authorization")
        }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.offline
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && auth && !retried {
            // Sunucu kaydı silinmiş olabilir: yeniden kaydol ve bir kez tekrar dene.
            registered = false
            return try await send(method, path, body: body, auth: true, retried: true)
        }
        if status == 409 && path == "/v1/register" {
            // Bu kimlik sunucuda başka bir sırla kayıtlı: yeni bir kimlik oluştur.
            resetIdentity()
            throw APIError.server(status, "conflict")
        }
        guard (200..<300).contains(status) else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError.server(status, code)
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    // MARK: Uç noktalar

    struct OK: Decodable { let ok: Bool? }
    struct PushResult: Decodable { let outcome: String; let reason: String? }

    func state() async throws -> SiteState { try await send("GET", "/v1/state") }

    func updateDevice(_ fields: [String: Any]) async throws { let _: OK = try await send("PUT", "/v1/device", body: fields) }

    func addSite(url: String, name: String?, interval: Int, notifyDown: Bool, notifyUp: Bool, packageId: String?) async throws -> Site {
        var b: [String: Any] = ["url": url, "intervalMin": interval, "notifyDown": notifyDown, "notifyUp": notifyUp]
        if let name, !name.isEmpty { b["name"] = name }
        if let packageId { b["packageId"] = packageId }
        return try await send("POST", "/v1/sites", body: b)
    }

    func updateSite(_ id: String, _ fields: [String: Any]) async throws -> Site { try await send("PATCH", "/v1/sites/\(id)", body: fields) }

    func deleteSite(_ id: String) async throws { let _: OK = try await send("DELETE", "/v1/sites/\(id)") }

    func checkNow(_ id: String) async throws -> Site { try await send("POST", "/v1/sites/\(id)/check") }

    func history(_ id: String, days: Int = 7) async throws -> SiteHistory { try await send("GET", "/v1/sites/\(id)/history?days=\(days)") }

    func clearHistory() async throws { let _: OK = try await send("DELETE", "/v1/history") }

    func deleteDevice() async throws { let _: OK = try await send("DELETE", "/v1/device") }

    func testPush() async throws -> PushResult { try await send("POST", "/v1/push/test") }

    // Paketler

    func createPackage(name: String) async throws -> SitePackage { try await send("POST", "/v1/packages", body: ["name": name]) }

    func joinPackage(key: String) async throws -> SitePackage { try await send("POST", "/v1/packages/join", body: ["key": key]) }

    func updatePackage(_ id: String, _ fields: [String: Any]) async throws -> SitePackage { try await send("PATCH", "/v1/packages/\(id)", body: fields) }

    func rotateKey(_ id: String) async throws -> SitePackage { try await send("POST", "/v1/packages/\(id)/key", body: [:]) }

    func leavePackage(_ id: String) async throws { let _: OK = try await send("POST", "/v1/packages/\(id)/leave", body: [:]) }

    func deletePackage(_ id: String) async throws { let _: OK = try await send("DELETE", "/v1/packages/\(id)") }

    func admin() async throws -> AdminState { try await send("GET", "/v1/admin") }

    var deviceId: String { creds().id }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static let supportURL = URL(string: "https://alpp.studio/upsite/")!
    static let privacyURL = URL(string: "https://alpp.studio/upsite/privacy/")!
    static let supportEmail = "help@alpp.studio"
    static let appStoreURL = URL(string: "itms-apps://apps.apple.com/app/id6830828921")!
}
