import Foundation

/// Conditions at one moment. SI units throughout: °C, m/s, mm, metres, hPa, W/m².
public struct Conditions: Equatable, Sendable {
    public var time: Date
    public var tempC: Double?
    public var dewC: Double?
    public var humidity: Double?
    public var precipMM: Double?
    public var precipChance: Double?
    public var code: Int?
    public var cloud: Double?
    public var cloudLow: Double?
    public var visibilityM: Double?
    public var windMS: Double?
    public var gustMS: Double?
    public var windDir: Double?
    /// Wind at 120 m (~400 ft).
    public var windAloftMS: Double?
    public var cape: Double?
    /// Chance of thunder in the hour (%), from the NWS grid.
    public var thunderChance: Double?
    /// Observed ceiling above ground (m): lowest broken / overcast layer in the nearest METAR.
    public var ceilingM: Double?
    /// An airport report too far away to stand in for this spot (10–30 km), kept as a regional warning sign.
    public var nearby: NearbyReport?
    /// Global horizontal irradiance.
    public var ghi: Double?
    /// Global tilted irradiance on the user's panel plane.
    public var gti: Double?
    public var uv: Double?
    public var pressureHPa: Double?
    public var aqi: Double?
    public var sun: SunPosition

    public init(time: Date, sun: SunPosition) { self.time = time; self.sun = sun }

    public var isDaylight: Bool { sun.elevation > -0.833 }
}

/// Wind measured at an airport near, but not at, the site.
public struct NearbyReport: Equatable, Sendable {
    public var station: String
    public var km: Double
    public var windMS: Double?
    public var gustMS: Double?
    public init(station: String, km: Double, windMS: Double?, gustMS: Double?) { self.station = station; self.km = km; self.windMS = windMS; self.gustMS = gustMS }
}

public enum WMO {
    public static func describe(_ code: Int?) -> String {
        switch code ?? -1 {
        case 0: return "Clear"; case 1: return "Mostly clear"; case 2: return "Partly cloudy"; case 3: return "Overcast"
        case 45: return "Fog"; case 48: return "Freezing fog"
        case 51: return "Light drizzle"; case 53: return "Drizzle"; case 55: return "Heavy drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Light rain"; case 63: return "Rain"; case 65: return "Heavy rain"; case 66, 67: return "Freezing rain"
        case 71: return "Light snow"; case 73: return "Snow"; case 75: return "Heavy snow"; case 77: return "Snow grains"
        case 80, 81: return "Rain showers"; case 82: return "Violent showers"; case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"; case 96, 99: return "Thunderstorm with hail"
        default: return "—"
        }
    }
    public static func isStorm(_ c: Int?) -> Bool { [95, 96, 99].contains(c ?? -1) }
    public static func isSnow(_ c: Int?) -> Bool { guard let c else { return false }; return (71...77).contains(c) || c == 85 || c == 86 }
    public static func isFreezing(_ c: Int?) -> Bool { [48, 56, 57, 66, 67].contains(c ?? -1) }
    public static func isFog(_ c: Int?) -> Bool { [45, 48].contains(c ?? -1) }
}

public enum Physics {
    /// Density altitude in metres from station pressure (hPa) and temperature (°C).
    public static func densityAltitudeM(pressureHPa: Double?, tempC: Double?) -> Double? {
        guard let p = pressureHPa, let t = tempC, p > 0 else { return nil }
        let paFt = (1 - pow(p / 1013.25, 0.190284)) * 145366.45
        let isa = 15 - 1.98 * paFt / 1000
        return (paFt + 118.8 * (t - isa)) * 0.3048
    }
    /// Estimated cloud base above ground (m) from the temperature/dew-point spread (2.5 °C per 1000 ft).
    public static func cloudBaseM(tempC: Double?, dewC: Double?) -> Double? {
        guard let t = tempC, let d = dewC else { return nil }
        return max(0, (t - d) / 2.5 * 1000 * 0.3048)
    }
}

/// Space weather: planetary K-index now and the max forecast for the next 24 h.
public struct SpaceWeather: Equatable, Sendable {
    public var kpNow: Double?
    public var kpMax24h: Double?
    public var kpMaxAt: Date?
    public init(kpNow: Double? = nil, kpMax24h: Double? = nil, kpMaxAt: Date? = nil) { self.kpNow = kpNow; self.kpMax24h = kpMax24h; self.kpMaxAt = kpMaxAt }
}

/// FAA UAS Facility Map result at a point.
public enum Airspace: Equatable, Sendable {
    /// Inside a LAANC grid: max altitude (ft AGL) LAANC can approve here, and the airport it belongs to.
    case laancGrid(ceilingFt: Int, airport: String?)
    /// No facility-map grid here (typically uncontrolled Class G airspace).
    case noGrid
    case unknown
}

/// An official alert from the National Weather Service.
public struct WeatherAlert: Equatable, Sendable {
    public var event: String
    public var headline: String
    public var severity: String
    public var description: String
    public var instruction: String
    public var sender: String
    public var onset: Date?
    public var ends: Date?
    public init(event: String, headline: String = "", severity: String = "", description: String = "", instruction: String = "",
                sender: String = "National Weather Service", onset: Date? = nil, ends: Date? = nil) {
        self.event = event; self.headline = headline; self.severity = severity; self.description = description
        self.instruction = instruction; self.sender = sender; self.onset = onset; self.ends = ends
    }
    /// Alerts that directly threaten a flight get the stronger "hold" treatment.
    public var isFlightThreat: Bool {
        let e = event.lowercased()
        return ["tornado", "severe thunderstorm", "high wind", "extreme wind", "blizzard", "ice storm",
                "winter storm warning", "dust storm", "hurricane", "tropical storm", "flash flood", "snow squall"].contains { e.contains($0) }
    }
}

/// Where the numbers came from, for the source notes and tile details.
public struct SourceInfo: Equatable, Sendable {
    public enum Forecast: String, Sendable { case nws, metNorway, openMeteo }
    public var forecast: Forecast
    /// Nearest airport observation used for "now", e.g. ("KAPA", 13 km).
    public var station: String?
    public var stationKm: Double?
    public var observedAt: Date?
    /// Outside the National Weather Service's (and the FAA's) coverage.
    public var outsideUS: Bool
    public init(forecast: Forecast, station: String? = nil, stationKm: Double? = nil, observedAt: Date? = nil, outsideUS: Bool = false) {
        self.forecast = forecast; self.station = station; self.stationKm = stationKm; self.observedAt = observedAt; self.outsideUS = outsideUS
    }
    /// Irradiance and 400 ft wind are calculated (sky cover + sun geometry; wind profile) rather than modelled.
    public var estimated: Bool { forecast != .openMeteo }
    public var forecastName: String {
        switch forecast { case .nws: "National Weather Service"; case .metNorway: "MET Norway"; case .openMeteo: "Open-Meteo" }
    }
}

/// Everything fetched for one place.
public struct SiteData: Sendable {
    public var sources: SourceInfo
    public var lat: Double
    public var lon: Double
    public var elevationM: Double?
    public var utcOffset: Int
    public var timezone: String?
    /// Best estimate of conditions right now (15-minute HRRR where available).
    public var now: Conditions
    /// Hourly forecast, starting a few hours in the past.
    public var hourly: [Conditions]
    public var space: SpaceWeather
    public var airspace: Airspace
    public var alerts: [WeatherAlert]
    public var fetchedAt: Date
    /// True when `now` came from the 15-minute model.
    public var nowcast: Bool

    public init(sources: SourceInfo = SourceInfo(forecast: .openMeteo), lat: Double, lon: Double, elevationM: Double?, utcOffset: Int, timezone: String?,
                now: Conditions, hourly: [Conditions], space: SpaceWeather, airspace: Airspace, alerts: [WeatherAlert], fetchedAt: Date, nowcast: Bool) {
        self.sources = sources; self.lat = lat; self.lon = lon; self.elevationM = elevationM; self.utcOffset = utcOffset; self.timezone = timezone
        self.now = now; self.hourly = hourly; self.space = space; self.airspace = airspace; self.alerts = alerts
        self.fetchedAt = fetchedAt; self.nowcast = nowcast
    }
}
