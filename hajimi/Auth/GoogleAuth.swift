import Foundation
import GoogleSignIn
import UIKit

enum AuthError: LocalizedError {
    case cancelled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return nil
        case .message(let text):
            return text
        }
    }
}

enum GoogleAuth {
    static func handle(_ url: URL) {
        GIDSignIn.sharedInstance.handle(url)
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    static func idToken() async throws -> String {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: AppConfig.googleClientID)
        guard let presenter = RootPresenter.viewController() else {
            throw AuthError.message("无法打开登录窗口")
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString, !token.isEmpty else {
                throw AuthError.message("Google 没有返回身份令牌")
            }
            return token
        } catch let error as AuthError {
            throw error
        } catch {
            if isCancelled(error) { throw AuthError.cancelled }
            throw AuthError.message("Google 登录失败：\(error.localizedDescription)")
        }
    }

    private static func isCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == kGIDSignInErrorDomain && nsError.code == GIDSignInError.canceled.rawValue
    }
}

private enum RootPresenter {
    static func viewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.compactMap(\.keyWindow).first ?? scenes.flatMap(\.windows).first
        return window?.rootViewController?.hajimiTopMost
    }
}

private extension UIViewController {
    var hajimiTopMost: UIViewController {
        if let presented = presentedViewController {
            return presented.hajimiTopMost
        }
        if let navigation = self as? UINavigationController, let visible = navigation.visibleViewController {
            return visible.hajimiTopMost
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.hajimiTopMost
        }
        return self
    }
}
