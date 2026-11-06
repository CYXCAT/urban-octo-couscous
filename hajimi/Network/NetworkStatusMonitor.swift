import Foundation
import Network
import Observation

/// Tracks two things: whether the device has a network path (Wi-Fi / cellular / none),
/// and whether the hajimi server answers /health (with latency).
@Observable
final class NetworkStatusMonitor {
    enum Interface: Equatable {
        case wifi, cellular, wired, other, none

        var label: String {
            switch self {
            case .wifi: "Wi-Fi"
            case .cellular: "Cellular"
            case .wired: "Ethernet"
            case .other: "Network"
            case .none: "No network"
            }
        }

        var symbol: String {
            switch self {
            case .wifi: "wifi"
            case .cellular: "antenna.radiowaves.left.and.right"
            case .wired: "cable.connector"
            case .other: "network"
            case .none: "wifi.slash"
            }
        }
    }

    enum ServerState: Equatable {
        case checking
        case online(latency: Duration)
        case unreachable
    }

    enum Overall {
        case good, degraded, offline, checking
    }

    private(set) var interface: Interface = .other
    private(set) var isConstrained = false
    private(set) var isExpensive = false
    private(set) var server: ServerState = .checking
    private(set) var lastChecked: Date?

    private let client: APIClient
    private let checkInterval: Duration
    private var pathTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    init(baseURL: URL = AppConfig.apiBaseURL, checkInterval: Duration = .seconds(30)) {
        client = APIClient(baseURL: baseURL)
        self.checkInterval = checkInterval
    }

    var overall: Overall {
        if interface == .none { return .offline }
        switch server {
        case .checking: return .checking
        case .unreachable: return .offline
        case .online(let latency): return latency > .milliseconds(1500) ? .degraded : .good
        }
    }

    var latencyText: String? {
        guard case .online(let latency) = server else { return nil }
        let ms = latency.components.seconds * 1000 + latency.components.attoseconds / 1_000_000_000_000_000
        return "\(ms) ms"
    }

    var summary: String {
        if interface == .none { return "No network" }
        switch server {
        case .checking: return "Checking…"
        case .unreachable: return "\(interface.label) · Server unreachable"
        case .online: return "\(interface.label) · \(latencyText ?? "")"
        }
    }

    func start() {
        guard pathTask == nil else { return }
        pathTask = Task { [weak self] in
            for await path in NWPathMonitor() {
                guard let self else { return }
                let previous = self.interface
                self.apply(path)
                if previous != self.interface {
                    await self.checkServer()
                }
            }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkServer()
                guard let interval = self?.checkInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pathTask?.cancel()
        pollTask?.cancel()
        pathTask = nil
        pollTask = nil
    }

    func checkServer() async {
        guard interface != .none else {
            server = .unreachable
            lastChecked = .now
            return
        }
        if case .unreachable = server { server = .checking }
        if let latency = await client.ping(timeout: 8) {
            server = .online(latency: latency)
        } else {
            server = .unreachable
        }
        lastChecked = .now
    }

    private func apply(_ path: NWPath) {
        isConstrained = path.isConstrained
        isExpensive = path.isExpensive
        guard path.status == .satisfied else {
            interface = .none
            server = .unreachable
            return
        }
        if path.usesInterfaceType(.wifi) {
            interface = .wifi
        } else if path.usesInterfaceType(.cellular) {
            interface = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = .wired
        } else {
            interface = .other
        }
    }
}
