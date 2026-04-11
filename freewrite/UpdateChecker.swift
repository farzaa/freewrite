//
//  UpdateChecker.swift
//  freewrite
//
//  Checks GitHub Releases API for newer versions on app launch.
//

import SwiftUI

@Observable
final class UpdateChecker {

    var updateAvailable = false
    var latestVersion = ""
    var releaseURL: URL?

    private static let endpoint = "https://api.github.com/repos/farzaa/freewrite/releases/latest"
    private static let cooldown: TimeInterval = 3600 // 1 hour
    private static let lastCheckKey = "UpdateChecker.lastCheckTime"
    private static let dismissedKey = "UpdateChecker.dismissedVersion"

    private struct GitHubRelease: Codable {
        let tagName: String
        let htmlUrl: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
        }
    }

    func checkForUpdate() async {
        let now = Date().timeIntervalSince1970
        let lastCheck = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        if now - lastCheck < Self.cooldown { return }
        UserDefaults.standard.set(now, forKey: Self.lastCheckKey)

        do {
            guard let url = URL(string: Self.endpoint) else { return }
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remote = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            guard isNewer(remote, than: current) else { return }

            let dismissed = UserDefaults.standard.string(forKey: Self.dismissedKey)
            if dismissed == remote { return }

            await MainActor.run {
                latestVersion = remote
                releaseURL = URL(string: release.htmlUrl)
                updateAvailable = true
            }
        } catch {
            // Silent failure — never bother the user
        }
    }

    func openReleasePage() {
        if let url = releaseURL {
            NSWorkspace.shared.open(url)
        }
        updateAvailable = false
    }

    func dismissUpdate() {
        UserDefaults.standard.set(latestVersion, forKey: Self.dismissedKey)
        updateAvailable = false
    }

    private func isNewer(_ remote: String, than current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }

        // If parsing failed for either, don't show update
        guard r.count == remote.split(separator: ".").count,
              c.count == current.split(separator: ".").count else { return false }

        let maxLen = max(r.count, c.count)
        for i in 0..<maxLen {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
