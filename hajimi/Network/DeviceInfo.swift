import Foundation
import UIKit

/// Describes this device to the server so the connection monitor can show who is connected.
enum DeviceInfo {
    /// Hardware identifier such as "iPhone16,1". The server-side monitor maps it to a marketing name.
    static let modelIdentifier: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    static let osVersion: String = {
        let device = UIDevice.current
        return "\(device.systemName) \(device.systemVersion)"
    }()

    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()

    /// Random per-install ID so one device shows up as one row even when its IP changes.
    static let clientID: String = {
        let key = "hajimi.clientID"
        if let saved = UserDefaults.standard.string(forKey: key) {
            return saved
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }()

    static func apply(to request: inout URLRequest) {
        request.setValue(clientID, forHTTPHeaderField: "X-Client-ID")
        request.setValue(modelIdentifier, forHTTPHeaderField: "X-Device-Model")
        request.setValue(osVersion, forHTTPHeaderField: "X-OS-Version")
        request.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
    }
}
