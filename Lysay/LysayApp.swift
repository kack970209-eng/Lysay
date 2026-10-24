import SwiftUI

@main
struct LysayApp: App {
    @StateObject private var coordinator = AppCoordinator.shared
    @StateObject private var engine = SpeechEngine.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var account = AccountManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(coordinator)
                .environmentObject(engine)
                .environmentObject(settings)
                .environmentObject(account)
                .tint(Color.lysay)
                .onOpenURL { coordinator.handle(url: $0) }
                .fullScreenCover(isPresented: $coordinator.showDictationGuide) {
                    DictationGuideView()
                        .environmentObject(coordinator)
                        .environmentObject(engine)
                        .environmentObject(settings)
                }
                .sheet(isPresented: $coordinator.showAccount) {
                    ProUpgradeView()
                        .environmentObject(account)
                        .environmentObject(coordinator)
                }
                .onAppear {
                    coordinator.boot()
                    _ = StoreManager.shared   // 开始监听订阅续订
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { coordinator.becameActive() }
            if phase == .background { coordinator.enteredBackground() }
        }
    }
}
