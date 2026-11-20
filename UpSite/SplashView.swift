import SwiftUI

/// Açılış animasyonu: logo çizilir, ok yükselir, yeşil nokta yanar.
/// Bu sırada siteler sunucudan alınır ve sertifikalar kontrol edilir.
struct SplashView: View {
    @State private var draw: CGFloat = 0
    @State private var arrow = false
    @State private var dot = false
    @State private var pulse = false
    @State private var title = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 112

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 27 * size / 120, style: .continuous)
                    .fill(Theme.accentFill)
                    .shadow(color: Theme.accentFill.opacity(0.45), radius: 24, y: 8)
                UShape().trim(from: 0, to: draw)
                    .stroke(.white, style: StrokeStyle(lineWidth: 12 * size / 120, lineCap: .round, lineJoin: .round))
                ArrowShape()
                    .stroke(.white, style: StrokeStyle(lineWidth: 12 * size / 120, lineCap: .round, lineJoin: .round))
                    .opacity(arrow ? 1 : 0)
                    .offset(y: arrow ? 0 : 10 * size / 120)
                Circle()
                    .fill(Theme.logoGreen.opacity(0.5))
                    .frame(width: 16 * size / 120, height: 16 * size / 120)
                    .scaleEffect(pulse ? 2.6 : 1)
                    .opacity(pulse ? 0 : (dot ? 1 : 0))
                    .position(x: 36 * size / 120, y: 31 * size / 120)
                Circle()
                    .fill(Theme.logoGreen)
                    .frame(width: 16 * size / 120, height: 16 * size / 120)
                    .scaleEffect(dot ? 1 : 0.2)
                    .opacity(dot ? 1 : 0)
                    .position(x: 36 * size / 120, y: 31 * size / 120)
            }
            .frame(width: size, height: size)

            Text("UpSite")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .opacity(title ? 1 : 0)
                .offset(y: title ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .accessibilityElement()
        .accessibilityLabel("UpSite")
        .onAppear(perform: animate)
    }

    private func animate() {
        if reduceMotion {
            draw = 1; arrow = true; dot = true; title = true
            return
        }
        withAnimation(.easeInOut(duration: 0.55)) { draw = 1 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.45)) { arrow = true }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55).delay(0.7)) { dot = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.55)) { title = true }
        withAnimation(.easeOut(duration: 0.9).delay(0.85).repeatForever(autoreverses: false)) { pulse = true }
    }
}

/// Logodaki U (sol üstten başlayıp sağ kolda yukarı çıkar).
private struct UShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 120
        var p = Path()
        p.move(to: CGPoint(x: 36 * s, y: 46 * s))
        p.addLine(to: CGPoint(x: 36 * s, y: 64 * s))
        p.addArc(center: CGPoint(x: 60 * s, y: 64 * s), radius: 24 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: 84 * s, y: 34 * s))
        return p
    }
}

private struct ArrowShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 120
        var p = Path()
        p.move(to: CGPoint(x: 71 * s, y: 45 * s))
        p.addLine(to: CGPoint(x: 84 * s, y: 32 * s))
        p.addLine(to: CGPoint(x: 97 * s, y: 45 * s))
        return p
    }
}
