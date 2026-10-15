import Foundation

/// Leave empty: AirField uses free public sources (National Weather Service grid, airport METARs, MET Norway).
/// Optional upgrade: paste a commercial Open-Meteo key to switch to model irradiance and 120 m wind.
enum Secrets {
    static let openMeteoKey = ""
}
