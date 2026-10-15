import SwiftUI

@main
struct AirFieldApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(.sun)
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active: model.becameActive()
            case .background: model.resignedActive()
            default: break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            if !model.accepted {
                DisclaimerView()
            } else if !model.onboarded {
                OnboardingView()
            } else {
                DashboardView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.accepted)
        .animation(.easeInOut(duration: 0.25), value: model.onboarded)
    }
}
