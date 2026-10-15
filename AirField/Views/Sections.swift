import SwiftUI
import Charts

/// "Right now" cards, chosen and ordered by the activity.
struct TileGrid: View {
    let tiles: [Briefing.Tile]
    let editPlane: () -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
            ForEach(tiles) { t in
                TileView(tile: t)
                    .contentShape(Rectangle())
                    .onTapGesture { if t.editable { editPlane() } }
                    .accessibilityAddTraits(t.editable ? .isButton : [])
                    .accessibilityHint(t.editable ? "Change panel tilt" : "")
            }
        }
        .background(Color.line)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.line, lineWidth: 1))
    }
}

struct TileView: View {
    let tile: Briefing.Tile
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let l = tile.level { LevelGlyph(level: l, size: 8) }
                Text(tile.title).font(.footnote).foregroundStyle(Color.ink3)
                Spacer(minLength: 0)
                if tile.editable { Image(systemName: "pencil").font(.footnote).foregroundStyle(Color.ink3) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tile.value).font(.system(size: 26, weight: .medium, design: .monospaced)).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.6)
                if !tile.unit.isEmpty { Text(tile.unit).font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.ink2) }
            }
            Text(tile.detail).font(.footnote).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
            if let m = tile.meter {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.raise)
                        Capsule().fill(Color.sun).frame(width: g.size.width * min(1, max(0, m.value / m.max)))
                        Rectangle().fill(Color.ink).frame(width: 2).offset(x: g.size.width * m.mark / m.max - 1)
                    }
                }
                .frame(height: 6).padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color.surface)
        .accessibilityElement(children: .combine)
    }
}

struct HeadsUpList: View {
    let items: [Briefing.HeadsUp]
    var body: some View {
        if items.isEmpty {
            Text("No cautions in the forecast. Conditions hold steady for the next 48 hours.")
                .font(.subheadline).foregroundStyle(Color.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(spacing: 8) { ForEach(items) { HeadsUpRow(item: $0) } }
        }
    }
}

struct HeadsUpRow: View {
    let item: Briefing.HeadsUp
    @State private var open = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LevelGlyph(level: item.level, size: 13).padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).foregroundStyle(Color.ink)
                if !item.detail.isEmpty { Text(item.detail).font(.subheadline).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true) }
                if let src = item.source { Text(src).font(.caption).foregroundStyle(Color.ink3) }
                if let more = item.more, !more.isEmpty {
                    Button(open ? "Hide statement" : "Full statement") { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } }
                        .font(.footnote).foregroundStyle(Color.ink3)
                    if open { Text(more).font(.footnote).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(item.level.color).frame(width: 3).padding(.vertical, 8) }
    }
}

/// 48-hour chart: irradiance (for panel/light work), wind, sky, and an hourly status strip, sharing one scrub position.
struct TimelineView48: View {
    let briefing: Briefing
    let panels: [ChartPanel]
    @State private var selected: Date?
    @State private var showTable = false

    var hours: [Briefing.Hour] { briefing.hours }
    var u: Units { briefing.units }
    var current: Briefing.Hour? {
        guard let s = selected else { return hours.first }
        return hours.min { abs($0.time.timeIntervalSince(s)) < abs($1.time.timeIntervalSince(s)) }
    }
    var domain: ClosedRange<Date> { (hours.first?.time ?? Date())...(hours.last?.time ?? Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            readout.padding(12)
            Divider().background(Color.line)
            VStack(alignment: .leading, spacing: 18) {
                if panels.contains(.irradiance) { irradianceChart }
                if panels.contains(.wind) { windChart }
                if panels.contains(.sky) { skyChart }
                statusStrip
            }
            .padding(.horizontal, 10).padding(.vertical, 12)
            legend.padding(.horizontal, 12).padding(.bottom, 8)
            Button(showTable ? "Hide hourly table" : "Show hourly table") { showTable.toggle() }
                .font(.footnote).foregroundStyle(Color.ink3).padding(.horizontal, 12).padding(.bottom, 10)
            if showTable { HourTable(hours: hours, u: u, irradiance: panels.contains(.irradiance)) }
        }
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.line, lineWidth: 1))
    }

    var readout: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let h = current {
                HStack(spacing: 8) {
                    Text(selected == nil ? "This hour" : "\(u.weekday(h.time)) \(u.clock(h.time))").font(.system(.subheadline, design: .monospaced).weight(.medium)).foregroundStyle(Color.ink)
                    LevelGlyph(level: h.level, size: 9)
                    Text(h.level.word + (h.reasons.isEmpty ? (h.reason.map { ": \($0)" } ?? "") : ": " + h.reasons.joined(separator: "; ")))
                        .font(.subheadline).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    if panels.contains(.irradiance) { key(.sun, Units.round(h.irradiance), "W/m²") }
                    key(.s1, u.speedNumber(h.wind), u.speedUnit)
                    key(.s2, u.speedNumber(h.gust), "gust")
                    key(.s3, u.speedNumber(h.aloft), "aloft")
                }
                HStack(spacing: 14) {
                    key(nil, Units.round(h.cloud), "% cloud"); key(nil, Units.round(h.rainChance), "% rain"); key(nil, u.tempNumber(h.temp), u.tempUnit)
                }
            }
        }
        .font(.footnote)
    }
    func key(_ c: Color?, _ v: String, _ unit: String) -> some View {
        HStack(spacing: 4) {
            if let c { Capsule().fill(c).frame(width: 12, height: 2) }
            Text(v).font(.system(.footnote, design: .monospaced).weight(.medium)).foregroundStyle(Color.ink)
            Text(unit).foregroundStyle(Color.ink2)
        }
    }

    func nightMarks() -> some ChartContent {
        ForEach(hours.filter(\.night)) { h in
            RectangleMark(xStart: .value("t", h.time.addingTimeInterval(-1800)), xEnd: .value("t", h.time.addingTimeInterval(1800)))
                .foregroundStyle(Color.black.opacity(0.28))
        }
    }
    func selectionRule() -> some ChartContent {
        ForEach(selected.map { [$0] } ?? [], id: \.self) { s in
            RuleMark(x: .value("Selected", s)).foregroundStyle(Color.ink).lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    var irradianceChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(briefing.irradianceTitle + ", W/m²").font(.caption).foregroundStyle(Color.ink2)
            Chart {
                nightMarks()
                ForEach(hours) { h in
                    AreaMark(x: .value("Time", h.time), y: .value("W/m²", h.irradiance ?? 0)).foregroundStyle(Color.sun.opacity(0.13)).interpolationMethod(.monotone)
                    LineMark(x: .value("Time", h.time), y: .value("W/m²", h.irradiance ?? 0)).foregroundStyle(Color.sun).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                RuleMark(y: .value("Thermal minimum", 600)).foregroundStyle(Color.ink2).lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .trailing) { Text("600 thermal minimum").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.ink2) }
                selectionRule()
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...max(1000, hours.compactMap(\.irradiance).max() ?? 0))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: [0.0, 600.0, 1000.0]) { _ in AxisGridLine().foregroundStyle(Color.line); AxisValueLabel().foregroundStyle(Color.ink3) } }
            .chartXSelection(value: $selected)
            .frame(height: 90)
        }
    }

    var windChart: some View {
        let limit = briefing.windLimitDisplay
        let top = max(limit * 1.3, (hours.flatMap { [$0.wind, $0.gust, $0.aloft] }.compactMap { u.speed($0) }.max() ?? 0) * 1.1)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Wind, \(u.speedUnit)").font(.caption).foregroundStyle(Color.ink2)
            Chart {
                nightMarks()
                RuleMark(y: .value("Your limit", limit)).foregroundStyle(Color.ink2).lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .trailing) { Text("your limit").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.ink2) }
                ForEach(hours) { h in
                    if let v = u.speed(h.aloft) { LineMark(x: .value("Time", h.time), y: .value("Speed", v), series: .value("Series", "At 400 ft")).foregroundStyle(Color.s3) }
                    if let v = u.speed(h.gust) { LineMark(x: .value("Time", h.time), y: .value("Speed", v), series: .value("Series", "Gusts")).foregroundStyle(Color.s2) }
                    if let v = u.speed(h.wind) { LineMark(x: .value("Time", h.time), y: .value("Speed", v), series: .value("Series", "Wind")).foregroundStyle(Color.s1) }
                }
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                selectionRule()
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...top)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(Color.line); AxisValueLabel().foregroundStyle(Color.ink3) } }
            .chartLegend(.hidden)
            .chartXSelection(value: $selected)
            .frame(height: 100)
        }
    }

    var skyChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sky, %").font(.caption).foregroundStyle(Color.ink2)
            Chart {
                nightMarks()
                ForEach(hours) { h in
                    AreaMark(x: .value("Time", h.time), y: .value("Cloud", h.cloud ?? 0)).foregroundStyle(Color.ink3.opacity(0.25))
                    if let r = h.rainChance, r > 0 {
                        BarMark(x: .value("Time", h.time), y: .value("Rain", r), width: .fixed(4)).foregroundStyle(Color.ink2).cornerRadius(2)
                    }
                }
                selectionRule()
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) { _ in AxisGridLine().foregroundStyle(Color.line); AxisValueLabel().foregroundStyle(Color.ink3) } }
            .chartXSelection(value: $selected)
            .frame(height: 70)
        }
    }

    var statusStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Flight status").font(.caption).foregroundStyle(Color.ink2)
            Chart {
                ForEach(hours) { h in
                    RectangleMark(xStart: .value("t", h.time.addingTimeInterval(-1500)), xEnd: .value("t", h.time.addingTimeInterval(1500)), yStart: 0, yEnd: 14)
                        .foregroundStyle(h.level.color).cornerRadius(2)
                }
                selectionRule()
            }
            .chartXScale(domain: domain)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { v in
                    AxisValueLabel {
                        if let d = v.as(Date.self) { Text(u.localHour(d) == 0 ? u.weekday(d) : u.hourShort(d)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.ink3) }
                    }
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 40)
        }
    }

    var legend: some View {
        HStack(spacing: 12) {
            legendItem(.s1, "Wind"); legendItem(.s2, "Gusts"); legendItem(.s3, "At 400 ft")
            HStack(spacing: 4) { LevelGlyph(level: .go, size: 8); LevelGlyph(level: .caution, size: 8); LevelGlyph(level: .hold, size: 8); Text("Status") }
        }
        .font(.caption).foregroundStyle(Color.ink3)
    }
    func legendItem(_ c: Color, _ t: String) -> some View { HStack(spacing: 5) { Capsule().fill(c).frame(width: 14, height: 2); Text(t) } }
}

struct HourTable: View {
    let hours: [Briefing.Hour]
    let u: Units
    let irradiance: Bool
    var body: some View {
        ScrollView(.vertical) {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Time").gridColumnAlignment(.leading); Text("Status").gridColumnAlignment(.leading)
                    if irradiance { Text("W/m²") }
                    Text("Wind"); Text("Gust"); Text("Aloft"); Text("Cloud"); Text("Rain"); Text(u.tempUnit)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(Color.ink3)
                ForEach(hours) { h in
                    GridRow {
                        Text("\(u.weekday(h.time)) \(u.clock(h.time))").gridColumnAlignment(.leading)
                        Text(h.level.word).foregroundStyle(h.level.color).gridColumnAlignment(.leading)
                        if irradiance { Text(Units.round(h.irradiance)) }
                        Text(u.speedNumber(h.wind)); Text(u.speedNumber(h.gust)); Text(u.speedNumber(h.aloft))
                        Text("\(Units.round(h.cloud))%"); Text("\(Units.round(h.rainChance))%"); Text(u.tempNumber(h.temp))
                    }
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(Color.ink2)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 320)
    }
}

struct WeekView: View {
    let days: [Briefing.Day]
    let units: Units
    /// The hour chosen by dragging any day's bars (local 0–23). One line runs through every day at that hour
    /// and every day's readout shows it, so you can compare the same hour across the week. Stays after you let go.
    @State private var hour: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(days) { d in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                        Text(d.subtitle).font(.caption2).foregroundStyle(Color.ink3)
                    }
                    .frame(width: 50, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        bars(d)
                        readout(d)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(d.high) / \(d.low)").foregroundStyle(Color.ink)
                        Text("gust \(d.gust)"); Text("rain \(d.rain)")
                    }
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.ink2)
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
                if d.id != days.last?.id { Divider().background(Color.line) }
            }
            HStack(spacing: 14) {
                ForEach([Level.go, .caution, .hold], id: \.self) { l in HStack(spacing: 5) { LevelGlyph(level: l, size: 9); Text(l.word) } }
                Spacer()
                Text("12a  6a  12p  6p").font(.system(.caption2, design: .monospaced))
            }
            .font(.caption).foregroundStyle(Color.ink3).padding(.top, 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.line, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: hour)
    }

    /// 24 hourly bars with the same vertical marker line the 48-hour chart uses.
    func bars(_ d: Briefing.Day) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<24, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(d.cells[i]?.color ?? Color.raise)
                    .opacity(i < d.pastCells ? 0.25 : 1)
                    .frame(height: 16)
            }
        }
        .overlay {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    if let hr = hour {
                        Rectangle().fill(Color.ink)
                            .frame(width: 2, height: g.size.height + 10)
                            .position(x: (CGFloat(hr) + 0.5) * w / 24, y: g.size.height / 2)
                    }
                    Color.clear.contentShape(Rectangle())
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let h = min(23, max(0, Int(v.location.x / max(w, 1) * 24)))
                            hour = h
                        })
                }
            }
        }
    }

    /// Under the bars: the picked hour, its call and why (like the 48-hour readout), or the day's summary.
    @ViewBuilder func readout(_ d: Briefing.Day) -> some View {
        if let hr = hour {
            let t = d.times[hr]
            HStack(spacing: 6) {
                Text(t.map { units.clock($0) } ?? hourLabel(hr))
                    .font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(Color.ink)
                if let l = d.cells[hr] {
                    LevelGlyph(level: l, size: 8)
                    Text(l.word + (d.reasons[hr].map { ": \($0)" } ?? (d.winds[hr].map { ", \($0)" } ?? "")))
                        .font(.caption).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No forecast").font(.caption).foregroundStyle(Color.ink3)
                }
            }
        } else {
            Text(d.summary).font(.caption).foregroundStyle(Color.ink2)
        }
    }

    func hourLabel(_ h: Int) -> String {
        units.imperial ? (h == 0 ? "12 AM" : h < 12 ? "\(h) AM" : h == 12 ? "12 PM" : "\(h - 12) PM") : String(format: "%02d:00", h)
    }
}

struct SunTimesView: View {
    let briefing: Briefing
    var body: some View {
        let st = briefing.sunTimes, u = briefing.units, s = briefing.sunNow
        let cells: [(String, String)] = [
            ("Civil dawn", u.clock(st.civilDawn)), ("Sunrise", u.clock(st.sunrise)), ("Solar noon", u.clock(st.solarNoon)),
            ("Golden hour", u.clock(st.goldenEveningStart)), ("Sunset", u.clock(st.sunset)), ("Civil dusk", u.clock(st.civilDusk)),
        ]
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                ForEach(cells.indices, id: \.self) { i in
                    let c = cells[i]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.0).font(.caption).foregroundStyle(Color.ink3)
                        Text(c.1).font(.system(.subheadline, design: .monospaced).weight(.medium)).foregroundStyle(Color.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color.surface)
                }
            }
            .background(Color.line)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text((s.elevation > -0.833 ? "Sun \(Units.round(s.elevation))° up toward \(Units.compass(s.azimuth)). " : "Sun is down. ") + briefing.sunNotes)
                .font(.footnote).foregroundStyle(Color.ink3).padding(.horizontal, 2)
        }
    }
}
