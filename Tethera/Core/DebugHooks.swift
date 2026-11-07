#if DEBUG
import AppKit
import SwiftUI

/// Scripted demo + window snapshots for development (Debug builds only).
///
///     TETHERA_SNAPSHOT_DIR=/tmp/shots \
///     TETHERA_SCRIPT='ls -la;;@shot:list;;@palette;;@shot:palette' .build/debug/Tethera
///
/// Steps: shell commands, `@wait:<sec>`, `@shot:<name>`, `@palette`, `@search`, `@settings`,
/// `@close` (dismiss overlays), `@type:<text>` (fill the prompt), `@ai:<question>`, `@gen:<request>`,
/// `@start:<command>` (run without waiting), `@keys:<text>` (raw keys to the PTY; `\e`, `\r`, `\x03` escapes),
/// `@size` (log emulator vs PTY size), `@quit`.
@MainActor
enum DebugHooks {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["TETHERA_SNAPSHOT_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let steps = (env["TETHERA_SCRIPT"] ?? "@wait:3;;@shot:window").components(separatedBy: ";;")
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            for step in steps {
                await run(step.trimmingCharacters(in: .whitespaces), directory: directory)
            }
        }
    }

    private static func run(_ step: String, directory: String) async {
        let commands = AppCommands.shared
        if step.hasPrefix("@wait:") {
            let seconds = Double(step.dropFirst(6)) ?? 1
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        } else if step.hasPrefix("@shot:") {
            // Shots look best with the window active (colored traffic lights, focused caret).
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { AppDelegate.isMainWindow($0) })?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot(name: String(step.dropFirst(6)), directory: directory)
        } else if step == "@palette" {
            commands.send(.palette)
        } else if step == "@search" {
            commands.send(.search)
        } else if step == "@settings" {
            commands.send(.openSettings)
        } else if step == "@close" {
            commands.send(.closeTab)
        } else if step.hasPrefix("@type:") {
            commands.send(.debugInsert(String(step.dropFirst(6))))
        } else if step.hasPrefix("@ai:") {
            commands.send(.debugAsk(String(step.dropFirst(4))))
            await waitForIdle(timeout: 120)
        } else if step.hasPrefix("@gen:") {
            commands.send(.debugGenerate(String(step.dropFirst(5))))
            await waitForIdle(timeout: 120)
        } else if step.hasPrefix("@start:") {
            commands.send(.runInActiveTab(String(step.dropFirst(7))))
        } else if step.hasPrefix("@keys:") {
            let keys = String(step.dropFirst(6))
                .replacingOccurrences(of: "\\e", with: "\u{1b}")
                .replacingOccurrences(of: "\\r", with: "\r")
                .replacingOccurrences(of: "\\x03", with: "\u{03}")
            commands.send(.debugSendKeys(keys))
        } else if step == "@size" {
            if let viewModel = DebugState.activeViewModel {
                let terminal = viewModel.live.terminal
                print("[DebugHooks] emulator \(terminal.cols)x\(terminal.rows) view \(viewModel.live.view.frame.size) pty \(viewModel.debugPTYSize)")
            }
        } else if step == "@quit" {
            NSApp.terminate(nil)
        } else if !step.isEmpty {
            commands.send(.runInActiveTab(step))
            await waitForIdle(timeout: 60)
        }
    }

    /// Waits until the active session has no running command or AI request.
    private static func waitForIdle(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        try? await Task.sleep(nanoseconds: 400_000_000)
        while Date() < deadline {
            if DebugState.activeViewModel?.isBusy == false { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    static func snapshot(name: String, directory: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && AppDelegate.isMainWindow($0) }) else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        // A real window capture keeps materials and glass; cacheDisplay can't render them.
        if let image = windowImage(window), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("[DebugHooks] wrote \(url.path) (window capture)")
            return
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("[DebugHooks] wrote \(url.path) (cacheDisplay)")
    }

    /// `CGWindowListCreateImage` is hidden from Swift in the current SDK but still works for
    /// the app's own windows, without Screen Recording permission.
    private static func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        let includingWindow: UInt32 = 1 << 3
        let bestResolution: UInt32 = 1 << 3
        return capture(.null, includingWindow, UInt32(window.windowNumber), bestResolution)?.takeRetainedValue()
    }
}

@MainActor
enum DebugState {
    static weak var tabManager: TabManager?
    static var activeViewModel: BlockTerminalViewModel? { tabManager?.activeViewModel }
}
#endif
