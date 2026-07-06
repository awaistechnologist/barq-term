import Foundation

enum ProxyFilterMode: String, Codable, CaseIterable, Identifiable {
    case all      // route everything through the tunnel
    case include  // only listed hosts via tunnel (PAC)
    case exclude  // everything except listed hosts (bypass list)

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All traffic"
        case .include: return "Include only"
        case .exclude: return "Exclude"
        }
    }
}

/// Builds the argument vector and any PAC file for launching Chrome through a
/// SOCKS5 dynamic port-forward. Pure logic — unit tested; the actual launch is
/// a thin wrapper.
enum ChromeProxyLauncher {
    static let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    /// Chrome arguments for a SOCKS5 proxy on `127.0.0.1:port`.
    /// - mode .all: `--proxy-server`
    /// - mode .exclude: `--proxy-server` + `--proxy-bypass-list`
    /// - mode .include: `--proxy-pac-url=file://<pacPath>` (caller writes the PAC)
    static func arguments(port: Int, mode: ProxyFilterMode, hosts: [String], pacPath: String?, profileDir: String) -> [String] {
        var args = [
            "--user-data-dir=\(profileDir)",
            "--no-first-run",
            "--no-default-browser-check"
        ]
        switch mode {
        case .all:
            args.append("--proxy-server=socks5://127.0.0.1:\(port)")
        case .exclude:
            args.append("--proxy-server=socks5://127.0.0.1:\(port)")
            let list = (hosts + ["<local>"]).joined(separator: ";")
            args.append("--proxy-bypass-list=\(list)")
        case .include:
            if let pacPath {
                args.append("--proxy-pac-url=file://\(pacPath)")
            }
        }
        return args
    }

    /// PAC script: listed hosts (exact, *.wildcard, or CIDR) go through the
    /// SOCKS proxy; everything else DIRECT.
    static func pacScript(port: Int, hosts: [String]) -> String {
        var conditions: [String] = []
        for host in hosts where !host.isEmpty {
            if host.contains("/") {
                let parts = host.split(separator: "/")
                if parts.count == 2, let bits = Int(parts[1]) {
                    let mask = cidrMask(bits)
                    conditions.append("isInNet(host, \"\(parts[0])\", \"\(mask)\")")
                }
            } else if host.hasPrefix("*.") {
                conditions.append("dnsDomainIs(host, \"\(host.dropFirst(1))\")")
            } else if host.contains("*") {
                conditions.append("shExpMatch(host, \"\(host)\")")
            } else {
                conditions.append("host == \"\(host)\"")
            }
        }
        let test = conditions.isEmpty ? "false" : conditions.joined(separator: " || ")
        return """
        function FindProxyForURL(url, host) {
            if (\(test)) {
                return "SOCKS5 127.0.0.1:\(port)";
            }
            return "DIRECT";
        }
        """
    }

    static func cidrMask(_ bits: Int) -> String {
        var mask = [0, 0, 0, 0]
        var remaining = max(0, min(32, bits))
        for i in 0..<4 {
            let take = min(8, remaining)
            mask[i] = take == 0 ? 0 : (0xFF << (8 - take)) & 0xFF
            remaining -= take
        }
        return mask.map(String.init).joined(separator: ".")
    }
}
