import Foundation
import SwiftUI

/// Kullanıcı tercihleri (UserDefaults'ta saklanır).
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var appearance: Appearance { didSet { d.set(appearance.rawValue, forKey: "appearance") } }
    @Published var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "language"); onServerSettingsChange?() } }
    @Published var retries: Int { didSet { d.set(retries, forKey: "retries"); onServerSettingsChange?() } }
    @Published var timeoutS: Int { didSet { d.set(timeoutS, forKey: "timeoutS"); onServerSettingsChange?() } }
    @Published var quietEnabled: Bool { didSet { d.set(quietEnabled, forKey: "quietEnabled"); onServerSettingsChange?() } }
    @Published var quietStart: String { didSet { d.set(quietStart, forKey: "quietStart"); onServerSettingsChange?() } }
    @Published var quietEnd: String { didSet { d.set(quietEnd, forKey: "quietEnd"); onServerSettingsChange?() } }
    @Published var certThresholdDays: Int { didSet { d.set(certThresholdDays, forKey: "certThresholdDays"); onCertSettingsChange?() } }
    /// Sertifikası takip edilmeyen site kimlikleri
    @Published var certExcluded: Set<String> { didSet { d.set(Array(certExcluded), forKey: "certExcluded") } }

    var onServerSettingsChange: (() -> Void)?
    var onCertSettingsChange: (() -> Void)?

    private init() {
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .dark
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        retries = d.object(forKey: "retries") as? Int ?? 2
        timeoutS = d.object(forKey: "timeoutS") as? Int ?? 15
        quietEnabled = d.bool(forKey: "quietEnabled")
        quietStart = d.string(forKey: "quietStart") ?? "23:00"
        quietEnd = d.string(forKey: "quietEnd") ?? "07:00"
        certThresholdDays = d.object(forKey: "certThresholdDays") as? Int ?? 14
        certExcluded = Set(d.stringArray(forKey: "certExcluded") ?? [])
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    /// Sunucuya gönderilen cihaz ayarları
    var serverFields: [String: Any] {
        [
            "lang": L.current.rawValue,
            "tz": TimeZone.current.identifier,
            "retries": retries,
            "timeoutS": timeoutS,
            "quietStart": quietEnabled ? quietStart : NSNull(),
            "quietEnd": quietEnabled ? quietEnd : NSNull(),
        ]
    }

    func resetAll() {
        for k in ["appearance", "language", "retries", "timeoutS", "quietEnabled", "quietStart", "quietEnd",
                  "certThresholdDays", "certExcluded", "certRecords"] {
            d.removeObject(forKey: k)
        }
    }
}

extension Date {
    /// "HH:mm" ↔ bugünün tarihi (DatePicker için)
    static func fromHHMM(_ s: String) -> Date {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = parts.first ?? 0
        c.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: c) ?? Date()
    }

    var hhmm: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
