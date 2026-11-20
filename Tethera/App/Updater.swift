import AppKit
import CryptoKit
import Foundation

/// Keeps Tethera current without an App Store or a paid developer account. It asks GitHub for
/// the latest release, downloads the DMG, checks its Ed25519 signature against the key built
/// into the app, swaps the app in place and relaunches. Sessions live in the daemon, so they
/// keep running through it.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// The public half of the release signing key (`scripts/sign_update.swift`).
    nonisolated static let publicKey = "bE4Het5IZ2ZQY4HE9p3tK7gLZeuOpuFzhEmyW6Zgs0U="
    static let latestRelease = URL(string: "https://api.github.com/repos/Tsogbat/tethera/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "tethera.update.lastCheck"

    struct Release: Equatable {
        let version: String
        let notes: String
        let dmg: URL
        let signature: URL
        let page: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var timer: Timer?

    /// Asked from the menu: says what happened, and offers to install.
    func checkFromMenu() {
        Task {
            await check(userInitiated: true)
            let alert = NSAlert()
            switch state {
            case .available(let release):
                alert.messageText = "Tethera \(release.version) is available"
                alert.informativeText = "You have \(currentVersion). Your sessions keep running while Tethera restarts."
                alert.addButton(withTitle: canInstall ? "Install and Restart" : "Open Release Page")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn { await install() }
            case .failed(let message):
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = message
                alert.runModal()
            default:
                alert.messageText = "Tethera is up to date"
                alert.informativeText = "You have the latest version, \(currentVersion)."
                alert.runModal()
            }
        }
    }

    var available: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Only a packaged app can replace itself; `swift run` builds just check.
    var canInstall: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Checks shortly after launch and then daily, unless turned off in Settings.
    func start() {
        // `TETHERA_UPDATE_NOW=1` installs the latest release straight away, without asking:
        // for scripted installs and for testing the updater end to end.
        if ProcessInfo.processInfo.environment["TETHERA_UPDATE_NOW"] == "1" {
            Task { @MainActor in
                await check(userInitiated: true)
                await install()
            }
            return
        }
        guard canInstall, PreferencesStore.shared.value.checkForUpdates else { return }
        let last = AppDefaults.store.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        let delay = max(8, Self.checkInterval - Date().timeIntervalSince(last))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { Updater.shared.scheduledCheck() }
        }
    }

    private func scheduledCheck() {
        Task { @MainActor in await check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: false) { _ in
            MainActor.assumeIsolated { Updater.shared.scheduledCheck() }
        }
    }

    // MARK: Checking

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        state = .checking
        AppDefaults.store.set(Date(), forKey: Self.lastCheckKey)
        do {
            var request = URLRequest(url: Self.latestRelease)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Tethera/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.message("GitHub didn't answer.") }
            let release = try Self.parse(data)
            if let release, Self.isNewer(release.version, than: currentVersion) {
                state = .available(release)
            } else {
                state = userInitiated ? .upToDate : .idle
            }
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    /// The release, if it has a DMG and its signature (a release isn't offered until it's signed).
    nonisolated static func parse(_ data: Data) throws -> Release? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else { throw UpdateError.message("Unexpected answer from GitHub.") }
        func asset(_ name: String) -> URL? {
            (assets.first { $0["name"] as? String == name }?["browser_download_url"] as? String).flatMap(URL.init(string:))
        }
        guard let dmg = asset("Tethera-macOS.dmg"), let signature = asset("Tethera-macOS.dmg.sig") else { return nil }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://github.com/Tsogbat/tethera/releases")!
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, notes: json["body"] as? String ?? "",
                       dmg: dmg, signature: signature, page: page)
    }

    /// Numeric comparison of dotted versions: 0.10.0 is newer than 0.9.3.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func verify(_ data: Data, signature: Data, publicKey: String = Updater.publicKey) -> Bool {
        guard let raw = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(signature, for: data)
    }

    // MARK: Installing

    func install() async {
        guard let release = available else { return }
        guard canInstall else {
            NSWorkspace.shared.open(release.page)
            return
        }
        do {
            state = .downloading(0)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("tethera-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let dmg = try await download(release.dmg, to: work.appendingPathComponent("Tethera.dmg"))
            let (signatureText, _) = try await URLSession.shared.data(from: release.signature)
            guard let signature = Data(base64Encoded: String(decoding: signatureText, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
                  Self.verify(try Data(contentsOf: dmg), signature: signature) else {
                throw UpdateError.message("The download's signature doesn't match. Nothing was changed.")
            }
            state = .installing
            let staged = try await Self.stage(dmg: dmg, in: work, expecting: release.version)
            try Self.relaunch(replacing: Bundle.main.bundleURL, with: staged, work: work)
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL, to destination: URL) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.message("The download failed.") }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// Mounts the DMG, checks the app inside is the version expected, copies it out.
    private static func stage(dmg: URL, in work: URL, expecting version: String) async throws -> URL {
        let mount = work.appendingPathComponent("mnt")
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path, dmg.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", mount.path]) }
        let app = mount.appendingPathComponent("Tethera.app")
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info?["CFBundleShortVersionString"] as? String == version else {
            throw UpdateError.message("The update isn't the Tethera \(version) it claimed to be.")
        }
        let staged = work.appendingPathComponent("Tethera.app")
        try run("/usr/bin/ditto", [app.path, staged.path])
        return staged
    }

    /// A detached helper waits for this app to quit, swaps the bundle, and opens the new one.
    /// The old bundle is kept until the new one is fully copied, and put back if the copy fails.
    private static func relaunch(replacing current: URL, with staged: URL, work: URL) throws {
        guard current.pathExtension == "app", staged.pathExtension == "app", work.lastPathComponent.hasPrefix("tethera-update-") else {
            throw UpdateError.message("Unexpected install location.")
        }
        let script = """
        set -u
        new="${1:?}"; app="${2:?}"; work="${3:?}"
        case "$app" in *.app) ;; *) exit 1 ;; esac
        case "$work" in */tethera-update-*) ;; *) exit 1 ;; esac
        while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 0.2; done
        old="$app.previous-$$"
        if /bin/mv "$app" "$old"; then
          if /usr/bin/ditto "$new" "$app"; then /bin/rm -rf "$old"; else /bin/rm -rf "$app"; /bin/mv "$old" "$app"; fi
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$app" 2>/dev/null
        if [ -n "${TETHERA_HOME:-}" ]; then /usr/bin/open --env "TETHERA_HOME=$TETHERA_HOME" "$app"; else /usr/bin/open "$app"; fi
        /bin/rm -rf "$work"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "tethera-update", staged.path, current.path, work.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.message("\((tool as NSString).lastPathComponent) failed: \(output)") }
        return output
    }

    enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let text) = self { return text }
            return nil
        }
    }
}
