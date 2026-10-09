import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        switch appModel.phase {
        case .signedOut:
            LoginView()
        case .signedIn:
            SignedInView()
        }
    }
}

struct SignedInView: View {
    @Environment(AppModel.self) private var appModel
    @State private var store: SessionStore?

    var body: some View {
        Group {
            if let store {
                SessionSplitView(store: store)
            } else {
                ProgressView("正在打开对话")
            }
        }
        .task {
            guard store == nil, let api = appModel.api else { return }
            let created = SessionStore(api: api)
            store = created
            await created.reloadSessions()
        }
    }
}
