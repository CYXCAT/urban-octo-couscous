import Foundation

enum AppConfig {
    static let googleClientID = "107833156473-ckhr78k7vplu3rfgppn62825h6ipph7u.apps.googleusercontent.com"
    static let defaultServerURL = URL(string: "http://127.0.0.1:8787")!
    static let bonjourType = "_hajimi._tcp"
}

enum ServerURL {
    static func parse(_ text: String) -> URL? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") {
            raw = "http://\(raw)"
        }
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        components.scheme = scheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
