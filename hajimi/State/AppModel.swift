import Foundation
import Observation

@Observable
final class AppModel {
    var serverURLText: String
    var isBusy = false
    var isServerReady = false
    var statusMessage: String?
    var errorMessage: String?
    var phase: Phase = .signedOut
    var user: UserProfile?
    var api: APIClient?

    private var didStart = false
    private static let serverURLKey = "hajimi.serverURL"

    enum Phase {
        case signedOut
        case signedIn
    }

    init() {
        serverURLText = UserDefaults.standard.string(forKey: Self.serverURLKey)
            ?? AppConfig.defaultServerURL.absoluteString
    }

    func bootstrap() async {
        guard !didStart else { return }
        didStart = true
        await connect(restoreSession: true)
    }

    func reconnect() async {
        guard phase == .signedOut else { return }
        await connect(restoreSession: true)
    }

    func signIn() async {
        errorMessage = nil
        if !isServerReady {
            await connect(restoreSession: false)
            guard isServerReady else { return }
        }
        guard let api else { return }

        isBusy = true
        defer { isBusy = false }
        do {
            let idToken = try await GoogleAuth.idToken()
            let session = try await api.login(idToken: idToken)
            try KeychainStore.save(session.token)
            user = session.user
            phase = .signedIn
        } catch let error as AuthError {
            if case .cancelled = error { return }
            errorMessage = error.errorDescription ?? "Google 登录失败"
        } catch {
            errorMessage = describeRequestError(error)
        }
    }

    func signOut() async {
        await api?.logout()
        GoogleAuth.signOut()
        KeychainStore.clear()
        api?.token = nil
        user = nil
        phase = .signedOut
    }

    private func connect(restoreSession: Bool) async {
        errorMessage = nil
        isBusy = true
        statusMessage = "正在连接本机服务…"
        defer {
            isBusy = false
            if isServerReady {
                statusMessage = nil
            }
        }

        guard let preferred = ServerURL.parse(serverURLText) else {
            isServerReady = false
            statusMessage = nil
            errorMessage = "服务器地址无效"
            return
        }

        let found = await ServerLocator().resolve(preferred: preferred)
        guard let found else {
            isServerReady = false
            statusMessage = nil
            errorMessage = "没有找到本机服务。请先在电脑上运行 server，或填写局域网地址。"
            return
        }

        serverURLText = found.absoluteString
        UserDefaults.standard.set(found.absoluteString, forKey: Self.serverURLKey)
        let client = APIClient(baseURL: found)
        client.onUnauthorized = { [weak self] in
            self?.handleUnauthorized()
        }
        api = client
        isServerReady = true

        guard restoreSession, let saved = KeychainStore.load() else { return }
        client.token = saved
        do {
            user = try await client.currentUser()
            phase = .signedIn
        } catch {
            client.token = nil
            KeychainStore.clear()
            phase = .signedOut
        }
    }

    private func handleUnauthorized() {
        guard phase == .signedIn else { return }
        KeychainStore.clear()
        api?.token = nil
        user = nil
        phase = .signedOut
        errorMessage = "登录已过期，请重新登录"
    }
}
