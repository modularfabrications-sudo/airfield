import Foundation
import CoreLocation
import Combine
import SwiftUI

/// App state: the user's setup, where we're looking, and the latest briefing.
@MainActor
final class AppModel: ObservableObject {
    // setup
    @Published var accepted: Bool { didSet { UserDefaults.standard.set(accepted, forKey: "accepted") } }
    @Published var profile: FlightProfile? { didSet { saveProfile(); rebuild() } }
    @Published var savedPlaces: [SavedPlace] { didSet { save(savedPlaces, "savedPlaces") } }

    // where
    /// true = follow the phone's GPS; false = locked to `lockedPlace`.
    @Published private(set) var following: Bool { didSet { UserDefaults.standard.set(following, forKey: "following") } }
    @Published private(set) var lockedPlace: SavedPlace? { didSet { save(lockedPlace, "lockedPlace") } }
    @Published private(set) var placeName: String = ""

    // data
    @Published private(set) var site: SiteData?
    @Published private(set) var briefing: Briefing?
    @Published private(set) var loading = false
    @Published private(set) var offline = false
    @Published private(set) var lastFetch: Date?
    @Published var compassOn: Bool { didSet { UserDefaults.standard.set(compassOn, forKey: "compassOn"); compassOn ? location.startHeading() : location.stopHeading() } }

    let location = LocationService()
    private let service = WeatherService(config: DataConfig(openMeteoKey: Secrets.openMeteoKey))
    private var bag = Set<AnyCancellable>()
    private var fetchedFor: CLLocation?
    private var timer: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        accepted = d.bool(forKey: "accepted")
        profile = AppModel.load(FlightProfile.self, "profile")
        savedPlaces = AppModel.load([SavedPlace].self, "savedPlaces") ?? []
        following = d.object(forKey: "following") as? Bool ?? true
        lockedPlace = AppModel.load(SavedPlace.self, "lockedPlace")
        compassOn = d.bool(forKey: "compassOn")
        if !following, let p = lockedPlace { placeName = p.name }
        loadCache()

        // relay location changes into the UI, and refresh when we've moved more than 1 km
        // Relay permission and position changes to the UI. Heading is left out on purpose: the dial
        // watches it directly, so a compass tick redraws the dial, not the whole dashboard.
        location.$status.removeDuplicates().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        location.$location.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        location.$lastError.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        location.$location.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] loc in
            guard let self, self.following else { return }
            if self.fetchedFor == nil || loc.distance(from: self.fetchedFor!) > 1000 { Task { await self.refresh() } }
        }.store(in: &bag)
        if compassOn { location.startHeading() }
    }

    var onboarded: Bool { profile != nil }

    // MARK: lifecycle

    func becameActive() {
        if following && location.isUndecided { location.requestPermission() }
        location.start()
        if compassOn { location.startHeading() }   // the compass is switched off in the background
        if lastFetch == nil || Date().timeIntervalSince(lastFetch!) > 300 { Task { await refresh() } }
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)   // every 10 minutes
                await self?.refresh()
            }
        }
    }
    func resignedActive() { timer?.cancel(); location.stop() }

    // MARK: place

    func lock(to p: SavedPlace) {
        following = false; lockedPlace = p; placeName = p.name; site = nil; briefing = nil
        Task { await refresh() }
    }
    func followMe() {
        following = true; placeName = ""; site = nil; briefing = nil
        if location.isDenied { return }
        location.requestPermission(); location.start()
        Task { await refresh() }
    }
    func saveCurrentPlace(named name: String) {
        guard let s = site else { return }
        savedPlaces.append(SavedPlace(lat: s.lat, lon: s.lon, name: name.isEmpty ? placeName : name))
    }

    var target: (lat: Double, lon: Double)? {
        if !following, let p = lockedPlace { return (p.lat, p.lon) }
        if let l = location.location { return (l.coordinate.latitude, l.coordinate.longitude) }
        return nil
    }

    // MARK: data

    func refresh() async {
        guard let p = profile, let t = target, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let raw = try await service.fetch(lat: t.lat, lon: t.lon, tilt: p.panelTilt, facing: p.panelFacing)
            let s = try Parse.site(raw)
            site = s; offline = false; lastFetch = raw.fetchedAt
            if following, let l = location.location { fetchedFor = l }
            saveCache(raw)
            rebuild()
            if following {
                if let l = location.location, let n = await LocationService.placeName(for: l) { placeName = n }
            }
        } catch {
            offline = true
        }
    }

    func rebuild() {
        guard let s = site, let p = profile else { briefing = nil; return }
        briefing = BriefingBuilder.build(s, profile: p)
    }

    /// Panel plane changed: irradiance has to be re-fetched for the new tilt.
    func setPanel(tilt: Double, facing: Double) {
        guard var p = profile else { return }
        p.panelTilt = tilt.rounded(); p.panelFacing = facing
        profile = p
        Task { await refresh() }
    }

    // MARK: persistence

    private func saveProfile() { save(profile, "profile") }
    private func save<T: Encodable>(_ v: T?, _ key: String) {
        if let v, let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
    private static func load<T: Decodable>(_ t: T.Type, _ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("last-briefing.json") }
    private func saveCache(_ raw: RawBundle) { if let d = try? JSONEncoder().encode(raw) { try? d.write(to: cacheURL, options: .atomic) } }
    private func loadCache() {
        guard let d = try? Data(contentsOf: cacheURL), let raw = try? JSONDecoder().decode(RawBundle.self, from: d),
              Date().timeIntervalSince(raw.fetchedAt) < 6 * 3600, let s = try? Parse.site(raw) else { return }
        if !following, let p = lockedPlace, abs(p.lat - raw.lat) > 0.001 || abs(p.lon - raw.lon) > 0.001 { return }
        site = s; lastFetch = raw.fetchedAt
        rebuild()
    }

    func resetSetup() { profile = nil }
}
