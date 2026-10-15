import Foundation

/// A drone's published operating limits. All values are SI: grams, m/s, °C, metres.
public struct Drone: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var maker: String
    public var model: String
    /// Take-off weight in grams (as published; max take-off weight where only that is given).
    public var weightG: Double
    /// Manufacturer "max wind speed resistance" in m/s.
    public var maxWindMS: Double
    public var tempMinC: Double
    public var tempMaxC: Double
    /// e.g. "IP55". nil when the maker publishes no rating.
    public var ipRating: String?
    /// Max take-off altitude / service ceiling above sea level, metres.
    public var ceilingM: Double
    /// Short note on how the wind figure is stated, shown in the drone picker.
    public var note: String?
    /// Where the numbers came from.
    public var source: String?

    public init(id: String, maker: String, model: String, weightG: Double, maxWindMS: Double,
                tempMinC: Double, tempMaxC: Double, ipRating: String? = nil, ceilingM: Double,
                note: String? = nil, source: String? = nil) {
        self.id = id; self.maker = maker; self.model = model; self.weightG = weightG
        self.maxWindMS = maxWindMS; self.tempMinC = tempMinC; self.tempMaxC = tempMaxC
        self.ipRating = ipRating; self.ceilingM = ceilingM; self.note = note; self.source = source
    }

    public var name: String { maker == "Custom" ? model : "\(maker) \(model)" }
    public var isCustom: Bool { id.hasPrefix("custom") }

    /// Second IP digit ≥ 3 means protected against spraying water (rain), per IEC 60529.
    public var rainResistant: Bool {
        guard let ip = ipRating, ip.count == 4, let d = Int(String(ip.last!)) else { return false }
        return d >= 3
    }
    /// Under 250 g: no FAA registration needed for purely recreational flying.
    public var sub250: Bool { weightG < 250 }
}

public enum DroneCatalog {
    /// Specs taken from each manufacturer's published spec page (October 2026).
    public static let all: [Drone] = [
        // DJI consumer
        Drone(id: "dji-neo", maker: "DJI", model: "Neo", weightG: 135, maxWindMS: 8, tempMinC: -10, tempMaxC: 40, ceilingM: 2000,
              source: "dji.com/neo/specs"),
        Drone(id: "dji-flip", maker: "DJI", model: "Flip", weightG: 249, maxWindMS: 10.7, tempMinC: -10, tempMaxC: 40, ceilingM: 3000,
              source: "dji.com/flip/specs"),
        Drone(id: "dji-mini-3", maker: "DJI", model: "Mini 3", weightG: 248, maxWindMS: 10.7, tempMinC: -10, tempMaxC: 40, ceilingM: 4000,
              source: "dji.com/mini-3/specs"),
        Drone(id: "dji-mini-4-pro", maker: "DJI", model: "Mini 4 Pro", weightG: 249, maxWindMS: 10.7, tempMinC: -10, tempMaxC: 40, ceilingM: 4000,
              source: "dji.com/mini-4-pro/specs"),
        Drone(id: "dji-mini-5-pro", maker: "DJI", model: "Mini 5 Pro", weightG: 249.9, maxWindMS: 12, tempMinC: -10, tempMaxC: 40, ceilingM: 6000,
              note: "Published weight 249.9 g ± 4 g", source: "dji.com/mini-5-pro/specs"),
        Drone(id: "dji-avata-2", maker: "DJI", model: "Avata 2", weightG: 377, maxWindMS: 10.7, tempMinC: -10, tempMaxC: 40, ceilingM: 5000,
              source: "dji.com/avata-2/specs"),
        Drone(id: "dji-air-3", maker: "DJI", model: "Air 3", weightG: 720, maxWindMS: 12, tempMinC: -10, tempMaxC: 40, ceilingM: 6000,
              source: "dji.com/air-3/specs"),
        Drone(id: "dji-air-3s", maker: "DJI", model: "Air 3S", weightG: 724, maxWindMS: 12, tempMinC: -10, tempMaxC: 40, ceilingM: 6000,
              source: "dji.com/air-3s/specs"),
        Drone(id: "dji-mavic-3-classic", maker: "DJI", model: "Mavic 3 Classic", weightG: 895, maxWindMS: 12, tempMinC: -10, tempMaxC: 40, ceilingM: 6000,
              source: "dji.com/mavic-3-classic/specs"),
        Drone(id: "dji-mavic-3-pro", maker: "DJI", model: "Mavic 3 Pro", weightG: 958, maxWindMS: 12, tempMinC: -10, tempMaxC: 40, ceilingM: 6000,
              source: "dji.com/mavic-3-pro/specs"),
        Drone(id: "dji-inspire-3", maker: "DJI", model: "Inspire 3", weightG: 4310, maxWindMS: 12, tempMinC: -20, tempMaxC: 40, ceilingM: 3800,
              note: "12 m/s take-off and landing, 14 m/s in flight", source: "dji.com/inspire-3/specs"),
        // DJI enterprise
        Drone(id: "dji-mavic-3-enterprise", maker: "DJI", model: "Mavic 3 Enterprise / Thermal", weightG: 1050, maxWindMS: 12, tempMinC: -10, tempMaxC: 40, ceilingM: 6000,
              note: "Wind figure is for take-off and landing", source: "enterprise.dji.com/mavic-3-enterprise/specs"),
        Drone(id: "dji-matrice-4", maker: "DJI", model: "Matrice 4E / 4T", weightG: 1219, maxWindMS: 12, tempMinC: -10, tempMaxC: 40, ceilingM: 6000,
              note: "Wind figure is for take-off and landing", source: "enterprise.dji.com/matrice-4-series/specs"),
        Drone(id: "dji-matrice-30", maker: "DJI", model: "Matrice 30 / 30T", weightG: 4069, maxWindMS: 12, tempMinC: -20, tempMaxC: 50, ipRating: "IP55", ceilingM: 5000,
              source: "enterprise.dji.com/matrice-30/specs"),
        Drone(id: "dji-matrice-350", maker: "DJI", model: "Matrice 350 RTK", weightG: 9200, maxWindMS: 12, tempMinC: -20, tempMaxC: 50, ipRating: "IP55", ceilingM: 5000,
              source: "enterprise.dji.com/matrice-350-rtk/specs"),
        Drone(id: "dji-matrice-400", maker: "DJI", model: "Matrice 400", weightG: 9740, maxWindMS: 12, tempMinC: -20, tempMaxC: 50, ipRating: "IP55", ceilingM: 7000,
              note: "Wind figure is for take-off and landing", source: "enterprise.dji.com/matrice-400/specs"),
        // Others
        Drone(id: "autel-evo-lite-plus", maker: "Autel", model: "EVO Lite+", weightG: 820, maxWindMS: 13.9, tempMinC: -10, tempMaxC: 40, ceilingM: 5000,
              note: "Autel lists \"Level 7\"; using that level's lower bound (13.9 m/s)", source: "Autel via Dronefly spec listing"),
        Drone(id: "autel-evo-max-4t", maker: "Autel", model: "EVO Max 4T", weightG: 1999, maxWindMS: 12, tempMinC: -20, tempMaxC: 50, ipRating: "IP43", ceilingM: 4000,
              note: "Wind figure is for take-off and landing", source: "auteldrones.com/products/evo-max-4t"),
        Drone(id: "skydio-x10", maker: "Skydio", model: "X10", weightG: 2490, maxWindMS: 12.8, tempMinC: -20, tempMaxC: 45, ipRating: "IP55", ceilingM: 4572,
              note: "Skydio publishes gust handling (12.8 m/s), not sustained wind", source: "skydio.com/x10/technical-specs"),
        Drone(id: "parrot-anafi-usa", maker: "Parrot", model: "ANAFI USA", weightG: 500, maxWindMS: 14.7, tempMinC: -36, tempMaxC: 50, ipRating: "IP53", ceilingM: 5000,
              source: "parrot.com/en/drones/anafi-usa/technical-specifications"),
    ]

    /// Starting point for a custom drone: a mid-size quad with no weather rating.
    /// Maximum payload (kg) by altitude (m), from the maker's manual, for aircraft that publish one.
    /// Read at density altitude: the altitude the propellers actually feel.
    public static let payloadByAltitude: [String: [(altM: Double, kg: Double)]] = [
        // DJI Matrice 400 user manual: max payload vs flight altitude
        "dji-matrice-400": [(1000, 6), (2000, 5), (3000, 4.3), (4000, 3.5), (5000, 2.5), (6000, 1.6), (7000, 1.0)],
    ]
    public static func maxPayloadKg(droneID: String, densityAltitudeM m: Double) -> Double? {
        guard let t = payloadByAltitude[droneID], let first = t.first, let last = t.last else { return nil }
        if m <= first.altM { return first.kg }
        for i in 1..<t.count where m <= t[i].altM {
            let a = t[i - 1], b = t[i]
            return a.kg + (b.kg - a.kg) * (m - a.altM) / (b.altM - a.altM)
        }
        return last.kg
    }

    public static let customTemplate = Drone(id: "custom", maker: "Custom", model: "My drone", weightG: 900, maxWindMS: 10,
                                             tempMinC: 0, tempMaxC: 40, ipRating: nil, ceilingM: 4000)

    public static func find(_ id: String) -> Drone? { all.first { $0.id == id } }

    public static var makers: [String] { Array(Set(all.map(\.maker))).sorted { a, b in
        // DJI first (most common), then alphabetical
        if a == "DJI" { return true }; if b == "DJI" { return false }; return a < b } }
}
