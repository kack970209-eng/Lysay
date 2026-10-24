import SwiftUI

@main
struct LysayApp: App {
    @StateObject private var coordinator = AppCoordinator.shared
    @StateObject private var engine = SpeechEngine.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var account = AccountManager.shared
    @Environment(\.scenePhase) private var scenePhase

    /// App Store 截图用：以 -LysayDemo <画面> 启动
    private let demoMode = UserDefaults.standard.string(forKey: "LysayDemo")

    var body: some Scene {
        WindowGroup {
            if let demoMode {
                DemoView(mode: demoMode)
                    .environmentObject(coordinator)
                    .environmentObject(engine)
                    .environmentObject(settings)
                    .environmentObject(account)
                    .tint(Color.lysay)
            } else {
                mainView
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard demoMode == nil else { return }
            if phase == .active { coordinator.becameActive() }
            if phase == .background { coordinator.enteredBackground() }
        }
    }

    private var mainView: some View {
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
}
