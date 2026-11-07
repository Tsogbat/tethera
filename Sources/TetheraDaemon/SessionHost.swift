import CPTY
import Foundation
import SwiftTerm
import TetheraKit

/// One persistent session: a shell on a PTY, plus a headless emulator that is the terminal of
/// record. Everything runs on the daemon's queue.
final class SessionHost: TerminalDelegate {
    private(set) var info: SessionInfo
    var id: UUID { info.id }

    /// Called (coalesced) when `info` changes, and when the shell exits.
    var onChange: ((SessionHost) -> Void)?
    var onExit: ((SessionHost) -> Void)?
    /// A unique name for a folder, so sessions without a custom name follow their cwd.
    var nameForFolder: ((String, UUID) -> String)?

    private let queue: DispatchQueue
    private let version: String
    private var terminal: Terminal?
    private var masterFD: Int32 = -1
    private var pid: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var writeSourceActive = false
    private var processSource: DispatchSourceProcess?
    private var pendingInput = Data()
    private var seq: UInt64 = 0
    private var clients: [ObjectIdentifier: FramedSocket] = [:]
    private var queryFilter = QueryFilter()
    private var promptScanner = PromptScanner()
    private var initialInput: String?
    private var restoredHistory: Data?
    private var cursorStyle: CursorStyle?
    /// While set, the emulator's replies are collected here instead of going to the program.
    private var captured: [UInt8]?
    private var lastOutput = Date.distantPast
    private var lastForegroundCheck = Date.distantPast
    private var programStatusActive = false
    private var lastHookAt: Double = 0
    private var changePending = false
    private(set) var isDirty = true

    static let maxClientBacklog = 32 * 1024 * 1024
    static let scrollback = 10_000

    init(info: SessionInfo, queue: DispatchQueue, version: String) {
        self.info = info
        self.queue = queue
        self.version = version
    }

    deinit {
        processSource?.cancel()
        teardownPTY()
    }

    /// A session saved before a reboot: shown in the list, revived with its history on attach.
    convenience init(restored info: SessionInfo, history: Data?, queue: DispatchQueue, version: String) {
        var info = info
        info.isAlive = false
        info.isRestored = true
        info.pid = nil
        info.clients = 0
        info.agent = nil
        info.foreground = nil
        info.isCommandRunning = false
        self.init(info: info, queue: queue, version: version)
        restoredHistory = history
    }

    // MARK: - Lifecycle

    func start(shell: String?, initialInput: String?) throws {
        self.initialInput = initialInput
        let terminal = makeTerminal()
        if let history = restoredHistory {
            terminal.feed(byteArray: Array(history))
            let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
            terminal.feed(text: "\r\n\u{1b}[0;2m── restored \(stamp) ──\u{1b}[0m\r\n")
            restoredHistory = nil
        }
        let launch = try ShellLaunch.make(shell: shell ?? info.shell, sessionID: info.id,
                                          base: ProcessInfo.processInfo.environment, version: version)
        try spawn(launch)
        info.shell = launch.executable
        info.isAlive = true
        info.isRestored = false
        info.pid = pid
        markChanged()
        // If the integration never reports a prompt, type the initial input anyway.
        if initialInput != nil {
            queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.sendInitialInput() }
        }
    }

    private func makeTerminal() -> Terminal {
        if let terminal { return terminal }
        let options = TerminalOptions(cols: max(info.cols, 10), rows: max(info.rows, 2), scrollback: Self.scrollback)
        let terminal = Terminal(delegate: self, options: options)
        self.terminal = terminal
        return terminal
    }

    private func spawn(_ launch: ShellLaunch) throws {
        var argv: [UnsafeMutablePointer<CChar>?] = launch.arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var envp: [UnsafeMutablePointer<CChar>?] = launch.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }
        var fd: Int32 = -1
        let cwd = FileManager.default.fileExists(atPath: info.cwd) ? info.cwd : NSHomeDirectory()
        let child = tethera_spawn_pty(launch.executable, &argv, &envp, cwd,
                                      UInt16(clamping: info.cols), UInt16(clamping: info.rows), &fd)
        guard child > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        pid = child
        masterFD = fd

        let read = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        read.setEventHandler { [weak self] in self?.readOutput() }
        read.setCancelHandler { Darwin.close(fd) }
        readSource = read
        let write = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
        write.setEventHandler { [weak self] in self?.flushInput() }
        writeSource = write
        let exit = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: queue)
        exit.setEventHandler { [weak self] in self?.processExited() }
        processSource = exit
        read.resume()
        exit.resume()
    }

    /// Hangs up the shell's process group, like closing a terminal window.
    func terminate() {
        guard pid > 0 else { return }
        let group = getpgid(pid)
        kill(group > 0 ? -group : pid, SIGHUP)
        kill(pid, SIGHUP)
        let target = pid
        queue.asyncAfter(deadline: .now() + 2) {
            if kill(target, 0) == 0 { kill(target, SIGKILL) }
        }
    }

    private func processExited() {
        var status: Int32 = 0
        waitpid(pid, &status, WNOHANG)
        processSource?.cancel()
        processSource = nil
        readOutput()  // drain what the shell wrote last
        teardownPTY()
        info.isAlive = false
        info.pid = nil
        info.agent = nil
        onExit?(self)
    }

    private func teardownPTY() {
        if let writeSource {
            if !writeSourceActive { writeSource.resume() }
            writeSource.cancel()
        }
        writeSource = nil
        writeSourceActive = false
        readSource?.cancel()
        readSource = nil
        masterFD = -1
        pid = 0
        pendingInput = Data()
    }

    // MARK: - Clients

    func attach(_ client: FramedSocket, cols: Int, rows: Int) throws {
        if !info.isAlive {
            try start(shell: nil, initialInput: nil)
        }
        resize(cols: cols, rows: rows)
        clients[ObjectIdentifier(client)] = client
        client.sendNow(.snapshot(session: id, seq: seq, bytes: snapshot()))
        info.clients = clients.count
        nudgeRedraw()
        if info.agent?.unseen == true { info.agent?.unseen = false }
        markChanged()
    }

    /// Full-screen programs repaint from their own idea of the screen; a brief size change makes
    /// them redraw everything for the client that just attached (what tmux does on attach).
    private func nudgeRedraw() {
        guard masterFD >= 0, let foreground = ProcessInspector.foreground(masterFD: masterFD), foreground.pid != pid else { return }
        let cols = UInt16(clamping: info.cols), rows = UInt16(clamping: info.rows)
        _ = tethera_set_winsize(masterFD, cols, rows > 3 ? rows - 1 : rows + 1)
        queue.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            _ = tethera_set_winsize(self.masterFD, UInt16(clamping: self.info.cols), UInt16(clamping: self.info.rows))
        }
    }

    func detach(_ client: FramedSocket) {
        guard clients.removeValue(forKey: ObjectIdentifier(client)) != nil else { return }
        info.clients = clients.count
        markChanged()
    }

    func snapshot(includeAlternate: Bool = true) -> Data {
        guard let terminal else { return restoredHistory ?? Data() }
        if !includeAlternate && terminal.isCurrentBufferAlternate {
            let text = String(decoding: terminal.getBufferAsData(kind: .normal), as: UTF8.self)
            return Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        }
        return VTSnapshot.capture(terminal, title: info.title, cursorStyle: cursorStyle, modes: queryModes())
    }

    /// Reads modes SwiftTerm keeps private by asking the emulator itself (DECRQM).
    private func queryModes() -> VTSnapshot.Modes {
        guard let terminal else { return VTSnapshot.Modes() }
        captured = []
        terminal.feed(text: "\u{1b}[?25$p\u{1b}[?1004$p\u{1b}[?1006$p\u{1b}[?1015$p\u{1b}[?1016$p")
        let reply = String(decoding: captured ?? [], as: UTF8.self)
        captured = nil
        func isSet(_ mode: Int) -> Bool {
            reply.contains("\u{1b}[?\(mode);1$y") || reply.contains("\u{1b}[?\(mode);3$y")
        }
        var modes = VTSnapshot.Modes()
        modes.cursorVisible = reply.contains("?25;") ? isSet(25) : true
        modes.focusReporting = isSet(1004)
        modes.sgrMouse = isSet(1006)
        modes.urxvtMouse = isSet(1015)
        modes.sgrPixelMouse = isSet(1016)
        return modes
    }

    // MARK: - Input

    func write(_ data: Data) {
        guard masterFD >= 0, !data.isEmpty else { return }
        pendingInput.append(data)
        flushInput()
    }

    private func flushInput() {
        while !pendingInput.isEmpty && masterFD >= 0 {
            let written = pendingInput.withUnsafeBytes { Darwin.write(masterFD, $0.baseAddress, $0.count) }
            if written > 0 {
                pendingInput.removeSubrange(0..<written)
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                break // EAGAIN: the shell isn't reading; wait for the write source
            }
        }
        if pendingInput.isEmpty {
            pendingInput = Data()
            if writeSourceActive { writeSource?.suspend(); writeSourceActive = false }
        } else if !writeSourceActive {
            writeSource?.resume()
            writeSourceActive = true
        }
    }

    func resize(cols: Int, rows: Int) {
        let cols = max(cols, 10), rows = max(rows, 2)
        guard cols != info.cols || rows != info.rows else { return }
        info.cols = cols
        info.rows = rows
        terminal?.resize(cols: cols, rows: rows)
        if masterFD >= 0 { _ = tethera_set_winsize(masterFD, UInt16(clamping: cols), UInt16(clamping: rows)) }
        markChanged()
    }

    /// Delivers a signal to whatever is in the foreground (⌃C without the keyboard).
    func signalForeground(_ signal: Int32) {
        guard masterFD >= 0 else { return }
        let group = tcgetpgrp(masterFD)
        if group > 0 { kill(-group, signal) }
    }

    /// A user rename sticks; an empty name goes back to following the folder.
    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            info.customName = nil
            info.name = nameForFolder?(info.cwd, id) ?? info.name
        } else {
            info.customName = trimmed
            info.name = trimmed
        }
        markChanged()
    }

    func setOrder(_ order: Int) {
        guard info.order != order else { return }
        info.order = order
        markChanged()
    }

    private func sendInitialInput() {
        guard let input = initialInput else { return }
        initialInput = nil
        write(Data(input.utf8))
    }

    // MARK: - Output

    private func readOutput() {
        guard masterFD >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        // Bounded per wake-up so one busy session can't starve the others.
        for _ in 0..<32 {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(masterFD, $0.baseAddress, $0.count) }
            if count > 0 {
                process(Array(buffer[0..<count]))
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                // EAGAIN: drained. EIO/EOF: the shell side closed; the exit source cleans up.
                return
            }
        }
    }

    private func process(_ bytes: [UInt8]) {
        for event in promptScanner.scan(bytes) {
            switch event {
            case .promptStart:
                info.isCommandRunning = false
                if initialInput != nil { sendInitialInput() }
            case .commandStart:
                info.isCommandRunning = true
            case .commandEnd(let code):
                info.isCommandRunning = false
                info.lastExitCode = code
            }
        }
        terminal?.feed(byteArray: bytes)

        let visible = queryFilter.filter(bytes)
        seq &+= 1
        if !visible.isEmpty && !clients.isEmpty {
            let frame = Frame.output(session: id, seq: seq, bytes: Data(visible))
            for (key, client) in clients {
                if client.pendingBytes > Self.maxClientBacklog {
                    // Too far behind: drop it; it reattaches and gets a fresh snapshot.
                    clients.removeValue(forKey: key)
                    client.close()
                } else {
                    client.sendNow(frame)
                }
            }
        }
        let now = Date()
        lastOutput = now
        info.lastActivity = now
        isDirty = true
        refreshForeground(force: false)
        if let agent = info.agent, !programStatusActive, agent.state != .working {
            info.agent?.state = .working
            info.agent?.since = now
        }
        markChanged()
    }

    // MARK: - Agent awareness

    /// Called on output and from the daemon's 1 s tick.
    func refreshForeground(force: Bool) {
        guard masterFD >= 0 else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastForegroundCheck) > 0.25 else { return }
        lastForegroundCheck = now
        let foreground = ProcessInspector.foreground(masterFD: masterFD)
        let name = foreground?.name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if info.foreground != name {
            info.foreground = name
            markChanged()
        }
        let kind = foreground.flatMap { AgentKind(executable: $0.executable, arguments: $0.arguments) }
        if let kind, kind != info.agent?.kind {
            info.agent = AgentInfo(kind: kind, state: .working, since: now)
            programStatusActive = false
            markChanged()
        } else if kind == nil, info.agent != nil, foreground == nil || foreground?.pid == pid {
            // The shell is back in front: the agent exited. Other programs (an agent's
            // subprocess, a wrapper) keep what hooks or OSC 7501 reported.
            info.agent = nil
            programStatusActive = false
            markChanged()
        }
    }

    /// Without hooks or OSC 7501, output is the only signal: quiet for a while means waiting.
    func tick() {
        refreshForeground(force: true)
        guard var agent = info.agent, !programStatusActive, agent.state == .working else { return }
        if Date().timeIntervalSince(lastOutput) > 2 {
            agent.state = .idle
            agent.since = Date()
            if clients.isEmpty { agent.unseen = true }
            info.agent = agent
            markChanged()
        }
    }

    private func applyProgramStatus(_ records: [TerminalProgramStatus]) {
        guard let record = records.first(where: { $0.id.isEmpty }) ?? records.first else {
            programStatusActive = false
            return
        }
        programStatusActive = true
        let kind = info.agent?.kind
            ?? (record.effectiveApp ?? record.app).flatMap { AgentKind(executable: $0) }
        guard let kind else { return }
        var agent = info.agent ?? AgentInfo(kind: kind)
        let state: AgentState
        switch record.state {
        case .idle: state = .idle
        case .working: state = .working
        case .done: state = .done
        case .blocked: state = .needsInput
        case .error: state = .error
        }
        if agent.state != state { agent.since = Date() }
        agent.state = state
        agent.reason = record.kind?.rawValue
        agent.message = record.message ?? record.title
        if (state == .done || state == .needsInput || state == .error) && clients.isEmpty { agent.unseen = true }
        info.agent = agent
        markChanged()
    }

    /// An event from an agent's hook (`tethera hook <source>`), routed here by session id.
    /// Hook state is authoritative while the agent runs; output heuristics stand down.
    func applyHook(agent source: String, payload: String, sentAt: Double? = nil) {
        guard let update = HookMapper.update(source: source, payload: Data(payload.utf8)) else { return }
        // Background hooks can land out of order; an older event must not undo a newer state.
        if update.state != nil, let sentAt {
            if sentAt < lastHookAt { return }
            lastHookAt = sentAt
        }
        var agent = info.agent?.kind == update.kind ? info.agent! : AgentInfo(kind: update.kind)
        if let state = update.state {
            programStatusActive = true
            if agent.state != state { agent.since = Date() }
            agent.state = state
            agent.reason = state == .needsInput ? update.reason : nil
            if (state == .done || state == .needsInput || state == .error) && clients.isEmpty { agent.unseen = true }
            if state == .working { agent.unseen = false }
        }
        if let message = update.message { agent.message = message }
        if let tool = update.tool { agent.lastTool = tool.isEmpty ? nil : tool }
        if let model = update.model { agent.model = model }
        if let context = update.contextPercent { agent.contextPercent = context }
        if let cost = update.costUSD { agent.costUSD = cost }
        info.agent = agent
        markChanged()
    }

    // MARK: - Change notification

    private func markChanged() {
        isDirty = true
        guard !changePending else { return }
        changePending = true
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            changePending = false
            onChange?(self)
        }
    }

    func markSaved() {
        isDirty = false
    }

    // MARK: - TerminalDelegate

    func send(source: Terminal, data: ArraySlice<UInt8>) {
        if captured != nil {
            captured?.append(contentsOf: data)
        } else {
            write(Data(data))
        }
    }

    func setTerminalTitle(source: Terminal, title: String) {
        info.title = title
        markChanged()
    }

    func hostCurrentDirectoryUpdated(source: Terminal) {
        guard let raw = source.hostCurrentDirectory else { return }
        let path = URL(string: raw)?.path.removingPercentEncoding ?? raw
        guard !path.isEmpty, path != info.cwd else { return }
        info.cwd = path
        if info.customName == nil, let name = nameForFolder?(path, id) { info.name = name }
        markChanged()
    }

    func bell(source: Terminal) {
        info.attention &+= 1
        markChanged()
    }

    func notify(source: Terminal, title: String, body: String) {
        info.attention &+= 1
        info.lastNotification = body.isEmpty ? title : body
        markChanged()
    }

    func programStatusChanged(source: Terminal, records: [TerminalProgramStatus]) {
        applyProgramStatus(records)
    }

    func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
        cursorStyle = newStyle
    }

    func isProcessTrusted(source: Terminal) -> Bool { true }
}
