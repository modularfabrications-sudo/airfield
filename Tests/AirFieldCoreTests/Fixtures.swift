import Foundation
#if canImport(AirFieldCore)
@testable import AirFieldCore
#else
@testable import AirField
#endif

/// Builds API responses shaped exactly like Open-Meteo / NWS / SWPC / FAA, for a fixed "now".
enum Fixture {
    static let lat = 39.3791, lon = -104.8561, offset = -21600   // Castle Rock, CO (MDT)
    static let now = Date(timeIntervalSince1970: 1_791_656_400)  // 2026-10-10 18:20 UTC (12:20 PM MDT)

    struct Hour { var temp = 18.0, dew = -2.0, rh = 26.0, pp = 0.0, precip = 0.0, code = 0, cloud = 10.0, low = 5.0, vis = 24000.0
                  var wind = 5.0, dir = 250.0, gust = 8.0, aloft = 8.5, cape = 100.0, ghi = 600.0, gti = 680.0, uv = 4.0, pres = 803.5 }

    /// 7 days + 3 past hours, hourly. `tweak` adjusts any hour by index from the start.
    static func forecast(tweak: (Int, inout Hour) -> Void = { _, _ in }, gtiKey: String = "global_tilted_irradiance_instant", current: [String: Any]? = nil) -> Data {
        let start = (Int(now.timeIntervalSince1970) / 3600 - 3) * 3600
        var cols: [String: [Any]] = ["time": []]
        let keys = ["temperature_2m", "dew_point_2m", "relative_humidity_2m", "precipitation_probability", "precipitation", "weather_code",
                    "cloud_cover", "cloud_cover_low", "visibility", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "wind_speed_120m",
                    "cape", "shortwave_radiation", gtiKey, "uv_index", "surface_pressure"]
        keys.forEach { cols[$0] = [] }
        for i in 0..<(7 * 24 + 3) {
            let t = start + i * 3600
            let sunUp = Sun.position(at: Date(timeIntervalSince1970: TimeInterval(t)), lat: lat, lon: lon).elevation > 0
            var h = Hour(); if !sunUp { h.ghi = 0; h.gti = 0; h.uv = 0 }
            tweak(i, &h)
            cols["time"]!.append(t)
            let vals: [Any] = [h.temp, h.dew, h.rh, h.pp, h.precip, h.code, h.cloud, h.low, h.vis, h.wind, h.dir, h.gust, h.aloft, h.cape, h.ghi, h.gti, h.uv, h.pres]
            for (k, v) in zip(keys, vals) { cols[k]!.append(v) }
        }
        cols["cape"]![5] = NSNull()   // real responses contain nulls
        var o: [String: Any] = ["latitude": lat, "longitude": lon, "elevation": 1925.0, "utc_offset_seconds": offset,
                                "timezone": "America/Denver", "hourly": cols]
        o["current"] = current ?? ["time": Int(now.timeIntervalSince1970) - 300, "interval": 900, "temperature_2m": 19.0, "dew_point_2m": -2.0,
                                   "relative_humidity_2m": 24, "precipitation": 0, "weather_code": 1, "cloud_cover": 12, "cloud_cover_low": 4,
                                   "surface_pressure": 803.5, "wind_speed_10m": 5.2, "wind_direction_10m": 255, "wind_gusts_10m": 8.4, "visibility": 24140]
        return try! JSONSerialization.data(withJSONObject: o)
    }

    static func nowcast(gti: Double = 671, wind: Double = 4.9) -> Data {
        let t0 = Int(now.timeIntervalSince1970) / 900 * 900
        let times = (-4...8).map { t0 + $0 * 900 }
        let n = times.count
        let m: [String: Any] = ["time": times, "global_tilted_irradiance_instant": Array(repeating: gti, count: n), "shortwave_radiation": Array(repeating: 618.0, count: n),
                                "wind_speed_10m": Array(repeating: wind, count: n), "wind_gusts_10m": Array(repeating: 7.6, count: n),
                                "wind_direction_10m": Array(repeating: 270.0, count: n), "precipitation": Array(repeating: 0.0, count: n),
                                "weather_code": Array(repeating: 0, count: n), "visibility": Array(repeating: 24140.0, count: n),
                                "temperature_2m": Array(repeating: 17.2, count: n), "dew_point_2m": Array(repeating: -2.2, count: n)]
        return try! JSONSerialization.data(withJSONObject: ["latitude": lat, "longitude": lon, "utc_offset_seconds": offset, "minutely_15": m])
    }

    static let alerts = Data("""
    {"type":"FeatureCollection","features":[{"properties":{"event":"Red Flag Warning","severity":"Severe",
    "headline":"Red Flag Warning issued October 10","description":"* WIND...Southwest 15 to 25 mph.","instruction":"Use caution.",
    "senderName":"NWS Boulder CO","onset":"2026-10-10T13:00:00-06:00","ends":"2026-10-10T20:00:00-06:00"}},
    {"properties":{"event":"High Wind Warning","severity":"Severe","headline":"","description":"","instruction":"",
    "senderName":"NWS Boulder CO","onset":"2026-10-11T08:00:00-06:00","ends":"2026-10-11T18:00:00-06:00"}}]}
    """.utf8)
    static let kpNowObjects = Data(#"[{"time_tag":"2026-10-10T18:00:00","kp_index":3,"estimated_kp":3.33,"kp":"3Z"}]"#.utf8)
    static let kpForecastObjects = Data(#"[{"time_tag":"2026-10-10T18:00:00","kp":2.67,"observed":"observed","noaa_scale":null},{"time_tag":"2026-10-11T03:00:00","kp":5.33,"observed":"predicted","noaa_scale":"G1"}]"#.utf8)
    static let kpForecastArrays = Data(#"[["time_tag","kp","observed","noaa_scale"],["2026-10-10 21:00:00","4.00","predicted",null]]"#.utf8)
    static let airspaceGrid = Data(#"{"features":[{"attributes":{"CEILING":200,"APT1_NAME":"CENTENNIAL","APT1_FAAID":"APA"}}]}"#.utf8)
    static let airspaceNone = Data(#"{"features":[]}"#.utf8)

    static func bundle(forecast f: Data = forecast(), nowcast: Data? = nowcast(), alerts al: Data? = alerts, airspace: Data? = airspaceGrid,
                       gtiKey: String = "global_tilted_irradiance_instant") -> RawBundle {
        RawBundle(lat: lat, lon: lon, fetchedAt: now, forecast: f, nowcast: nowcast, airQuality: nil, alerts: al,
                  kpNow: kpNowObjects, kpForecast: kpForecastObjects, airspace: airspace, gtiKey: gtiKey)
    }

    static func profile(_ variant: String = "rec-casual", drone: String = "dji-matrice-400", rules: PilotRules? = nil) -> FlightProfile {
        FlightProfile(variantID: variant, drone: DroneCatalog.find(drone)!, rules: rules ?? ActivityCatalog.activity(for: variant)!.defaultRules)
    }
}
