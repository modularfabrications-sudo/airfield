import XCTest
#if canImport(AirFieldCore)
@testable import AirFieldCore
#else
@testable import AirField
#endif

/// Live responses captured 2026-10-10 23:49 UTC for Castle Rock, CO (trimmed to ~3 days).
enum Live {
    static let now = Date(timeIntervalSince1970: 1_791_676_140)   // 2026-10-10 23:49 UTC (5:49 PM MDT)
    static let lat = 39.3791, lon = -104.8561
    static func sample(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Samples/\(name).json")
        return try! Data(contentsOf: url)
    }
    static func nws(metar: Bool = true, lat: Double = lat, lon: Double = lon) -> RawBundle {
        RawBundle(lat: lat, lon: lon, fetchedAt: now, forecast: sample("grid"), nowcast: nil, airQuality: nil, alerts: nil,
                  kpNow: nil, kpForecast: nil, airspace: nil, source: "nws", points: sample("points"), metar: metar ? sample("metar") : nil)
    }
    static func metno() -> RawBundle {
        RawBundle(lat: lat, lon: lon, fetchedAt: now, forecast: sample("metno"), nowcast: nil, airQuality: nil, alerts: nil,
                  kpNow: nil, kpForecast: nil, airspace: nil, source: "metno", points: nil, metar: sample("metar"))
    }
}

final class FreeSourceTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(ISO.duration("PT2H"), 7200)
        XCTAssertEqual(ISO.duration("P1D"), 86400)
        XCTAssertEqual(ISO.duration("P7DT13H"), 7 * 86400 + 13 * 3600)
        XCTAssertEqual(ISO.duration("PT30M"), 1800)
        XCTAssertNil(ISO.duration("2H"))
        let iv = ISO.interval("2026-10-10T12:00:00+00:00/PT2H")!
        XCTAssertEqual(iv.1.timeIntervalSince(iv.0), 7200)
    }

    func testNWSGridParses() throws {
        let s = try Parse.site(Live.nws(), now: Live.now)
        XCTAssertEqual(s.sources.forecast, .nws)
        XCTAssertEqual(s.utcOffset, -21600)
        XCTAssertEqual(s.timezone, "America/Denver")
        XCTAssertEqual(s.elevationM!, 1890, accuracy: 1)
        XCTAssertGreaterThan(s.hourly.count, 60)
        // hourly steps, starting 3 h back
        XCTAssertEqual(s.hourly[1].time.timeIntervalSince(s.hourly[0].time), 3600)
        XCTAssertLessThanOrEqual(s.hourly[0].time, Live.now.addingTimeInterval(-3 * 3600 + 1))
        // every hour has the basics, converted to SI
        for c in s.hourly.prefix(60) {
            XCTAssertNotNil(c.tempC); XCTAssertNotNil(c.windMS); XCTAssertNotNil(c.cloud); XCTAssertNotNil(c.code)
            XCTAssertLessThan(c.windMS!, 25)
            XCTAssertGreaterThanOrEqual(c.gustMS!, c.windMS!)
        }
        // 2026-10-10T12:00Z/PT2H temperature 11.67 °C covers 12Z and 13Z
        let t12 = Date(timeIntervalSince1970: 1_791_633_600)
        if let c = s.hourly.first(where: { $0.time == t12 }) { XCTAssertEqual(c.tempC!, 11.667, accuracy: 0.01) }
    }

    func testFarAirportOnlyCautions() throws {
        // Castle Rock: Centennial is 20 km off, so "now" stays the forecast for the spot and KAPA rides along
        let s = try Parse.site(Live.nws(), now: Live.now)
        XCTAssertNil(s.sources.station)
        XCTAssertFalse(s.nowcast)
        let n = s.now
        XCTAssertEqual(n.nearby?.station, "KAPA")
        XCTAssertEqual(n.nearby!.km, 20.1, accuracy: 0.5)
        XCTAssertEqual(n.nearby!.gustMS!, 18 * 0.514444, accuracy: 0.01)
        XCTAssertNotEqual(n.gustMS, n.nearby!.gustMS)
        XCTAssertEqual(n.pressureHPa!, 803, accuracy: 2)          // the altimeter setting is regional: still used
        // a nearby gust over the limit is a caution with the airport named, never a hold on its own
        var c = n; c.windMS = 4; c.gustMS = 6; c.windAloftMS = 6; c.nearby?.gustMS = 14
        let a = Rules.assess(c, profile: Fixture.profile(drone: "dji-matrice-400"), units: Units(imperial: true))
        XCTAssertTrue(a.reasons.contains { $0.level == .caution && $0.text.contains("KAPA 20 km away") })
        XCTAssertFalse(a.reasons.contains { $0.level == .hold && $0.text.contains("KAPA") })
    }

    func testNearestMETARDrivesNow() throws {
        // right next to Centennial: the airport is measuring this spot
        let s = try Parse.site(Live.nws(lat: 39.565, lon: -104.85), now: Live.now)
        XCTAssertEqual(s.sources.station, "KAPA")
        XCTAssertLessThan(s.sources.stationKm!, 1)
        let n = s.now
        XCTAssertNil(n.nearby)
        XCTAssertEqual(n.windMS!, 11 * 0.514444, accuracy: 0.01)
        XCTAssertEqual(n.gustMS!, 18 * 0.514444, accuracy: 0.01)
        XCTAssertEqual(n.ceilingM!, 11000 * 0.3048, accuracy: 1)
        XCTAssertEqual(n.cloud!, 75)
        XCTAssertEqual(n.visibilityM!, 10 * 1609.34, accuracy: 1)
        XCTAssertTrue(s.nowcast)
        // station pressure from the 1009.9 hPa altimeter at 1890 m
        XCTAssertEqual(n.pressureHPa!, 803, accuracy: 2)
    }

    func testFallsBackToForecastWithoutMETAR() throws {
        let s = try Parse.site(Live.nws(metar: false), now: Live.now)
        XCTAssertNil(s.sources.station)
        XCTAssertFalse(s.nowcast)
        XCTAssertNotNil(s.now.windMS)
        XCTAssertEqual(s.now.pressureHPa!, Estimate.standardPressure(elevationM: 1890), accuracy: 0.5)
    }

    func testMETARStationTooHighIsSkipped() {
        let o = METAR.nearest(Live.sample("metar"), lat: Live.lat, lon: Live.lon, siteElevationM: 3000, now: Live.now)
        XCTAssertNil(o)
        let old = METAR.nearest(Live.sample("metar"), lat: Live.lat, lon: Live.lon, siteElevationM: 1890, now: Live.now.addingTimeInterval(4 * 3600))
        XCTAssertNil(old)
    }

    func testMETARWeather() {
        XCTAssertEqual(METAR.weather("-RA BR").0, 61)
        XCTAssertEqual(METAR.weather("+TSRA").0, 95)
        XCTAssertEqual(METAR.weather("FZFG").0, 48)
        XCTAssertEqual(METAR.weather("-SHSN").0, 85)
        XCTAssertEqual(METAR.weather("HZ").0, nil)
        XCTAssertEqual(METAR.weather("").1, 0)
    }

    func testClearSkyIrradianceIsRealistic() {
        // Castle Rock solar noon on 10 Oct: sun ~44° up. Clear Colorado autumn noon GHI is typically 700–800 W/m².
        let noon = Date(timeIntervalSince1970: 1_791_658_000)   // 18:46 UTC
        let sun = Sun.position(at: noon, lat: Live.lat, lon: Live.lon)
        XCTAssertEqual(sun.elevation, 44, accuracy: 1.5)
        let clear = Estimate.irradiance(sun: sun, date: noon, altitudeM: 1890, cloudPct: 0, tilt: 30, facing: 180)
        XCTAssertGreaterThan(clear.ghi, 680); XCTAssertLessThan(clear.ghi, 830)
        // a 30° south panel faces the low October sun better than flat ground
        XCTAssertGreaterThan(clear.gti, clear.ghi * 1.15); XCTAssertLessThan(clear.gti, 1080)
        // facing north it gets less than flat
        let north = Estimate.irradiance(sun: sun, date: noon, altitudeM: 1890, cloudPct: 0, tilt: 30, facing: 0)
        XCTAssertLessThan(north.gti, clear.ghi)
        // overcast cuts it to about a quarter
        let ovc = Estimate.irradiance(sun: sun, date: noon, altitudeM: 1890, cloudPct: 100, tilt: 30, facing: 180)
        XCTAssertEqual(ovc.ghi / clear.ghi, 0.25, accuracy: 0.01)
        XCTAssertLessThan(ovc.gti, Rules.solarIrradiance)
        // night is zero
        let night = Sun.position(at: noon.addingTimeInterval(12 * 3600), lat: Live.lat, lon: Live.lon)
        XCTAssertEqual(Estimate.irradiance(sun: night, date: noon, altitudeM: 1890, cloudPct: 0, tilt: 30, facing: 180).gti, 0)
        // UV around 5 at this sun height and altitude
        XCTAssertEqual(Estimate.uvIndex(sun: sun, altitudeM: 1890, cloudPct: 0), 5, accuracy: 1)
    }

    func testWindAloftEstimate() {
        let day = Estimate.windAloft(surfaceMS: 5, sunElevation: 40, cloudPct: 0)
        let night = Estimate.windAloft(surfaceMS: 5, sunElevation: -20, cloudPct: 0)
        XCTAssertEqual(day / 5, 1.35, accuracy: 0.05)
        XCTAssertEqual(night / 5, 2.1, accuracy: 0.1)
        XCTAssertGreaterThan(night, day)
    }

    func testMetNorwayFallbackParses() throws {
        let s = try Parse.site(Live.metno(), now: Live.now)
        XCTAssertEqual(s.sources.forecast, .metNorway)
        XCTAssertEqual(s.elevationM!, 1922, accuracy: 1)
        XCTAssertGreaterThan(s.hourly.count, 30)
        XCTAssertEqual(s.hourly[1].time.timeIntervalSince(s.hourly[0].time), 3600)
        for c in s.hourly { XCTAssertNotNil(c.windMS); XCTAssertNotNil(c.code); XCTAssertNotNil(c.pressureHPa) }
        XCTAssertEqual(Parse.metNoCode("partlycloudy_day"), 2)
        XCTAssertEqual(Parse.metNoCode("heavyrainandthunder"), 95)
        XCTAssertEqual(Parse.metNoCode("lightsnowshowers_night"), 85)
    }

    func testBriefingFromFreeSources() throws {
        let s = try Parse.site(Live.nws(), now: Live.now)
        let b = BriefingBuilder.build(s, profile: Fixture.profile("thermal-solar"), now: Live.now)
        XCTAssertEqual(b.sourceNote, "NWS forecast for this spot; KAPA is 20 km away")
        let near = BriefingBuilder.build(try Parse.site(Live.nws(lat: 39.565, lon: -104.85), now: Live.now), profile: Fixture.profile("thermal-solar"), now: Live.now)
        XCTAssertTrue(near.sourceNote.hasPrefix("KAPA obs, 1 km") || near.sourceNote.hasPrefix("KAPA obs, 0 km"))
        XCTAssertTrue(b.credits.contains("National Weather Service"))
        XCTAssertTrue(b.credits.contains("calculated"))
        let irr = b.tiles.first { $0.id == .irradiance }!
        XCTAssertTrue(irr.detail.hasSuffix("calculated"))
        XCTAssertFalse(b.hours.isEmpty)
        XCTAssertFalse(b.days.isEmpty)
    }

    func testThunderAndCeilingRules() {
        var c = Conditions(time: Live.now, sun: Sun.position(at: Live.now, lat: Live.lat, lon: Live.lon))
        c.windMS = 3; c.gustMS = 4; c.tempC = 15; c.thunderChance = 40
        let p = Fixture.profile()
        let u = Units(imperial: true, utcOffset: -21600)
        XCTAssertTrue(Rules.assess(c, profile: p, units: u).reasons.contains { $0.text.hasPrefix("Thunder chance 40%") })
        c.thunderChance = nil; c.ceilingM = 200
        let a = Rules.assess(c, profile: Fixture.profile("photo-realestate"), units: u)
        XCTAssertTrue(a.reasons.contains { $0.text.hasPrefix("Ceiling") }, "\(a.reasons)")
    }

    func testWeekCellsCarryTimeReasonAndWind() throws {
        let s = try Parse.site(Live.nws(), now: Live.now)
        let b = BriefingBuilder.build(s, profile: Fixture.profile(), now: Live.now)
        let d = b.days[0]
        for h in 0..<24 where d.cells[h] != nil {
            XCTAssertNotNil(d.times[h]); XCTAssertNotNil(d.winds[h])
            XCTAssertEqual(b.units.localHour(d.times[h]!), h)
            if d.cells[h] != .go { XCTAssertNotNil(d.reasons[h]) }
        }
    }

    func testOutsideUSAirspaceCard() throws {
        var b = Live.metno(); b.outsideUS = true; b.airspace = Data(#"{"features":[]}"#.utf8)
        let s = try Parse.site(b, now: Live.now)
        XCTAssertTrue(s.sources.outsideUS)
        let card = BriefingBuilder.build(s, profile: Fixture.profile(), now: Live.now).airspace
        XCTAssertEqual(card.title, "Outside FAA coverage")
        // a Weather Service outage inside the US must not claim we're abroad
        var us = Live.metno(); us.airspace = Data(#"{"features":[]}"#.utf8)
        let s2 = try Parse.site(us, now: Live.now)
        XCTAssertEqual(BriefingBuilder.build(s2, profile: Fixture.profile(), now: Live.now).airspace.title, "No LAANC grid here")
    }

    func testRequestsUseRoundedCoordinates() {
        let u = WeatherService.airspaceURL(lat: 39.379123456, lon: -104.856198765).absoluteString
        XCTAssertTrue(u.contains("geometry=-104.8562,39.3791"), u)
    }

    func testM400PayloadByDensityAltitude() {
        XCTAssertEqual(DroneCatalog.maxPayloadKg(droneID: "dji-matrice-400", densityAltitudeM: 500)!, 6)
        XCTAssertEqual(DroneCatalog.maxPayloadKg(droneID: "dji-matrice-400", densityAltitudeM: 2550)!, 4.615, accuracy: 0.01)
        XCTAssertEqual(DroneCatalog.maxPayloadKg(droneID: "dji-matrice-400", densityAltitudeM: 9000)!, 1.0)
        XCTAssertNil(DroneCatalog.maxPayloadKg(droneID: "dji-mini-4-pro", densityAltitudeM: 2000))
    }

    func testSolarSetupMatchesFieldPage() throws {
        let s = try Parse.site(Live.nws(), now: Live.now)
        let b = BriefingBuilder.build(s, profile: Fixture.profile("thermal-solar", drone: "dji-matrice-400"), now: Live.now)
        let ids = b.tiles.map(\.id)
        for k in [TileKind.irradiance, .sky, .wind, .windAloft, .visibility, .air, .densityAltitude, .gnss] { XCTAssertTrue(ids.contains(k), "\(k)") }
        XCTAssertFalse(ids.contains(.smoke), "no air-quality feed, so no empty smoke tile")
        let da = b.tiles.first { $0.id == .densityAltitude }!
        XCTAssertTrue(da.detail.hasPrefix("Max payload ") && da.detail.hasSuffix(" lb"), da.detail)
        // week summary names the window's hours on days that have one
        XCTAssertTrue(b.days.contains { $0.summary.contains("in the inspection window") })
    }
}
