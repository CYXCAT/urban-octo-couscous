import Foundation
import Observation

@Observable
final class AppModel {
    var isBusy = false
    var isServerReady = false
    var statusMessage: String?
    var errorMessage: String?
    var phase: Phase = .signedOut
    var user: UserProfile?
    var api: APIClient?

    private var didStart = false
    enum Phase {
        case signedOut
        case signedIn
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
            errorMessage = error.errorDescription ?? "Google sign-in failed"
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
        statusMessage = "Connecting…"
        defer {
            isBusy = false
            if isServerReady {
                statusMessage = nil
            }
        }

        let client = APIClient(baseURL: AppConfig.apiBaseURL)
        guard await client.isHealthy() else {
            isServerReady = false
            statusMessage = nil
            errorMessage = "The service is temporarily unavailable. Please try again."
            return
        }

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
        errorMessage = "Session expired. Sign in again."
    }
}
