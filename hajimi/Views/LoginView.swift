import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("hajimi")
                    .font(.largeTitle.bold())
                Text("登录后和模型对话")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("本机服务")
                    .font(.subheadline.weight(.semibold))
                TextField("http://127.0.0.1:8787", text: $appModel.serverURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await appModel.reconnect() } }
                Text("模拟器用 127.0.0.1。真机可留空等待自动发现，或填写电脑的局域网地址。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    Text("通过 Google 登录")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appModel.isBusy)

            Button("重新连接") {
                Task { await appModel.reconnect() }
            }
            .disabled(appModel.isBusy)
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoginView()
        .environment(AppModel())
}
