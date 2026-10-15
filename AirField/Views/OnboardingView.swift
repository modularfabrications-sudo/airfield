import SwiftUI
import CoreLocation

/// First launch: what this is and what it isn't.
struct DisclaimerView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // The logo carries the name, so it leads the screen on its own: full width, centred.
                AppMark()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                Text("Flight conditions for drone pilots.")
                    .font(.title3).foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    Bullet("A planning aid, not an authorization. AirField doesn't grant LAANC or any FAA approval.")
                    Bullet("Forecasts can be wrong. Check conditions on site before every flight.")
                    Bullet("You are the pilot in command and responsible for flying safely and legally.")
                }
                .padding(16)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("I understand") { model.accepted = true }.buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
    }
    struct Bullet: View {
        let text: String
        init(_ t: String) { text = t }
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Color.sun).frame(width: 6, height: 6).offset(y: -2)
                Text(text).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Set-up flow: activity → variant → drone → rules → location.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = 0
    @State private var activity: Activity?
    @State private var variant: ActivityVariant?
    @State private var drone: Drone?
    @State private var custom = DroneCatalog.customTemplate
    @State private var rules: PilotRules = .part107
    @State private var imperial = Locale.current.measurementSystem == .us

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case 0: ActivityPicker(selected: activity) { a in activity = a; rules = a.defaultRules; next() }
                case 1: VariantPicker(activity: activity ?? ActivityCatalog.all[0], selected: variant) { v in variant = v; next() }
                case 2: DronePicker(selected: drone) { d in
                    if d.isCustom { step = 3 } else { drone = d; step = 4 } }
                case 3: CustomDroneEditor(drone: $custom, imperial: imperial) { drone = custom; step = 4 }
                case 4: RulesStep(rules: $rules, imperial: $imperial) { next() }
                default: LocationStep { finish() }
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
        .animation(.easeInOut(duration: 0.22), value: step)
    }

    var header: some View {
        HStack {
            if step > 0 {
                Button { step = step == 4 && drone?.isCustom != true ? 2 : step - 1 } label: {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
            } else { Spacer().frame(width: 44, height: 44) }
            Spacer()
            HStack(spacing: 6) { ForEach(0..<5) { i in Capsule().fill(i <= min(step, 4) ? Color.ink : Color.line2).frame(width: i == min(step, 4) ? 18 : 6, height: 6) } }
                .accessibilityLabel("Step \(min(step, 4) + 1) of 6")
            Spacer()
            Spacer().frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .foregroundStyle(Color.ink)
    }

    func next() { step += 1 }
    func finish() {
        guard let v = variant, let d = drone else { step = 0; return }
        model.profile = FlightProfile(variantID: v.id, drone: d, rules: rules, imperial: imperial)
        model.followMe()
    }
}

// MARK: steps

struct StepTitle: View {
    let title: String, subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(Color.ink)
            Text(subtitle).foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 14)
    }
}

struct ActivityPicker: View {
    let selected: Activity?
    let pick: (Activity) -> Void
    var body: some View {
        ScrollView {
            StepTitle(title: "What do you fly for?", subtitle: "AirField shows the conditions that matter for it.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(ActivityCatalog.all) { a in
                    Button { pick(a) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: a.symbol).font(.title2).foregroundStyle(Color.sun)
                            Text(a.name).font(.headline).foregroundStyle(Color.ink)
                            Text(a.summary).font(.footnote).foregroundStyle(Color.ink3).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(14).frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected?.id == a.id ? Color.ink : Color.line, lineWidth: selected?.id == a.id ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
    }
}

struct VariantPicker: View {
    let activity: Activity
    let selected: ActivityVariant?
    let pick: (ActivityVariant) -> Void
    var body: some View {
        ScrollView {
            StepTitle(title: activity.name, subtitle: "Which kind?")
            VStack(spacing: 10) {
                ForEach(activity.variants) { v in
                    Button { pick(v) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(v.name).font(.headline).foregroundStyle(Color.ink)
                                Text(v.detail).font(.subheadline).foregroundStyle(Color.ink3).multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.ink3)
                        }
                        .padding(16)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected?.id == v.id ? Color.ink : Color.line, lineWidth: selected?.id == v.id ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct DronePicker: View {
    let selected: Drone?
    let pick: (Drone) -> Void
    @State private var query = ""
    var filtered: [Drone] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? DroneCatalog.all : DroneCatalog.all.filter { $0.name.lowercased().contains(q) }
    }
    var body: some View {
        ScrollView {
            StepTitle(title: "Your drone", subtitle: "We use the maker's published wind and temperature limits.")
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.ink3)
                    TextField("Search models", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(12).background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button { pick(DroneCatalog.customTemplate) } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(Color.sun)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom or other drone").font(.headline).foregroundStyle(Color.ink)
                            Text("Set the wind and temperature limits yourself").font(.footnote).foregroundStyle(Color.ink3)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(Color.ink3)
                    }
                    .padding(14).background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                ForEach(DroneCatalog.makers, id: \.self) { maker in
                    let list = filtered.filter { $0.maker == maker }
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(maker).font(.footnote.weight(.semibold)).foregroundStyle(Color.ink3).padding(.horizontal, 14).padding(.vertical, 8)
                            ForEach(list) { d in
                                Button { pick(d) } label: { DroneRow(drone: d, selected: selected?.id == d.id) }.buttonStyle(.plain)
                                if d.id != list.last?.id { Divider().background(Color.line).padding(.leading, 14) }
                            }
                        }
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
    }
}

struct DroneRow: View {
    let drone: Drone
    var selected = false
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(drone.model).foregroundStyle(Color.ink)
                Text(specLine).font(.caption).foregroundStyle(Color.ink3)
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.sun) }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
    var specLine: String {
        let mph = Int((drone.maxWindMS * 2.236936).rounded())
        var parts = ["Wind \(mph) mph", "\(Int((drone.tempMinC * 9 / 5 + 32).rounded()))–\(Int((drone.tempMaxC * 9 / 5 + 32).rounded()))°F"]
        if let ip = drone.ipRating { parts.append(ip) }
        if drone.sub250 { parts.append("under 250 g") }
        return parts.joined(separator: " · ")
    }
}

struct CustomDroneEditor: View {
    @Binding var drone: Drone
    let imperial: Bool
    let done: () -> Void
    @State private var sealed = false

    var body: some View {
        ScrollView {
            StepTitle(title: "Custom drone", subtitle: "Use the numbers from your drone's spec sheet.")
            VStack(spacing: 12) {
                field("Name") { TextField("My drone", text: $drone.model).multilineTextAlignment(.trailing) }
                stepper("Max wind resistance", value: Binding(get: { speed(drone.maxWindMS) }, set: { drone.maxWindMS = fromSpeed($0) }),
                        range: imperial ? 10...45 : 4...20, unit: imperial ? "mph" : "m/s")
                stepper("Lowest operating temp", value: Binding(get: { temp(drone.tempMinC) }, set: { drone.tempMinC = fromTemp($0) }),
                        range: imperial ? -40...50 : -40...10, unit: imperial ? "°F" : "°C")
                stepper("Highest operating temp", value: Binding(get: { temp(drone.tempMaxC) }, set: { drone.tempMaxC = fromTemp($0) }),
                        range: imperial ? 60...130 : 15...55, unit: imperial ? "°F" : "°C")
                stepper("Take-off weight", value: $drone.weightG, range: 50...25000, unit: "g", step: 10)
                field("Rain resistant (IP rating)") { Toggle("", isOn: $sealed).labelsHidden() }
                Text("Only turn this on if the maker publishes an IP rating with a second digit of 3 or more (IP43, IP54, IP55…).")
                    .font(.footnote).foregroundStyle(Color.ink3).frame(maxWidth: .infinity, alignment: .leading)
                Button("Use this drone") {
                    drone.ipRating = sealed ? "IPX4" : nil
                    drone.id = "custom-\(UUID().uuidString.prefix(8))"
                    if drone.model.trimmingCharacters(in: .whitespaces).isEmpty { drone.model = "My drone" }
                    done()
                }
                .buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .onAppear { sealed = drone.rainResistant }
    }

    func speed(_ ms: Double) -> Double { (imperial ? ms * 2.236936 : ms).rounded() }
    func fromSpeed(_ v: Double) -> Double { imperial ? v / 2.236936 : v }
    func temp(_ c: Double) -> Double { (imperial ? c * 9 / 5 + 32 : c).rounded() }
    func fromTemp(_ v: Double) -> Double { imperial ? (v - 32) * 5 / 9 : v }

    func field<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack { Text(label).foregroundStyle(Color.ink); Spacer(); c() }
            .padding(14).background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    func stepper(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double = 1) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.ink)
            Spacer()
            Text("\(Int(value.wrappedValue)) \(unit)").font(.body.monospacedDigit()).foregroundStyle(Color.ink2)
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
        .padding(14).background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RulesStep: View {
    @Binding var rules: PilotRules
    @Binding var imperial: Bool
    let done: () -> Void
    var body: some View {
        ScrollView {
            StepTitle(title: "How you fly", subtitle: "This changes the visibility and airspace guidance.")
            VStack(spacing: 10) {
                choice(.part107, "Part 107", "Commercial work or any flight for business. Needs a Remote Pilot Certificate.")
                choice(.recreational, "Recreational", "Purely for fun, with the TRUST certificate and a community-based organization's guidelines.")
                HStack {
                    Text("Units").foregroundStyle(Color.ink)
                    Spacer()
                    Picker("Units", selection: $imperial) { Text("mph · °F · ft").tag(true); Text("m/s · °C · m").tag(false) }
                        .pickerStyle(.segmented).frame(width: 220)
                }
                .padding(14).background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 8)
                Button("Continue", action: done).buttonStyle(PrimaryButtonStyle()).padding(.top, 12)
            }
            .padding(.horizontal, 16)
        }
    }
    func choice(_ r: PilotRules, _ title: String, _ detail: String) -> some View {
        Button { rules = r } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: rules == r ? "largecircle.fill.circle" : "circle").foregroundStyle(rules == r ? Color.sun : Color.ink3).font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Color.ink)
                    Text(detail).font(.subheadline).foregroundStyle(Color.ink3).multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(16).background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(rules == r ? Color.ink : Color.line, lineWidth: rules == r ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct LocationStep: View {
    @EnvironmentObject var model: AppModel
    let done: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            StepTitle(title: "Where you fly", subtitle: "AirField uses your location to show the conditions and airspace right where you're standing. It never leaves your phone except to look up the forecast for that spot.")
            Spacer()
            Image(systemName: "location.circle.fill").font(.system(size: 88)).foregroundStyle(Color.sun)
            Spacer()
            VStack(spacing: 10) {
                if model.location.isDenied {
                    Text("Location is turned off for AirField. Turn it on in Settings, or search any place from the top of the app.")
                        .font(.subheadline).foregroundStyle(Color.ink2).multilineTextAlignment(.center).padding(.bottom, 4)
                    Button("Open iPhone Settings") { LocationService.openAppSettings() }.buttonStyle(PrimaryButtonStyle())
                    Button("Continue without location", action: done).buttonStyle(SecondaryButtonStyle())
                } else if model.location.isAuthorized {
                    Button("Continue", action: done).buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Allow location") { model.location.requestPermission() }.buttonStyle(PrimaryButtonStyle())
                    Button("Not now", action: done).buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .onChange(of: model.location.status) { _, s in
            if s == .authorizedWhenInUse || s == .authorizedAlways { done() }
        }
    }
}
