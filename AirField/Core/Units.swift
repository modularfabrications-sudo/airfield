import Foundation

/// Display formatting. Everything is stored in SI and converted only here.
public struct Units: Equatable, Sendable {
    public var imperial: Bool
    public var utcOffset: Int
    public init(imperial: Bool, utcOffset: Int = 0) { self.imperial = imperial; self.utcOffset = utcOffset }

    public static func round(_ x: Double?, _ digits: Int = 0) -> String {
        guard let x, x.isFinite else { return "—" }
        let p = pow(10, Double(digits))
        var v = (x * p).rounded() / p
        if v == 0 { v = 0 }   // no "-0"
        let s = String(format: "%.\(digits)f", v)
        guard abs(v) >= 10000 else { return s }
        // thousands separators for big numbers (e.g. density altitude in feet)
        let parts = s.split(separator: ".", maxSplits: 1).map(String.init)
        var intPart = parts[0], sign = ""
        if intPart.hasPrefix("-") { sign = "-"; intPart.removeFirst() }
        var out = ""; for (i, ch) in intPart.reversed().enumerated() { if i > 0 && i % 3 == 0 { out.append(",") }; out.append(ch) }
        return sign + String(out.reversed()) + (parts.count > 1 ? "." + parts[1] : "")
    }

    // speed
    public var speedUnit: String { imperial ? "mph" : "m/s" }
    public func speed(_ ms: Double?) -> Double? { ms.map { imperial ? $0 * 2.236936 : $0 } }
    public func speedText(_ ms: Double?) -> String { "\(Units.round(speed(ms), imperial ? 0 : 1)) \(speedUnit)" }
    public func speedNumber(_ ms: Double?) -> String { Units.round(speed(ms), imperial ? 0 : 1) }

    // temperature
    public var tempUnit: String { imperial ? "°F" : "°C" }
    public func temp(_ c: Double?) -> Double? { c.map { imperial ? $0 * 9 / 5 + 32 : $0 } }
    public func tempNumber(_ c: Double?) -> String { Units.round(temp(c)) }
    public func tempDelta(_ dc: Double) -> String { "\(Units.round(imperial ? dc * 9 / 5 : dc))\(imperial ? "°F" : "°C")" }

    // distance / height
    public func visibility(_ m: Double?) -> (String, String) {
        guard let m else { return ("—", imperial ? "mi" : "km") }
        if imperial { let mi = m / 1609.344; return (mi >= 9.95 ? "10+" : Units.round(mi, 1), "mi") }
        let km = m / 1000; return (km >= 15.95 ? "16+" : Units.round(km, 1), "km")
    }
    public var heightUnit: String { imperial ? "ft" : "m" }
    public func height(_ m: Double?) -> Double? { m.map { imperial ? $0 * 3.28084 : $0 } }
    public func heightText(_ m: Double?, roundTo step: Double = 100) -> String {
        guard let h = height(m) else { return "—" }
        let s = imperial ? step : step / 4
        return "\(Units.round((h / s).rounded() * s)) \(heightUnit)"
    }
    public var altitudeLabel400: String { imperial ? "400 ft" : "120 m" }

    // time, in the site's local time
    private func formatter(_ fmt: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: utcOffset); f.dateFormat = fmt; return f
    }
    public func clock(_ d: Date?) -> String {
        guard let d else { return "—" }
        let s = formatter("h:mm a").string(from: d)
        return s.hasSuffix(":00 AM") || s.hasSuffix(":00 PM") ? formatter("h a").string(from: d) : s
    }
    public func hourShort(_ d: Date) -> String { formatter("ha").string(from: d).lowercased().replacingOccurrences(of: "m", with: "") }
    public func weekday(_ d: Date) -> String { formatter("EEE").string(from: d) }
    public func monthDay(_ d: Date) -> String { formatter("MMM d").string(from: d) }
    public func localHour(_ d: Date) -> Int { Int(((d.timeIntervalSince1970 + Double(utcOffset)).truncatingRemainder(dividingBy: 86400) + 86400).truncatingRemainder(dividingBy: 86400) / 3600) }
    public func dayKey(_ d: Date) -> Int { Int(floor((d.timeIntervalSince1970 + Double(utcOffset)) / 86400)) }
    /// "3 PM", "tomorrow 3 PM" or "Tue 3 PM" relative to `now`.
    public func when(_ d: Date, now: Date) -> String {
        let k = dayKey(d), today = dayKey(now)
        return (k == today ? "" : k == today + 1 ? "tomorrow " : weekday(d) + " ") + clock(d)
    }

    public static let compassPoints = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
    public static func compass(_ deg: Double?) -> String {
        guard let deg, deg.isFinite else { return "—" }
        let i = Int(((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 22.5).rounded()) % 16
        return compassPoints[i]
    }
}
