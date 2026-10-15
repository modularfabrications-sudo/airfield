import Foundation

// Free, commercial-use-friendly sources:
//   • National Weather Service gridded forecast (US public domain)
//   • Nearest airport METAR from aviationweather.gov (US public domain) for "right now"
//   • MET Norway Locationforecast (CC BY 4.0) outside the US or when NWS is down
// None of them publish irradiance on a tilted panel or wind at 400 ft, so those are calculated here.

// MARK: - Estimates

public enum Estimate {
    static let d2r = Double.pi / 180

    /// Sun's irradiance at the top of the atmosphere for the date (W/m²).
    public static func extraterrestrial(_ date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let doy = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        return 1361 * (1 + 0.033 * cos(2 * .pi * doy / 365))
    }

    /// Clear-sky global horizontal irradiance (Ineichen–Perez, Linke turbidity 3).
    public static func clearSkyGHI(sun: SunPosition, date: Date, altitudeM: Double) -> Double {
        guard sun.elevation > 0 else { return 0 }
        let cz = sin(sun.elevation * d2r)
        let am = 1 / (cz + 0.50572 * pow(sun.elevation + 6.07995, -1.6364))      // Kasten–Young
        let amAbs = am * exp(-max(altitudeM, 0) / 8434.5)
        let h = max(altitudeM, 0), tl = 3.0
        let cg1 = 5.09e-5 * h + 0.868, cg2 = 3.92e-5 * h + 0.0387
        let fh1 = exp(-h / 8000), fh2 = exp(-h / 1250)
        return max(0, cg1 * extraterrestrial(date) * cz * exp(-cg2 * amAbs * (fh1 + fh2 * (tl - 1))))
    }

    /// Cloud attenuation (Kasten–Czeplak): cover in percent.
    public static func cloudFactor(_ coverPct: Double?) -> Double {
        let n = min(max((coverPct ?? 0) / 100, 0), 1)
        return 1 - 0.75 * pow(n, 3.4)
    }

    /// Global horizontal and tilted-plane irradiance from sky cover and sun geometry.
    /// Erbs splits direct and diffuse; Hay–Davies moves them onto the panel plane.
    public static func irradiance(sun: SunPosition, date: Date, altitudeM: Double, cloudPct: Double?,
                                  tilt: Double, facing: Double, albedo: Double = 0.2) -> (ghi: Double, gti: Double) {
        guard sun.elevation > 0 else { return (0, 0) }
        let ghi = clearSkyGHI(sun: sun, date: date, altitudeM: altitudeM) * cloudFactor(cloudPct)
        let i0 = extraterrestrial(date)
        let cz = sin(sun.elevation * d2r), sz = cos(sun.elevation * d2r)
        let kt = min(ghi / (i0 * max(cz, 0.01)), 1)
        let kd: Double
        if kt <= 0.22 { kd = 1 - 0.09 * kt }
        else if kt <= 0.8 { kd = 0.9511 - 0.1604 * kt + 4.388 * kt * kt - 16.638 * pow(kt, 3) + 12.336 * pow(kt, 4) }
        else { kd = 0.165 }
        let dhi = kd * ghi
        let dni = max(0, (ghi - dhi) / max(cz, 0.087))
        let b = tilt * d2r
        let cosAOI = max(0, cz * cos(b) + sz * sin(b) * cos((sun.azimuth - facing) * d2r))
        let ai = min(dni / i0, 1)
        let rb = cosAOI / max(cz, 0.087)
        let sky = dhi * (ai * rb + (1 - ai) * (1 + cos(b)) / 2)
        let ground = ghi * albedo * (1 - cos(b)) / 2
        return (ghi, dni * cosAOI + sky + ground)
    }

    /// UV index: clear-sky estimate from sun height and altitude, reduced by cloud.
    public static func uvIndex(sun: SunPosition, altitudeM: Double, cloudPct: Double?) -> Double {
        guard sun.elevation > 0 else { return 0 }
        let clear = 12.5 * pow(sin(sun.elevation * d2r), 2.42) * (1 + 0.06 * max(altitudeM, 0) / 1000)
        return clear * uvCloudFactor(cloudPct)
    }
    static func uvCloudFactor(_ coverPct: Double?) -> Double { 1 - 0.65 * pow(min(max((coverPct ?? 0) / 100, 0), 1), 3) }

    /// Wind at 120 m (~400 ft) from the 10 m wind with a stability-dependent power law:
    /// well mixed by day (α ≈ 0.12–0.18), stable at night (α up to 0.30, when the air aloft decouples).
    public static func windAloft(surfaceMS: Double, sunElevation: Double, cloudPct: Double?) -> Double {
        let c = min(max((cloudPct ?? 50) / 100, 0), 1)
        let alpha: Double
        if sunElevation > 15 { alpha = 0.12 + 0.06 * c }
        else if sunElevation > 0 { alpha = 0.18 }
        else { alpha = 0.30 - 0.10 * c }
        return surfaceMS * pow(12.0, alpha)
    }

    /// Station pressure (hPa) from a sea-level or altimeter value and site elevation.
    public static func stationPressure(seaLevelHPa: Double, elevationM: Double) -> Double {
        seaLevelHPa * pow(1 - 2.25577e-5 * elevationM, 5.25588)
    }
    /// Standard-atmosphere station pressure when nothing better is available.
    public static func standardPressure(elevationM: Double) -> Double { stationPressure(seaLevelHPa: 1013.25, elevationM: elevationM) }
}

// MARK: - ISO 8601 helpers

enum ISO {
    static let formatter: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    static func date(_ s: String) -> Date? { formatter.date(from: s) }

    /// "PT2H", "P1D", "P7DT13H", "PT30M" → seconds.
    static func duration(_ s: String) -> TimeInterval? {
        guard s.hasPrefix("P") else { return nil }
        var total = 0.0, num = "", inTime = false
        for ch in s.dropFirst() {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber || ch == "." { num.append(ch); continue }
            guard let v = Double(num) else { return nil }
            switch (ch, inTime) {
            case ("W", false): total += v * 604800
            case ("D", false): total += v * 86400
            case ("H", true): total += v * 3600
            case ("M", true): total += v * 60
            case ("S", true): total += v
            default: return nil
            }
            num = ""
        }
        return total
    }

    /// "2026-10-10T12:00:00+00:00/PT2H" → (start, end)
    static func interval(_ s: String) -> (Date, Date)? {
        let parts = s.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let a = date(parts[0]), let d = duration(parts[1]) else { return nil }
        return (a, a.addingTimeInterval(d))
    }
}

// MARK: - National Weather Service grid

public enum NWSGrid {
    /// The forecastGridData URL and time zone from a /points response.
    public static func points(_ d: Data) -> (grid: URL, timeZone: String?)? {
        guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let p = o["properties"] as? [String: Any],
              let s = p["forecastGridData"] as? String, let u = URL(string: s) else { return nil }
        return (u, p["timeZone"] as? String)
    }

    /// One numeric layer spread over whole hours (unix hour → value, converted to SI).
    /// `amount` layers (precipitation) are divided evenly across the hours they cover.
    static func layer(_ props: [String: Any], _ key: String, amount: Bool = false) -> [Int: Double] {
        guard let l = props[key] as? [String: Any], let vals = l["values"] as? [[String: Any]] else { return [:] }
        let uom = (l["uom"] as? String) ?? ""
        func convert(_ x: Double) -> Double {
            switch uom {
            case "wmoUnit:km_h-1": return x / 3.6
            case "wmoUnit:degF": return (x - 32) * 5 / 9
            case "wmoUnit:km": return x * 1000
            case "wmoUnit:kn", "wmoUnit:kt": return x * 0.514444
            default: return x
            }
        }
        var out: [Int: Double] = [:]
        for v in vals {
            guard let vt = v["validTime"] as? String, let (a, b) = ISO.interval(vt), let x = Parse.number(v["value"]) else { continue }
            let h0 = Int(a.timeIntervalSince1970) / 3600, h1 = max(h0 + 1, Int(ceil(b.timeIntervalSince1970 / 3600)))
            let each = amount ? convert(x) / Double(h1 - h0) : convert(x)
            for h in h0..<h1 { out[h * 3600] = each }
        }
        return out
    }

    /// The NWS "weather" layer turned into a WMO-style code, a thunder chance and a visibility hint, per hour.
    struct Wx { var code: Int?; var thunder: Double?; var visibilityM: Double? }
    static func weather(_ props: [String: Any]) -> [Int: Wx] {
        guard let l = props["weather"] as? [String: Any], let vals = l["values"] as? [[String: Any]] else { return [:] }
        var out: [Int: Wx] = [:]
        for v in vals {
            guard let vt = v["validTime"] as? String, let (a, b) = ISO.interval(vt), let items = v["value"] as? [[String: Any]] else { continue }
            var wx = Wx()
            for it in items {
                guard let kind = it["weather"] as? String else { continue }
                let cov = (it["coverage"] as? String) ?? ""
                let inten = (it["intensity"] as? String) ?? ""
                let likely = !["slight_chance", "chance", "isolated", "scattered"].contains(cov)
                if kind.contains("thunder") {
                    let p: Double = ["slight_chance": 15, "isolated": 15, "chance": 35, "scattered": 35][cov] ?? 65
                    wx.thunder = max(wx.thunder ?? 0, p)
                }
                if let vis = it["visibility"] as? [String: Any], let x = Parse.number(vis["value"]) {
                    wx.visibilityM = (vis["unitCode"] as? String) == "wmoUnit:km" ? x * 1000 : x
                }
                guard likely, let c = wmo(kind, inten) else { continue }
                if severity(c) > severity(wx.code) { wx.code = c }
            }
            if wx.visibilityM == nil, let c = wx.code {
                if WMO.isFog(c) { wx.visibilityM = 1000 } else if c == 75 { wx.visibilityM = 1200 } else if c == 73 { wx.visibilityM = 3000 }
            }
            let h0 = Int(a.timeIntervalSince1970) / 3600, h1 = max(h0 + 1, Int(ceil(b.timeIntervalSince1970 / 3600)))
            for h in h0..<h1 { out[h * 3600] = wx }
        }
        return out
    }

    static func wmo(_ kind: String, _ intensity: String) -> Int? {
        let i = intensity.contains("heavy") ? 2 : intensity == "moderate" ? 1 : 0
        switch kind {
        case let k where k.contains("thunder"): return 95
        case "freezing_rain": return 66 + min(i, 1)
        case "freezing_drizzle": return 56 + min(i, 1)
        case "freezing_fog": return 48
        case "fog": return 45
        case "snow", "blowing_snow": return [71, 73, 75][i]
        case "snow_showers": return i == 2 ? 86 : 85
        case "sleet", "ice_pellets", "hail": return 66
        case "rain_showers": return [80, 81, 82][i]
        case "rain": return [61, 63, 65][i]
        case "drizzle": return [51, 53, 55][i]
        default: return nil
        }
    }
    static func severity(_ c: Int?) -> Int {
        guard let c else { return 0 }
        if WMO.isStorm(c) { return 6 }; if WMO.isFreezing(c) && c != 48 { return 5 }; if WMO.isSnow(c) { return 4 }
        if (51...82).contains(c) { return 3 }; if WMO.isFog(c) { return 2 }; return 1
    }
    static func skyCode(_ cover: Double?) -> Int? {
        guard let c = cover else { return nil }
        return c < 20 ? 0 : c < 45 ? 1 : c < 85 ? 2 : 3
    }
}

// MARK: - METAR

public struct Observation: Equatable, Sendable {
    public var station: String
    public var distanceKm: Double
    public var time: Date
    public var tempC: Double?, dewC: Double?
    public var windMS: Double?, gustMS: Double?, windDir: Double?
    public var visibilityM: Double?
    public var altimeterHPa: Double?
    public var cloudPct: Double?, cloudLowPct: Double?, ceilingM: Double?
    public var code: Int?, precipMM: Double?
    /// Automated stations only report cloud up to 12,000 ft.
    public var automated: Bool
    public var elevationM: Double?
}

public enum METAR {
    /// An airport this close (km) is measuring your site: its report replaces the forecast for "now".
    /// Farther out (up to 30 km) the forecast for the exact spot leads, and the airport only raises a caution.
    public static let localKm = 10.0
    static func km(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Estimate.d2r
        let dlat = (lat2 - lat1) * r, dlon = (lon2 - lon1) * r
        let a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1 * r) * cos(lat2 * r) * sin(dlon / 2) * sin(dlon / 2)
        return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    static let cover: [String: Double] = ["SKC": 0, "CLR": 0, "NSC": 0, "NCD": 0, "CAVOK": 0, "FEW": 19, "SCT": 44, "BKN": 75, "OVC": 100, "OVX": 100, "VV": 100]

    /// The closest recent report within `maxKm`, ignoring stations far above or below the site.
    public static func nearest(_ d: Data?, lat: Double, lon: Double, siteElevationM: Double?, now: Date,
                               maxKm: Double = 30, maxAge: TimeInterval = 7200) -> Observation? {
        guard let d, let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return nil }
        var best: Observation?
        for o in arr {
            guard let id = o["icaoId"] as? String, let la = Parse.number(o["lat"]), let lo = Parse.number(o["lon"]),
                  let t = Parse.number(o["obsTime"]) else { continue }
            let time = Date(timeIntervalSince1970: t)
            let dist = km(lat, lon, la, lo)
            guard dist <= maxKm, now.timeIntervalSince(time) <= maxAge else { continue }
            let elev = Parse.number(o["elev"])
            if let e = elev, let s = siteElevationM, abs(e - s) > 350 { continue }
            if let b = best, b.distanceKm <= dist { continue }
            best = parse(o, id: id, dist: dist, time: time, elev: elev)
        }
        return best
    }

    static func parse(_ o: [String: Any], id: String, dist: Double, time: Date, elev: Double?) -> Observation {
        let kt = 0.514444
        var ob = Observation(station: id, distanceKm: dist, time: time, automated: ((o["rawOb"] as? String) ?? "").contains(" AUTO "), elevationM: elev)
        ob.tempC = Parse.number(o["temp"]); ob.dewC = Parse.number(o["dewp"])
        ob.windMS = Parse.number(o["wspd"]).map { $0 * kt }
        ob.gustMS = Parse.number(o["wgst"]).map { $0 * kt } ?? ob.windMS
        ob.windDir = Parse.number(o["wdir"])            // "VRB" → nil
        if let v = o["visib"] {
            if let s = v as? String { ob.visibilityM = Double(s.replacingOccurrences(of: "+", with: "")).map { $0 * 1609.34 } }
            else { ob.visibilityM = Parse.number(v).map { $0 * 1609.34 } }
        }
        ob.altimeterHPa = Parse.number(o["altim"])
        var total = 0.0, low = 0.0, ceilingM: Double? = nil
        if let layers = o["clouds"] as? [[String: Any]] {
            for l in layers {
                guard let c = l["cover"] as? String else { continue }
                let pct = cover[c] ?? 0
                let baseFt = Parse.number(l["base"]) ?? (c == "OVX" ? Parse.number(o["vertVis"]) : nil)
                total = max(total, pct)
                if let b = baseFt, b < 6500 { low = max(low, pct) }
                if pct >= 75, let b = baseFt, ceilingM == nil { ceilingM = b * 0.3048 }
            }
        }
        ob.cloudPct = total; ob.cloudLowPct = low; ob.ceilingM = ceilingM
        let wx = (o["wxString"] as? String) ?? ""
        (ob.code, ob.precipMM) = weather(wx)
        if ob.code == nil { ob.code = NWSGrid.skyCode(total) }
        return ob
    }

    /// "-RA BR", "+TSRA", "FZFG", "SHSN" → WMO-style code and an hourly precipitation rate.
    static func weather(_ s: String) -> (Int?, Double?) {
        guard !s.isEmpty else { return (nil, 0) }
        let tokens = s.split(separator: " ").map(String.init)
        var code: Int? = nil, mm = 0.0
        for t in tokens {
            let i = t.hasPrefix("+") ? 2 : t.hasPrefix("-") ? 0 : 1
            var c: Int?
            if t.contains("TS") { c = 95 }
            else if t.contains("FZRA") { c = 66 + min(i, 1) }
            else if t.contains("FZDZ") { c = 56 + min(i, 1) }
            else if t.contains("FZFG") { c = 48 }
            else if t.contains("PL") || t.contains("GR") || t.contains("GS") { c = 66 }
            else if t.contains("SN") || t.contains("SG") { c = t.contains("SH") ? (i == 2 ? 86 : 85) : [71, 73, 75][i] }
            else if t.contains("RA") { c = t.contains("SH") ? [80, 81, 82][i] : [61, 63, 65][i] }
            else if t.contains("DZ") { c = [51, 53, 55][i] }
            else if t.contains("FG") { c = 45 }
            if let c, NWSGrid.severity(c) > NWSGrid.severity(code) { code = c }
            if t.contains("RA") || t.contains("SN") || t.contains("DZ") || t.contains("PL") || t.contains("GR") {
                mm = max(mm, t.contains("DZ") ? 0.2 : [0.5, 2.5, 8][i])
            }
        }
        return (code, mm)
    }
}

// MARK: - parsing the free bundles

extension Parse {
    /// NWS grid (+ METAR for now).
    static func nwsSite(_ b: RawBundle, now: Date) throws -> SiteData {
        guard let o = (try? JSONSerialization.jsonObject(with: b.forecast)) as? [String: Any],
              let props = o["properties"] as? [String: Any] else { throw FetchError.noForecast }
        let elev = ((props["elevation"] as? [String: Any]).flatMap { number($0["value"]) })
        let tzName = b.points.flatMap { NWSGrid.points($0)?.timeZone }
        let tz = tzName.flatMap { TimeZone(identifier: $0) }
        let offset = tz?.secondsFromGMT(for: now) ?? Int((b.lon / 15).rounded()) * 3600

        let temp = NWSGrid.layer(props, "temperature"), dew = NWSGrid.layer(props, "dewpoint"), rh = NWSGrid.layer(props, "relativeHumidity")
        let sky = NWSGrid.layer(props, "skyCover"), dir = NWSGrid.layer(props, "windDirection")
        let wind = NWSGrid.layer(props, "windSpeed"), gust = NWSGrid.layer(props, "windGust")
        let pop = NWSGrid.layer(props, "probabilityOfPrecipitation"), qpf = NWSGrid.layer(props, "quantitativePrecipitation", amount: true)
        let thunder = NWSGrid.layer(props, "probabilityOfThunder"), vis = NWSGrid.layer(props, "visibility")
        let ceiling = NWSGrid.layer(props, "ceilingHeight")
        let wx = NWSGrid.weather(props)
        guard !temp.isEmpty || !wind.isEmpty else { throw FetchError.noForecast }

        let found = METAR.nearest(b.metar, lat: b.lat, lon: b.lon, siteElevationM: elev, now: now)
        let obs = found.flatMap { $0.distanceKm <= METAR.localKm ? $0 : nil }       // measured at the site
        let alt = elev ?? 0
        // pressure is regional (the altimeter setting is reduced to sea level), so a farther airport is fine for it
        let pressure = found?.altimeterHPa.map { Estimate.stationPressure(seaLevelHPa: $0, elevationM: alt) } ?? Estimate.standardPressure(elevationM: alt)

        let first = (Int(now.timeIntervalSince1970) / 3600 - 3) * 3600
        var hourly: [Conditions] = []
        for k in 0..<(168 + 3) {
            let t = first + k * 3600
            guard temp[t] != nil || wind[t] != nil else { continue }
            let date = Date(timeIntervalSince1970: TimeInterval(t))
            var c = Conditions(time: date, sun: Sun.position(at: date, lat: b.lat, lon: b.lon))
            c.tempC = temp[t]; c.dewC = dew[t]; c.humidity = rh[t]
            c.cloud = sky[t]; c.windDir = dir[t]; c.windMS = wind[t]
            c.gustMS = max(gust[t] ?? 0, wind[t] ?? 0)
            c.precipChance = pop[t]
            // Spread 6-hour totals only over hours where rain is reasonably likely.
            c.precipMM = (pop[t] ?? 0) >= 30 ? (qpf[t] ?? 0) : 0
            let w = wx[t]
            c.code = w?.code ?? NWSGrid.skyCode(c.cloud)
            c.thunderChance = [thunder[t], w?.thunder].compactMap { $0 }.max()
            c.visibilityM = vis[t] ?? w?.visibilityM
            // NWS writes -30.48 m (-100 ft) when there is no ceiling at all (clear or scattered sky): that is "unlimited", not a low ceiling
            c.ceilingM = ceiling[t].flatMap { $0 > 0 ? $0 : nil }
            c.pressureHPa = pressure
            fillEstimates(&c, altitude: alt, tilt: b.tilt, facing: b.facing)
            hourly.append(c)
        }
        guard !hourly.isEmpty else { throw FetchError.noForecast }
        let n = nowConditions(hourly, obs: obs, regional: found, now: now, lat: b.lat, lon: b.lon, altitude: alt, tilt: b.tilt, facing: b.facing)
        return SiteData(sources: SourceInfo(forecast: .nws, station: obs?.station, stationKm: obs?.distanceKm, observedAt: obs?.time),
                        lat: b.lat, lon: b.lon, elevationM: elev, utcOffset: offset, timezone: tzName,
                        now: n, hourly: hourly, space: space(b, now: now), airspace: airspace(b.airspace), alerts: alerts(b.alerts),
                        fetchedAt: b.fetchedAt, nowcast: obs != nil)
    }

    /// MET Norway Locationforecast "complete" (+ METAR for now).
    static func metNoSite(_ b: RawBundle, now: Date) throws -> SiteData {
        guard let o = (try? JSONSerialization.jsonObject(with: b.forecast)) as? [String: Any],
              let props = o["properties"] as? [String: Any], let ts = props["timeseries"] as? [[String: Any]] else { throw FetchError.noForecast }
        let coords = (o["geometry"] as? [String: Any])?["coordinates"] as? [Any]
        let elev = coords.flatMap { $0.count > 2 ? number($0[2]) : nil }
        let alt = elev ?? 0
        let found = METAR.nearest(b.metar, lat: b.lat, lon: b.lon, siteElevationM: elev, now: now)
        let obs = found.flatMap { $0.distanceKm <= METAR.localKm ? $0 : nil }

        struct Step { var t: Int; var d: [String: Any]; var n1: [String: Any]?; var n6: [String: Any]? }
        let steps: [Step] = ts.compactMap { e in
            guard let s = e["time"] as? String, let t = ISO.date(s), let data = e["data"] as? [String: Any],
                  let inst = (data["instant"] as? [String: Any])?["details"] as? [String: Any] else { return nil }
            return Step(t: Int(t.timeIntervalSince1970), d: inst, n1: data["next_1_hours"] as? [String: Any], n6: data["next_6_hours"] as? [String: Any])
        }
        guard !steps.isEmpty else { throw FetchError.noForecast }
        let first = (Int(now.timeIntervalSince1970) / 3600 - 3) * 3600, last = first + 171 * 3600
        var hourly: [Conditions] = []
        for (i, s) in steps.enumerated() {
            let end = i + 1 < steps.count ? steps[i + 1].t : s.t + 3600
            var t = s.t
            while t < end {
                defer { t += 3600 }
                guard t >= first, t < last else { continue }
                let date = Date(timeIntervalSince1970: TimeInterval(t))
                var c = Conditions(time: date, sun: Sun.position(at: date, lat: b.lat, lon: b.lon))
                let d = s.d
                c.tempC = number(d["air_temperature"]); c.dewC = number(d["dew_point_temperature"]); c.humidity = number(d["relative_humidity"])
                c.cloud = number(d["cloud_area_fraction"]); c.cloudLow = number(d["cloud_area_fraction_low"])
                c.windMS = number(d["wind_speed"]); c.windDir = number(d["wind_from_direction"])
                c.gustMS = number(d["wind_speed_of_gust"]).map { max($0, c.windMS ?? 0) }
                c.pressureHPa = number(d["air_pressure_at_sea_level"]).map { Estimate.stationPressure(seaLevelHPa: $0, elevationM: alt) }
                if (number(d["fog_area_fraction"]) ?? 0) >= 50 { c.visibilityM = 1000 }
                let next = (s.n1 ?? s.n6)
                let nd = next?["details"] as? [String: Any]
                let hours = s.n1 != nil ? 1.0 : 6.0
                c.precipMM = nd.flatMap { number($0["precipitation_amount"]) }.map { $0 / hours }
                c.precipChance = nd.flatMap { number($0["probability_of_precipitation"]) }
                c.thunderChance = nd.flatMap { number($0["probability_of_thunder"]) }
                let sym = ((next?["summary"] as? [String: Any])?["symbol_code"] as? String) ?? ""
                c.code = metNoCode(sym) ?? NWSGrid.skyCode(c.cloud)
                fillEstimates(&c, altitude: alt, tilt: b.tilt, facing: b.facing)
                if let uvClear = number(d["ultraviolet_index_clear_sky"]) { c.uv = uvClear * Estimate.uvCloudFactor(c.cloud) }
                hourly.append(c)
            }
        }
        guard !hourly.isEmpty else { throw FetchError.noForecast }
        let n = nowConditions(hourly, obs: obs, regional: found, now: now, lat: b.lat, lon: b.lon, altitude: alt, tilt: b.tilt, facing: b.facing)
        return SiteData(sources: SourceInfo(forecast: .metNorway, station: obs?.station, stationKm: obs?.distanceKm, observedAt: obs?.time,
                                            outsideUS: b.outsideUS),
                        lat: b.lat, lon: b.lon, elevationM: elev, utcOffset: Int((b.lon / 15).rounded()) * 3600, timezone: nil,
                        now: n, hourly: hourly, space: space(b, now: now), airspace: airspace(b.airspace), alerts: alerts(b.alerts),
                        fetchedAt: b.fetchedAt, nowcast: obs != nil)
    }

    static func metNoCode(_ symbol: String) -> Int? {
        let s = symbol.components(separatedBy: "_").first ?? symbol
        if s.contains("thunder") { return 95 }
        switch s {
        case "clearsky": return 0; case "fair": return 1; case "partlycloudy": return 2; case "cloudy": return 3; case "fog": return 45
        case "lightrain": return 61; case "rain": return 63; case "heavyrain": return 65
        case "lightrainshowers": return 80; case "rainshowers": return 81; case "heavyrainshowers": return 82
        case "lightsnow": return 71; case "snow": return 73; case "heavysnow": return 75
        case "lightsnowshowers", "snowshowers": return 85; case "heavysnowshowers": return 86
        case let x where x.contains("sleet"): return 66
        default: return nil
        }
    }

    /// Calculated irradiance, UV and 400 ft wind for an hour.
    static func fillEstimates(_ c: inout Conditions, altitude: Double, tilt: Double, facing: Double) {
        let irr = Estimate.irradiance(sun: c.sun, date: c.time, altitudeM: altitude, cloudPct: c.cloud, tilt: tilt, facing: facing)
        c.ghi = irr.ghi; c.gti = irr.gti
        c.uv = Estimate.uvIndex(sun: c.sun, altitudeM: altitude, cloudPct: c.cloud)
        c.windAloftMS = c.windMS.map { Estimate.windAloft(surfaceMS: $0, sunElevation: c.sun.elevation, cloudPct: c.cloud) }
    }

    /// "Right now": the forecast for this exact spot, replaced by an airport's measurement when the airport is
    /// close enough (`METAR.localKm`) to be measuring the same air. A farther airport is only carried along as `nearby`.
    static func nowConditions(_ hourly: [Conditions], obs: Observation?, regional: Observation? = nil, now: Date, lat: Double, lon: Double,
                              altitude: Double, tilt: Double, facing: Double) -> Conditions {
        var n = hourly.last { $0.time <= now } ?? hourly[0]
        n.time = now; n.sun = Sun.position(at: now, lat: lat, lon: lon)
        if obs == nil, let r = regional {
            n.nearby = NearbyReport(station: r.station, km: r.distanceKm, windMS: r.windMS, gustMS: r.gustMS)
        }
        if let o = obs {
            n.tempC = o.tempC ?? n.tempC; n.dewC = o.dewC ?? n.dewC
            if let t = n.tempC, let d = n.dewC {   // RH from the observed pair
                n.humidity = 100 * exp(17.625 * d / (243.04 + d)) / exp(17.625 * t / (243.04 + t))
            }
            n.windMS = o.windMS ?? n.windMS; n.gustMS = o.gustMS ?? n.gustMS; n.windDir = o.windDir ?? n.windDir
            n.visibilityM = o.visibilityM ?? n.visibilityM
            if let a = o.altimeterHPa { n.pressureHPa = Estimate.stationPressure(seaLevelHPa: a, elevationM: altitude) }
            // Automated stations can't see above 12,000 ft, so keep the forecast's high cloud.
            if let oc = o.cloudPct { n.cloud = o.automated ? max(oc, n.cloud ?? 0) : oc }
            n.cloudLow = o.cloudLowPct ?? n.cloudLow
            n.ceilingM = o.ceilingM
            n.code = o.code ?? n.code
            n.precipMM = o.precipMM ?? n.precipMM
        }
        fillEstimates(&n, altitude: altitude, tilt: tilt, facing: facing)
        return n
    }
}
