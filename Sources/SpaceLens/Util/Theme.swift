import SwiftUI

enum Theme {
    static let bg = Color(red: 0.047, green: 0.055, blue: 0.098)
    static let bgRaised = Color(red: 0.075, green: 0.086, blue: 0.145)
    static let sidebar = Color(red: 0.035, green: 0.041, blue: 0.075)
    static let card = Color.white.opacity(0.05)
    static let cardHover = Color.white.opacity(0.09)
    static let stroke = Color.white.opacity(0.08)
    static let textDim = Color.white.opacity(0.55)
    static let accentA = Color(red: 0.33, green: 0.56, blue: 1.0)
    static let accentB = Color(red: 0.62, green: 0.40, blue: 1.0)
    static let good = Color(red: 0.30, green: 0.85, blue: 0.58)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let bad = Color(red: 1.0, green: 0.42, blue: 0.45)

    static let accent = LinearGradient(colors: [accentA, accentB], startPoint: .leading, endPoint: .trailing)

    static var background: some View {
        ZStack {
            bg
            RadialGradient(colors: [accentB.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [accentA.opacity(0.10), .clear], center: .bottomLeading, startRadius: 0, endRadius: 600)
        }
    }
}

enum Fmt {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func bytes(_ n: Int64) -> String {
        byteFormatter.string(fromByteCount: max(n, 0))
    }

    static func count(_ n: Int) -> String {
        n.formatted(.number)
    }

    static func percent(_ part: Int64, of whole: Int64) -> String {
        guard whole > 0 else { return "0%" }
        let p = Double(part) / Double(whole) * 100
        return p < 0.1 ? "<0.1%" : String(format: p < 10 ? "%.1f%%" : "%.0f%%", p)
    }
}

/// Primary call-to-action button with the accent gradient.
struct AccentButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 15 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 30 : 16)
            .padding(.vertical, large ? 12 : 7)
            .background(Theme.accent, in: Capsule())
            .shadow(color: Theme.accentB.opacity(enabled ? 0.45 : 0), radius: 12, y: 4)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet secondary button.
struct GhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

/// Thin rounded usage bar.
struct UsageBar: View {
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(fraction > 0.9 ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(Theme.accent))
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}
