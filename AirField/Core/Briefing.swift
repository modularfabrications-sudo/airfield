import Foundation

/// Everything the dashboard shows, already worded and formatted. Built from SiteData + FlightProfile.
public struct Briefing: Sendable {
    public struct Verdict: Sendable {
        public var level: Level
        public var word: String
        public var why: String
        public var next: String?
        public var reasons: [Reason]
    }
    public struct Tile: Identifiable, Sendable {
        public var id: TileKind
        public var title: String
        public var value: String
        public var unit: String
        public var detail: String
        public var level: Level?
        public var meter: Meter?
        public var editable: Bool = false
    }
    public struct Meter: Sendable { public var value: Double; public var max: Double; public var mark: Double }
    public struct AirspaceCard: Sendable {
        public var level: Level
        public var title: String
        public var detail: String
        public var action: String
        public var url: String
    }
    public struct HeadsUp: Identifiable, Sendable {
        public var id = UUID()
        public var level: Level
        public var title: String
        public var detail: String
        public var source: String?
        public var more: String?
        public var at: Date
        public var official: Bool
    }
    public struct Hour: Identifiable, Sendable {
        public var id: Date { time }
        public var time: Date
        public var level: Level
        public var reason: String?
        /// Every reason this hour isn't a plain go, worst first, word for word.
        public var reasons: [String] = []
        public var irradiance: Double?
        public var wind: Double?, gust: Double?, aloft: Double?
        public var cloud: Double?, rainChance: Double?
        public var temp: Double?
        public var night: Bool
    }
    public struct Day: Identifiable, Sendable {
        public var id: Int
        public var date: Date
        public var title: String
        public var subtitle: String
        /// 24 cells, local hours 0–23; nil where there's no forecast.
        public var cells: [Level?]
        /// Per-cell details for the drag readout: the hour, its main reason, and wind.
        public var times: [Date?] = Array(repeating: nil, count: 24)
        public var reasons: [String?] = Array(repeating: nil, count: 24)
        public var winds: [String?] = Array(repeating: nil, count: 24)
        public var pastCells: Int
        public var summary: String
        public var high: String, low: String, gust: String, rain: String
    }

    public var verdict: Verdict
    public var tiles: [Tile]
    public var airspace: AirspaceCard
    public var headsUp: [HeadsUp]
    public var hours: [Hour]
    public var days: [Day]
    public var sunTimes: SunTimes
    public var sunNow: SunPosition
    public var windDirNow: Double?
    public var windNowText: String
    public var glare: (elevation: Double, azimuth: Double)?
    /// Where the panels face in the sky (panel work only): the sun and its glare mirror each other across it.
    public var panelNormal: (elevation: Double, azimuth: Double)? = nil
    public var sunNotes: String
    public var sourceNote: String
    /// Footer credit line for the data actually used.
    public var credits: String
    public var units: Units
    public var irradianceTitle: String
    public var windLimitDisplay: Double
}

public enum BriefingBuilder {
    public static func build(_ s: SiteData, profile p: FlightProfile, now: Date = Date()) -> Briefing {
        let u = Units(imperial: p.imperial, utcOffset: s.utcOffset)
        let v = p.variant, L = WindLimits.derive(for: p)

        // per-hour assessments
        let assessed = s.hourly.map { ($0, Rules.assess($0, profile: p, space: s.space, units: u)) }
        var nowA = Rules.assess(s.now, profile: p, space: s.space, units: u)

        // active official alerts join the call
        var extra: [Reason] = []
        for a in s.alerts where isActive(a, now) { extra.append(Reason(a.isFlightThreat ? .hold : .caution, a.event)) }
        if !extra.isEmpty { nowA = Assessment(reasons: extra + nowA.reasons) }

        // verdict
        let lvl = nowA.level
        let top = nowA.reasons.filter { $0.level == lvl }.map(\.text)
        let why: String
        if lvl == .go {
            if v.checks.contains(.solarWindow) {
                why = "\(Units.round(s.now.gti)) W/m² on the panels, \(Units.round(s.now.cloud))% cloud, wind \(u.speedText(s.now.windMS))."
            } else if v.checks.contains(.prefersDark) {
                why = "Dark, wind \(u.speedText(s.now.windMS)), \(Units.round(s.now.cloud))% cloud."
            } else {
                why = "Wind \(u.speedText(s.now.windMS)), gusts \(u.speedNumber(s.now.gustMS)), \(WMO.describe(s.now.code).lowercased())."
            }
        } else { why = top.prefix(2).joined(separator: ", ") + "." }
        let verdict = Briefing.Verdict(level: lvl, word: v.checks.contains(.solarWindow) && lvl == .go ? "In window" : lvl.word, why: why, next: nextWindow(assessed, nowLevel: lvl, now: now, u: u, solar: v.checks.contains(.solarWindow)),
                                       reasons: Array(nowA.reasons.dropFirst(lvl == .go ? 0 : min(2, top.count)).prefix(6)))

        // tiles
        let tiles = v.tiles.compactMap { tile($0, s: s, p: p, u: u, L: L) }

        // 48 h
        let startIdx = max(0, (s.hourly.firstIndex { $0.time > now } ?? 1) - 1)
        let hours = assessed[startIdx..<min(assessed.count, startIdx + 48)].map { (c, a) in
            Briefing.Hour(time: c.time, level: a.level, reason: a.reasons.first?.text, reasons: a.reasons.filter { $0.level > .go }.map(\.text),
                          irradiance: v.usesPanelPlane ? c.gti : c.ghi, wind: c.windMS, gust: c.gustMS, aloft: c.windAloftMS,
                          cloud: c.cloud, rainChance: c.precipChance, temp: c.tempC, night: !c.isDaylight)
        }

        // sun
        let st = Sun.times(on: now, lat: s.lat, lon: s.lon, utcOffset: s.utcOffset)
        var glare: (Double, Double)? = nil
        if v.usesPanelPlane, s.now.sun.elevation > 0 {
            let g = Sun.glare(sun: s.now.sun, tilt: p.panelTilt, facing: p.panelFacing)
            if g.lit, g.reflectionElevation > 0 { glare = (g.reflectionElevation, g.reflectionAzimuth) }
        }

        // Outside the US there's no FAA grid at all; don't let "no grid" read as "uncontrolled".
        let card: Briefing.AirspaceCard
        if s.sources.outsideUS, s.airspace == .noGrid || s.airspace == .unknown {
            card = .init(level: .caution, title: "Outside FAA coverage",
                         detail: "LAANC and FAA airspace data cover the United States only. Check your country's drone rules and airspace before flying.",
                         action: "More in AirField support", url: Site.support)
        } else {
            card = airspaceCard(s.airspace, rules: p.rules, u: u)
        }
        return Briefing(verdict: verdict, tiles: tiles, airspace: card,
                        headsUp: surprises(s, assessed: Array(assessed[startIdx...]), profile: p, units: u, now: now, limits: L),
                        hours: hours, days: days(assessed, u: u, now: now, solar: v.checks.contains(.solarWindow), variant: v),
                        sunTimes: st, sunNow: s.now.sun, windDirNow: s.now.windDir, windNowText: u.speedText(s.now.windMS),
                        glare: glare, panelNormal: v.usesPanelPlane ? (90 - p.panelTilt, p.panelFacing) : nil, sunNotes: sunNotes(st, s: s, p: p, u: u),
                        sourceNote: sourceNote(s, now: now),
                        credits: credits(s.sources), units: u, irradianceTitle: v.usesPanelPlane ? "Irradiance on panels" : "Sunlight",
                        windLimitDisplay: u.speed(L.sustainedHold) ?? 0)
    }

    static func sourceNote(_ s: SiteData, now: Date) -> String {
        let src = s.sources
        if src.forecast == .openMeteo { return s.nowcast ? "NOAA HRRR, 15-min" : "Hourly model" }
        if let st = src.station, let km = src.stationKm {
            let mins = src.observedAt.map { max(0, Int(now.timeIntervalSince($0) / 60)) }
            return "\(st) obs, \(Units.round(km)) km" + (mins.map { $0 < 90 ? ", \($0) min ago" : "" } ?? "")
        }
        let base = src.forecast == .nws ? "NWS forecast for this spot" : "MET Norway forecast for this spot"
        if let nb = s.now.nearby { return base + "; \(nb.station) is \(Units.round(nb.km)) km away" }
        return base
    }

    static func credits(_ src: SourceInfo) -> String {
        let fc: String
        switch src.forecast {
        case .nws: fc = "Forecast: National Weather Service. Now: an airport report (aviationweather.gov) when one is within 10 km, otherwise the forecast for this spot."
        case .metNorway: fc = "Forecast: MET Norway (CC BY 4.0). Now: an airport report (aviationweather.gov) when one is within 10 km, otherwise the forecast for this spot."
        case .openMeteo: fc = "Forecast: Open-Meteo (NOAA HRRR and GFS, CC BY 4.0)."
        }
        let est = src.estimated ? " Panel irradiance, UV and 400 ft wind are calculated from sky cover, sun position and surface wind." : ""
        return fc + " Alerts: National Weather Service. Space weather: NOAA SWPC. Airspace: FAA UAS Facility Map." + est
    }

    static func isActive(_ a: WeatherAlert, _ now: Date) -> Bool {
        (a.onset == nil || a.onset! <= now) && (a.ends == nil || a.ends! >= now)
    }

    // MARK: next window

    static func nextWindow(_ hs: [(Conditions, Assessment)], nowLevel: Level, now: Date, u: Units, solar: Bool) -> String? {
        guard let cur = hs.lastIndex(where: { $0.0.time <= now }) else { return nil }
        let start = nowLevel == .go ? cur : cur + 1
        guard start < hs.count, let s = (start..<min(hs.count, cur + 72)).first(where: { hs[$0].1.level == .go }) else {
            return "No clear window in the next 3 days"
        }
        var e = s; while e + 1 < hs.count && hs[e + 1].1.level == .go { e += 1 }
        let end = hs[e].0.time.addingTimeInterval(3600)
        if s == cur && nowLevel == .go { return "Good until \(u.when(end, now: now))" }
        return "Next \(solar ? "inspection " : "")window \(u.when(hs[s].0.time, now: now)) – \(u.clock(end)) (\(e - s + 1) h)"
    }

    // MARK: tiles

    static func tile(_ k: TileKind, s: SiteData, p: FlightProfile, u: Units, L: WindLimits) -> Briefing.Tile? {
        let n = s.now
        func lv(_ x: Double?, _ c: Double, _ h: Double) -> Level? { guard let x else { return nil }; return x > h ? .hold : x > c ? .caution : .go }
        switch k {
        case .wind:
            let l = max(lv(n.windMS, L.sustainedCaution, L.sustainedHold) ?? .go, lv(n.gustMS, L.gustCaution, L.gustHold) ?? .go)
            return .init(id: k, title: "Wind", value: u.speedNumber(n.windMS), unit: u.speedUnit,
                         detail: "from \(Units.compass(n.windDir)), gusts \(u.speedNumber(n.gustMS))", level: l)
        case .windAloft:
            return .init(id: k, title: "Wind at \(u.altitudeLabel400)", value: u.speedNumber(n.windAloftMS), unit: u.speedUnit,
                         detail: (s.sources.estimated ? "Estimated from surface wind" : "Model level 120 m") + "; hold above \(u.speedNumber(L.aloftHold))",
                         level: lv(n.windAloftMS, L.aloftCaution, L.aloftHold))
        case .irradiance:
            if p.variant.usesPanelPlane {
                let l: Level? = p.variant.checks.contains(.solarWindow) ? (n.sun.elevation < 5 ? .hold : ((n.gti ?? 0) >= Rules.solarIrradiance ? .go : .caution)) : nil
                return .init(id: k, title: "Irradiance on panels", value: Units.round(n.gti), unit: "W/m²",
                             detail: "\(Units.round(p.panelTilt))° tilt facing \(Units.compass(p.panelFacing)); \(Units.round(n.ghi)) flat" + (s.sources.estimated ? "; calculated" : ""),
                             level: l, meter: .init(value: n.gti ?? 0, max: 1100, mark: Rules.solarIrradiance), editable: true)
            }
            return .init(id: k, title: "Sunlight", value: Units.round(n.ghi), unit: "W/m²", detail: "On flat ground, \(Units.round(n.cloud))% cloud",
                         level: nil, meter: .init(value: n.ghi ?? 0, max: 1100, mark: Rules.solarIrradiance))
        case .sky:
            let rain = n.precipChance.map { ", \(Units.round($0))% rain chance" } ?? ""
            return .init(id: k, title: "Sky", value: Units.round(n.cloud), unit: "% cloud", detail: WMO.describe(n.code) + rain, level: nil)
        case .visibility:
            let (val, unit) = u.visibility(n.visibilityM)
            let base = Physics.cloudBaseM(tempC: n.tempC, dewC: n.dewC)
            let detail = n.ceilingM.map { "Ceiling \(u.heightText($0))" }
                ?? (((n.cloudLow ?? 0) >= 30 && base != nil) ? "Cloud base ~\(u.heightText(base))" : "No low cloud")
            let l: Level? = n.visibilityM.map { $0 < Rules.visibilityMinM ? (p.rules == .part107 ? .hold : .caution) : .go }
            return .init(id: k, title: "Visibility", value: val, unit: unit, detail: detail, level: l)
        case .air:
            let spread = (n.tempC != nil && n.dewC != nil) ? n.tempC! - n.dewC! : nil
            var detail = "Dew point \(u.tempNumber(n.dewC))°, \(Units.round(n.humidity))% RH"
            if let sp = spread, sp <= 2.5 { detail += ". Condensation risk" }
            if let t = n.tempC, t < p.drone.tempMinC + 5, t >= p.drone.tempMinC { detail += ". Warm batteries" }
            let l: Level? = n.tempC.map { ($0 < p.drone.tempMinC || $0 > p.drone.tempMaxC) ? .hold : .go }
            return .init(id: k, title: "Air", value: u.tempNumber(n.tempC), unit: u.tempUnit, detail: detail, level: l)
        case .light:
            let st = Sun.times(on: n.time, lat: s.lat, lon: s.lon, utcOffset: s.utcOffset)
            let el = n.sun.elevation
            let phase = el >= 6 ? "Daylight" : el >= -4 ? (el >= -0.833 ? "Golden hour" : "Golden hour") : el >= -6 ? "Blue hour" : "Night"
            var detail: String
            if let gs = st.goldenEveningStart, n.time < gs { detail = "Golden hour \(u.clock(gs))–\(u.clock(st.sunset))" }
            else if let dusk = st.civilDusk, n.time < dusk { detail = "Sunset \(u.clock(st.sunset)), dusk \(u.clock(dusk))" }
            else {
                let tomorrow = Sun.times(on: n.time.addingTimeInterval(86400), lat: s.lat, lon: s.lon, utcOffset: s.utcOffset)
                detail = "Sunrise \(u.clock(tomorrow.sunrise)), golden until \(u.clock(tomorrow.goldenMorningEnd))"
            }
            return .init(id: k, title: "Light", value: phase, unit: el > 0 ? "\(Units.round(el))°" : "", detail: detail, level: nil)
        case .densityAltitude:
            guard let da = Physics.densityAltitudeM(pressureHPa: n.pressureHPa, tempC: n.tempC) else { return nil }
            let l: Level = da > p.drone.ceilingM ? .hold : da > p.drone.ceilingM - 600 ? .caution : .go
            let payload = DroneCatalog.maxPayloadKg(droneID: p.drone.id, densityAltitudeM: da).map {
                "Max payload " + (u.imperial ? "\(Units.round($0 * 2.20462, 1)) lb" : "\(Units.round($0, 1)) kg")
            }
            return .init(id: k, title: "Density altitude", value: Units.round((u.height(da)! / 100).rounded() * 100), unit: u.heightUnit,
                         detail: payload ?? "Drone ceiling \(u.heightText(p.drone.ceilingM, roundTo: 100))", level: l)
        case .gnss:
            let kp = s.space.kpNow
            let detail: String
            if let kp {
                detail = (kp >= 7 ? "Strong storm: GPS may wander, RTK likely drops" : kp >= 5 ? "Minor storm: RTK fixes may drop" : kp >= 4 ? "Unsettled: watch fix status" : "Quiet: good for GPS/RTK")
                    + (s.space.kpMax24h.map { "; up to \(Units.round($0, 1)) next 24 h" } ?? "")
            } else { detail = "Space weather unavailable" }
            return .init(id: k, title: "GPS / RTK", value: Units.round(kp, 1), unit: "Kp", detail: detail,
                         level: kp.map { $0 >= Rules.kpCaution(gnssSensitive: p.variant.checks.contains(.gnssSensitive)) ? .caution : .go })
        case .smoke:
            guard n.aqi != nil else { return nil }          // no air-quality feed: leave the tile out rather than show a blank
            return .init(id: k, title: "Smoke and haze", value: Units.round(n.aqi), unit: "US AQI",
                         detail: (n.aqi ?? 0) > 100 ? "Reduced contrast and color" : (n.aqi == nil ? "Air quality unavailable" : "Clear air"),
                         level: n.aqi.map { $0 > 150 ? .caution : .go })
        case .uv:
            return .init(id: k, title: "UV index", value: Units.round(n.uv), unit: "", detail: "Pilot sun exposure", level: nil)
        case .spray:
            guard let w = n.windMS else { return nil }
            let l: Level = w > Rules.sprayWindMaxMS ? .hold : w < Rules.sprayWindMinMS ? .caution : .go
            let text = l == .hold ? "Too windy" : l == .caution ? "Too calm" : "In range"
            return .init(id: k, title: "Spray drift", value: text, unit: "",
                         detail: "\(u.speedText(w)) now; common label range \(u.speedNumber(Rules.sprayWindMinMS))–\(u.speedNumber(Rules.sprayWindMaxMS)) \(u.speedUnit). Always follow the label.", level: l)
        }
    }

    // MARK: airspace

    static func airspaceCard(_ a: Airspace, rules: PilotRules, u: Units) -> Briefing.AirspaceCard {
        let link = "https://www.faa.gov/uas/getting_started/laanc"
        switch a {
        case .laancGrid(let ceil, let apt):
            let place = apt.map { " near \($0.capitalized)" } ?? ""
            if ceil == 0 {
                return .init(level: .hold, title: "Controlled airspace\(place)",
                             detail: "LAANC can't approve flights at this spot (0 ft grid). You need a further-coordination request through FAA DroneZone.",
                             action: "How to get authorization", url: link)
            }
            return .init(level: .caution, title: "Controlled airspace\(place)",
                         detail: "LAANC authorization required, available up to \(u.imperial ? "\(ceil) ft" : "\(Int((Double(ceil) * 0.3048).rounded())) m") AGL here. Request it in an FAA-approved LAANC app before flying.",
                         action: "Get LAANC authorization", url: link)
        case .noGrid:
            return .init(level: .go, title: "No LAANC grid here",
                         detail: "Usually uncontrolled Class G airspace: up to \(u.altitudeLabel400) without authorization. Still check TFRs, NOTAMs, parks and local rules.",
                         action: "Check B4UFLY", url: "https://www.faa.gov/uas/getting_started/b4ufly")
        case .unknown:
            return .init(level: .caution, title: "Airspace unavailable",
                         detail: "Couldn't reach the FAA facility map. Check airspace in B4UFLY or a LAANC app before flying.",
                         action: "Check B4UFLY", url: "https://www.faa.gov/uas/getting_started/b4ufly")
        }
    }

    // MARK: heads up

    static func surprises(_ s: SiteData, assessed: [(Conditions, Assessment)], profile p: FlightProfile, units u: Units, now: Date, limits L: WindLimits) -> [Briefing.HeadsUp] {
        var out: [Briefing.HeadsUp] = []
        for a in s.alerts {
            let active = isActive(a, now)
            let when = active ? (a.ends.map { "In effect until \(u.when($0, now: now))." } ?? "In effect now.")
                : (a.onset.map { "From \(u.when($0, now: now))" + (a.ends.map { " until \(u.when($0, now: now))." } ?? ".") } ?? "")
            out.append(.init(level: a.isFlightThreat ? .hold : .caution, title: a.event, detail: when, source: a.sender,
                             more: [a.headline, a.description, a.instruction].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                             at: a.onset ?? now, official: true))
        }
        let H = assessed.map(\.0)
        guard let first = H.first else { return out }
        let end = min(H.count, 25)
        func firstIndex(from: Int = 1, to: Int = end, _ f: (Int) -> Bool) -> Int? { (from..<max(from, to)).first(where: f) }
        var covered: [String] = []
        func add(_ l: Level, _ t: String, _ d: String, _ i: Int) {
            out.append(.init(level: l, title: t, detail: d, source: nil, more: nil, at: H[i].time, official: false))
            switch t {
            case "Thunderstorms", "Thunder possible", "Storm potential": covered += ["Thunder", "Storm potential"]
            case "Gusts over your limit": covered += ["Gusts"]
            case "Rain coming", "Snow coming": covered += ["Rain", "Light precipitation", "Heavy rain", "Snow"]
            case "Visibility drops": covered += ["Visibility", "Low visibility"]
            case "Fog or dew likely", "Icing risk": covered += ["Fog"]
            default: break
            }
        }

        if let i = firstIndex(from: 0, { WMO.isStorm(H[$0].code) }) {
            add(.hold, "Thunderstorms", "Forecast from \(u.when(H[i].time, now: now)). Land well before: lightning reaches miles ahead of the rain.", i)
        } else if let i = firstIndex({ (H[$0].thunderChance ?? 0) >= 25 }) {
            let peak = H[i..<end].compactMap(\.thunderChance).max() ?? H[i].thunderChance ?? 0
            add(.caution, "Thunder possible", "\(Units.round(peak))% chance of thunder from \(u.when(H[i].time, now: now)). Watch the sky and land at the first rumble.", i)
        } else if let i = firstIndex({ (H[$0].cape ?? 0) >= 1000 && (H[$0].precipChance ?? 0) >= 30 }) {
            add(.caution, "Storm potential", "Unstable air with \(Units.round(H[i].precipChance))% rain chance around \(u.when(H[i].time, now: now)).", i)
        }
        if let i = firstIndex({ (H[$0].gustMS ?? 0) > L.gustHold }) {
            let peak = H[i..<end].compactMap(\.gustMS).max()
            add(.hold, "Gusts over your limit", "Gusts reach \(u.speedText(H[i].gustMS)) by \(u.when(H[i].time, now: now)), peaking near \(u.speedText(peak)).", i)
        }
        if let w0 = first.windMS, let i = firstIndex(to: min(end, 5), { (H[$0].windMS ?? 0) - w0 >= 4.5 }) {
            add(.caution, "Wind picking up", "From \(u.speedText(w0)) to \(u.speedText(H[i].windMS)) by \(u.when(H[i].time, now: now)).", i)
        }
        if let i = firstIndex(from: 0, { let a = H[$0].windAloftMS ?? 0, g = H[$0].windMS ?? 0; return a - g >= 5.4 && a > L.aloftCaution }) {
            add(.caution, "Stronger wind at altitude", "\(u.speedText(H[i].windAloftMS)) at \(u.altitudeLabel400) vs \(u.speedText(H[i].windMS)) at the ground around \(u.when(H[i].time, now: now)).", i)
        }
        if (s.now.precipMM ?? 0) == 0, let i = firstIndex({ (H[$0].precipChance ?? 0) >= 50 || (H[$0].precipMM ?? 0) >= 0.25 }) {
            add(.caution, WMO.isSnow(H[i].code) ? "Snow coming" : "Rain coming", "\(Units.round(H[i].precipChance))% chance from \(u.when(H[i].time, now: now)).", i)
        }
        if let i = firstIndex({ (H[$0].visibilityM ?? 1e9) < Rules.visibilityMinM }) {
            add(p.rules == .part107 ? .hold : .caution, "Visibility drops", "Under 3 miles around \(u.when(H[i].time, now: now)).", i)
        }
        if let i = firstIndex(from: 3, to: min(end, 5), { k in
            guard let t = H[k].tempC, let t3 = H[k - 3].tempC else { return false }
            return H[k].sun.elevation > 10 && H[k - 1].sun.elevation > 10 && t3 - t >= 5.5 }) {
            add(.caution, "Front moving through", "Temperature falls \(u.tempDelta(H[i - 3].tempC! - H[i].tempC!)) in 3 hours by \(u.when(H[i].time, now: now)); expect a wind shift.", i)
        }
        if let i = firstIndex({ k in
            guard let t = H[k].tempC, let d = H[k].dewC else { return false }
            return t - d <= 1.7 && t <= 2 && t >= -10 && ((H[k].cloudLow ?? 0) >= 60 || (H[k].precipMM ?? 0) > 0 || (H[k].visibilityM ?? 1e9) < 5000) }) {
            add(.caution, "Icing risk", "Near-freezing saturated air around \(u.when(H[i].time, now: now)). Ice on props kills lift.", i)
        } else if let i = firstIndex({ k in guard let t = H[k].tempC, let d = H[k].dewC else { return false }; return t - d <= 1.1 }) {
            add(.caution, "Fog or dew likely", "Air near saturation around \(u.when(H[i].time, now: now)). Dew on lenses and panels.", i)
        }
        if p.variant.checks.contains(.solarWindow) {
            let inWin: (Conditions) -> Bool = { $0.isDaylight && ($0.gti ?? 0) >= Rules.solarIrradiance && ($0.cloud ?? 100) <= Rules.solarCloudMax }
            if inWin(first), let i = firstIndex(to: min(end, 5), { !inWin(H[$0]) && H[$0].sun.elevation > 15 }) {
                add(.caution, "Inspection window closing", "Irradiance or cloud leaves the window at \(u.when(H[i].time, now: now)) (\(Units.round(H[i].gti)) W/m², \(Units.round(H[i].cloud))% cloud).", i)
            }
        }
        if let i = firstIndex(from: 0, { (H[$0].aqi ?? 0) > 100 }) {
            add(.caution, "Smoke or haze", "US AQI \(Units.round(H[i].aqi)) around \(u.when(H[i].time, now: now)).", i)
        }
        out.append(contentsOf: everyCaution(assessed, covered: covered, units: u, now: now))
        if let kp = s.space.kpMax24h, kp >= Rules.kpCaution(gnssSensitive: p.variant.checks.contains(.gnssSensitive)) {
            out.append(.init(level: .caution, title: "Geomagnetic storm forecast",
                             detail: "Kp up to \(Units.round(kp, 1)). " + (kp >= 7 ? "GPS position may wander; RTK fixes likely to drop." : "RTK fixes may drop; regular GPS is fine."),
                             source: nil, more: nil, at: s.space.kpMaxAt ?? now, official: false))
        }
        // official alerts first, in effect before upcoming, then the more serious, then the sooner
        let active: (Briefing.HeadsUp) -> Bool = { $0.official && $0.at <= now }
        return out.sorted { a, b in
            if a.official != b.official { return a.official }
            if active(a) != active(b) { return active(a) }
            if a.level != b.level { return a.level > b.level }
            return a.at < b.at
        }
    }

    /// Every reason that makes an hour of the next 48 a caution or a hold, in the same words the 48-hour chart uses,
    /// grouped by kind ("Ceiling 100 ft" and "Ceiling 300 ft" are one item) with the hours it applies. The day/night
    /// cycle is left out (it is in the light tile and the chart), and so are kinds a heads-up above already explains.
    static func everyCaution(_ assessed: [(Conditions, Assessment)], covered: [String], units u: Units, now: Date) -> [Briefing.HeadsUp] {
        let routine = ["Sun down", "Too dark for imagery", "Night: anti-collision lights (3 mi)", "Night: use anti-collision lights", "Daylight: best contrast after dark"]
        struct G { var level: Level; var texts: [String]; var hours: [Date] }
        var groups: [String: G] = [:], order: [String] = []
        for (c, a) in assessed.prefix(48) {
            for r in a.reasons where r.level > .go && !routine.contains(r.text) {
                if covered.contains(where: { r.text.hasPrefix($0) }) { continue }
                let key = r.text.filter { !$0.isNumber }
                if groups[key] == nil { groups[key] = G(level: r.level, texts: [], hours: []); order.append(key) }
                groups[key]!.level = max(groups[key]!.level, r.level)
                if !groups[key]!.texts.contains(r.text) { groups[key]!.texts.append(r.text) }
                if groups[key]!.hours.last != c.time { groups[key]!.hours.append(c.time) }
            }
        }
        return order.compactMap { k -> Briefing.HeadsUp? in
            guard let g = groups[k], let first = g.hours.first else { return nil }
            // contiguous runs of hours: "Fri 6 AM – 2 PM (9 h)"
            var runs: [(Date, Date, Int)] = []
            for t in g.hours {
                if let last = runs.last, t.timeIntervalSince(last.1) <= 3600.5 { runs[runs.count - 1] = (last.0, t, last.2 + 1) }
                else { runs.append((t, t, 1)) }
            }
            let when = runs.prefix(4).map { r in
                r.2 == 1 ? u.when(r.0, now: now) : "\(u.when(r.0, now: now)) – \(u.clock(r.1.addingTimeInterval(3600))) (\(r.2) h)"
            }.joined(separator: "; ") + (runs.count > 4 ? "; and later" : "")
            let also = g.texts.count > 1 ? "\nAlso: " + g.texts.dropFirst().prefix(3).joined(separator: "; ") + (g.texts.count > 4 ? "…" : "") : ""
            return .init(level: g.level, title: g.texts[0], detail: when + also, source: nil, more: nil, at: first, official: false)
        }
    }

    // MARK: week

    static func days(_ hs: [(Conditions, Assessment)], u: Units, now: Date, solar: Bool, variant: ActivityVariant) -> [Briefing.Day] {
        var groups: [Int: [(Conditions, Assessment)]] = [:]
        for h in hs { groups[u.dayKey(h.0.time), default: []].append(h) }
        let today = u.dayKey(now)
        return groups.keys.sorted().filter { $0 >= today }.prefix(7).map { k in
            let items = groups[k]!
            var cells = [Level?](repeating: nil, count: 24)
            var times = [Date?](repeating: nil, count: 24), reasons = [String?](repeating: nil, count: 24), winds = [String?](repeating: nil, count: 24)
            var past = 0, good = 0, firstGood: Date?, lastGood: Date?
            for (c, a) in items {
                let h = u.localHour(c.time); cells[h] = a.level
                times[h] = c.time; reasons[h] = a.reasons.isEmpty ? nil : a.reasons.map(\.text).joined(separator: "; ")
                winds[h] = "wind \(u.speedNumber(c.windMS)), gusts \(u.speedText(c.gustMS))"
                if c.time.addingTimeInterval(3600) <= now { past = max(past, h + 1) }
                else if a.level == .go { good += 1; firstGood = firstGood ?? c.time; lastGood = c.time }
            }
            let date = items[0].0.time
            let temps = items.compactMap(\.0.tempC), gusts = items.compactMap(\.0.gustMS), rain = items.compactMap(\.0.precipChance)
            let noun = solar ? "in the inspection window" : variant.checks.contains(.prefersDark) ? "good for night thermal" : "flyable"
            return Briefing.Day(id: k, date: date, title: k == today ? "Today" : u.weekday(date), subtitle: u.monthDay(date),
                                cells: cells, times: times, reasons: reasons, winds: winds, pastCells: k == today ? past : 0,
                                summary: "\(good) h \(noun)\(k == today ? " left" : "")"
                                    + (solar ? (firstGood.map { f in ", \(u.hourShort(f))–\(u.hourShort(lastGood!.addingTimeInterval(3600)))" } ?? "") : ""),
                                high: "\(u.tempNumber(temps.max()))°", low: "\(u.tempNumber(temps.min()))°",
                                gust: u.speedNumber(gusts.max()), rain: "\(Units.round(rain.max()))%")
        }
    }

    static func sunNotes(_ st: SunTimes, s: SiteData, p: FlightProfile, u: Units) -> String {
        var notes: [String] = []
        let el = s.now.sun.elevation
        if el > 2 { notes.append("Shadows are \(Units.round(1 / tan(el * .pi / 180), 1))× object height; peak sun today is \(Units.round(st.noonElevation))°.") }
        if p.variant.usesPanelPlane, el > 0 {
            let g = Sun.glare(sun: s.now.sun, tilt: p.panelTilt, facing: p.panelFacing)
            notes.append(g.lit ? "Sun hits the panels \(Units.round(g.incidence))° from straight on." : "Sun is behind the panel plane.")
        }
        if p.variant.checks.contains(.prefersDark), let ss = st.sunset { notes.append("Best after \(u.clock(ss.addingTimeInterval(7200))), once surfaces shed the day's heat.") }
        return notes.joined(separator: " ")
    }
}
