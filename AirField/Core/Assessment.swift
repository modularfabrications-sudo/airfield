import Foundation

public enum Level: Int, Comparable, Codable, Sendable {
    case go = 0, caution = 1, hold = 2
    public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    public var word: String { switch self { case .go: "Go"; case .caution: "Caution"; case .hold: "Hold" } }
}

public struct Reason: Equatable, Sendable {
    public let level: Level
    public let text: String
    public init(_ level: Level, _ text: String) { self.level = level; self.text = text }
}

public struct Assessment: Equatable, Sendable {
    public var level: Level
    public var reasons: [Reason]
    public init(reasons: [Reason]) {
        self.reasons = reasons.sorted { $0.level > $1.level }
        self.level = reasons.map(\.level).max() ?? .go
    }
}

/// The user's setup: what they fly, how, and their display preferences.
public struct FlightProfile: Codable, Equatable, Sendable {
    public var variantID: String
    public var drone: Drone
    public var rules: PilotRules
    public var panelTilt: Double
    public var panelFacing: Double
    public var imperial: Bool
    /// Optional personal sustained-wind limit (m/s) that replaces the drone-derived one.
    public var personalWindLimitMS: Double?

    public init(variantID: String, drone: Drone, rules: PilotRules, panelTilt: Double = 30, panelFacing: Double = 180,
                imperial: Bool = true, personalWindLimitMS: Double? = nil) {
        self.variantID = variantID; self.drone = drone; self.rules = rules; self.panelTilt = panelTilt
        self.panelFacing = panelFacing; self.imperial = imperial; self.personalWindLimitMS = personalWindLimitMS
    }

    public var variant: ActivityVariant { ActivityCatalog.variant(variantID) ?? ActivityCatalog.all[0].variants[0] }
    public var activity: Activity { ActivityCatalog.activity(for: variantID) ?? ActivityCatalog.all[0] }
}

/// Wind thresholds derived from the drone's published max wind resistance.
public struct WindLimits: Equatable, Sendable {
    public var sustainedCaution: Double, sustainedHold: Double
    public var gustCaution: Double, gustHold: Double
    public var aloftCaution: Double, aloftHold: Double

    /// Gusts and wind at 400 ft hold at the maker's published wind resistance (DJI Matrice 400: 12 m/s ≈ 27 mph),
    /// with a caution from 80% of it. Steady wind holds earlier, at 85% (≈ 23 mph for the M400), leaving room for the
    /// gusts on top of it and for the trip home into it; caution from 65%. Learners get 75% of everything;
    /// a personal limit replaces the steady-wind hold and scales the rest with it.
    public static func derive(for p: FlightProfile) -> WindLimits {
        let max = p.drone.maxWindMS
        var f = 1.0
        if p.variantID == "rec-learning" { f = 0.75 }
        if let personal = p.personalWindLimitMS, personal > 0 { f = personal / (0.85 * max) }
        return WindLimits(sustainedCaution: 0.65 * max * f, sustainedHold: 0.85 * max * f,
                          gustCaution: 0.8 * max * f, gustHold: max * f,
                          aloftCaution: 0.8 * max * f, aloftHold: max * f)
    }
}

public enum Rules {
    /// FAA Part 107.51(c): 3 statute miles flight visibility.
    public static let visibilityMinM = 4828.0
    /// 400 ft ceiling + 500 ft below cloud (107.51(b),(d)).
    public static let cloudBaseMinM = 900 * 0.3048
    /// IEC TS 62446-3 solar thermography window.
    public static let solarIrradiance = 600.0, solarCloudMax = 25.0, solarWindMaxMS = 28 / 3.6
    /// Kp that earns a caution: 5 (G1) for RTK / survey work, 7 (G3) for everyone else.
    public static func kpCaution(gnssSensitive: Bool) -> Double { gnssSensitive ? 5 : 7 }
    /// Common pesticide label language: no application above 10 mph; near-calm air risks inversions.
    /// Gusts this far above the steady wind mean choppy, unpredictable air even when both are under the limits.
    public static let gustSpreadMS = 13 / 2.236936
    public static let sprayWindMaxMS = 10 / 2.236936, sprayWindMinMS = 2 / 2.236936

    public static func assess(_ c: Conditions, profile p: FlightProfile, space: SpaceWeather? = nil, units u: Units) -> Assessment {
        var r: [Reason] = []
        let v = p.variant, d = p.drone, L = WindLimits.derive(for: p)
        let checks = v.checks

        // storms and precipitation
        if WMO.isStorm(c.code) { r.append(Reason(.hold, "Thunderstorms")) }
        else if let th = c.thunderChance, th >= 25 { r.append(Reason(.caution, "Thunder chance \(Units.round(th))%")) }
        else if let cape = c.cape, cape >= 1000, (c.precipChance ?? 0) >= 30 { r.append(Reason(.caution, "Storm potential")) }
        if WMO.isFreezing(c.code) { r.append(Reason(.hold, "Freezing precipitation")) }
        else if WMO.isSnow(c.code) { r.append(d.rainResistant ? Reason(.caution, "Snow") : Reason(.hold, "Snow")) }
        else if let mm = c.precipMM, mm > 0 {
            if d.rainResistant { r.append(mm >= 2.5 ? Reason(.hold, "Heavy rain") : Reason(.caution, "Rain (\(d.ipRating ?? "") rated)")) }
            else if mm >= 0.1 { r.append(Reason(.hold, "Rain: drone isn't weather sealed")) }
            else { r.append(Reason(.caution, "Light precipitation")) }
        }
        if WMO.isFog(c.code) { r.append(Reason(.caution, "Fog")) }

        // visibility and cloud (Part 107.51)
        if let vis = c.visibilityM, vis < visibilityMinM {
            r.append(p.rules == .part107 ? Reason(.hold, "Visibility under 3 mi") : Reason(.caution, "Low visibility: keep it in sight"))
        }
        if let ceil = c.ceilingM, ceil > 0 {
            if ceil < cloudBaseMinM { r.append(Reason(.caution, "Ceiling \(u.heightText(ceil))" + (p.rules == .part107 ? ": stay 500 ft below" : ""))) }
        } else if let low = c.cloudLow, low >= 50, let base = Physics.cloudBaseM(tempC: c.tempC, dewC: c.dewC), base < cloudBaseMinM {
            r.append(Reason(.caution, "Low cloud ~\(u.heightText(base))" + (p.rules == .part107 ? ": stay 500 ft below" : "")))
        }

        // wind against the drone's limits
        if let w = c.windMS {
            if w > L.sustainedHold { r.append(Reason(.hold, "Wind \(u.speedText(w))")) }
            else if w > L.sustainedCaution { r.append(Reason(.caution, "Wind \(u.speedText(w))")) }
        }
        if let g = c.gustMS {
            if g > L.gustHold { r.append(Reason(.hold, "Gusts \(u.speedText(g))")) }
            else if g > L.gustCaution { r.append(Reason(.caution, "Gusts \(u.speedText(g))")) }
            else if checks.contains(.smoothFootage), g > 0.6 * d.maxWindMS { r.append(Reason(.caution, "Gusty: footage may be shaky")) }
        }
        // Choppy air: a big gap between the steady wind and the gusts, with neither over its own threshold yet
        if let w = c.windMS, let g = c.gustMS, g - w >= gustSpreadMS, g <= L.gustCaution, w <= L.sustainedCaution {
            r.append(Reason(.caution, "Choppy: gusts \(u.speedText(g - w)) above the wind"))
        }
        // An airport 10–30 km away measuring more than your limit: worth knowing, not proof it's like that here.
        if let nb = c.nearby {
            let siteHolds = (c.windMS ?? 0) > L.sustainedHold || (c.gustMS ?? 0) > L.gustHold
            let where_ = "\(nb.station) \(Units.round(nb.km)) km away"
            if !siteHolds, let g = nb.gustMS, g > L.gustHold { r.append(Reason(.caution, "Gusts \(u.speedText(g)) at \(where_)")) }
            else if !siteHolds, let w = nb.windMS, w > L.sustainedHold { r.append(Reason(.caution, "Wind \(u.speedText(w)) at \(where_)")) }
        }
        if let a = c.windAloftMS {
            if a > L.aloftHold { r.append(Reason(.hold, "\(u.altitudeLabel400) wind \(u.speedText(a))")) }
            else if a > L.aloftCaution { r.append(Reason(.caution, "\(u.altitudeLabel400) wind \(u.speedText(a))")) }
        }

        // temperature against the drone's operating range
        if let t = c.tempC {
            if t < d.tempMinC || t > d.tempMaxC { r.append(Reason(.hold, "\(u.tempNumber(t))\(u.tempUnit) is outside the drone's range")) }
            else if t < d.tempMinC + 5 { r.append(Reason(.caution, "Near the cold limit: warm batteries")) }
            else if t > d.tempMaxC - 3 { r.append(Reason(.caution, "Near the heat limit")) }
        }

        // altitude performance
        if let da = Physics.densityAltitudeM(pressureHPa: c.pressureHPa, tempC: c.tempC) {
            if da > d.ceilingM { r.append(Reason(.hold, "Density altitude above the drone's ceiling")) }
            else if da > d.ceilingM - 600 { r.append(Reason(.caution, "Thin air: near the drone's ceiling")) }
        }

        // light
        let dark = !c.isDaylight
        if dark {
            if checks.contains(.needsDaylight) { r.append(Reason(.hold, "Too dark for imagery")) }
            else if !checks.contains(.prefersDark) && p.variantID != "map-lidar" && !checks.contains(.solarWindow) {
                r.append(Reason(.caution, p.rules == .part107 ? "Night: anti-collision lights (3 mi)" : "Night: use anti-collision lights"))
            }
        } else if checks.contains(.needsDaylight), checks.contains(.evenLight), c.sun.elevation < 10 {
            r.append(Reason(.caution, "Low sun: long shadows"))
        }
        if checks.contains(.evenLight), !dark, let cl = c.cloud, cl > 30, cl < 80 { r.append(Reason(.caution, "Patchy cloud: light changes between photos")) }

        // activity windows
        if checks.contains(.solarWindow) {
            if c.sun.elevation < 5 { r.append(Reason(.hold, "Sun down")) }
            else {
                if let g = c.gti, g < solarIrradiance { r.append(Reason(.caution, "\(Units.round(g)) W/m² on panels")) }
                if let cl = c.cloud, cl > solarCloudMax { r.append(Reason(.caution, "Cloud \(Units.round(cl))%")) }
                if let w = c.windMS, w > solarWindMaxMS, w <= L.sustainedCaution { r.append(Reason(.caution, "Wind over \(u.speedText(solarWindMaxMS)) for thermal")) }
            }
        }
        if checks.contains(.prefersDark), !dark { r.append(Reason(.caution, "Daylight: best contrast after dark")) }
        if checks.contains(.sprayDrift), let w = c.windMS {
            if w > sprayWindMaxMS { r.append(Reason(.hold, "Over \(u.speedText(sprayWindMaxMS)): above common label limits")) }
            else if w < sprayWindMinMS { r.append(Reason(.caution, "Near-calm: inversion and drift risk")) }
        }

        // smoke
        if let aqi = c.aqi, aqi > 150, (checks.contains(.needsDaylight) || checks.contains(.solarWindow) || checks.contains(.smoothFootage)) {
            r.append(Reason(.caution, "Smoke: AQI \(Units.round(aqi))"))
        }

        // GNSS
        // At mid-latitudes a minor storm (Kp 5-6) barely moves a multi-constellation GPS fix or the
        // compass, but it can break RTK fixes. Only strong storms (Kp 7+) matter for everyone.
        if let kp = space?.kpNow, kp >= Rules.kpCaution(gnssSensitive: checks.contains(.gnssSensitive)) {
            r.append(Reason(.caution, kp >= 7 ? "Strong geomagnetic storm: Kp \(Units.round(kp, 1))" : "Kp \(Units.round(kp, 1)): RTK fixes may drop"))
        }
        return Assessment(reasons: r)
    }
}
