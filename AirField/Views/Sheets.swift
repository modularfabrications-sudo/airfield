import SwiftUI
import MapKit

/// Search a town, address, coordinates or saved site. Picking one locks the dashboard to it.
struct PlaceSearchSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = PlaceSearch()
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                if let c = PlaceSearch.coordinates(query) {
                    Button { pick(c) } label: { row(c.name, "Coordinates", "mappin") }
                }
                if query.isEmpty {
                    Section {
                        Button { model.followMe(); dismiss() } label: { row("My location", "Follow the phone's GPS", "location.fill") }
                        if model.location.isDenied {
                            Button { LocationService.openAppSettings() } label: { row("Turn on location", "Opens iPhone Settings", "gear") }
                        }
                    }
                    if !model.savedPlaces.isEmpty {
                        Section("Saved sites") {
                            ForEach(model.savedPlaces) { p in Button { pick(p) } label: { row(p.name, String(format: "%.4f, %.4f", p.lat, p.lon), "star.fill") } }
                                .onDelete { model.savedPlaces.remove(atOffsets: $0) }
                        }
                    }
                } else {
                    ForEach(search.results, id: \.self) { r in
                        Button {
                            Task { if let p = await PlaceSearch.resolve(r) { pick(p) } }
                        } label: { row(r.title, r.subtitle, "mappin.and.ellipse") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Town, address or lat, lon")
            .onChange(of: query) { _, q in search.update(q) }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    func pick(_ p: SavedPlace) { model.lock(to: p); dismiss() }

    func row(_ title: String, _ sub: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.sun).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Color.ink)
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(Color.ink3) }
            }
        }
        .listRowBackground(Color.surface)
    }
}

/// Panel tilt and facing for irradiance on the panel plane.
struct TiltSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tilt: Double = 30
    @State private var facing: Double = 180

    let presets: [(String, Double)] = [("Flat", 0), ("4/12 roof", 18), ("6/12 roof", 27), ("Default", 30), ("Steep", 40), ("Wall", 90)]
    let faces: [(String, Double)] = [("E", 90), ("SE", 135), ("S", 180), ("SW", 225), ("W", 270)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Panel tilt").font(.title2.weight(.bold)).foregroundStyle(Color.ink)
                Spacer()
                Button("Done") { apply(); dismiss() }.font(.headline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(tilt))°").font(.system(size: 44, weight: .medium, design: .monospaced)).foregroundStyle(Color.ink)
                Text("facing \(Units.compass(facing))").foregroundStyle(Color.ink2)
            }
            Slider(value: $tilt, in: 0...90, step: 1) { Text("Tilt") } minimumValueLabel: { Text("0°") } maximumValueLabel: { Text("90°") }
                .tint(.sun).foregroundStyle(Color.ink3)
            Text("Quick picks").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(presets.indices, id: \.self) { i in
                    let p = presets[i]
                    Button { tilt = p.1 } label: {
                        VStack(spacing: 2) { Text(p.0).font(.subheadline); Text("\(Int(p.1))°").font(.caption.monospaced()).opacity(0.7) }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(tilt == p.1 ? Color.black : Color.ink)
                            .background(tilt == p.1 ? Color.ink : Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            Text("Panels face").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink2)
            Picker("Panels face", selection: $facing) { ForEach(faces.indices, id: \.self) { i in Text(faces[i].0).tag(faces[i].1) } }.pickerStyle(.segmented)
            Text("Irradiance is recalculated for this plane, and the 600 W/m² thermal window updates with it. Match the array or roof you're inspecting.")
                .font(.footnote).foregroundStyle(Color.ink3)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.bg)
        .onAppear { tilt = model.profile?.panelTilt ?? 30; facing = model.profile?.panelFacing ?? 180 }
        .onDisappear { apply() }
    }

    func apply() {
        guard let p = model.profile, p.panelTilt != tilt || p.panelFacing != facing else { return }
        model.setPanel(tilt: tilt, facing: facing)
    }
}

struct SettingsView: View {
    static var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "1.0") (\(i?["CFBundleVersion"] as? String ?? "1"))"
    }
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var saveName = ""
    @State private var askName = false

    var body: some View {
        NavigationStack {
            List {
                if let p = model.profile {
                    Section("Your flying") {
                        NavigationLink { ActivitySettings() } label: { LabeledContent("Activity", value: p.variant.name) }
                        NavigationLink { DroneSettings() } label: { LabeledContent("Drone", value: p.drone.name) }
                        Picker("Rules", selection: binding(\.rules)) { ForEach(PilotRules.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Picker("Units", selection: binding(\.imperial)) { Text("mph · °F · ft").tag(true); Text("m/s · °C · m").tag(false) }
                    }
                    Section {
                        LabeledContent("Hold above", value: holdText(p))
                        Toggle("Use my own wind limit", isOn: Binding(get: { p.personalWindLimitMS != nil },
                                                                     set: { on in update { $0.personalWindLimitMS = on ? 0.85 * $0.drone.maxWindMS : nil } }))
                        if let w = p.personalWindLimitMS {
                            Stepper(value: Binding(get: { p.imperial ? w * 2.236936 : w }, set: { v in update { $0.personalWindLimitMS = p.imperial ? v / 2.236936 : v } }),
                                    in: p.imperial ? 5...40 : 2...18, step: 1) {
                                Text("Sustained wind limit: \(Int((p.imperial ? w * 2.236936 : w).rounded())) \(p.imperial ? "mph" : "m/s")")
                            }
                        }
                    } header: { Text("Wind") } footer: {
                        Text("By default AirField holds when gusts or wind at 400 ft pass your drone's published wind resistance (27 mph for the Matrice 400), or steady wind passes 85% of it (23 mph), and cautions when gusts run 13 mph or more above the wind.")
                    }
                    if p.variant.usesPanelPlane {
                        Section("Panels") { LabeledContent("Tilt and facing", value: "\(Int(p.panelTilt))° \(Units.compass(p.panelFacing))") }
                    }
                }
                Section("Sites") {
                    Button("Save this location") { saveName = model.placeName; askName = true }.disabled(model.site == nil)
                    ForEach(model.savedPlaces) { s in Text(s.name) }.onDelete { model.savedPlaces.remove(atOffsets: $0) }
                }
                Section("Location access") {
                    LabeledContent("Status", value: model.location.isAuthorized ? "On" : model.location.isDenied ? "Off" : "Not asked")
                    Button("Open iPhone Settings") { LocationService.openAppSettings() }
                }
                Section("About") {
                    Text("AirField is a planning aid. It doesn't authorize flights. Forecasts can be wrong; check conditions on site. You remain the pilot in command.")
                        .font(.footnote).foregroundStyle(Color.ink2)
                    Link("Support", destination: URL(string: Site.support)!)
                    Link("Privacy policy", destination: URL(string: Site.privacy)!)
                    Link("FAA LAANC", destination: URL(string: "https://www.faa.gov/uas/getting_started/laanc")!)
                    Link("Forecasts: National Weather Service", destination: URL(string: "https://www.weather.gov")!)
                    Link("Observations: aviationweather.gov METARs", destination: URL(string: "https://aviationweather.gov")!)
                    Link("Outside the US: MET Norway, CC BY 4.0", destination: URL(string: "https://api.met.no/doc/License")!)
                    if !Secrets.openMeteoKey.isEmpty {
                        Link("Weather data by Open-Meteo.com (CC BY 4.0)", destination: URL(string: "https://open-meteo.com")!)
                    }
                    Text("AirField \(Self.version)")
                        .font(.footnote).foregroundStyle(Color.ink3)
                    Button("Start setup again", role: .destructive) { model.resetSetup(); dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .alert("Name this site", isPresented: $askName) {
                TextField("Name", text: $saveName)
                Button("Save") { model.saveCurrentPlace(named: saveName) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    func holdText(_ p: FlightProfile) -> String {
        let L = WindLimits.derive(for: p), u = Units(imperial: p.imperial)
        return "wind \(u.speedText(L.sustainedHold)), gusts \(u.speedText(L.gustHold))"
    }
    func update(_ f: (inout FlightProfile) -> Void) { guard var p = model.profile else { return }; f(&p); model.profile = p }
    func binding<T>(_ kp: WritableKeyPath<FlightProfile, T>) -> Binding<T> {
        Binding(get: { model.profile![keyPath: kp] }, set: { v in update { $0[keyPath: kp] = v } })
    }
}

struct ActivitySettings: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            ForEach(ActivityCatalog.all) { a in
                Section(a.name) {
                    ForEach(a.variants) { v in
                        Button {
                            guard var p = model.profile else { return }
                            p.variantID = v.id; model.profile = p; dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) { Text(v.name).foregroundStyle(Color.ink); Text(v.detail).font(.caption).foregroundStyle(Color.ink3) }
                                Spacer()
                                if model.profile?.variantID == v.id { Image(systemName: "checkmark").foregroundStyle(Color.sun) }
                            }
                        }
                        .listRowBackground(Color.surface)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Color.bg).navigationTitle("Activity")
    }
}

struct DroneSettings: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var custom = DroneCatalog.customTemplate
    var body: some View {
        Group {
            if editing {
                CustomDroneEditor(drone: $custom, imperial: model.profile?.imperial ?? true) { set(custom) }
            } else {
                DronePicker(selected: model.profile?.drone) { d in
                    if d.isCustom { custom = model.profile?.drone.isCustom == true ? model.profile!.drone : d; editing = true } else { set(d) }
                }
            }
        }
        .background(Color.bg)
        .navigationTitle("Drone")
    }
    func set(_ d: Drone) { guard var p = model.profile else { return }; p.drone = d; model.profile = p; dismiss() }
}
