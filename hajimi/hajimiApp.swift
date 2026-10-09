import SwiftUI

@main
struct hajimiApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .task { await appModel.bootstrap() }
                .onOpenURL { url in
                    GoogleAuth.handle(url)
                }
        }
    }
}
