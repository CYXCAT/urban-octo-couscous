import SwiftUI

@main
struct hajimiApp: App {
    @State private var appModel = AppModel()
    @State private var networkMonitor = NetworkStatusMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(networkMonitor)
                .task {
                    networkMonitor.start()
                    await appModel.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        networkMonitor.start()
                        Task { await networkMonitor.checkServer() }
                    } else if phase == .background {
                        networkMonitor.stop()
                    }
                }
                .onOpenURL { url in
                    GoogleAuth.handle(url)
                }
        }
    }
}
