import AppKit
import SwiftUI

/// What's playing in Music or Spotify, for the status bar. Updates come from the players' own
/// notifications (no permission needed); play/pause/skip and artwork use AppleScript, which
/// macOS asks you to allow the first time you press a control.
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()

    enum Player: String {
        case music = "Music"
        case spotify = "Spotify"

        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var player: Player
        var duration: Double?
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var position: Double?
    private var observers: [NSObjectProtocol] = []
    private var artworkKey = ""

    private init() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { NowPlaying.shared.update(from: info, player: .music) }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { NowPlaying.shared.update(from: info, player: .spotify) }
        })
    }

    /// Starts listening (the notifications only arrive once someone asks).
    func start() {}

    private func update(from info: [AnyHashable: Any], player: Player) {
        let state = info["Player State"] as? String ?? ""
        guard state != "Stopped", let title = info["Name"] as? String, !title.isEmpty else {
            if track?.player == player { track = nil; artwork = nil }
            return
        }
        // Music reports milliseconds, Spotify milliseconds too ("Duration"); either may be missing.
        let duration = (info["Total Time"] as? Double ?? info["Duration"] as? Double).map { $0 / 1000 }
        let next = Track(title: title, artist: info["Artist"] as? String ?? "", album: info["Album"] as? String ?? "",
                         isPlaying: state == "Playing", player: player, duration: duration)
        // Another player pausing doesn't replace the one that's playing.
        if let current = track, current.player != player, current.isPlaying, !next.isPlaying { return }
        track = next
        let key = "\(player.rawValue)|\(title)|\(next.album)"
        if key != artworkKey {
            artworkKey = key
            artwork = nil
        }
    }

    // MARK: Controls

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    private func send(_ command: String) {
        guard let player = track?.player else { return }
        run("tell application \"\(player.rawValue)\" to \(command)")
    }

    /// Fetches the artwork and position when the popover opens.
    func refreshDetails() {
        guard let track else { return }
        if let seconds = run("tell application \"\(track.player.rawValue)\" to player position")?.doubleValue { position = seconds }
        guard artwork == nil else { return }
        switch track.player {
        case .spotify:
            if let url = run("tell application \"Spotify\" to artwork url of current track")?.stringValue.flatMap(URL.init(string:)) {
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: url) { self.artwork = NSImage(data: data) }
                }
            }
        case .music:
            if let data = run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data, !data.isEmpty {
                artwork = NSImage(data: data)
            }
        }
    }

    func openPlayer() {
        guard let player = track?.player, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @discardableResult
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let player = track?.player, !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty else { return nil }
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}

/// The status-bar item: ♪ title · artist, play/pause, next. Click for artwork and controls.
struct NowPlayingItem: View {
    @ObservedObject private var nowPlaying = NowPlaying.shared
    @ObservedObject private var preferences = PreferencesStore.shared
    @Environment(\.theme) private var theme
    @State private var showing = false

    var body: some View {
        if preferences.value.showNowPlaying, let track = nowPlaying.track {
            HStack(spacing: 6) {
                Button {
                    showing.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "music.note").font(.system(size: 9.5, weight: .semibold))
                        Text(track.artist.isEmpty ? track.title : "\(track.title) · \(track.artist)")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 240, alignment: .leading)
                    }
                    .foregroundStyle(track.isPlaying ? theme.text2.color : theme.text3.color)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showing, arrowEdge: .top) { NowPlayingPopover().environment(\.theme, theme) }
                Button { nowPlaying.playPause() } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .help(track.isPlaying ? "Pause" : "Play")
                Button { nowPlaying.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .help("Next")
            }
            .foregroundStyle(theme.text2.color)
        }
    }
}

private struct NowPlayingPopover: View {
    @ObservedObject private var nowPlaying = NowPlaying.shared
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(theme.raised.color)
                if let artwork = nowPlaying.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 34, weight: .light)).foregroundStyle(theme.text3.color)
                }
            }
            .frame(width: 236, height: 236)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            if let track = nowPlaying.track {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(TypeScale.ui(14, .semibold)).foregroundStyle(theme.text.color).lineLimit(2)
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(TypeScale.ui(12)).foregroundStyle(theme.text2.color).lineLimit(2)
                }
                if let duration = track.duration, let position = nowPlaying.position, duration > 0 {
                    ProgressView(value: min(position, duration), total: duration).progressViewStyle(.linear).tint(theme.text2.color)
                }
                HStack(spacing: 26) {
                    Spacer()
                    Button { nowPlaying.previous() } label: { Image(systemName: "backward.fill") }
                    Button { nowPlaying.playPause() } label: { Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18)) }
                    Button { nowPlaying.next() } label: { Image(systemName: "forward.fill") }
                    Spacer()
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text.color)
                Button("Open \(track.player.rawValue)") { nowPlaying.openPlayer() }
                    .buttonStyle(.plain)
                    .font(TypeScale.ui(11.5))
                    .foregroundStyle(theme.text3.color)
            }
        }
        .padding(16)
        .frame(width: 268)
        .background(theme.surface.color)
        .onAppear { nowPlaying.refreshDetails() }
    }
}
