import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showTilt = false
    @State private var waitedLong = false
    @State private var snap = SnapStore()

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 28) {
                topBar.snap(-1)
                if let b = model.briefing, let s = model.site {
                    VStack(spacing: 6) {
                        CompassDial(site: s, briefing: b, location: model.location, compassOn: $model.compassOn)
                        VerdictView(verdict: b.verdict)
                    }
                    .roll().snap(0)
                    VStack(spacing: 10) {
                        SectionHeader(title: "Airspace", aside: "LAANC")
                        AirspaceView(card: b.airspace)
                    }
                    .padding(.top, 14)                       // its own stop, clear of the dial above
                    .roll().snap(1)
                    VStack(spacing: 10) {
                        SectionHeader(title: "Right now", aside: b.sourceNote)
                        TileGrid(tiles: b.tiles) { showTilt = true }
                    }.roll().snap(2)
                    VStack(spacing: 10) {
                        SectionHeader(title: "Heads up", aside: "next 48 h")
                        HeadsUpList(items: b.headsUp)
                    }.roll().snap(3)
                    VStack(spacing: 10) {
                        SectionHeader(title: "Next 48 hours", aside: "drag to read")
                        TimelineView48(briefing: b, panels: model.profile?.variant.chart ?? [.wind, .sky, .status])
                    }.roll().snap(4)
                    VStack(spacing: 10) {
                        SectionHeader(title: "Week", aside: "drag for the hour")
                        WeekView(days: b.days, units: b.units)
                    }.roll().snap(5)
                    VStack(spacing: 10) {
                        SectionHeader(title: "Sun today")
                        SunTimesView(briefing: b)
                    }.roll().snap(6)
                    footer(s).snap(99)
                } else {
                    placeholder.padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .coordinateSpace(name: SnapStore.space)
            .onPreferenceChange(SnapFramesKey.self) { snap.frames = $0 }
        }
        .modifier(MagnetSnap(store: snap, proxy: proxy))
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
        .onAppear { model.becameActive() }
        .background(Color.bg)
        .sheet(isPresented: $showSearch) { PlaceSearchSheet().environmentObject(model) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(model) }
        .sheet(isPresented: $showTilt) { TiltSheet().environmentObject(model).presentationDetents([.medium, .large]) }
        }
    }

    // MARK: top bar

    var topBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { showSearch = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.ink3)
                        Text(placeTitle).font(.headline).foregroundStyle(Color.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.line, lineWidth: 1))
                }
                .accessibilityLabel("Location: \(placeTitle). Search a place")
                iconButton(model.following ? "location.fill" : "location", filled: model.following, label: model.following ? "Following your location" : "Follow my location") { model.followMe() }
                iconButton("gearshape", label: "Settings") { showSettings = true }
            }
            HStack {
                Text(statusText).foregroundStyle(model.following && model.location.isDenied ? Color.warn : Color.ink3)
                Spacer()
                Text(updatedText).foregroundStyle(model.offline ? Color.warn : Color.ink3)
            }
            .font(.footnote)
            .padding(.horizontal, 2)
        }
    }

    var placeTitle: String {
        if !model.placeName.isEmpty { return model.placeName }
        if model.following { return model.location.isDenied ? "Search a place" : "Finding you…" }
        return "Search a place"
    }
    var statusText: String {
        if !model.following { return "Locked to this site" }
        return model.location.isDenied ? "Location is off" : "Following your location"
    }
    var updatedText: String {
        let act = model.profile?.variant.name ?? ""
        guard let t = model.lastFetch else { return model.loading ? "\(act), loading…" : act }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        let age = Date().timeIntervalSince(t)
        return "\(act), " + (model.offline ? "offline, " : "") + (age < 60 ? "updated now" : "updated \(f.string(from: t))")
    }

    func iconButton(_ symbol: String, filled: Bool = false, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(filled ? Color.black : Color.ink2)
                .frame(width: 44, height: 44)
                .background(filled ? Color.ink : Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(filled ? Color.ink : Color.line, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }

    var placeholder: some View {
        VStack(spacing: 14) {
            if model.loading { ProgressView().tint(.ink) }
            else if model.offline { Text("Couldn't reach the forecast. Pull down to try again.").foregroundStyle(Color.ink2) }
            else if model.following && model.location.isDenied {
                Text("Location is off for AirField.").font(.headline).foregroundStyle(Color.ink)
                Text("Search a place above, or turn location on in Settings.").foregroundStyle(Color.ink2).multilineTextAlignment(.center)
                Button("Open iPhone Settings") { LocationService.openAppSettings() }.buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 260)
            } else if model.following && model.location.isUndecided {
                Text("AirField needs your location").font(.headline).foregroundStyle(Color.ink)
                Text("To show conditions where you're standing. Or search a place above.").foregroundStyle(Color.ink2).multilineTextAlignment(.center)
                Button("Allow location") { model.location.requestPermission() }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 260)
            } else if !model.following {
                ProgressView().tint(.ink)
            } else {
                ProgressView().tint(.ink)
                Text("Finding your location…").foregroundStyle(Color.ink2)
                if waitedLong {
                    Text(slowFixHint).font(.footnote).foregroundStyle(Color.ink3).multilineTextAlignment(.center).frame(maxWidth: 300)
                    Button("Search a place instead") { showSearch = true }.buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 260)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: model.following) {
            waitedLong = false
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            waitedLong = true
        }
    }

    var slowFixHint: String {
        #if targetEnvironment(simulator)
        return "The Simulator has no GPS. In the Simulator menu choose Features › Location › Custom Location (or Apple)."
        #else
        let e = model.location.lastError.map { "\($0). " } ?? ""
        return e + "GPS can take a moment indoors. Step outside, or search a place."
        #endif
    }

    func footer(_ s: SiteData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.briefing?.credits ?? "")
            Text("AirField is a planning aid. It doesn't authorize flights; check conditions on site, and you remain the pilot in command.")
            Text(String(format: "%.4f, %.4f", s.lat, s.lon) + (s.elevationM.map { "  ·  \(Units.round($0 * 3.28084)) ft" } ?? ""))
        }
        .font(.caption).foregroundStyle(Color.ink3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// The "rolling drum", tuned to match the field web page: a block sits flat while any part of it is in the
    /// middle band of the screen (±18% of its height); past that it tilts back up to ~20°, shrinks a little and dims,
    /// in proportion to how far its nearest edge is from that band.
    func roll() -> some View {
        visualEffect { content, proxy in
            let f = proxy.frame(in: .scrollView(axis: .vertical))
            let vh = max(proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? 800, 1)
            let mid = vh / 2, band = vh * 0.18
            var d: CGFloat = 0
            if f.maxY < mid - band { d = (f.maxY - (mid - band)) / vh }        // above the middle: negative
            else if f.minY > mid + band { d = (f.minY - (mid + band)) / vh }   // below the middle: positive
            d = min(max(d, -0.6), 0.6)
            return content
                .rotation3DEffect(.degrees(Double(-d * 34)), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
                .scaleEffect(1 - abs(d) * 0.10)
                .opacity(1 - abs(d) * 0.75)
        }
    }
}

// MARK: - snap each section to the middle of the screen

/// One resting place on the page: a scroll offset, plus the section and edge to scroll to for it.
struct SnapStop {
    var y: CGFloat
    var id: Int
    var anchor: UnitPoint
}

/// Where each section sits inside the scroll content (content coordinates, so they don't move as you scroll).
final class SnapStore {
    static let space = "snap"
    var frames: [Int: CGRect] = [:]
    /// The visible part of the content (iOS 18+), in the same content coordinates as `frames`.
    var visible: CGRect = .zero
    /// iOS 18+: how scroll offsets map onto content coordinates, and the offset range (safe-area insets included).
    var shift: CGFloat = 0
    var minOffset: CGFloat = 0, maxOffset: CGFloat = 0
    /// Current scroll offset (iOS 18+), i.e. where the finger let go when a flick's target is being decided.
    var offset: CGFloat = 0
    /// Offset when the finger last touched down, so a slow drag still has a direction when it's let go.
    var dragStart: CGFloat?
    var calibrated = false
    /// Recent (time, offset) samples while the finger is down: the release speed, measured here in points
    /// per second rather than trusting any one API's units or coordinate space.
    var touching = false
    var samples: [(t: TimeInterval, y: CGFloat)] = []
    /// Which way the last release was heading (+1 down the page, −1 up), for settling after a free coast.
    var lastDir: CGFloat = 0
    /// Speed at the last release (pt/s), so the glide carries it on instead of starting from a standstill.
    var releaseVelocity: CGFloat = 0
    /// What was on screen when the finger touched down (same content coordinates as `frames`).
    var visibleStart: CGRect = .zero
    /// The tall section the last release left you reading, so a coast that runs past its end settles on it.
    var reading: Int?
    /// A section taller than this share of the screen is read by scrolling, not centred.
    static let tallShare: CGFloat = 0.85

    /// Sections too tall to centre, top to bottom.
    private func tallSections() -> [(id: Int, f: CGRect)] {
        frames.filter { $0.key != -1 && $0.key != 99 && $0.value.height > visible.height * Self.tallShare }
            .map { (id: $0.key, f: $0.value) }.sorted { $0.f.minY < $1.f.minY }
    }
    /// Glide targets that put a section's last line at the bottom of the screen, or its first line at the top,
    /// measured from where it is on screen right now (no offset bookkeeping to drift out of step).
    private func endStop(_ id: Int, _ f: CGRect) -> SnapStop { SnapStop(y: offset + f.maxY - visible.maxY, id: id, anchor: .bottom) }
    private func startStop(_ id: Int, _ f: CGRect) -> SnapStop { SnapStop(y: offset + f.minY - visible.minY, id: id, anchor: .top) }

    /// Stops closer than this are one stop, so a small scroll always reaches a new section.
    static let merge: CGFloat = 90
    /// A drag this long (pt) with no flick at the end still counts as "go to the next one".
    static let nudge: CGFloat = 12
    /// A stop within this of where you are counts as the one you're on (a glide can land a few points off,
    /// safe-area rounding), so "next" is always a different section.
    static let slack: CGFloat = 24
    /// Below this release speed (pt/s) it's a drag that stopped, not a flick.
    static let flickSpeed: CGFloat = 150

    struct Tall { var range: ClosedRange<CGFloat>; var top: SnapStop; var bottom: SnapStop }

    func record(_ y: CGFloat) {
        guard touching else { return }
        let t = ProcessInfo.processInfo.systemUptime
        samples.append((t, y)); samples.removeAll { t - $0.t > 0.15 }
    }
    private var releaseSpeed: CGFloat {
        let now = ProcessInfo.processInfo.systemUptime
        let recent = samples.filter { now - $0.t <= 0.1 }       // a finger that stopped before lifting has no speed
        guard let a = recent.first, let b = recent.last, b.t - a.t > 0.012 else { return 0 }
        return (b.y - a.y) / CGFloat(b.t - a.t)
    }

    /// Every resting place, top to bottom, in scroll-offset space; plus the stretches inside sections taller
    /// than the screen, where you read freely.
    func stops(viewHeight vh: CGFloat, shift: CGFloat, lo: CGFloat, hi: CGFloat) -> (stops: [SnapStop], tall: [Tall]) {
        let off = { (contentTop: CGFloat) in min(max(contentTop - shift, lo), hi) }
        var raw: [SnapStop] = [SnapStop(y: lo, id: -1, anchor: .top), SnapStop(y: hi, id: 99, anchor: .bottom)]
        var tall: [Tall] = []
        for (id, f) in frames where id != -1 && id != 99 {
            if f.height <= vh * Self.tallShare {                       // fits on screen: centre it
                raw.append(SnapStop(y: off(f.midY - vh / 2), id: id, anchor: .center))
            } else {
                let a = SnapStop(y: off(f.minY), id: id, anchor: .top), b = SnapStop(y: off(f.maxY - vh), id: id, anchor: .bottom)
                raw += [a, b]
                if b.y > a.y { tall.append(Tall(range: a.y...b.y, top: a, bottom: b)) }
            }
        }
        raw.sort { $0.y < $1.y }
        // Fold near-duplicates (the page top and a section centred just below it, say) into one stop,
        // keeping the page ends, so a nudge never lands on a "new" stop that shows the same thing.
        var out: [SnapStop] = []
        for s in raw {
            guard let last = out.last, s.y - last.y < Self.merge else { out.append(s); continue }
            if s.id == 99 && last.id != -1 { out[out.count - 1] = s }
        }
        return (out, tall)
    }

    /// Where to go from `from`, with `to` where momentum alone would coast.
    /// Every section lands centred. A drag that stopped goes on to the next one that way, never back.
    /// A flick goes to the first section its momentum hasn't reached yet: if the speed carried it past a
    /// section, it keeps going to the next one rather than being pulled back (only a hair past counts as there).
    /// Sections a flick can't skip by accident: Airspace is short and sits right under the dial, so an ordinary
    /// flick from the top (or up from Right now) would fly straight past it. It's only skipped by a flick strong
    /// enough to also carry past the section beyond it.
    static let sticky: Set<Int> = [1]

    static func destination(stops: [SnapStop], from: CGFloat, to: CGFloat, dragged: CGFloat) -> SnapStop? {
        guard !stops.isEmpty else { return nil }
        let flick = to - from
        let dir: CGFloat = abs(flick) > 2 ? flick : (abs(dragged) >= nudge ? dragged : 0)
        if dir == 0 { return stops.min { abs($0.y - from) < abs($1.y - from) } }
        // walk the stops in the direction of travel, measured as distance from `from`
        let s = dir > 0 ? stops : Array(stops.reversed())
        let sign: CGFloat = dir > 0 ? 1 : -1
        let ahead = s.filter { ($0.y - from) * sign > slack }
        guard let first = ahead.first else { return s.last }
        guard abs(flick) > 2 else { return first }
        let reach = (to - from) * sign
        let dist = { (t: SnapStop) in (t.y - from) * sign }
        var chosen: SnapStop
        if let after = ahead.first(where: { dist($0) >= reach }) {
            chosen = after
            if let before = ahead.last(where: { dist($0) < reach }) {
                let past = reach - dist(before), gap = abs(after.y - before.y)
                if past < 0.1 * gap { chosen = before }
            }
        } else {
            chosen = ahead.last!
        }
        // Don't fly past a sticky section unless the flick also carried past the section beyond it.
        if let i = ahead.firstIndex(where: { sticky.contains($0.id) && dist($0) < dist(chosen) }) {
            let beyond = i + 1 < ahead.count ? dist(ahead[i + 1]) : .infinity
            if reach < beyond { return ahead[i] }
        }
        return chosen
    }

    private var layout: (stops: [SnapStop], tall: [Tall])? {
        guard calibrated, visible.height > 0, !frames.isEmpty else { return nil }
        return stops(viewHeight: visible.height, shift: shift, lo: minOffset, hi: maxOffset)
    }

    /// The finger just lifted (iOS 18+): where to glide to, or nil to let it coast (reading inside a tall section).
    func release() -> SnapStop? {
        defer { touching = false; samples = []; dragStart = nil }
        guard let l = layout else { return nil }
        let stops = l.stops
        let v = releaseSpeed
        let dragged = dragStart.map { offset - $0 } ?? 0
        let flick = abs(v) >= Self.flickSpeed
        let dir: CGFloat = flick ? v : (abs(dragged) >= Self.nudge ? dragged : 0)
        lastDir = dir > 0 ? 1 : dir < 0 ? -1 : 0
        let projected = flick ? offset + v * 0.5 : offset      // where iOS's normal deceleration would coast to
        // Reading a section taller than the screen (Heads up with a long list, say): it scrolls freely, and
        // whenever its end comes on screen the page rests on that end. Only a swipe that STARTS with its end
        // already showing moves on to the next section. All judged from what is actually on screen, so it
        // can't be thrown off by safe-area insets or by where a glide happened to land.
        reading = nil
        let vis0 = visibleStart.height > 0 ? visibleStart : visible
        let moved = projected - offset                          // how much further a coast would carry the page
        let m: CGFloat = 8
        var leaving: Int?
        for (id, f) in tallSections() where f.minY < vis0.midY && f.maxY > vis0.midY {   // the one you were reading
            if dir > 0 {
                if f.maxY <= vis0.maxY + m || f.maxY < visible.minY + visible.height * 0.5 { leaving = id; break }
                reading = id
                if f.maxY <= visible.maxY + moved + m { let t = endStop(id, f); return abs(t.y - offset) <= 3 ? nil : t }
                return nil
            } else if dir < 0 {
                if f.minY >= vis0.minY - m || f.minY > visible.minY + visible.height * 0.5 { leaving = id; break }
                reading = id
                if f.minY >= visible.minY + moved - m { let t = startStop(id, f); return abs(t.y - offset) <= 3 ? nil : t }
                return nil
            }
            return nil                                          // no swipe: stay put
        }
        releaseVelocity = flick ? v : 0
        let d = Self.destination(stops: stops.filter { $0.id != leaving }, from: offset, to: projected, dragged: dragged)
        return d.flatMap { abs($0.y - offset) <= 3 ? nil : $0 }
    }

    /// A free coast inside a tall section came to rest (iOS 18+). If it drifted out between sections,
    /// carry on to the next one the way it was going.
    func settle() -> SnapStop? {
        guard let l = layout else { return nil }
        let stops = l.stops
        // Coasted until the end of the section you were reading came on screen: rest on that end.
        if let id = reading, let f = frames[id] {
            reading = nil
            if f.maxY < visible.maxY - 8 && f.maxY > visible.minY + visible.height * 0.5 { return endStop(id, f) }
            if f.minY > visible.minY + 8 && f.minY < visible.minY + visible.height * 0.5 { return startStop(id, f) }
        }
        if stops.contains(where: { abs($0.y - offset) <= 6 }) { return nil }
        // Still inside a tall section: leave it where you stopped reading.
        if tallSections().contains(where: { $0.f.minY < visible.midY && $0.f.maxY > visible.midY }) { return nil }
        return Self.destination(stops: stops, from: offset, to: offset, dragged: lastDir * Self.nudge)
    }
}

/// The magnet (iOS 18+): the moment the finger lifts, measure the flick and glide to the next section that way,
/// or further for a strong flick. It never pulls back to the section you left.
/// iOS 17 falls back to a scroll-target behaviour.
struct MagnetSnap: ViewModifier {
    let store: SnapStore
    let proxy: ScrollViewProxy
    @State private var pulls = 0

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, g in
                    store.visible = g.visibleRect
                    store.shift = g.visibleRect.minY - g.contentOffset.y
                    store.offset = g.contentOffset.y
                    store.minOffset = -g.contentInsets.top
                    store.maxOffset = max(store.minOffset, g.contentSize.height + g.contentInsets.bottom - g.containerSize.height)
                    store.calibrated = true
                    store.record(g.contentOffset.y)
                }
                .onScrollPhaseChange { old, new in
                    let touching = { (p: ScrollPhase) in p == .tracking || p == .interacting }
                    if touching(new) && !touching(old) {                       // finger down
                        store.dragStart = store.offset; store.visibleStart = store.visible; store.samples = []; store.touching = true
                        store.record(store.offset)
                    } else if touching(old) && !touching(new) {                // finger up
                        if let t = store.release() { glide(t) }
                    } else if new == .idle && old == .decelerating {           // a free coast ended
                        if let t = store.settle() { glide(t) }
                    }
                }
                .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: pulls)
        } else {
            content.scrollTargetBehavior(CenterSnap(store: store))
        }
    }

    private func glide(_ t: SnapStop) {
        pulls += 1
        // A critically damped spring that starts at the flick's own speed: it keeps the momentum and eases
        // to rest on the section, like a natural deceleration that happens to stop in the right place.
        let distance: CGFloat = t.y - store.offset
        var v0: Double = 0                                     // speed relative to the distance to go
        if abs(distance) > 1 { v0 = Double(store.releaseVelocity / distance) }
        v0 = min(max(v0, 0), 6)
        let k: Double = 110
        let damping: Double = 2 * k.squareRoot()                 // critically damped: no bounce
        store.releaseVelocity = 0
        let glideAnimation = Animation.interpolatingSpring(mass: 1, stiffness: k, damping: damping, initialVelocity: v0)
        withAnimation(glideAnimation) {
            proxy.scrollTo(t.id, anchor: t.anchor)
        }
    }
}

struct SnapFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
}

extension View {
    /// Marks a section as a snap stop: records where it sits in the content and gives it an id to scroll to.
    func snap(_ id: Int) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: SnapFramesKey.self, value: [id: g.frame(in: .named(SnapStore.space))])
        })
        .id(id)
    }
}

/// iOS 17 only (iOS 18 uses MagnetSnap's glide): decides where a flick comes to rest, onward in its direction.
/// Works purely in the scroll target's own coordinates, with the page top at 0.
struct CenterSnap: ScrollTargetBehavior {
    let store: SnapStore
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let vh = context.containerSize.height
        let hi = max(0, context.contentSize.height - vh)
        let (stops, tall) = store.stops(viewHeight: vh, shift: 0, lo: 0, hi: hi)
        guard !stops.isEmpty else { return }
        let to = target.rect.minY                                   // where momentum alone would take it
        let from = to - context.velocity.dy * 0.5                   // about where the finger let go
        // Reading inside a tall section: scroll freely, but never fly past its edges in one flick.
        for z in tall {
            let zTop: CGFloat = z.range.lowerBound, zEnd: CGFloat = z.range.upperBound
            let inZone: Bool = from > zTop - 1 && from < zEnd + 1
            let leavingTop: Bool = from <= zTop + 1 && to < from       // at its top edge heading up: leave normally
            let leavingBottom: Bool = from >= zEnd - 1 && to > from    // at its bottom edge heading down: leave normally
            if inZone && !leavingTop && !leavingBottom {
                target.rect.origin.y = min(max(to, zTop), zEnd)
                return
            }
        }
        if let dest = SnapStore.destination(stops: stops, from: from, to: to, dragged: 0) {
            target.rect.origin.y = dest.y
        }
    }
}

/// The sky dial plus its compass button. It watches the compass itself, so the dial turns smoothly
/// without redrawing the rest of the dashboard on every heading update.
struct CompassDial: View {
    let site: SiteData
    let briefing: Briefing
    @ObservedObject var location: LocationService
    @Binding var compassOn: Bool

    var body: some View {
        SkyDial(site: site, briefing: briefing, heading: compassOn ? location.heading : nil)
            .overlay(alignment: .topLeading) { chip }
    }

    var chip: some View {
        Button { compassOn.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "location.north.line").font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(.footnote, design: .monospaced))
            }
            .padding(.horizontal, 10).frame(height: 30)
            .foregroundStyle(compassOn ? Color.black : Color.ink2)
            .background(compassOn ? Color.ink : Color.surface, in: Capsule())
            .overlay(Capsule().stroke(compassOn ? Color.ink : Color.line, lineWidth: 1))
        }
        .accessibilityLabel(compassOn ? "Dial turns with your heading. Switch to north up" : "Turn the dial with the compass")
    }
    var text: String {
        guard compassOn else { return "North up" }
        guard let h = location.heading else { return "Calibrating…" }
        return "\(Units.compass(h)) \(String(format: "%03d", Int(h.rounded()) % 360))°"
    }
}
