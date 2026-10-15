import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
    // Surfaces: true black page, charcoal panels
    static let bg = Color.black
    static let surface = Color(hex: 0x252422)
    static let raise = Color(hex: 0x2E2D2A)
    static let line = Color(hex: 0x3B3936)
    static let line2 = Color(hex: 0x4A4844)
    // Ink
    static let ink = Color(hex: 0xEDE9E2)
    static let ink2 = Color(hex: 0xB3AEA5)
    static let ink3 = Color(hex: 0x8A857C)
    // Accents
    static let sun = Color(hex: 0xFF6437)
    static let go = Color(hex: 0x3FBF7F)
    static let warn = Color(hex: 0xE9B44C)
    static let stop = Color(hex: 0xF0534F)
    // Chart series (validated for colour-vision deficiency on the dark surface)
    static let s1 = Color(hex: 0x3987E5)
    static let s2 = Color(hex: 0x199E70)
    static let s3 = Color(hex: 0x9085E9)
}

extension Level {
    var color: Color { switch self { case .go: .go; case .caution: .warn; case .hold: .stop } }
}

extension Font {
    /// Anton for the GO / CAUTION / HOLD call. Falls back to a heavy condensed system face if the font failed to load.
    static func verdict(_ size: CGFloat) -> Font {
        if UIFont(name: "Anton-Regular", size: size) != nil { return .custom("Anton-Regular", size: size) }
        return .system(size: size, weight: .black, design: .default).width(.condensed)
    }
    static let num = Font.system(.body, design: .monospaced)
}

/// Status shape + colour: circle = go, triangle = caution, square = hold (never colour alone).
struct LevelGlyph: View {
    let level: Level
    var size: CGFloat = 10
    var body: some View {
        Group {
            switch level {
            case .go: Circle()
            case .caution: Triangle()
            case .hold: RoundedRectangle(cornerRadius: size * 0.12)
            }
        }
        .foregroundStyle(level.color)
        .frame(width: size, height: size)
        .accessibilityLabel(level.word)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.line, lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    var aside: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink2)
            Spacer()
            if let aside { Text(aside).font(.footnote).foregroundStyle(Color.ink3) }
        }
        .padding(.horizontal, 2)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Color.black)
            .background(Color.ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Color.ink)
            .background(Color.surface.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.line2, lineWidth: 1))
    }
}
