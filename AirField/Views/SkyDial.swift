import SwiftUI
import UIKit

/// Polar sky chart: today's sun path, the sun now, wind, and (for panel work) the glare zone.
/// With a heading it turns so the top of the dial is where the phone points; labels stay upright.
struct SkyDial: View {
    let site: SiteData
    let briefing: Briefing
    var heading: Double?

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = side / 2 * 0.80
            let rot = heading ?? 0
            func P(_ az: Double, _ el: Double) -> CGPoint {
                let r = R * (90 - min(max(el, 0), 90)) / 90
                let a = (az - rot) * .pi / 180
                return CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
            }
            func label(_ s: String, _ p: CGPoint, _ color: Color, _ font: Font = .system(size: 11, design: .monospaced)) {
                ctx.draw(Text(s).font(font).foregroundColor(color), at: p)
            }

            // rim, rings, ticks
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - R - 18, y: c.y - R - 18, width: 2 * (R + 18), height: 2 * (R + 18))), with: .color(.surface))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R - 18, y: c.y - R - 18, width: 2 * (R + 18), height: 2 * (R + 18))), with: .color(.line2), lineWidth: 1)
            for el in [0.0, 30, 60] {
                let r = R * (90 - el) / 90
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.line), lineWidth: 1)
            }
            for az in stride(from: 0.0, to: 360, by: 15) where az.truncatingRemainder(dividingBy: 90) != 0 {
                let a = (az - rot) * .pi / 180, r1 = R + (az.truncatingRemainder(dividingBy: 45) == 0 ? 4 : 8), r2 = R + 14
                var p = Path(); p.move(to: CGPoint(x: c.x + r1 * sin(a), y: c.y - r1 * cos(a))); p.addLine(to: CGPoint(x: c.x + r2 * sin(a), y: c.y - r2 * cos(a)))
                ctx.stroke(p, with: .color(.line2), lineWidth: 1)
            }
            for (t, az) in [("N", 0.0), ("E", 90), ("S", 180), ("W", 270)] {
                let a = (az - rot) * .pi / 180, r = R + 9
                label(t, CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a)), t == "N" ? Color.ink : Color.ink3)
            }
            label("30°", CGPoint(x: c.x + 12, y: c.y - R * 60 / 90 - 6), .ink3, .system(size: 9, design: .monospaced))
            label("60°", CGPoint(x: c.x + 12, y: c.y - R * 30 / 90 - 6), .ink3, .system(size: 9, design: .monospaced))

            // today's sun path with hour marks
            let st = briefing.sunTimes
            if let rise = st.sunrise, let set = st.sunset {
                var path = Path(); var first = true
                var t = rise
                while t <= set {
                    let s = Sun.position(at: t, lat: site.lat, lon: site.lon)
                    let p = P(s.azimuth, max(s.elevation, 0))
                    if first { path.move(to: p); first = false } else { path.addLine(to: p) }
                    t = t.addingTimeInterval(360)
                }
                ctx.stroke(path, with: .color(Color.sun.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                var h = Date(timeIntervalSince1970: ceil(rise.timeIntervalSince1970 / 3600) * 3600)
                while h < set {
                    let s = Sun.position(at: h, lat: site.lat, lon: site.lon)
                    if s.elevation > 3 {
                        let p = P(s.azimuth, s.elevation)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(Color.sun.opacity(0.7)))
                        if briefing.units.localHour(h) % 2 == 0 {
                            let dx = p.x - c.x, dy = p.y - c.y, L = max(hypot(dx, dy), 1)
                            label(briefing.units.hourShort(h), CGPoint(x: p.x + dx / L * 12, y: p.y + dy / L * 12), .ink2, .system(size: 9, design: .monospaced))
                        }
                    }
                    h = h.addingTimeInterval(3600)
                }
            }

            // where the panels face (small hollow diamond), as on /field
            if let n = briefing.panelNormal {
                let p = P(n.azimuth, n.elevation)
                var d = Path()
                d.move(to: CGPoint(x: p.x, y: p.y - 5)); d.addLine(to: CGPoint(x: p.x + 5, y: p.y))
                d.addLine(to: CGPoint(x: p.x, y: p.y + 5)); d.addLine(to: CGPoint(x: p.x - 5, y: p.y)); d.closeSubpath()
                ctx.stroke(d, with: .color(.ink3), lineWidth: 1.5)
            }

            // glare zone for panel work
            if let g = briefing.glare {
                let p = P(g.azimuth, g.elevation), r = R * 15 / 90
                let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(circle, with: .color(Color.sun.opacity(0.16)))
                ctx.stroke(circle, with: .color(.sun), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                label("glare", p, .sun, .system(size: 9, design: .monospaced))
            }

            // wind: arrow from the rim pointing where the wind blows
            if let dir = briefing.windDirNow {
                let a = (dir - rot) * .pi / 180
                let p0 = CGPoint(x: c.x + (R - 4) * sin(a), y: c.y - (R - 4) * cos(a))
                let p1 = CGPoint(x: c.x + (R - 40) * sin(a), y: c.y - (R - 40) * cos(a))
                var shaft = Path(); shaft.move(to: p0); shaft.addLine(to: p1)
                ctx.stroke(shaft, with: .color(.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                let ang = atan2(p1.y - p0.y, p1.x - p0.x), hl: CGFloat = 9
                var head = Path()
                head.move(to: CGPoint(x: p1.x + cos(ang) * 4, y: p1.y + sin(ang) * 4))
                head.addLine(to: CGPoint(x: p1.x - hl * cos(ang - 0.45), y: p1.y - hl * sin(ang - 0.45)))
                head.addLine(to: CGPoint(x: p1.x - hl * cos(ang + 0.45), y: p1.y - hl * sin(ang + 0.45)))
                head.closeSubpath()
                ctx.fill(head, with: .color(.ink))
                // label beside the shaft, clear of it at any heading
                let mid = CGPoint(x: c.x + (R - 22) * sin(a), y: c.y - (R - 22) * cos(a))
                let px = cos(a), py = sin(a), side: CGFloat = (px < -0.2 || (abs(px) <= 0.2 && py > 0)) ? -1 : 1
                label(briefing.windNowText, CGPoint(x: mid.x + side * px * 30, y: mid.y + side * py * 30), .ink, .system(size: 11, weight: .medium, design: .monospaced))
            }

            // the sun now
            let sun = briefing.sunNow
            if sun.elevation > 0 {
                let p = P(sun.azimuth, sun.elevation)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32)), with: .color(Color.sun.opacity(0.16)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(.surface))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.sun))
            } else {
                let p = P(sun.azimuth, 0)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(Color.sun.opacity(0.45)))
            }

            // heading index: where the phone is pointing
            if heading != nil {
                var tri = Path()
                let top = c.y - R - 18
                tri.move(to: CGPoint(x: c.x, y: top + 12)); tri.addLine(to: CGPoint(x: c.x - 7, y: top)); tri.addLine(to: CGPoint(x: c.x + 7, y: top)); tri.closeSubpath()
                ctx.fill(tri, with: .color(.ink))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 420)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    var accessibilityText: String {
        let s = briefing.sunNow
        return "Sky dial. Sun " + (s.elevation > 0 ? "\(Int(s.elevation)) degrees up toward \(Units.compass(s.azimuth))" : "below the horizon")
            + ". Wind from \(Units.compass(briefing.windDirNow)) at \(briefing.windNowText)."
    }
}

/// GO / CAUTION / HOLD, the reasons, and the next good window.
struct VerdictView: View {
    let verdict: Briefing.Verdict
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                LevelGlyph(level: verdict.level, size: 20)
                Text(verdict.word.uppercased())
                    .font(.verdict(68))
                    .foregroundStyle(verdict.level.color)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
            Text(verdict.why).font(.body).foregroundStyle(Color.ink2).multilineTextAlignment(.center).frame(maxWidth: 320)
            if let n = verdict.next { Text(n).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink) }
            if !verdict.reasons.isEmpty {
                FlowChips(reasons: verdict.reasons).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct FlowChips: View {
    let reasons: [Reason]
    var body: some View {
        // wrap with ViewThatFits-friendly simple layout: two columns of chips is enough for six reasons
        let rows = stride(from: 0, to: reasons.count, by: 2).map { Array(reasons[$0..<min($0 + 2, reasons.count)]) }
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(rows[i].indices, id: \.self) { j in
                        let r = rows[i][j]
                        HStack(spacing: 6) { LevelGlyph(level: r.level, size: 9); Text(r.text).lineLimit(1) }
                            .font(.footnote).foregroundStyle(Color.ink2)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.surface, in: Capsule())
                            .overlay(Capsule().stroke(Color.line, lineWidth: 1))
                    }
                }
            }
        }
    }
}

/// Always-visible airspace status.
struct AirspaceView: View {
    let card: Briefing.AirspaceCard
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "airplane.circle.fill").font(.title2).foregroundStyle(card.level.color)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { LevelGlyph(level: card.level, size: 9); Text(card.title).font(.headline).foregroundStyle(Color.ink) }
                Text(card.detail).font(.subheadline).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
                if let url = URL(string: card.url) {
                    Link(destination: url) { HStack(spacing: 4) { Text(card.action); Image(systemName: "arrow.up.right") }.font(.subheadline.weight(.semibold)) }
                        .foregroundStyle(Color.sun).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(card.level.color).frame(width: 3).padding(.vertical, 10) }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.line, lineWidth: 1))
    }
}

/// App mark used on the welcome screen: the sectional-chart logo by day, the night chart in Dark Mode.
/// AirField itself always draws dark, so this asks the system (the screen), not the app's own appearance.
struct AppMark: View {
    @Environment(\.scenePhase) private var phase
    @State private var night = AppMark.systemIsDark

    static var systemIsDark: Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.traitCollection.userInterfaceStyle == .dark
    }

    var body: some View {
        Image(night ? "MarkNight" : "Mark").resizable().scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .accessibilityLabel("AirField")
            .onAppear { night = AppMark.systemIsDark }
            // switching Light/Dark in Control Center sends the app through inactive → active
            .onChange(of: phase) { _, _ in night = AppMark.systemIsDark }
    }
}
