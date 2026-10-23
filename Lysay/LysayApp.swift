import SwiftUI

@main
struct LysayApp: App {
    @StateObject private var coordinator = AppCoordinator.shared
    @StateObject private var engine = SpeechEngine.shared
    @StateObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(coordinator)
                .environmentObject(engine)
                .environmentObject(settings)
                .tint(Color.lysay)
                .onOpenURL { coordinator.handle(url: $0) }
                .fullScreenCover(isPresented: $coordinator.showDictationGuide) {
                    DictationGuideView()
                        .environmentObject(coordinator)
                        .environmentObject(engine)
                        .environmentObject(settings)
                }
                .onAppear { coordinator.boot() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { coordinator.becameActive() }
            if phase == .background { coordinator.enteredBackground() }
        }
    }
}
