import XCTest
#if canImport(AirFieldCore)
@testable import AirFieldCore
#else
@testable import AirField
#endif

final class SunTests: XCTestCase {
    func testSolsticeNoonElevationMatchesGeometry() {
        // June solstice, Castle Rock: 90 − (39.38 − 23.44) ≈ 74.06°
        var best = SunPosition(elevation: -99, azimuth: 0)
        var t = Date(timeIntervalSince1970: 1_782_064_800) // 2026-06-21 18:00 UTC
        for _ in 0..<120 { let p = Sun.position(at: t, lat: 39.3791, lon: -104.8561); if p.elevation > best.elevation { best = p }; t += 60 }
        XCTAssertEqual(best.elevation, 74.06, accuracy: 0.05)
        XCTAssertEqual(best.azimuth, 180, accuracy: 1.0)
    }
    func testSunTimesOrdered() {
        let st = Sun.times(on: Fixture.now, lat: Fixture.lat, lon: Fixture.lon, utcOffset: Fixture.offset)
        let u = Units(imperial: true, utcOffset: Fixture.offset)
        XCTAssertNotNil(st.sunrise); XCTAssertNotNil(st.sunset)
        XCTAssertLessThan(st.civilDawn!, st.sunrise!); XCTAssertLessThan(st.sunrise!, st.goldenMorningEnd!)
        XCTAssertLessThan(st.goldenEveningStart!, st.sunset!); XCTAssertLessThan(st.sunset!, st.civilDusk!)
        // Castle Rock, Oct 10: sunrise ~7:04 AM, sunset ~6:27 PM MDT (NOAA)
        XCTAssertEqual(u.clock(st.sunrise), "7:04 AM"); XCTAssertEqual(u.clock(st.sunset), "6:27 PM")
        // sunrise-sunset.org, Castle Rock, Oct 10 2026: dawn 6:37:30, noon 12:46:20, dusk 6:54:32
        XCTAssertEqual(u.clock(st.civilDawn), "6:37 AM"); XCTAssertEqual(u.clock(st.civilDusk), "6:54 PM")
        XCTAssertEqual(st.solarNoon.timeIntervalSince1970, Date(timeIntervalSince1970: 1_791_657_980).timeIntervalSince1970, accuracy: 120)
    }
    func testGlareMirrorsAboutPanelNormal() {
        let g = Sun.glare(sun: SunPosition(elevation: 44, azimuth: 180), tilt: 30, facing: 180)
        XCTAssertEqual(g.incidence, 16, accuracy: 0.01)
        XCTAssertEqual(g.reflectionElevation, 76, accuracy: 0.01)
        XCTAssertTrue(g.lit)
    }
}

final class CatalogTests: XCTestCase {
    func testEveryDroneIsSane() {
        XCTAssertGreaterThanOrEqual(DroneCatalog.all.count, 20)
        XCTAssertEqual(Set(DroneCatalog.all.map(\.id)).count, DroneCatalog.all.count, "duplicate drone ids")
        for d in DroneCatalog.all {
            XCTAssert((5...20).contains(d.maxWindMS), d.name)
            XCTAssertLessThan(d.tempMinC, d.tempMaxC, d.name)
            XCTAssertNotNil(d.source, d.name)
        }
    }
    func testRainRatingFromIPCode() {
        XCTAssertTrue(DroneCatalog.find("dji-matrice-400")!.rainResistant)      // IP55
        XCTAssertTrue(DroneCatalog.find("autel-evo-max-4t")!.rainResistant)     // IP43
        XCTAssertFalse(DroneCatalog.find("dji-mini-4-pro")!.rainResistant)      // none
        XCTAssertTrue(DroneCatalog.find("dji-neo")!.sub250)
    }
    func testActivitiesHaveUniqueVariantsAndWindTile() {
        let ids = ActivityCatalog.all.flatMap(\.variants).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for v in ActivityCatalog.all.flatMap(\.variants) {
            XCTAssert(v.tiles.contains(.wind) || v.tiles.contains(.spray), "\(v.id) should show wind")
            XCTAssertNotNil(ActivityCatalog.activity(for: v.id))
        }
    }
}

final class RulesTests: XCTestCase {
    let u = Units(imperial: true, utcOffset: Fixture.offset)
    func cond(_ f: (inout Conditions) -> Void) -> Conditions {
        var c = Conditions(time: Fixture.now, sun: SunPosition(elevation: 40, azimuth: 190))
        c.tempC = 18; c.dewC = -2; c.windMS = 4; c.gustMS = 6; c.windAloftMS = 6; c.visibilityM = 24000; c.cloud = 10; c.precipMM = 0; c.code = 0
        c.pressureHPa = 1013; f(&c); return c
    }

    func testWindLimitsFromDrone() {
        let L = WindLimits.derive(for: Fixture.profile(drone: "dji-matrice-400"))
        XCTAssertEqual(L.sustainedHold, 10.2, accuracy: 0.001)        // ≈ 23 mph, 85% of the DJI rating
        XCTAssertEqual(L.gustHold, 12, accuracy: 0.001)
        let learn = WindLimits.derive(for: Fixture.profile("rec-learning", drone: "dji-matrice-400"))
        XCTAssertEqual(learn.sustainedHold, 7.65, accuracy: 0.001)
        var p = Fixture.profile(drone: "dji-matrice-400"); p.personalWindLimitMS = 6
        XCTAssertEqual(WindLimits.derive(for: p).sustainedHold, 6, accuracy: 0.001)
    }
    func testCalmDayIsGo() {
        XCTAssertEqual(Rules.assess(cond { _ in }, profile: Fixture.profile(), units: u).level, .go)
    }
    func testWindAndGustThresholds() {
        let p = Fixture.profile(drone: "dji-mini-4-pro") // 10.7 m/s
        XCTAssertEqual(Rules.assess(cond { $0.windMS = 7.5 }, profile: p, units: u).level, .caution)   // > 6.96 (65%)
        XCTAssertEqual(Rules.assess(cond { $0.windMS = 9.5 }, profile: p, units: u).level, .hold)      // > 9.10 (85%)
        XCTAssertEqual(Rules.assess(cond { $0.gustMS = 11.0 }, profile: p, units: u).level, .hold)     // > 10.7
        XCTAssertEqual(Rules.assess(cond { $0.windAloftMS = 9.0 }, profile: p, units: u).level, .caution)
        // M400: 6 mph gusting 20 is under every limit but choppy; 10 gusting 16 isn't
        let m4 = Fixture.profile(drone: "dji-matrice-400")
        let choppy = Rules.assess(cond { $0.windMS = 6 / 2.236936; $0.gustMS = 20 / 2.236936 }, profile: m4, units: u)
        XCTAssertEqual(choppy.level, .caution)
        XCTAssertTrue(choppy.reasons.contains { $0.text.hasPrefix("Choppy") })
        XCTAssertEqual(Rules.assess(cond { $0.windMS = 10 / 2.236936; $0.gustMS = 16 / 2.236936 }, profile: m4, units: u).level, .go)
    }
    func testRainDependsOnIPRating() {
        let rain: (inout Conditions) -> Void = { $0.precipMM = 0.8; $0.code = 61 }
        XCTAssertEqual(Rules.assess(cond(rain), profile: Fixture.profile(drone: "dji-matrice-400"), units: u).level, .caution)
        XCTAssertEqual(Rules.assess(cond(rain), profile: Fixture.profile(drone: "dji-air-3s"), units: u).level, .hold)
        XCTAssertEqual(Rules.assess(cond { $0.precipMM = 3; $0.code = 65 }, profile: Fixture.profile(drone: "dji-matrice-400"), units: u).level, .hold)
    }
    func testVisibilityRuleDependsOnRuleSet() {
        let fog: (inout Conditions) -> Void = { $0.visibilityM = 3000 }
        XCTAssertEqual(Rules.assess(cond(fog), profile: Fixture.profile("photo-realestate"), units: u).level, .hold)      // Part 107
        XCTAssertEqual(Rules.assess(cond(fog), profile: Fixture.profile("rec-casual"), units: u).level, .caution)         // recreational
    }
    func testTemperatureAgainstDroneRange() {
        let mini = Fixture.profile(drone: "dji-mini-4-pro")  // −10…40
        XCTAssertEqual(Rules.assess(cond { $0.tempC = -12 }, profile: mini, units: u).level, .hold)
        XCTAssertEqual(Rules.assess(cond { $0.tempC = -7 }, profile: mini, units: u).level, .caution)
        XCTAssertEqual(Rules.assess(cond { $0.tempC = -12 }, profile: Fixture.profile(drone: "dji-matrice-400"), units: u).level, .go)
    }
    func testSolarWindow() {
        let p = Fixture.profile("thermal-solar")
        XCTAssertEqual(Rules.assess(cond { $0.gti = 700; $0.cloud = 10 }, profile: p, units: u).level, .go)
        XCTAssertEqual(Rules.assess(cond { $0.gti = 450 }, profile: p, units: u).level, .caution)
        XCTAssertEqual(Rules.assess(cond { $0.gti = 700; $0.cloud = 40 }, profile: p, units: u).level, .caution)
        XCTAssertEqual(Rules.assess(cond { $0.gti = 700; $0.windMS = 8.2 }, profile: p, units: u).level, .caution)  // >28 km/h, < drone caution
        XCTAssertEqual(Rules.assess(cond { $0.sun = SunPosition(elevation: 2, azimuth: 260) }, profile: p, units: u).level, .hold)
    }
    func testDaylightAndNight() {
        let night: (inout Conditions) -> Void = { $0.sun = SunPosition(elevation: -20, azimuth: 0) }
        XCTAssertEqual(Rules.assess(cond(night), profile: Fixture.profile("map-ortho"), units: u).level, .hold)
        XCTAssertEqual(Rules.assess(cond(night), profile: Fixture.profile("map-lidar"), units: u).level, .go)
        XCTAssertEqual(Rules.assess(cond(night), profile: Fixture.profile("thermal-envelope"), units: u).level, .go)
        XCTAssertEqual(Rules.assess(cond { _ in }, profile: Fixture.profile("thermal-envelope"), units: u).level, .caution)
        XCTAssertEqual(Rules.assess(cond(night), profile: Fixture.profile("rec-casual"), units: u).level, .caution)
    }
    func testSprayDrift() {
        let p = Fixture.profile("ag-spray")
        XCTAssertEqual(Rules.assess(cond { $0.windMS = 3 }, profile: p, units: u).level, .go)
        XCTAssertEqual(Rules.assess(cond { $0.windMS = 5 }, profile: p, units: u).level, .hold)
        XCTAssertEqual(Rules.assess(cond { $0.windMS = 0.5 }, profile: p, units: u).level, .caution)
    }
    func testDensityAltitudeAgainstCeiling() {
        // Neo: ceiling 2000 m. Castle Rock pressure on a warm day ≈ 2,600 m density altitude.
        XCTAssertEqual(Rules.assess(cond { $0.pressureHPa = 803.5; $0.tempC = 25 }, profile: Fixture.profile(drone: "dji-neo"), units: u).level, .hold)
        XCTAssertEqual(Physics.densityAltitudeM(pressureHPa: 1013.25, tempC: 15)!, 0, accuracy: 1)
    }
}

final class ParseTests: XCTestCase {
    func testParsesForecastNowcastAndExtras() throws {
        let s = try Parse.site(Fixture.bundle(), now: Fixture.now)
        XCTAssertEqual(s.utcOffset, Fixture.offset)
        XCTAssertEqual(s.hourly.count, 7 * 24 + 3)
        XCTAssertTrue(s.nowcast)
        XCTAssertEqual(s.now.gti, 671)               // from the 15-minute block
        XCTAssertEqual(s.now.windMS, 4.9)
        XCTAssertEqual(s.now.code, 0)
        XCTAssertNil(s.hourly[5].cape)               // nulls survive
        XCTAssertEqual(s.space.kpNow!, 3.33, accuracy: 0.001)
        XCTAssertEqual(s.space.kpMax24h!, 5.33, accuracy: 0.001)
        XCTAssertEqual(s.airspace, .laancGrid(ceilingFt: 200, airport: "CENTENNIAL"))
        XCTAssertEqual(s.alerts.count, 2)
        XCTAssertEqual(s.alerts[0].event, "Red Flag Warning")
        XCTAssertNotNil(s.alerts[0].onset)
        XCTAssertFalse(s.alerts[0].isFlightThreat); XCTAssertTrue(s.alerts[1].isFlightThreat)
    }
    func testWithoutNowcastFallsBackToCurrentBlock() throws {
        let s = try Parse.site(Fixture.bundle(nowcast: nil), now: Fixture.now)
        XCTAssertFalse(s.nowcast)
        XCTAssertEqual(s.now.windMS, 5.2)
        XCTAssertEqual(s.now.code, 1)
    }
    func testHourlyGTIFallbackKey() throws {
        let b = Fixture.bundle(forecast: Fixture.forecast(gtiKey: "global_tilted_irradiance"), nowcast: nil, gtiKey: "global_tilted_irradiance")
        let s = try Parse.site(b, now: Fixture.now)
        XCTAssertNotNil(s.hourly.first { $0.isDaylight }?.gti)
    }
    func testKpArrayFormatAndAirspaceVariants() {
        var b = Fixture.bundle(); b.kpForecast = Fixture.kpForecastArrays
        XCTAssertEqual(Parse.space(b, now: Fixture.now).kpMax24h!, 4.0, accuracy: 0.001)
        XCTAssertEqual(Parse.airspace(Fixture.airspaceNone), .noGrid)
        XCTAssertEqual(Parse.airspace(Data("garbage".utf8)), .unknown)
        XCTAssertEqual(Parse.airspace(nil), .unknown)
    }
    func testBadForecastThrows() {
        XCTAssertThrowsError(try Parse.site(Fixture.bundle(forecast: Data("{}".utf8)), now: Fixture.now))
    }
    func testOpenMeteoAzimuthConvention() {
        XCTAssertEqual(WeatherService.openMeteoAzimuth(180), 0)
        XCTAssertEqual(WeatherService.openMeteoAzimuth(90), -90)
        XCTAssertEqual(WeatherService.openMeteoAzimuth(270), 90)
        XCTAssertEqual(abs(WeatherService.openMeteoAzimuth(0)), 180)
        let url = WeatherService().forecastURL(lat: 39.3791, lon: -104.8561, tilt: 30, facing: 225, gtiKey: "global_tilted_irradiance_instant").absoluteString
        XCTAssertTrue(url.contains("tilt=30&azimuth=45"))
        // past_hours alone makes Open-Meteo return 16 days; forecast_hours pins it to 7 (verified against the live API)
        XCTAssertTrue(url.contains("past_hours=3&forecast_hours=168"))
        XCTAssertTrue(url.hasPrefix("https://api.open-meteo.com/"))
        XCTAssertTrue(WeatherService(config: DataConfig(openMeteoKey: "abc")).forecastURL(lat: 0, lon: 0, tilt: 0, facing: 180, gtiKey: "x").absoluteString.contains("customer-api.open-meteo.com"))
    }
}

final class BriefingTests: XCTestCase {
    func site(_ tweak: @escaping (Int, inout Fixture.Hour) -> Void = { _, _ in }, alerts: Data? = Fixture.alerts, airspace: Data? = Fixture.airspaceGrid) throws -> SiteData {
        try Parse.site(Fixture.bundle(forecast: Fixture.forecast(tweak: tweak), alerts: alerts, airspace: airspace), now: Fixture.now)
    }
    func testEveryVariantBuilds() throws {
        let s = try site()
        for v in ActivityCatalog.all.flatMap(\.variants) {
            for d in DroneCatalog.all {
                let b = BriefingBuilder.build(s, profile: Fixture.profile(v.id, drone: d.id), now: Fixture.now)
                XCTAssertFalse(b.verdict.why.isEmpty)
                XCTAssertEqual(b.hours.count, 48, v.id)
                XCTAssertGreaterThanOrEqual(b.days.count, 6, v.id)
                XCTAssertEqual(b.days[0].title, "Today")
                XCTAssertTrue(b.tiles.allSatisfy { !$0.value.isEmpty })
            }
        }
    }
    func testActiveRedFlagWarningRaisesCaution() throws {
        let s = try site()
        // 12:20 MDT, warning starts 1 PM → not yet active
        XCTAssertEqual(BriefingBuilder.build(s, profile: Fixture.profile(), now: Fixture.now).verdict.level, .go)
        let later = Fixture.now.addingTimeInterval(3600)
        let b = BriefingBuilder.build(s, profile: Fixture.profile(), now: later)
        XCTAssertEqual(b.verdict.level, .caution)
        XCTAssertTrue(b.verdict.why.contains("Red Flag Warning"))
        XCTAssertEqual(b.headsUp.first?.title, "Red Flag Warning")  // the warning in effect comes first
        XCTAssertEqual(b.headsUp[1].title, "High Wind Warning")      // then tomorrow's official warning
    }
    func testGustSurpriseAndNextWindow() throws {
        // gusts of 14 m/s from hour 6 to 10 (3–7 h ahead)
        let s = try site({ i, h in if (6...10).contains(i) { h.gust = 14; h.wind = 10 } }, alerts: nil)
        let b = BriefingBuilder.build(s, profile: Fixture.profile(drone: "dji-matrice-400"), now: Fixture.now)
        XCTAssertTrue(b.headsUp.contains { $0.title == "Gusts over your limit" && $0.level == .hold })
        XCTAssertEqual(b.verdict.level, .go)
        XCTAssertNotNil(b.verdict.next); XCTAssertTrue(b.verdict.next!.hasPrefix("Good until"))
    }
    func testEveryHourlyCautionReachesHeadsUpWordForWord() throws {
        // a low ceiling over a stretch of hours: the 48-hour chart says "Ceiling 100 ft: stay 500 ft below";
        // heads up must carry the same words, once, with the hours it applies
        var s = try site(alerts: nil)
        let i0 = s.hourly.firstIndex { $0.time > Fixture.now }!
        for k in (i0 + 4)...(i0 + 9) { s.hourly[k].ceilingM = 100 * 0.3048 }
        let b = BriefingBuilder.build(s, profile: Fixture.profile(rules: .part107), now: Fixture.now)
        let chart = b.hours.flatMap(\.reasons).first { $0.hasPrefix("Ceiling") }
        XCTAssertEqual(chart, "Ceiling 100 ft: stay 500 ft below")
        let items = b.headsUp.filter { $0.title.hasPrefix("Ceiling") }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, chart)
        XCTAssertTrue(items.first!.detail.contains("(6 h)"), items.first!.detail)
    }
    func testNoCeilingSentinelIsNotALowCeiling() throws {
        // NWS's grid uses -100 ft for "no ceiling"; it must never read as a ceiling under 900 ft
        var s = try site(alerts: nil)
        for k in s.hourly.indices { s.hourly[k].ceilingM = -30.48 }
        let b = BriefingBuilder.build(s, profile: Fixture.profile(rules: .part107), now: Fixture.now)
        XCTAssertFalse(b.hours.flatMap(\.reasons).contains { $0.hasPrefix("Ceiling") })
        XCTAssertFalse(b.headsUp.contains { $0.title.hasPrefix("Ceiling") })
    }
    func testAirspaceCards() throws {
        let p = Fixture.profile()
        XCTAssertEqual(BriefingBuilder.build(try site(airspace: Fixture.airspaceGrid), profile: p, now: Fixture.now).airspace.level, .caution)
        XCTAssertEqual(BriefingBuilder.build(try site(airspace: Fixture.airspaceNone), profile: p, now: Fixture.now).airspace.level, .go)
        XCTAssertEqual(BriefingBuilder.build(try site(airspace: Data(#"{"features":[{"attributes":{"CEILING":0,"APT1_NAME":"DENVER INTL"}}]}"#.utf8)),
                                             profile: p, now: Fixture.now).airspace.level, .hold)
        XCTAssertEqual(BriefingBuilder.build(try site(airspace: nil), profile: p, now: Fixture.now).airspace.level, .caution)
    }
    func testSolarTileIsEditableAndUsesPanelPlane() throws {
        let b = BriefingBuilder.build(try site(), profile: Fixture.profile("thermal-solar"), now: Fixture.now)
        let t = b.tiles.first { $0.id == .irradiance }!
        XCTAssertTrue(t.editable); XCTAssertEqual(t.value, "671"); XCTAssertEqual(t.level, .go)
        XCTAssertEqual(b.verdict.level, .go)
        XCTAssertNotNil(b.glare)
    }
    func testMetricUnits() throws {
        var p = Fixture.profile(); p.imperial = false
        let b = BriefingBuilder.build(try site(), profile: p, now: Fixture.now)
        XCTAssertEqual(b.tiles.first { $0.id == .wind }!.unit, "m/s")
        XCTAssertEqual(b.tiles.first { $0.id == .air }!.unit, "°C")
    }
}

final class UnitsTests: XCTestCase {
    func testConversionsAndFormatting() {
        let u = Units(imperial: true, utcOffset: Fixture.offset)
        XCTAssertEqual(u.speedText(10), "22 mph")
        XCTAssertEqual(u.tempNumber(0), "32")
        XCTAssertEqual(u.visibility(24140).0, "10+")
        XCTAssertEqual(Units.compass(250), "WSW")
        XCTAssertEqual(Units.compass(359), "N")
        XCTAssertEqual(u.clock(Fixture.now), "12:20 PM")
        XCTAssertEqual(u.when(Fixture.now.addingTimeInterval(86400), now: Fixture.now), "tomorrow 12:20 PM")
        XCTAssertEqual(u.localHour(Fixture.now), 12)
        let m = Units(imperial: false)
        XCTAssertEqual(m.speedText(4.94), "4.9 m/s")
    }
}
