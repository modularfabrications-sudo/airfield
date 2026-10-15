import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Raw responses for one place, kept as bytes so they can be cached offline and re-parsed.
public struct RawBundle: Codable, Sendable {
    public var lat: Double
    public var lon: Double
    public var fetchedAt: Date
    public var forecast: Data
    public var nowcast: Data?
    public var airQuality: Data?
    public var alerts: Data?
    public var kpNow: Data?
    public var kpForecast: Data?
    public var airspace: Data?
    /// Which irradiance variable the forecast carries (instant, or hourly mean when instant isn't offered).
    public var gtiKey: String = "global_tilted_irradiance_instant"
    /// "nws", "metno" or "open-meteo": what `forecast` holds.
    public var source: String = "open-meteo"
    /// NWS /points response (time zone, grid URL).
    public var points: Data? = nil
    /// aviationweather.gov METARs around the site.
    public var metar: Data? = nil
    /// Panel plane, for calculated irradiance.
    public var tilt: Double = 30
    public var facing: Double = 180
    /// The Weather Service said this point isn't in its coverage (not a temporary outage).
    public var outsideUS: Bool = false
}

public struct DataConfig: Sendable {
    /// Optional commercial Open-Meteo key. Empty = free public sources (NWS, METAR, MET Norway).
    public var openMeteoKey: String
    /// NWS asks every client to identify itself with contact details.
    public var userAgent: String
    public init(openMeteoKey: String = "", userAgent: String = "AirField/1.0 (+\(Site.base))") {
        self.openMeteoKey = openMeteoKey; self.userAgent = userAgent
    }
}

public enum FetchError: Error, Equatable { case http(Int), noForecast }

public struct WeatherService: Sendable {
    public var config: DataConfig
    public init(config: DataConfig = DataConfig()) { self.config = config }

    // MARK: URLs

    var base: String { config.openMeteoKey.isEmpty ? "https://api.open-meteo.com" : "https://customer-api.open-meteo.com" }
    var aqBase: String { config.openMeteoKey.isEmpty ? "https://air-quality-api.open-meteo.com" : "https://customer-air-quality-api.open-meteo.com" }
    var key: String { config.openMeteoKey.isEmpty ? "" : "&apikey=\(config.openMeteoKey)" }

    /// Open-Meteo's azimuth: 0 = south, −90 = east, 90 = west. Ours is compass degrees.
    public static func openMeteoAzimuth(_ facing: Double) -> Int {
        var a = (facing - 180).truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }; if a < -180 { a += 360 }
        return Int(a.rounded())
    }

    public func forecastURL(lat: Double, lon: Double, tilt: Double, facing: Double, gtiKey: String) -> URL {
        let hourly = ["temperature_2m", "dew_point_2m", "relative_humidity_2m", "precipitation_probability", "precipitation", "weather_code",
                      "cloud_cover", "cloud_cover_low", "visibility", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "wind_speed_120m",
                      "cape", "shortwave_radiation", gtiKey, "uv_index", "surface_pressure"]
        let current = ["temperature_2m", "dew_point_2m", "relative_humidity_2m", "precipitation", "weather_code", "cloud_cover", "cloud_cover_low",
                       "surface_pressure", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "visibility"]
        return URL(string: "\(base)/v1/forecast?latitude=\(lat)&longitude=\(lon)&timezone=auto&timeformat=unixtime&past_hours=3&forecast_hours=168"
                   + "&wind_speed_unit=ms&tilt=\(Int(tilt.rounded()))&azimuth=\(Self.openMeteoAzimuth(facing))"
                   + "&hourly=\(hourly.joined(separator: ","))&current=\(current.joined(separator: ","))\(key)")!
    }
    public func nowcastURL(lat: Double, lon: Double, tilt: Double, facing: Double) -> URL {
        let v = ["global_tilted_irradiance_instant", "shortwave_radiation", "wind_speed_10m", "wind_gusts_10m", "wind_direction_10m",
                 "precipitation", "weather_code", "visibility", "temperature_2m", "dew_point_2m"]
        return URL(string: "\(base)/v1/forecast?latitude=\(lat)&longitude=\(lon)&timezone=auto&timeformat=unixtime&forecast_days=2"
                   + "&wind_speed_unit=ms&tilt=\(Int(tilt.rounded()))&azimuth=\(Self.openMeteoAzimuth(facing))&minutely_15=\(v.joined(separator: ","))\(key)")!
    }
    public func airQualityURL(lat: Double, lon: Double) -> URL {
        URL(string: "\(aqBase)/v1/air-quality?latitude=\(lat)&longitude=\(lon)&timezone=auto&timeformat=unixtime&forecast_days=2&current=us_aqi&hourly=us_aqi\(key)")!
    }
    public static func alertsURL(lat: Double, lon: Double) -> URL {
        URL(string: String(format: "https://api.weather.gov/alerts/active?point=%.4f,%.4f", lat, lon))!
    }
    public static func pointsURL(lat: Double, lon: Double) -> URL {
        URL(string: String(format: "https://api.weather.gov/points/%.4f,%.4f", lat, lon))!
    }
    public static func metarURL(lat: Double, lon: Double) -> URL {
        URL(string: String(format: "https://aviationweather.gov/api/data/metar?bbox=%.3f,%.3f,%.3f,%.3f&format=json", lat - 0.3, lon - 0.4, lat + 0.3, lon + 0.4))!
    }
    public static func metNoURL(lat: Double, lon: Double) -> URL {
        URL(string: String(format: "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=%.4f&lon=%.4f", lat, lon))!
    }
    public static let kpNowURL = URL(string: "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json")!
    public static let kpForecastURL = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json")!
    public static func airspaceURL(lat: Double, lon: Double) -> URL {
        URL(string: "https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/ArcGIS/rest/services/FAA_UAS_FacilityMap_Data/FeatureServer/0/query"
            + String(format: "?geometry=%.4f,%.4f", lon, lat) + "&geometryType=esriGeometryPoint&inSR=4326&spatialRel=esriSpatialRelIntersects"
            + "&outFields=CEILING,APT1_NAME,APT1_FAAID&returnGeometry=false&f=json")!
    }

    // MARK: fetch

    func get(_ url: URL, accept: String? = nil) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw FetchError.http(h.statusCode) }
        return data
    }
    func optional(_ url: URL, accept: String? = nil) async -> Data? { try? await get(url, accept: accept) }

    public func fetch(lat: Double, lon: Double, tilt: Double, facing: Double) async throws -> RawBundle {
        config.openMeteoKey.isEmpty ? try await fetchFree(lat: lat, lon: lon, tilt: tilt, facing: facing)
                                    : try await fetchOpenMeteo(lat: lat, lon: lon, tilt: tilt, facing: facing)
    }

    /// NWS grid forecast + nearest METAR; MET Norway outside the US or if NWS doesn't answer.
    func fetchFree(lat: Double, lon: Double, tilt: Double, facing: Double) async throws -> RawBundle {
        async let met = optional(Self.metarURL(lat: lat, lon: lon))
        async let al = optional(Self.alertsURL(lat: lat, lon: lon), accept: "application/geo+json")
        async let k1 = optional(Self.kpNowURL)
        async let k2 = optional(Self.kpForecastURL)
        async let air = optional(Self.airspaceURL(lat: lat, lon: lon))
        var source = "nws", points: Data? = nil, fc: Data? = nil, outsideUS = false
        do {
            let p = try await get(Self.pointsURL(lat: lat, lon: lon))
            if let grid = NWSGrid.points(p)?.grid {
                points = p
                for _ in 0..<2 where fc == nil {     // the grid endpoint sometimes returns a transient 500
                    fc = await optional(grid, accept: "application/geo+json")
                }
            }
        } catch FetchError.http(404) {
            outsideUS = true                         // NWS: "Data Unavailable For Requested Point"
        } catch {}
        if fc == nil { source = "metno"; fc = try await get(Self.metNoURL(lat: lat, lon: lon)) }
        return RawBundle(lat: lat, lon: lon, fetchedAt: Date(), forecast: fc!, nowcast: nil, airQuality: nil,
                         alerts: await al, kpNow: await k1, kpForecast: await k2, airspace: await air,
                         source: source, points: points, metar: await met, tilt: tilt, facing: facing, outsideUS: outsideUS)
    }

    func fetchOpenMeteo(lat: Double, lon: Double, tilt: Double, facing: Double) async throws -> RawBundle {
        async let now = optional(nowcastURL(lat: lat, lon: lon, tilt: tilt, facing: facing))
        async let aq = optional(airQualityURL(lat: lat, lon: lon))
        async let al = optional(Self.alertsURL(lat: lat, lon: lon), accept: "application/geo+json")
        async let k1 = optional(Self.kpNowURL)
        async let k2 = optional(Self.kpForecastURL)
        async let air = optional(Self.airspaceURL(lat: lat, lon: lon))
        var gtiKey = "global_tilted_irradiance_instant"
        let fc: Data
        do { fc = try await get(forecastURL(lat: lat, lon: lon, tilt: tilt, facing: facing, gtiKey: gtiKey)) }
        catch FetchError.http(400) {
            gtiKey = "global_tilted_irradiance"
            fc = try await get(forecastURL(lat: lat, lon: lon, tilt: tilt, facing: facing, gtiKey: gtiKey))
        }
        return RawBundle(lat: lat, lon: lon, fetchedAt: Date(), forecast: fc, nowcast: await now, airQuality: await aq,
                         alerts: await al, kpNow: await k1, kpForecast: await k2, airspace: await air, gtiKey: gtiKey,
                         tilt: tilt, facing: facing)
    }
}

// MARK: - parsing (pure, testable)

public enum Parse {
    struct OMBlock: Decodable { let values: [String: [Double?]]
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            values = (try? c.decode([String: [Double?]].self)) ?? [:]
        }
    }
    struct OMForecast: Decodable {
        let latitude: Double, longitude: Double
        let elevation: Double?
        let utc_offset_seconds: Int?
        let timezone: String?
        let current: [String: Double?]?
        let hourly: OMBlock?
        let minutely_15: OMBlock?
    }

    public static func site(_ b: RawBundle, now: Date = Date()) throws -> SiteData {
        switch b.source {
        case "nws": return try nwsSite(b, now: now)
        case "metno": return try metNoSite(b, now: now)
        default: return try openMeteoSite(b, now: now)
        }
    }

    static func openMeteoSite(_ b: RawBundle, now: Date) throws -> SiteData {
        let dec = JSONDecoder()
        guard let fc = try? dec.decode(OMForecast.self, from: b.forecast), let H = fc.hourly?.values, let times = H["time"] else { throw FetchError.noForecast }
        let lat = b.lat, lon = b.lon
        // air quality by unix hour
        var aqi: [Int: Double] = [:]; var aqiNow: Double? = nil
        if let d = b.airQuality, let q = try? dec.decode(OMForecast.self, from: d) {
            if let t = q.hourly?.values["time"], let v = q.hourly?.values["us_aqi"] { for (i, x) in t.enumerated() { if let x, i < v.count, let y = v[i] { aqi[Int(x)] = y } } }
            aqiNow = q.current?["us_aqi"] ?? nil
        }
        func col(_ k: String, _ i: Int) -> Double? { guard let a = H[k], i < a.count else { return nil }; return a[i] }
        var hourly: [Conditions] = []
        for (i, t) in times.enumerated() {
            guard let t else { continue }
            let date = Date(timeIntervalSince1970: t)
            var c = Conditions(time: date, sun: Sun.position(at: date, lat: lat, lon: lon))
            c.tempC = col("temperature_2m", i); c.dewC = col("dew_point_2m", i); c.humidity = col("relative_humidity_2m", i)
            c.precipChance = col("precipitation_probability", i); c.precipMM = col("precipitation", i)
            c.code = col("weather_code", i).map { Int($0) }
            c.cloud = col("cloud_cover", i); c.cloudLow = col("cloud_cover_low", i); c.visibilityM = col("visibility", i)
            c.windMS = col("wind_speed_10m", i); c.windDir = col("wind_direction_10m", i); c.gustMS = col("wind_gusts_10m", i)
            c.windAloftMS = col("wind_speed_120m", i); c.cape = col("cape", i); c.ghi = col("shortwave_radiation", i)
            c.gti = col(b.gtiKey, i); c.uv = col("uv_index", i); c.pressureHPa = col("surface_pressure", i)
            c.aqi = aqi[Int(t)]
            hourly.append(c)
        }
        guard !hourly.isEmpty else { throw FetchError.noForecast }

        // "now": the current block, refined by the latest 15-minute step at or before now
        let hNow = hourly.last { $0.time <= now } ?? hourly[0]
        var n = hNow
        n.time = now; n.sun = Sun.position(at: now, lat: lat, lon: lon)
        let cur = fc.current ?? [:]
        func cv(_ k: String) -> Double? { cur[k] ?? nil }
        n.tempC = cv("temperature_2m") ?? n.tempC; n.dewC = cv("dew_point_2m") ?? n.dewC; n.humidity = cv("relative_humidity_2m") ?? n.humidity
        n.precipMM = cv("precipitation") ?? n.precipMM; n.code = cv("weather_code").map { Int($0) } ?? n.code
        n.cloud = cv("cloud_cover") ?? n.cloud; n.cloudLow = cv("cloud_cover_low") ?? n.cloudLow; n.pressureHPa = cv("surface_pressure") ?? n.pressureHPa
        n.windMS = cv("wind_speed_10m") ?? n.windMS; n.windDir = cv("wind_direction_10m") ?? n.windDir; n.gustMS = cv("wind_gusts_10m") ?? n.gustMS
        n.visibilityM = cv("visibility") ?? n.visibilityM
        n.aqi = aqiNow ?? n.aqi
        var usedNowcast = false
        if let d = b.nowcast, let m = try? dec.decode(OMForecast.self, from: d), let M = m.minutely_15?.values, let mt = M["time"] {
            if let idx = mt.lastIndex(where: { ($0 ?? .infinity) <= now.timeIntervalSince1970 }) {
                func mv(_ k: String) -> Double? { guard let a = M[k], idx < a.count else { return nil }; return a[idx] }
                n.gti = mv("global_tilted_irradiance_instant") ?? n.gti; n.ghi = mv("shortwave_radiation") ?? n.ghi
                n.windMS = mv("wind_speed_10m") ?? n.windMS; n.gustMS = mv("wind_gusts_10m") ?? n.gustMS; n.windDir = mv("wind_direction_10m") ?? n.windDir
                n.code = mv("weather_code").map { Int($0) } ?? n.code; n.visibilityM = mv("visibility") ?? n.visibilityM
                n.tempC = mv("temperature_2m") ?? n.tempC; n.dewC = mv("dew_point_2m") ?? n.dewC
                if let p = mv("precipitation") { n.precipMM = p * 4 }   // 15-minute sum → hourly rate
                usedNowcast = true
            }
        }
        return SiteData(lat: lat, lon: lon, elevationM: fc.elevation, utcOffset: fc.utc_offset_seconds ?? 0, timezone: fc.timezone,
                        now: n, hourly: hourly, space: space(b, now: now), airspace: airspace(b.airspace), alerts: alerts(b.alerts),
                        fetchedAt: b.fetchedAt, nowcast: usedNowcast)
    }

    static func number(_ x: Any?) -> Double? {
        if let d = x as? Double { return d }; if let i = x as? Int { return Double(i) }
        if let s = x as? String { return Double(s) }; if let n = x as? NSNumber { return n.doubleValue }; return nil
    }
    static func swpcDate(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss'Z'"] {
            f.dateFormat = fmt; if let d = f.date(from: s) { return d }
        }
        return nil
    }

    public static func space(_ b: RawBundle, now: Date) -> SpaceWeather {
        var sw = SpaceWeather()
        if let d = b.kpNow, let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]], let last = arr.last {
            sw.kpNow = number(last["estimated_kp"]) ?? number(last["kp_index"]) ?? number(last["kp"])
        }
        if let d = b.kpForecast, let arr = (try? JSONSerialization.jsonObject(with: d)) as? [Any] {
            for row in arr {
                var tag: String?, kp: Double?
                if let o = row as? [String: Any] { tag = o["time_tag"] as? String; kp = number(o["kp"]) }
                else if let a = row as? [Any], a.count >= 2 { tag = a[0] as? String; kp = number(a[1]) }
                guard let tag, let kp, let t = swpcDate(tag) else { continue }
                if t >= now.addingTimeInterval(-3 * 3600), t <= now.addingTimeInterval(24 * 3600), kp > (sw.kpMax24h ?? -1) { sw.kpMax24h = kp; sw.kpMaxAt = t }
            }
        }
        return sw
    }

    public static func airspace(_ d: Data?) -> Airspace {
        guard let d, let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let feats = o["features"] as? [[String: Any]] else { return .unknown }
        guard let a = feats.first?["attributes"] as? [String: Any] else { return .noGrid }
        let name = (a["APT1_NAME"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (a["APT1_FAAID"] as? String)
        return .laancGrid(ceilingFt: Int(number(a["CEILING"]) ?? 0), airport: name)
    }

    public static func alerts(_ d: Data?) -> [WeatherAlert] {
        guard let d, let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let feats = o["features"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        func date(_ x: Any?) -> Date? { (x as? String).flatMap { iso.date(from: $0) } }
        return feats.compactMap { f in
            guard let p = f["properties"] as? [String: Any] else { return nil }
            return WeatherAlert(event: (p["event"] as? String) ?? "Weather alert", headline: (p["headline"] as? String) ?? "",
                                severity: (p["severity"] as? String) ?? "", description: (p["description"] as? String) ?? "",
                                instruction: (p["instruction"] as? String) ?? "", sender: (p["senderName"] as? String) ?? "National Weather Service",
                                onset: date(p["onset"]) ?? date(p["effective"]), ends: date(p["ends"]) ?? date(p["expires"]))
        }
    }
}
