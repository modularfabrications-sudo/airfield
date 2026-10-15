import Foundation

/// Solar position from the NOAA solar calculator algorithm (accurate to ~0.01° for current dates).
public struct SunPosition: Equatable, Sendable {
    /// Degrees above the horizon, refraction-corrected.
    public let elevation: Double
    /// Compass azimuth, degrees clockwise from true north.
    public let azimuth: Double
}

public enum Sun {
    private static let d2r = Double.pi / 180, r2d = 180 / Double.pi

    /// `refraction: false` gives the geometric position, which is what the standard sunrise/twilight definitions use.
    public static func position(at date: Date, lat: Double, lon: Double, refraction: Bool = true) -> SunPosition {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (jd - 2451545) / 36525
        var l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360); if l0 < 0 { l0 += 360 }
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m * d2r) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * m * d2r) * (0.019993 - 0.000101 * t) + sin(3 * m * d2r) * 0.000289
        let om = 125.04 - 1934.136 * t
        let lam = l0 + c - 0.00569 - 0.00478 * sin(om * d2r)
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(om * d2r)
        let dec = asin(sin(eps * d2r) * sin(lam * d2r))
        let y = pow(tan(eps * d2r / 2), 2)
        let eqt = 4 * r2d * (y * sin(2 * l0 * d2r) - 2 * e * sin(m * d2r) + 4 * e * y * sin(m * d2r) * cos(2 * l0 * d2r)
                             - 0.5 * y * y * sin(4 * l0 * d2r) - 1.25 * e * e * sin(2 * m * d2r))
        let secs = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400)
        var tst = (secs < 0 ? secs + 86400 : secs) / 60 + eqt + 4 * lon
        tst = tst.truncatingRemainder(dividingBy: 1440); if tst < 0 { tst += 1440 }
        let ha = (tst / 4 - 180) * d2r, la = lat * d2r
        let cz = max(-1, min(1, sin(la) * sin(dec) + cos(la) * cos(dec) * cos(ha)))
        var elev = 90 - acos(cz) * r2d
        // atmospheric refraction (NOAA)
        let te = tan(elev * d2r)
        if !refraction { return SunPosition(elevation: elev, azimuth: azimuth(ha: ha, la: la, dec: dec)) }
        var r = 0.0
        if elev > 85 { r = 0 }
        else if elev > 5 { r = 58.1 / te - 0.07 / pow(te, 3) + 0.000086 / pow(te, 5) }
        else if elev > -0.575 { r = 1735 + elev * (-518.2 + elev * (103.4 + elev * (-12.79 + elev * 0.711))) }
        else { r = -20.774 / te }
        elev += r / 3600
        return SunPosition(elevation: elev, azimuth: azimuth(ha: ha, la: la, dec: dec))
    }

    private static func azimuth(ha: Double, la: Double, dec: Double) -> Double {
        var az = atan2(sin(ha), cos(ha) * sin(la) - tan(dec) * cos(la)) * r2d + 180
        az = az.truncatingRemainder(dividingBy: 360); if az < 0 { az += 360 }
        return az
    }

    /// First time in [from, to] at which the sun's elevation crosses `target` degrees (bisection).
    public static func crossing(from: Date, to: Date, lat: Double, lon: Double, target: Double) -> Date? {
        var a = from.timeIntervalSince1970, b = to.timeIntervalSince1970
        var fa = position(at: from, lat: lat, lon: lon, refraction: false).elevation - target
        let fb = position(at: to, lat: lat, lon: lon, refraction: false).elevation - target
        if fa * fb > 0 { return nil }
        for _ in 0..<40 {
            let mid = (a + b) / 2
            let fm = position(at: Date(timeIntervalSince1970: mid), lat: lat, lon: lon, refraction: false).elevation - target
            if fa * fm <= 0 { b = mid } else { a = mid; fa = fm }
        }
        return Date(timeIntervalSince1970: (a + b) / 2)
    }

    /// Key sun times for the local day containing `day`. `utcOffset` is the site's offset in seconds.
    public static func times(on day: Date, lat: Double, lon: Double, utcOffset: Int) -> SunTimes {
        let localMidnight = floor((day.timeIntervalSince1970 + Double(utcOffset)) / 86400) * 86400 - Double(utcOffset)
        let m0 = Date(timeIntervalSince1970: localMidnight)
        // solar noon: maximum elevation, searched at 2-minute resolution then refined
        var best = m0, bestEl = -99.0
        var t = m0
        while t < m0.addingTimeInterval(86400) {
            let el = position(at: t, lat: lat, lon: lon).elevation
            if el > bestEl { bestEl = el; best = t }
            t = t.addingTimeInterval(120)
        }
        let noon = best
        let end = m0.addingTimeInterval(86400)
        func rise(_ target: Double) -> Date? { crossing(from: m0, to: noon, lat: lat, lon: lon, target: target) }
        func set(_ target: Double) -> Date? { crossing(from: noon, to: end, lat: lat, lon: lon, target: target) }
        return SunTimes(civilDawn: rise(-6), sunrise: rise(-0.833), goldenMorningEnd: rise(6),
                        solarNoon: noon, noonElevation: bestEl,
                        goldenEveningStart: set(6), sunset: set(-0.833), civilDusk: set(-6))
    }

    // MARK: panel geometry

    private static func vector(az: Double, el: Double) -> (Double, Double, Double) {
        (cos(el * d2r) * sin(az * d2r), cos(el * d2r) * cos(az * d2r), sin(el * d2r))
    }

    /// Angle of incidence on a tilted plane, and where its specular reflection points (glare).
    public static func glare(sun: SunPosition, tilt: Double, facing: Double) -> (incidence: Double, reflectionElevation: Double, reflectionAzimuth: Double, lit: Bool) {
        let s = vector(az: sun.azimuth, el: sun.elevation)
        let n = (sin(tilt * d2r) * sin(facing * d2r), sin(tilt * d2r) * cos(facing * d2r), cos(tilt * d2r))
        let dot = s.0 * n.0 + s.1 * n.1 + s.2 * n.2
        let aoi = acos(max(-1, min(1, dot))) * r2d
        let r = (2 * dot * n.0 - s.0, 2 * dot * n.1 - s.1, 2 * dot * n.2 - s.2)
        let gel = asin(max(-1, min(1, r.2))) * r2d
        var gaz = atan2(r.0, r.1) * r2d; gaz = gaz.truncatingRemainder(dividingBy: 360); if gaz < 0 { gaz += 360 }
        return (aoi, gel, gaz, dot > 0)
    }
}

public struct SunTimes: Equatable, Sendable {
    public let civilDawn: Date?
    public let sunrise: Date?
    /// Morning golden hour runs from sunrise until the sun reaches 6°.
    public let goldenMorningEnd: Date?
    public let solarNoon: Date
    public let noonElevation: Double
    /// Evening golden hour starts when the sun drops to 6°.
    public let goldenEveningStart: Date?
    public let sunset: Date?
    public let civilDusk: Date?
}
