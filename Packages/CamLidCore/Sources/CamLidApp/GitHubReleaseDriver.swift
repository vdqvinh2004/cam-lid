import Foundation

/// A release tag such as "v0.1.0" read as numbers. Anything else (a pre-release suffix, a date) is not a version.
struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]

    init?(_ text: String) {
        var rest = Substring(text)
        if rest.hasPrefix("v") { rest = rest.dropFirst() }
        let pieces = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 6, piece.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        parts = numbers
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0, b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }
    static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// Asks GitHub's public API for the newest published release, only when the user clicks "Check for Updates".
/// Read-only: no account, no cookies, no system profile, nothing downloaded or installed. Pre-releases count
/// (`/releases/latest` hides them, and early versions are pre-releases).
@MainActor final class GitHubReleaseDriver: UpdateProbeDriver {
    static let releasesAPI = URL(string: "https://api.github.com/repos/vdqvinh2004/cam-lid/releases?per_page=5")!
    static let releasesPage = URL(string: "https://github.com/vdqvinh2004/cam-lid/releases")!
    nonisolated private static let maximumResponseBytes = 256 * 1024

    private let currentVersion: String
    private var task: Task<Void, Never>?
    init(currentVersion: String) { self.currentVersion = currentVersion }

    func checkInformation(completion: @escaping @MainActor (UpdateProbeOutcome) -> Void) throws {
        guard let current = ReleaseVersion(currentVersion) else { throw NSError(domain: "CamLid.Updates", code: 1) }
        task?.cancel()
        task = Task { @MainActor in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            var request = URLRequest(url: Self.releasesAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("CamLid/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession(configuration: configuration).data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                completion(Self.outcome(status: status, body: data, current: current))
            } catch let error as URLError where Self.isOffline(error) {
                completion(.offline)
            } catch {
                if !Task.isCancelled { completion(.failed) }
            }
        }
    }

    /// Pure: the newest non-draft release with a version tag, compared with the installed version.
    nonisolated static func outcome(status: Int, body: Data, current: ReleaseVersion) -> UpdateProbeOutcome {
        if status == 404 { return .noCompatibleUpdate }   // no release published yet
        guard status == 200, body.count <= maximumResponseBytes,
              let releases = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] else { return .failed }
        for release in releases where release["draft"] as? Bool != true {
            guard let tag = release["tag_name"] as? String, let version = ReleaseVersion(tag) else { continue }
            return version > current ? .available(String(tag.drop { $0 == "v" })) : .current
        }
        return .noCompatibleUpdate
    }

    nonisolated static func isOffline(_ error: URLError) -> Bool {
        [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut,
         .dnsLookupFailed].contains(error.code)
    }
}
