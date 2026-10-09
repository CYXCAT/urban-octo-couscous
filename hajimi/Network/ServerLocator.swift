import Foundation
import Network

nonisolated struct ServerLocator {
    func resolve(preferred: URL?) async -> URL? {
        if let preferred, await Self.healthy(preferred) {
            return preferred
        }

        let local = AppConfig.defaultServerURL
        if !sameEndpoint(preferred, local), await Self.healthy(local) {
            return local
        }
        return await browse()
    }

    private static func healthy(_ url: URL) async -> Bool {
        var request = URLRequest(url: url.appending(path: "health"))
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func browse() async -> URL? {
        await withCheckedContinuation { continuation in
            let gate = BrowseGate(continuation)
            let browser = NWBrowser(for: .bonjour(type: AppConfig.bonjourType, domain: nil), using: .tcp)
            gate.hold(browser)
            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    gate.finish(nil)
                }
            }
            browser.browseResultsChangedHandler = { results, _ in
                let endpoints = results.map(\.endpoint)
                Task {
                    for endpoint in endpoints {
                        guard let url = await Self.connectURL(endpoint), await Self.healthy(url) else { continue }
                        gate.finish(url)
                        return
                    }
                }
            }
            browser.start(queue: .global())
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                gate.finish(nil)
            }
        }
    }

    private static func connectURL(_ endpoint: NWEndpoint) async -> URL? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let url = hostURL(connection.currentPath?.remoteEndpoint)
                    connection.cancel()
                    once.run { continuation.resume(returning: url) }
                case .failed, .cancelled:
                    once.run { continuation.resume(returning: nil) }
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                connection.cancel()
                once.run { continuation.resume(returning: nil) }
            }
        }
    }

    private static func hostURL(_ endpoint: NWEndpoint?) -> URL? {
        guard case let .hostPort(host, port) = endpoint else { return nil }
        let hostString: String
        switch host {
        case let .ipv4(address):
            hostString = "\(address)"
            if hostString.hasPrefix("169.254.") { return nil }
        case let .name(name, _):
            hostString = name
        default:
            return nil
        }
        return URL(string: "http://\(hostString):\(port.rawValue)")
    }

    private func sameEndpoint(_ lhs: URL?, _ rhs: URL) -> Bool {
        guard let lhs, let leftHost = lhs.host, let rightHost = rhs.host else { return false }
        let leftPort = lhs.port ?? (lhs.scheme == "https" ? 443 : 80)
        let rightPort = rhs.port ?? (rhs.scheme == "https" ? 443 : 80)
        return leftHost == rightHost && leftPort == rightPort
    }
}

nonisolated private final class BrowseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var browser: NWBrowser?
    private let continuation: CheckedContinuation<URL?, Never>

    init(_ continuation: CheckedContinuation<URL?, Never>) {
        self.continuation = continuation
    }

    func hold(_ browser: NWBrowser) {
        lock.lock()
        self.browser = browser
        lock.unlock()
    }

    func finish(_ url: URL?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let active = self.browser
        self.browser = nil
        lock.unlock()
        active?.cancel()
        continuation.resume(returning: url)
    }
}

nonisolated private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        body()
    }
}
