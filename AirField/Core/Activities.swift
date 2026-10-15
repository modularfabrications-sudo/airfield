import Foundation

/// Which FAA rule set the pilot flies under. Changes visibility and airspace wording.
public enum PilotRules: String, Codable, CaseIterable, Sendable {
    case part107, recreational
    public var title: String { self == .part107 ? "Part 107 (commercial)" : "Recreational (TRUST)" }
}

/// The cards the dashboard can show under "Right now". Each activity picks its own set and order.
public enum TileKind: String, Codable, CaseIterable, Sendable {
    case wind, windAloft, irradiance, sky, visibility, air, light, densityAltitude, gnss, smoke, uv, spray
}

/// Extra condition checks layered on the drone and regulatory limits.
public enum ActivityCheck: String, Codable, CaseIterable, Sendable {
    /// IEC TS 62446-3 solar thermography window: >600 W/m² on the panel plane, <2 okta cloud, wind <28 km/h.
    case solarWindow
    /// Building envelope / night thermal: contrast is best after dark.
    case prefersDark
    /// Needs daylight for photos.
    case needsDaylight
    /// Photogrammetry and multispectral: patchy cloud changes exposure between frames.
    case evenLight
    /// Video and photo: gusts make footage shaky well below the airframe limit.
    case smoothFootage
    /// RTK / mapping accuracy: geomagnetic activity degrades GNSS.
    case gnssSensitive
    /// Spray drift: typical label wind limits and calm-air inversion risk.
    case sprayDrift
}

/// The 48-hour chart panels an activity shows, top to bottom.
public enum ChartPanel: String, Codable, CaseIterable, Sendable { case irradiance, wind, sky, status }

public struct ActivityVariant: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let tiles: [TileKind]
    public let checks: Set<ActivityCheck>
    public let chart: [ChartPanel]
    /// True when the activity is about panels or a surface plane, so the tilt setting matters.
    public let usesPanelPlane: Bool
}

public struct Activity: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    /// SF Symbol name.
    public let symbol: String
    public let summary: String
    public let defaultRules: PilotRules
    public let variants: [ActivityVariant]
}

public enum ActivityCatalog {
    private static func v(_ id: String, _ name: String, _ detail: String, tiles: [TileKind], checks: Set<ActivityCheck> = [],
                          chart: [ChartPanel] = [.wind, .sky, .status], plane: Bool = false) -> ActivityVariant {
        ActivityVariant(id: id, name: name, detail: detail, tiles: tiles, checks: checks, chart: chart, usesPanelPlane: plane)
    }

    public static let all: [Activity] = [
        Activity(id: "recreational", name: "Recreational", symbol: "paperplane.fill",
                 summary: "Flying for fun under the recreational exception",
                 defaultRules: .recreational, variants: [
                    v("rec-casual", "Casual flying", "Camera drone for fun and travel",
                      tiles: [.wind, .sky, .visibility, .air, .light, .gnss]),
                    v("rec-fpv", "FPV freestyle", "Goggles, acro, proximity flying",
                      tiles: [.wind, .sky, .visibility, .air, .light]),
                    v("rec-learning", "Learning to fly", "New pilots: gentler wind thresholds",
                      tiles: [.wind, .sky, .visibility, .air, .light]),
                 ]),
        Activity(id: "photo", name: "Photo & video", symbol: "camera.fill",
                 summary: "Aerial photography and filming",
                 defaultRules: .part107, variants: [
                    v("photo-realestate", "Real estate", "Exteriors, lots and neighborhoods",
                      tiles: [.light, .wind, .sky, .visibility, .smoke, .air], checks: [.needsDaylight, .smoothFootage]),
                    v("photo-landscape", "Landscape & golden hour", "Sunrise, sunset and scenic work",
                      tiles: [.light, .sky, .wind, .smoke, .visibility, .air], checks: [.smoothFootage]),
                    v("photo-cinema", "Events & cinematic", "Video, tracking shots, productions",
                      tiles: [.wind, .light, .sky, .visibility, .air, .gnss], checks: [.smoothFootage]),
                 ]),
        Activity(id: "mapping", name: "Mapping & survey", symbol: "map.fill",
                 summary: "Photogrammetry, models and LiDAR",
                 defaultRules: .part107, variants: [
                    v("map-ortho", "Orthomosaic", "Nadir grids for maps and measurements",
                      tiles: [.wind, .windAloft, .sky, .light, .gnss, .air, .densityAltitude], checks: [.needsDaylight, .evenLight, .gnssSensitive]),
                    v("map-3d", "3D model", "Obliques and orbits for meshes",
                      tiles: [.wind, .windAloft, .sky, .light, .gnss, .air, .densityAltitude], checks: [.needsDaylight, .evenLight, .gnssSensitive]),
                    v("map-lidar", "LiDAR", "Point clouds; works without daylight",
                      tiles: [.wind, .windAloft, .gnss, .sky, .air, .densityAltitude], checks: [.gnssSensitive]),
                 ]),
        Activity(id: "thermal", name: "Thermal inspection", symbol: "thermometer.sun.fill",
                 summary: "Radiometric inspection work",
                 defaultRules: .part107, variants: [
                    v("thermal-solar", "Solar PV", "Hot cells, diodes and strings (IEC TS 62446-3 window)",
                      tiles: [.irradiance, .sky, .wind, .windAloft, .visibility, .air, .densityAltitude, .gnss, .light, .smoke],
                      checks: [.solarWindow],
                      chart: [.irradiance, .wind, .sky, .status], plane: true),
                    v("thermal-envelope", "Roofs & buildings", "Moisture, insulation and heat loss after dark",
                      tiles: [.wind, .sky, .air, .light, .visibility], checks: [.prefersDark]),
                    v("thermal-electrical", "Electrical & substations", "Hot connections and equipment",
                      tiles: [.wind, .windAloft, .sky, .air, .light, .gnss]),
                 ]),
        Activity(id: "inspection", name: "Infrastructure", symbol: "building.2.fill",
                 summary: "Visual inspection of structures",
                 defaultRules: .part107, variants: [
                    v("insp-tower", "Towers & telecom", "Close work up high around steel",
                      tiles: [.windAloft, .wind, .gnss, .sky, .visibility, .air], checks: [.needsDaylight, .gnssSensitive]),
                    v("insp-powerline", "Power lines", "Corridors and pole-top work",
                      tiles: [.wind, .windAloft, .sky, .visibility, .gnss, .air], checks: [.needsDaylight, .gnssSensitive]),
                    v("insp-bridge", "Bridges & structures", "Facades, decks and undersides",
                      tiles: [.wind, .windAloft, .light, .sky, .gnss, .air], checks: [.needsDaylight, .gnssSensitive]),
                 ]),
        Activity(id: "agriculture", name: "Agriculture", symbol: "leaf.fill",
                 summary: "Crop scouting and application",
                 defaultRules: .part107, variants: [
                    v("ag-scout", "Crop scouting", "RGB and multispectral health maps",
                      tiles: [.sky, .light, .wind, .irradiance, .gnss, .air], checks: [.needsDaylight, .evenLight, .gnssSensitive],
                      chart: [.irradiance, .wind, .sky, .status]),
                    v("ag-spray", "Spraying", "Drift-sensitive application work",
                      tiles: [.spray, .wind, .air, .sky, .gnss, .densityAltitude], checks: [.sprayDrift]),
                 ]),
        Activity(id: "safety", name: "Public safety", symbol: "light.beacon.max.fill",
                 summary: "Search, rescue and incident support",
                 defaultRules: .part107, variants: [
                    v("safety-sar", "Search & rescue", "Thermal search, day or night",
                      tiles: [.wind, .sky, .visibility, .air, .light, .gnss]),
                    v("safety-overwatch", "Incident overwatch", "Scene awareness and documentation",
                      tiles: [.wind, .windAloft, .sky, .visibility, .air, .light]),
                 ]),
    ]

    public static func activity(for variantID: String) -> Activity? { all.first { $0.variants.contains { $0.id == variantID } } }
    public static func variant(_ id: String) -> ActivityVariant? { all.lazy.flatMap(\.variants).first { $0.id == id } }
}
