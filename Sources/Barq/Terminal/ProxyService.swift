import Foundation
import AppKit

/// Launches Chrome through a profile's first enabled dynamic SOCKS5 rule.
enum ProxyService {

    static func firstDynamicRule(_ profile: ConnectionProfile) -> PortForward? {
        profile.portForwards.first { $0.kind == .dynamic && $0.enabled }
    }

    static func canLaunchChrome(_ profile: ConnectionProfile) -> Bool {
        FileManager.default.fileExists(atPath: ChromeProxyLauncher.chromePath) && firstDynamicRule(profile) != nil
    }

    @discardableResult
    static func launchChrome(for profile: ConnectionProfile) -> Bool {
        guard let rule = firstDynamicRule(profile) else { return false }
        let profileDir = AppPaths.supportDirectory
            .appendingPathComponent("chrome-\(profile.id.uuidString)", isDirectory: true).path
        try? FileManager.default.createDirectory(atPath: profileDir, withIntermediateDirectories: true)

        var pacPath: String?
        if rule.filterMode == .include {
            let pac = ChromeProxyLauncher.pacScript(port: rule.listenPort, hosts: rule.filterHosts)
            let url = AppPaths.supportDirectory.appendingPathComponent("pac-\(profile.id.uuidString).pac")
            try? pac.write(to: url, atomically: true, encoding: .utf8)
            pacPath = url.path
        }

        let args = ChromeProxyLauncher.arguments(
            port: rule.listenPort, mode: rule.filterMode, hosts: rule.filterHosts,
            pacPath: pacPath, profileDir: profileDir
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ChromeProxyLauncher.chromePath)
        process.arguments = args
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
