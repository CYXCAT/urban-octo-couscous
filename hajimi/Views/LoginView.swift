import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(NetworkStatusMonitor.self) private var networkMonitor

    var body: some View {
        @Bindable var appModel = appModel
        VStack(spacing: 28) {
            NetworkStatusView()
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("hajimi")
                    .font(.largeTitle.bold())
                Text("Sign in to chat with a model")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let statusMessage = appModel.statusMessage {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = appModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await appModel.signIn() }
            } label: {
                if appModel.isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign in with Google")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appModel.isBusy)
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: networkMonitor.server) { _, server in
            // Server came back after a failed launch: reconnect automatically.
            if case .online = server, !appModel.isServerReady, !appModel.isBusy {
                Task { await appModel.reconnect() }
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AppModel())
        .environment(NetworkStatusMonitor())
}
