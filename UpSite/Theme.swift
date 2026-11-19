import SwiftUI
import UIKit

/// UpSite renk ve bileşen dili. Koyu tema varsayılan; açık tema da desteklenir.
enum Theme {
    private static func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark) })
    }

    static let bg = dyn(0x0B1020, 0xF5F6FA)
    static let surface = dyn(0x151B2E, 0xFFFFFF)
    static let surface2 = dyn(0x1E263D, 0xEEF0F5)
    static let divider = dyn(0x232B42, 0xE3E6EE)
    static let border = dyn(0x2A3350, 0xD5D9E2)
    static let tabBar = dyn(0x10162A, 0xFFFFFF)

    static let text = dyn(0xEEF1F8, 0x0E1525)
    static let text2 = dyn(0xB4BCD0, 0x4A5568)
    static let text3 = dyn(0x9AA4BC, 0x5D6B82)
    static let chevron = dyn(0x5E6886, 0xA3ACBD)

    /// Düğme ve logo dolgusu
    static let accentFill = Color(UIColor(hex: 0x5B4BDB))
    /// Vurgulu metin ve simgeler (koyu zeminde daha açık)
    static let accent = dyn(0x9D93E9, 0x4B3FD1)
    static let accentSoft = dyn(0x2A2552, 0xE9E7FB)

    static let up = dyn(0x32D583, 0x067647)
    static let upBg = dyn(0x0F2E22, 0xDCFAE6)
    static let upBorder = dyn(0x1D4A35, 0xABEFC6)
    static let down = dyn(0xF97066, 0xB42318)
    static let downBg = dyn(0x3B1A1A, 0xFEE4E2)
    static let downBorder = dyn(0x4A2222, 0xFECDCA)
    static let warn = dyn(0xFDB022, 0xB54708)
    static let warnBg = dyn(0x3A2A0B, 0xFEF0C7)
    static let warnBorder = dyn(0x5C4310, 0xFEDF89)
    static let paused = dyn(0x9AA4BC, 0x5D6B82)
    static let pausedBg = dyn(0x232B42, 0xEEF0F5)

    static let barUp = Color(UIColor(hex: 0x12B76A))
    static let barDown = Color(UIColor(hex: 0xF04438))
    static let barNone = dyn(0x2A3350, 0xE3E6EE)

    static let logoGreen = Color(UIColor(hex: 0x35D07F))
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Logo

/// "Yükselen U": sağ kolu yukarı oka dönüşen U ve yeşil durum noktası.
struct LogoMark: View {
    var size: CGFloat = 36

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 120
            let tile = Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: 27 * s, style: .continuous)
            ctx.fill(tile, with: .color(Theme.accentFill))
            var u = Path()
            u.move(to: CGPoint(x: 36 * s, y: 46 * s))
            u.addLine(to: CGPoint(x: 36 * s, y: 64 * s))
            u.addArc(center: CGPoint(x: 60 * s, y: 64 * s), radius: 24 * s,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            u.addLine(to: CGPoint(x: 84 * s, y: 34 * s))
            var arrow = Path()
            arrow.move(to: CGPoint(x: 71 * s, y: 45 * s))
            arrow.addLine(to: CGPoint(x: 84 * s, y: 32 * s))
            arrow.addLine(to: CGPoint(x: 97 * s, y: 45 * s))
            let style = StrokeStyle(lineWidth: 12 * s, lineCap: .round, lineJoin: .round)
            ctx.stroke(u, with: .color(.white), style: style)
            ctx.stroke(arrow, with: .color(.white), style: style)
            ctx.fill(Path(ellipseIn: CGRect(x: 28 * s, y: 23 * s, width: 16 * s, height: 16 * s)), with: .color(Theme.logoGreen))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Ortak bileşenler

struct StatusBadge: View {
    let status: SiteStatus
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(background)
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .heavy))
                .foregroundStyle(foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch status {
        case .up: return "checkmark"
        case .down: return "xmark"
        case .paused: return "pause.fill"
        case .unknown: return "ellipsis"
        }
    }

    private var foreground: Color {
        switch status {
        case .up: return Theme.up
        case .down: return Theme.down
        case .paused, .unknown: return Theme.paused
        }
    }

    private var background: Color {
        switch status {
        case .up: return Theme.upBg
        case .down: return Theme.downBg
        case .paused, .unknown: return Theme.pausedBg
        }
    }
}

/// Son kontrollerin çubukları (soldan sağa eskiden yeniye).
struct UptimeBars: View {
    /// true = erişilebilir, false = erişilemedi, nil = veri yok
    let values: [Bool?]
    var height: CGFloat = 16
    var count: Int = 24

    var body: some View {
        let padded = Array(repeating: nil, count: max(0, count - values.count)) + values.suffix(count)
        HStack(spacing: 2) {
            ForEach(Array(padded.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 2)
                    .fill(v == nil ? Theme.barNone : (v! ? Theme.barUp : Theme.barDown))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.s("bars.a11y", values.compactMap { $0 }.filter { !$0 }.count, values.compactMap { $0 }.count))
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Theme.text3)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var border: Color = Theme.divider
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(border, lineWidth: 1))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.accentFill.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    /// Liste satırlarını tasarımdaki yüzey rengiyle boyar.
    func themedRow() -> some View {
        listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.divider)
    }

    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
    }
}
