#if DEBUG
import AppKit
import TetheraKit

/// Scripted runs and window captures for development (Debug builds only).
///
///     TETHERA_SNAPSHOT_DIR=… TETHERA_SCRIPT='ls -G;;@wait:1;;@shot:main;;@quit' .build/debug/Tethera
///
/// Steps: a shell line (typed into the focused session with ↩), `@type:<text>`, `@keys:<text>`
/// (`\e`, `\r`, `\x03` escapes), `@new`, `@agent:<kind>`, `@split`, `@select:<n>`, `@palette`,
/// `@overview`, `@inspector`, `@close`, `@home`, `@about` (captures about.png), `@open:<path>`, `@preview`,
/// `@changes`, `@closepane`, `@appearance:<dark|light>`, `@remote:<name>=<address>`, `@newon:<n>`, `@phone:<token>`,
/// `@wait:<sec>`, `@shot:<name>`, `@quit`.
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
                if env["TETHERA_SCRIPT_TRACE"] != nil { print("[DebugHooks] \(step.prefix(60))") }
                await run(step.trimmingCharacters(in: .whitespaces), directory: directory)
            }
        }
    }

    private static func run(_ step: String, directory: String) async {
        let workspace = Workspace.shared
        let client = DaemonClient.shared
        func type(_ text: String) {
            guard let id = workspace.focusedSessionID else { return }
            if let terminal = TerminalStore.shared.existing(id) { terminal.input(text) } else { client.send(id, Data(text.utf8)) }
        }
        if step.hasPrefix("@wait:") {
            try? await Task.sleep(nanoseconds: UInt64((Double(step.dropFirst(6)) ?? 1) * 1e9))
        } else if step.hasPrefix("@shot:") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 600_000_000)
            snapshot(name: String(step.dropFirst(6)), directory: directory)
        } else if step == "@new" {
            workspace.newSession()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        } else if step.hasPrefix("@agent:") {
            if let kind = AgentKind(rawValue: String(step.dropFirst(7))) { workspace.newSession(agent: kind) }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        } else if step == "@split" {
            workspace.split(.horizontal)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        } else if step.hasPrefix("@select:") {
            workspace.show(index: Int(step.dropFirst(8)) ?? 0)
        } else if step.hasPrefix("@rename:") {
            if let id = workspace.focusedSessionID { client.rename(id, to: String(step.dropFirst(8))) }
        } else if step.hasPrefix("@splitwith:") {
            let sessions = client.sessions
            if let index = Int(step.dropFirst(11)), sessions.indices.contains(index) {
                workspace.axis = .horizontal
                let pane = Workspace.Pane(content: .session(sessions[index].id))
                workspace.panes.append(pane)
                workspace.focus(pane: pane.id)
            }
        } else if step.hasPrefix("@open:") {
            workspace.open(path: (String(step.dropFirst(6)) as NSString).expandingTildeInPath, besideSession: workspace.focusedSessionID)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        } else if step == "@preview" {
            if let id = workspace.focusedSessionID { PreviewDetector.shared.open(for: id) }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        } else if step == "@changes" {
            workspace.showChanges()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        } else if step == "@dumpeditor" {
            func walk(_ view: NSView, _ depth: Int) {
                if view is NSScrollView || view is NSTextView || view is NSRulerView || String(describing: Swift.type(of: view)).contains("Hosting") && depth < 6 {
                    let frame = view.convert(view.bounds, to: nil)
                    print("[dump] \(String(repeating: " ", count: depth))\(Swift.type(of: view)) frame=\(frame) hidden=\(view.isHidden) \((view as? NSTextView).map { "len=\($0.string.count) color=\(String(describing: $0.textColor)) tv.frame=\($0.frame)" } ?? "")")
                }
                view.subviews.forEach { walk($0, depth + 1) }
            }
            if let content = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) })?.contentView { walk(content, 0) }
        } else if step == "@git" {
            workspace.showGit()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        } else if step == "@costs" || step == "@audit" || step == "@board" {
            switch step {
            case "@costs": workspace.showCosts()
            case "@audit": workspace.showAudit()
            default: workspace.showBoard()
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        } else if step == "@brew" {
            workspace.showBrew()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        } else if step.hasPrefix("@worktree:") {
            WorktreeActions.newAgent(AgentKind(rawValue: String(step.dropFirst(10))))
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        } else if step.hasPrefix("@away:") {
            AwayTracker.shared.simulateReturn(since: Date().addingTimeInterval(-(TimeInterval(step.dropFirst(6)) ?? 3600)))
            workspace.showHome()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        } else if step == "@transcript" {
            workspace.showTranscript()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        } else if step == "@approvals" {
            workspace.showApprovals()
            try? await Task.sleep(nanoseconds: 800_000_000)
        } else if step.hasPrefix("@answer:") {
            if let first = ApprovalCenter.shared.pending.first,
               let answer = ApprovalCenter.Answer(rawValue: String(step.dropFirst(8))) {
                ApprovalCenter.shared.answer(first.id, answer)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        } else if step == "@closepane" {
            workspace.closeFocusedPane()
        } else if step == "@home" {
            workspace.showHome()
            try? await Task.sleep(nanoseconds: 800_000_000)
        } else if step == "@about" {
            AboutWindow.show()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if let window = NSApp.windows.first(where: { $0.title == "About Tethera" }) {
                capture(window, name: "about", directory: directory)
            }
        } else if step == "@palette" {
            workspace.showPalette = true
        } else if step == "@overview" {
            workspace.showOverview = true
        } else if step == "@inspector" {
            PreferencesStore.shared.value.showInspector.toggle()
        } else if step == "@close" {
            workspace.showPalette = false
            workspace.showOverview = false
        } else if step.hasPrefix("@appearance:") {
            PreferencesStore.shared.value.appearance = step.hasSuffix("light") ? .light : .dark
        } else if step.hasPrefix("@type:") {
            // `_` stands for a space, which the step list would trim.
            type(String(step.dropFirst(6)).replacingOccurrences(of: "_", with: " "))
        } else if step.hasPrefix("@keys:") {
            type(String(step.dropFirst(6))
                .replacingOccurrences(of: "\\e", with: "\u{1b}")
                .replacingOccurrences(of: "\\r", with: "\r")
                .replacingOccurrences(of: "\\x03", with: "\u{03}"))
        } else if step.hasPrefix("@settings") {
            SettingsOpener.open()
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let tab = step.split(separator: ":").dropFirst().first, let window = NSApp.keyWindow,
               let toolbar = window.toolbar, let item = toolbar.items.first(where: { $0.label == String(tab) }) {
                window.toolbar?.selectedItemIdentifier = item.itemIdentifier
                _ = item.target.map { NSApp.sendAction(item.action!, to: $0, from: item) }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        } else if step.hasPrefix("@shotkey:") {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let window = NSApp.keyWindow { capture(window, name: String(step.dropFirst(9)), directory: directory) }
        } else if step.hasPrefix("@remote:") {
            // `@remote:Studio=exec:TETHERA_HOME=… tethera bridge` stands in another Mac.
            let parts = step.dropFirst(8).split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !PreferencesStore.shared.value.remoteHosts.contains(where: { $0.address == parts[1] }) else { return }
            PreferencesStore.shared.value.remoteHosts.append(RemoteHost(name: parts[0], address: parts[1]))
            client.syncRemoteHosts(PreferencesStore.shared.value.remoteHosts)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        } else if step.hasPrefix("@newon:") {
            let hosts = PreferencesStore.shared.value.remoteHosts
            if let index = Int(step.dropFirst(7)), hosts.indices.contains(index) { workspace.newSession(on: hosts[index].id) }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        } else if step.hasPrefix("@phone") {
            // `@phone:<token>` turns the dashboard on (bind it with TETHERA_PHONE_HOST=127.0.0.1).
            let token = step.split(separator: ":").dropFirst().first.map(String.init) ?? PhoneServer.randomToken()
            PreferencesStore.shared.value.phoneToken = token
            PreferencesStore.shared.value.phoneEnabled = true
            PhoneServer.shared.apply(PreferencesStore.shared.value)
            try? await Task.sleep(nanoseconds: 500_000_000)
            print("[DebugHooks] phone \(PhoneServer.shared.pairingURL?.absoluteString ?? PhoneServer.shared.problem ?? "off")")
        } else if step == "@accept" || step == "@complete" || step == "@down" || step == "@insert" {
            // Keys for suggestions: → takes the ghost text, ⌃Space lists, ↓ moves, Return inserts.
            guard let id = workspace.focusedSessionID, let terminal = TerminalStore.shared.existing(id) else { return }
            let (code, characters, flags): (UInt16, String, NSEvent.ModifierFlags) = switch step {
            case "@accept": (124, "\u{F703}", [.function, .numericPad])
            case "@complete": (49, " ", [.control])
            case "@down": (125, "\u{F701}", [.function, .numericPad])
            default: (36, "\r", [])
            }
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                                            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
                _ = terminal.handleKey(event)
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        } else if step.hasPrefix("@clickrow:") {
            // A real click (posted mouse events, through SwiftUI's gestures) on the i-th sidebar
            // session row, timed until the pane switches. Rows: 40 pt apart from y 81 below the
            // window's top, with no Approvals row or repository headers above them.
            let index = Int(step.dropFirst(10)) ?? 0
            guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 200_000_000)
            // Past the last row is the empty sidebar below them.
            let target = client.sessions.indices.contains(index) ? client.sessions[index].id : nil
            let point = NSPoint(x: 120, y: window.contentLayoutRect.maxY - 81 - CGFloat(index) * 40)
            let start = Date()
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(event, atStart: false)
                }
            }
            guard let target else { return print("[DebugHooks] click below the rows") }
            while workspace.focusedSessionID != target, Date().timeIntervalSince(start) < 2 {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            print("[DebugHooks] click \(client.sessions[index].name): switched=\(workspace.focusedSessionID == target) after \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        } else if step.hasPrefix("@dblclickrow:") || step == "@esc" {
            // A real double-click on the i-th session row (it should start renaming), or Escape.
            guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if step == "@esc" {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: now, windowNumber: window.windowNumber,
                                                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            } else {
                let index = Int(step.dropFirst(13)) ?? 0
                let point = NSPoint(x: 120, y: window.contentLayoutRect.maxY - 81 - CGFloat(index) * 40)
                for clicks in [1, 2] {
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: now, windowNumber: window.windowNumber,
                                                          context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) {
                            NSApp.postEvent(event, atStart: false)
                        }
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            print("[DebugHooks] \(step): renaming=\(workspace.renaming.flatMap { client.session($0)?.name } ?? "none")")
        } else if step == "@focus" {
            // Whether typing would reach the focused session: prints the session and the window's first responder.
            let name = workspace.focusedSession?.name ?? "none"
            let typing = workspace.focusedSessionID.flatMap { TerminalStore.shared.existing($0)?.hasFocus } ?? false
            let responder = NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }?.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "nil"
            print("[DebugHooks] focus \(name): terminal=\(typing) responder=\(responder)")
        } else if step == "@quit" {
            NSApp.terminate(nil)
        } else if !step.isEmpty {
            // Tethera opens to Home; a script's first shell line gets a session to type into.
            if workspace.focusedSessionID == nil {
                workspace.newSession()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            type(step + "\r")
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }

    /// Captures the window with materials and shadow. `CGWindowListCreateImage` is hidden from
    /// Swift in the current SDK but still works for the app's own windows without permission.
    static func snapshot(name: String, directory: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) && $0.styleMask.contains(.titled) && $0.title != "Settings" && !$0.title.hasSuffix("Settings") }) else { return }
        capture(window, name: name, directory: directory)
    }

    static func capture(_ window: NSWindow, name: String, directory: String) {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGWindowListCreateImage") else { return }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        guard let image = capture(.null, 1 << 3, UInt32(window.windowNumber), 1 << 3)?.takeRetainedValue(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("[DebugHooks] wrote \(url.path)")
    }
}
#endif
