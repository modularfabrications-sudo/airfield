import Foundation
import CoreLocation
import CoreMotion
import MapKit
import UIKit

/// Wraps CoreLocation: permission, position while the app is open, and compass heading for the sky dial.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    @Published private(set) var location: CLLocation?
    /// True-north heading in degrees (falls back to magnetic when true isn't available).
    @Published private(set) var heading: Double?
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private let motion = CMMotionManager()
    /// True minus magnetic north here, from Core Location (0 until it knows).
    private var declination = 0.0
    private var motionHeading = false

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.headingFilter = 0.5
        manager.headingOrientation = .portrait
    }

    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isDenied: Bool { status == .denied || status == .restricted }

    var isUndecided: Bool { status == .notDetermined }

    func requestPermission() { if status == .notDetermined { manager.requestWhenInUseAuthorization() } }

    /// Starts updates. Uses the system's last known
    /// position right away when it's recent, so the first forecast doesn't wait on GPS.
    func start() {
        guard isAuthorized else { return }
        if location == nil, let last = manager.location, last.horizontalAccuracy >= 0,
           Date().timeIntervalSince(last.timestamp) < 1800 { location = last }
        manager.startUpdatingLocation()
    }
    func stop() { manager.stopUpdatingLocation(); stopHeading() }

    /// Compass for the sky dial: where the BACK of the phone faces when you hold it up, or the top edge when it lies flat.
    /// The heading comes from iOS's own fused attitude (gyro + accelerometer + magnetometer, true north), the same
    /// sensor fusion behind Apple's Compass and Safari, so it matches them; the gyro keeps it steady as you tilt.
    /// Core Location's heading is the fallback, and the reference used to check the fused one.
    func startHeading() {
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        refFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical
                 : frames.contains(.xMagneticNorthZVertical) ? .xMagneticNorthZVertical : nil
        guard let f = refFrame else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: f, to: .main) { [weak self] dm, _ in
            if let dm { self?.motionFix(dm) }
        }
    }
    func stopHeading() {
        manager.stopUpdatingHeading(); motion.stopDeviceMotionUpdates()
        heading = nil; motionHeading = false; systemHeading = nil
    }

    private var refFrame: CMAttitudeReferenceFrame?
    /// Core Location's latest true heading (top edge), for checking the fused one while the phone is flat.
    private var systemHeading: Double?
    /// Whether the attitude matrix's columns (true) or rows (false) hold the north/up axes in phone coordinates.
    /// Settled the first time the phone lies flat and Core Location can say which reading is right.
    private var useColumns: Bool?

    private typealias V3 = (Double, Double, Double)
    private static func dot(_ a: V3, _ b: V3) -> Double { a.0 * b.0 + a.1 * b.1 + a.2 * b.2 }
    private static func cross(_ a: V3, _ b: V3) -> V3 { (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0) }
    private static func norm(_ a: V3) -> V3? { let l = dot(a, a).squareRoot(); return l > 1e-6 ? (a.0 / l, a.1 / l, a.2 / l) : nil }
    private static func angleGap(_ a: Double, _ b: Double) -> Double { abs((a - b + 540).truncatingRemainder(dividingBy: 360) - 180) }

    /// Heading of "facing" (top edge + back of the phone) for one reading of the attitude's north axis.
    private static func facingHeading(north raw: V3, up: V3) -> Double? {
        let k = dot(raw, up)
        guard let n = norm((raw.0 - k * up.0, raw.1 - k * up.1, raw.2 - k * up.2)) else { return nil }
        let e = cross(n, up)                                  // north × up = east
        let f: V3 = (0, 1, -1)                                // phone axes: y = top edge, −z = out the back
        return atan2(dot(f, e), dot(f, n)) * 180 / .pi
    }

    private func motionFix(_ dm: CMDeviceMotion) {
        guard dm.magneticField.accuracy != .uncalibrated, let up = Self.norm((-dm.gravity.x, -dm.gravity.y, -dm.gravity.z)) else {
            motionHeading = false; return
        }
        let m = dm.attitude.rotationMatrix
        guard let hc = Self.facingHeading(north: (m.m11, m.m21, m.m31), up: up),
              let hr = Self.facingHeading(north: (m.m11, m.m12, m.m13), up: up) else { return }
        let offset = refFrame == .xTrueNorthZVertical ? 0 : declination
        if useColumns == nil {
            // Tilted: the matrix's vertical axis must line up with gravity, which tells columns from rows directly.
            let colZ = abs(Self.dot((m.m13, m.m23, m.m33), up)), rowZ = abs(Self.dot((m.m31, m.m32, m.m33), up))
            if colZ > 0.95 && rowZ < 0.8 { useColumns = true } else if rowZ > 0.95 && colZ < 0.8 { useColumns = false }
        }
        if useColumns == nil {
            // Flat on a hand or table, Core Location's heading is trustworthy: keep whichever reading agrees with it.
            if abs(up.2) > 0.85, let sys = systemHeading, Self.angleGap(hc + offset, hr + offset) > 30 {
                if Self.angleGap(hc + offset, sys) < 20 { useColumns = true }
                else if Self.angleGap(hr + offset, sys) < 20 { useColumns = false }
            }
            guard let _ = useColumns else { motionHeading = false; return }   // until then, Core Location drives it
        }
        motionHeading = true
        publish((useColumns! ? hc : hr) + offset, smoothing: 0.25)
    }

    /// Smooth toward a new heading, taking the short way round through north.
    private func publish(_ raw: Double, smoothing k: Double) {
        let target = (raw.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        guard let prev = heading else { heading = target; return }
        var d = target - prev
        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        if abs(d) > 0.25 { heading = (prev + d * k + 360).truncatingRemainder(dividingBy: 360) }
    }

    /// Opens this app's page in the iPhone Settings app (Location lives there).
    static func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        status = m.authorizationStatus
        if isAuthorized { start() }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last, l.horizontalAccuracy >= 0 else { return }
        // A rough first fix (cell / Wi-Fi) is fine for weather; after that, keep only decent ones.
        if location != nil && l.horizontalAccuracy > 3000 { return }
        location = l; lastError = nil
    }
    func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        guard h.headingAccuracy >= 0 else { return }
        if h.trueHeading >= 0 {
            var d = h.trueHeading - h.magneticHeading
            if d > 180 { d -= 360 } else if d < -180 { d += 360 }
            declination = d
        }
        let sys = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        systemHeading = sys
        // Drives the dial until the fused heading is ready, or whenever the motion sensors aren't calibrated.
        if !motionHeading { publish(sys, smoothing: 0.35) }
    }
    func locationManagerShouldDisplayHeadingCalibration(_ m: CLLocationManager) -> Bool { true }
    func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {
        switch (e as? CLError)?.code {
        case .locationUnknown?: lastError = "No GPS fix yet"
        case .denied?: lastError = "Location is off"
        default: lastError = e.localizedDescription
        }
    }

    // MARK: names

    static func placeName(for loc: CLLocation) async -> String? {
        // ~10 m is plenty to name a place; don't hand out more precision than needed
        let r = { (x: Double) in (x * 10_000).rounded() / 10_000 }
        let coarse = CLLocation(latitude: r(loc.coordinate.latitude), longitude: r(loc.coordinate.longitude))
        guard let p = try? await CLGeocoder().reverseGeocodeLocation(coarse).first else { return nil }
        return p.locality ?? p.subLocality ?? p.subAdministrativeArea ?? p.name
    }
}

/// Address and place search for the search bar.
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.count < 2 { results = []; return }
        completer.queryFragment = q
    }

    func completerDidUpdateResults(_ c: MKLocalSearchCompleter) { results = Array(c.results.prefix(8)) }
    func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) { results = [] }

    static func resolve(_ c: MKLocalSearchCompletion) async -> SavedPlace? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start().mapItems.first else { return nil }
        let co = item.placemark.coordinate
        return SavedPlace(lat: co.latitude, lon: co.longitude, name: c.title)
    }

    /// "39.38, -104.86" or "39.38 -104.86"
    static func coordinates(_ text: String) -> SavedPlace? {
        let parts = text.replacingOccurrences(of: ",", with: " ").split(separator: " ").compactMap { Double($0) }
        guard parts.count == 2, abs(parts[0]) <= 90, abs(parts[1]) <= 180 else { return nil }
        return SavedPlace(lat: parts[0], lon: parts[1], name: String(format: "%.4f, %.4f", parts[0], parts[1]))
    }
}

struct SavedPlace: Codable, Equatable, Identifiable, Hashable {
    var id: String { String(format: "%.5f,%.5f", lat, lon) }
    var lat: Double
    var lon: Double
    var name: String
}
