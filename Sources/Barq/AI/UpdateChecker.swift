import Foundation

/// Semantic-ish version comparison for update checks. Pure — unit tested.
enum AppVersion {
    static func components(_ s: String) -> [Int] {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// True if `a` is a strictly newer version than `b`.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = components(a), y = components(b)
        for i in 0..<max(x.count, y.count) {
            let xi = i < x.count ? x[i] : 0
            let yi = i < y.count ? y[i] : 0
            if xi != yi { return xi > yi }
        }
        return false
    }
}

/// Checks GitHub Releases for a newer Barq and surfaces a download link.
/// No dependency, no signing required — works for unsigned public releases.
enum UpdateChecker {
    static let repo = "awaistechnologist/barq-term"

    struct Release: Equatable {
        let version: String
        let url: String   // .dmg asset if present, else the release page
    }

    static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// The latest published release, or nil on any error / no releases.
    static func latest() async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        // Prefer a .dmg asset; fall back to the release page.
        var link = json["html_url"] as? String ?? "https://github.com/\(repo)/releases/latest"
        if let assets = json["assets"] as? [[String: Any]],
           let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
           let dl = dmg["browser_download_url"] as? String {
            link = dl
        }
        return Release(version: tag, url: link)
    }

    /// Returns a release only if it's newer than what's running.
    static func availableUpdate() async -> Release? {
        guard let latest = await latest(),
              AppVersion.isNewer(latest.version, than: currentVersion()) else { return nil }
        return latest
    }
}
