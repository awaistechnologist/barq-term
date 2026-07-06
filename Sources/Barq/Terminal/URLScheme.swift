import Foundation

/// Parses `barq://` deep links into an action. Pure — unit tested.
///
/// Supported forms:
///   barq://connect/<profileName>
///   barq://open?path=/some/dir
///   barq://ssh?host=h&user=u&port=22
enum BarqURL {
    enum Action: Equatable {
        case connectProfile(String)
        case openPath(String)
        case sshQuick(host: String, user: String?, port: Int?)
        case unknown
    }

    static func parse(_ url: URL) -> Action {
        guard url.scheme == "barq" else { return .unknown }
        let host = url.host
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }

        switch host {
        case "connect":
            let name = url.pathComponents.filter { $0 != "/" }.joined(separator: "/")
            return name.isEmpty ? .unknown : .connectProfile(name.removingPercentEncoding ?? name)
        case "open":
            guard let path = q("path"), !path.isEmpty else { return .unknown }
            return .openPath(path)
        case "ssh":
            guard let h = q("host"), !h.isEmpty else { return .unknown }
            return .sshQuick(host: h, user: q("user"), port: q("port").flatMap { Int($0) })
        default:
            return .unknown
        }
    }
}
