import Foundation
import SwiftUI
import Combine
import OSLog

/// Text the input bar should adopt (AI suggestions, "Insert", history search).
struct InputInsertion: Equatable {
    let id = UUID()
    let text: String
    var selectAll = false
}

enum LivePresentation: Equatable {
    case inline
    case fullPane
}

enum ShellState: Equatable {
    case starting
    case ready
    case exited
}

struct ScrollRequest: Equatable {
    enum Anchor { case bottom, center }
    let id: UUID
    let anchor: Anchor
    let nonce = UUID()
}

enum GenerationState: Equatable {
    case idle
    case loading(String)
    case failed(AgentFailure)
}

/// One terminal session: its shell, emulator, blocks and AI requests.
@MainActor
final class BlockTerminalViewModel: ObservableObject, ShellSessionDelegate {
    @Published private(set) var blocks: [TerminalBlock] = []
    @Published private(set) var workingDirectory: String
    @Published private(set) var gitInfo: GitInfo?
    @Published private(set) var runningBlockID: UUID?
    @Published private(set) var presentation: LivePresentation = .inline
    @Published private(set) var runningAgent: AgentCLI?
    @Published private(set) var shellState: ShellState = .starting
    @Published private(set) var title: String = "Terminal"
    @Published var selectedBlockID: UUID?
    @Published private(set) var scrollRequest: ScrollRequest?
    @Published var aiModeSticky = false
    @Published private(set) var insertion: InputInsertion?
    @Published private(set) var generation: GenerationState = .idle
    @Published private(set) var aiGhost: String?
    @Published private(set) var attachedBlockIDs: [UUID] = []
    @Published private(set) var focusEditorToken = 0
    @Published private(set) var focusTerminalToken = 0
    @Published private(set) var integrationMissing = false

    let live = LiveTerminal()
    var onAttention: ((String) -> Void)?
    var onCloseRequest: (() -> Void)?
    var tabID: UUID?

    private var session: ShellSession?
    private var commandStartTime: Date?
    private var commandStarted = false
    private var preCommandBytes: [UInt8] = []
    private var startupBytes: [UInt8] = []
    private var queuedCommand: String?
    private var historyIndex: Int?
    private var historyDraft = ""
    private var lastExchange: (question: String, answer: String)?
    /// Set once a provider turns out to be missing or signed out, so failures don't nag on every command.
    private var autoFixSuspended = false
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var generationTask: Task<Void, Never>?
    private var gitTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.tethera.app", category: "BlockTerminalViewModel")

    private var settings: UserSettings { UserSettings.shared }

    init(workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.workingDirectory = workingDirectory
        configureLiveTerminal()
        startShell()
        refreshGit()
        updateTitle()

        settings.$themeConfiguration
            .combineLatest(settings.$terminal)
            .receive(on: RunLoop.main)
            .sink { [weak self] theme, terminal in
                self?.applyAppearance(theme: theme, terminal: terminal)
            }
            .store(in: &cancellables)
    }

    // MARK: - Shell lifecycle

    private func startShell() {
        let session = ShellSession(shellPath: settings.terminal.resolvedShell)
        session.delegate = self
        self.session = session
        shellState = .starting
        startupBytes.removeAll()
        session.start(workingDirectory: workingDirectory, columns: live.columns, rows: live.rows)
        if !session.isRunning {
            shellState = .exited
            appendSystemBlock("Couldn't start \(session.shellPath).", isError: true)
            return
        }
        // If the integration never reports a prompt, say so instead of hanging silently.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self, weak session] in
            guard let self, let session, session === self.session, self.shellState == .starting else { return }
            self.integrationMissing = true
            self.shellState = .ready
            let startup = ANSIStripper.strip(String(decoding: self.startupBytes, as: UTF8.self))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var message = "Shell integration didn't load, so commands won't split into blocks. Check your shell startup files for prompts waiting on input."
            if !startup.isEmpty { message += "\n\n" + String(startup.suffix(1_500)) }
            self.appendSystemBlock(message, isError: true)
            if let command = self.queuedCommand {
                self.queuedCommand = nil
                session.submit(command)
            }
        }
    }

    func restartShell() {
        session?.terminate()
        session = nil
        if runningBlockID != nil { finishRunningBlock(exitCode: nil) }
        integrationMissing = false
        startShell()
    }

    func shutdown() {
        tasks.values.forEach { $0.cancel() }
        generationTask?.cancel()
        session?.terminate()
        session = nil
    }

    private func configureLiveTerminal() {
        live.onInput = { [weak self] bytes in
            self?.session?.send(bytes)
        }
        live.onResize = { [weak self] columns, rows in
            self?.session?.resize(columns: columns, rows: rows)
        }
        live.onBell = { [weak self] in
            guard let self, self.runningBlockID != nil else { return }
            self.onAttention?(self.runningAgent.map { "\($0.displayName) needs your attention" } ?? "Command needs your attention")
        }
        live.onTitle = { [weak self] _ in
            self?.updateTitle()
        }
        applyAppearance(theme: settings.themeConfiguration, terminal: settings.terminal)
    }

    private func applyAppearance(theme: ThemeConfiguration, terminal: TerminalPreferences) {
        let font = TerminalFont.nsFont(family: theme.fontFamily, size: CGFloat(theme.fontSize))
        live.applyAppearance(font: font,
                             palette: theme.effectivePalette,
                             caret: theme.accentColor.nsColor,
                             cursorStyle: terminal.cursorShape.swiftTermStyle(blink: terminal.cursorBlink),
                             optionAsMeta: terminal.optionAsMeta,
                             scrollbackLines: terminal.scrollbackLines)
    }

    /// Called by the pane with its size; keeps the PTY matched to what's on screen.
    func updatePaneSize(_ size: CGSize) {
        let width = size.width - Layout.paneGutter * 2 - Layout.blockInsetH * 2
        let height = size.height - Layout.fullPaneHeader - 12
        live.setGeometry(width: width, height: height)
    }

    // MARK: - ShellSessionDelegate

    func shellSession(_ session: ShellSession, didReceive event: OSC133Splitter.Event) {
        guard session === self.session else { return }
        switch event {
        case .bytes(let region, let bytes):
            route(bytes, region: region)
        case .promptStart:
            handlePromptStart()
        case .commandStart:
            commandStarted = true
        case .outputStart:
            break
        case .commandEnd(let exitCode):
            if runningBlockID != nil {
                finishRunningBlock(exitCode: exitCode)
            }
        case .workingDirectory(let path):
            updateWorkingDirectory(path)
        case .bracketedPaste:
            break
        case .notification(let message):
            onAttention?(message)
        }
    }

    func shellSessionDidExit(_ session: ShellSession, status: Int32?) {
        guard session === self.session else { return }
        if runningBlockID != nil {
            finishRunningBlock(exitCode: nil)
        }
        shellState = .exited
        appendSystemBlock("The shell exited. Press Restart to start a new one.", isError: false, restartable: true)
    }

    private func route(_ bytes: [UInt8], region: OSC133Splitter.Region) {
        switch region {
        case .output:
            if runningBlockID != nil { live.feed(bytes[...]) }
        case .prompt, .input:
            if runningBlockID != nil && !commandStarted && preCommandBytes.count < 16_384 {
                preCommandBytes.append(contentsOf: bytes)
            }
        case .startup:
            if integrationMissing, runningBlockID != nil {
                live.feed(bytes[...])
            } else if startupBytes.count < 32_768 {
                startupBytes.append(contentsOf: bytes)
            }
        case .idle:
            break
        }
    }

    private func handlePromptStart() {
        let wasStarting = shellState == .starting
        shellState = .ready
        integrationMissing = false
        if runningBlockID != nil && !commandStarted && !wasStarting && queuedCommand == nil {
            // The line never ran (parse error, unclosed quote cancelled with ⌃C …).
            let text = Self.lineEditorResidue(preCommandBytes)
            finishRunningBlock(exitCode: 1, fallbackOutput: text.isEmpty ? "The command didn't run." : text)
        }
        if let command = queuedCommand {
            queuedCommand = nil
            session?.submit(command)
        }
    }

    /// What zsh/bash printed between accepting a line and the next prompt, minus the echo.
    private static func lineEditorResidue(_ bytes: [UInt8]) -> String {
        let text = ANSIStripper.strip(String(decoding: bytes, as: UTF8.self))
        var lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if !lines.isEmpty { lines.removeFirst() } // the echoed command line
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: - Running commands

    var isRunning: Bool { runningBlockID != nil }

    /// A command, AI request or shell startup is still in flight.
    var isBusy: Bool {
        isRunning || shellState == .starting || !tasks.isEmpty || generation != .idle
    }

    #if DEBUG
    func debugSendKeys(_ keys: String) {
        session?.send(keys)
    }

    var debugPTYSize: String {
        session.map { "\($0.windowColumns)x\($0.windowRows)" } ?? "none"
    }
    #endif

    var runningBlock: TerminalBlock? {
        guard let id = runningBlockID else { return nil }
        return blocks.first { $0.id == id }
    }

    func submit(_ input: String) {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, runningBlockID == nil else { return }
        resetHistoryNavigation()
        aiGhost = nil

        switch command {
        case "clear", "cls", "reset":
            clearBlocks()
            return
        case "exit", "quit", "logout":
            onCloseRequest?()
            return
        default:
            break
        }
        if command.hasPrefix("preview ") || command.hasPrefix("show ") {
            handlePreviewCommand(command)
            return
        }

        let block = TerminalBlock(status: .running, input: command, workingDirectory: workingDirectory, gitBranch: gitInfo?.branch)
        withAnimation(Motion.smooth) {
            blocks.append(block)
        }
        start(blockID: block.id, command: command)
    }

    /// Runs a block's command again in place.
    func rerun(blockID: UUID, command: String? = nil) {
        guard runningBlockID == nil, let index = index(of: blockID) else { return }
        let text = (command ?? blocks[index].input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        blocks[index].input = text
        blocks[index].status = .running
        blocks[index].output = ""
        blocks[index].styledOutput = nil
        blocks[index].success = nil
        blocks[index].exitCode = nil
        blocks[index].durationMs = nil
        blocks[index].timestamp = Date()
        blocks[index].workingDirectory = workingDirectory
        blocks[index].gitBranch = gitInfo?.branch
        blocks[index].category = CommandCategory.categorize(text)
        blocks[index].fix = .idle
        blocks[index].explanation = .idle
        blocks[index].outputVersion += 1
        start(blockID: blockID, command: text)
    }

    private func start(blockID: UUID, command: String) {
        runningBlockID = blockID
        selectedBlockID = nil
        commandStarted = false
        preCommandBytes.removeAll()
        commandStartTime = Date()
        runningAgent = AgentCLI(programName: CommandLineParser.programName(of: command))
        let interactive = InteractivePrograms.isInteractive(command)
        withAnimation(Motion.snappy) {
            presentation = interactive ? .fullPane : .inline
        }
        live.view.forwardsScrollWheel = !interactive
        live.beginRun()
        scrollRequest = ScrollRequest(id: blockID, anchor: .bottom)
        updateTitle()

        if shellState == .ready, let session {
            session.submit(command)
        } else {
            queuedCommand = command
        }

        if interactive {
            focusTerminalToken += 1
        } else {
            // Quick commands finish before the user notices; only hand keys over if it keeps running.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.runningBlockID == blockID else { return }
                self.focusTerminalToken += 1
            }
        }
    }

    private func finishRunningBlock(exitCode: Int32?, fallbackOutput: String? = nil) {
        guard let id = runningBlockID, let index = index(of: id) else {
            runningBlockID = nil
            return
        }
        let snapshot = live.snapshot()
        var block = blocks[index]
        if snapshot.isEmpty, let fallbackOutput {
            block.styledOutput = StyledText(plain: fallbackOutput)
            block.output = fallbackOutput
        } else {
            block.styledOutput = snapshot.isEmpty ? nil : snapshot
            block.output = snapshot.plainText
        }
        block.status = .finished
        block.exitCode = exitCode
        block.success = exitCode.map { $0 == 0 }
        if let start = commandStartTime {
            block.durationMs = Int64(Date().timeIntervalSince(start) * 1000)
        }
        block.outputVersion += 1
        // Leaving an agent or TUI (⌃C, :cq …) exits non-zero but isn't a failure to fix.
        let wasInteractive = presentation == .fullPane || InteractivePrograms.isInteractive(block.input)

        withAnimation(Motion.snappy) {
            blocks[index] = block
            runningBlockID = nil
            presentation = .inline
            runningAgent = nil
        }
        live.view.forwardsScrollWheel = true
        commandStartTime = nil
        CommandHistoryManager.shared.addEntry(from: block, tabId: tabID)
        refreshGit()
        updateTitle()
        scrollRequest = ScrollRequest(id: id, anchor: .bottom)
        focusEditorToken += 1

        if block.isFailure, !block.wasInterrupted, !wasInteractive, !autoFixSuspended,
           settings.aiSettings.isEnabled, settings.aiSettings.autoFixOnFailure {
            requestFix(blockID: id, automatic: true)
        }
    }

    func interrupt() {
        session?.interrupt()
    }

    /// Cancels a command that is still waiting for the shell (e.g. the shell is busy).
    func stopRunning() {
        if queuedCommand != nil {
            queuedCommand = nil
            finishRunningBlock(exitCode: 130, fallbackOutput: "Cancelled before it started.")
        } else {
            interrupt()
        }
    }

    func togglePresentation() {
        guard runningBlockID != nil else { return }
        withAnimation(Motion.snappy) {
            presentation = presentation == .fullPane ? .inline : .fullPane
        }
        live.view.forwardsScrollWheel = presentation == .inline
        focusTerminalToken += 1
    }

    // MARK: - Built-ins

    func clearBlocks() {
        guard runningBlockID == nil else { return }
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        withAnimation(Motion.smooth) {
            blocks.removeAll()
        }
        selectedBlockID = nil
        attachedBlockIDs.removeAll()
        aiGhost = nil
    }

    func removeBlock(_ id: UUID) {
        guard id != runningBlockID else { return }
        tasks[id]?.cancel()
        withAnimation(Motion.smooth) {
            blocks.removeAll { $0.id == id }
        }
        attachedBlockIDs.removeAll { $0 == id }
    }

    private func handlePreviewCommand(_ command: String) {
        let start = Date()
        var block = TerminalBlock(input: command, workingDirectory: workingDirectory, gitBranch: gitInfo?.branch)
        if let result = MediaService.shared.parsePreviewCommandDetailed(command, workingDirectory: workingDirectory) {
            if !result.urls.isEmpty {
                var lines = ["Previewing " + result.urls.map(\.lastPathComponent).joined(separator: ", ")]
                lines += result.errors.map { "· \($0)" }
                block.output = lines.joined(separator: "\n")
                block.mediaFiles = result.urls.map(\.path)
                block.success = true
                block.exitCode = 0
            } else {
                block.output = result.errors.isEmpty ? "No previewable files found" : result.errors.joined(separator: "\n")
                block.success = false
                block.exitCode = 1
            }
        } else {
            block.output = "Usage: preview <image…>"
            block.success = false
            block.exitCode = 1
        }
        block.styledOutput = StyledText(plain: block.output)
        block.durationMs = Int64(Date().timeIntervalSince(start) * 1000)
        withAnimation(Motion.smooth) {
            blocks.append(block)
        }
        CommandHistoryManager.shared.addEntry(from: block, tabId: tabID)
        scrollRequest = ScrollRequest(id: block.id, anchor: .bottom)
    }

    private func appendSystemBlock(_ message: String, isError: Bool, restartable: Bool = false) {
        var block = TerminalBlock(kind: .system, input: restartable ? "restart" : "", output: message,
                                  workingDirectory: workingDirectory, success: !isError)
        block.styledOutput = StyledText(plain: message)
        withAnimation(Motion.smooth) {
            blocks.append(block)
        }
        scrollRequest = ScrollRequest(id: block.id, anchor: .bottom)
    }

    // MARK: - Working directory & git

    private func updateWorkingDirectory(_ path: String) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
              path != workingDirectory else { return }
        workingDirectory = path
        refreshGit()
        updateTitle()
    }

    func refreshGit() {
        gitTask?.cancel()
        let directory = workingDirectory
        gitTask = Task { [weak self] in
            let info = await GitService.info(for: directory)
            guard !Task.isCancelled, let self, self.workingDirectory == directory else { return }
            if self.gitInfo != info {
                withAnimation(Motion.snappy) { self.gitInfo = info }
            }
        }
    }

    var displayWorkingDirectory: String {
        Self.abbreviate(workingDirectory)
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func updateTitle() {
        let newTitle: String
        if let agent = runningAgent {
            newTitle = agent.displayName
        } else if let block = runningBlock {
            newTitle = CommandLineParser.programName(of: block.input).isEmpty ? "Terminal" : CommandLineParser.programName(of: block.input)
        } else {
            let display = displayWorkingDirectory
            newTitle = display == "~" ? "~" : (display as NSString).lastPathComponent
        }
        if newTitle != title { title = newTitle }
    }

    // MARK: - History navigation

    func historyPrevious(currentInput: String) -> String? {
        let history = CommandHistoryManager.shared.navigationHistory
        guard !history.isEmpty else { return nil }
        if let index = historyIndex {
            guard index > 0 else { return history[0] }
            historyIndex = index - 1
        } else {
            historyDraft = currentInput
            historyIndex = history.count - 1
        }
        return historyIndex.map { history[$0] }
    }

    func historyNext() -> String? {
        let history = CommandHistoryManager.shared.navigationHistory
        guard let index = historyIndex else { return nil }
        if index < history.count - 1 {
            historyIndex = index + 1
            return history[index + 1]
        }
        historyIndex = nil
        return historyDraft
    }

    private func resetHistoryNavigation() {
        historyIndex = nil
        historyDraft = ""
    }

    // MARK: - Selection & navigation

    func index(of id: UUID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    func block(_ id: UUID) -> TerminalBlock? {
        blocks.first { $0.id == id }
    }

    func select(_ id: UUID?) {
        withAnimation(Motion.quick) { selectedBlockID = id }
    }

    func selectAdjacent(_ offset: Int) {
        guard !blocks.isEmpty else { return }
        let current = selectedBlockID.flatMap(index(of:)) ?? blocks.count
        let next = min(max(current + offset, 0), blocks.count - 1)
        select(blocks[next].id)
        scrollRequest = ScrollRequest(id: blocks[next].id, anchor: .bottom)
    }

    func reveal(_ id: UUID) {
        guard index(of: id) != nil else { return }
        select(id)
        scrollRequest = ScrollRequest(id: id, anchor: .center)
    }

    func copySelectedBlock() -> Bool {
        guard let id = selectedBlockID, let block = block(id) else { return false }
        let text = block.output.isEmpty ? block.input : "$ \(block.input)\n\(block.output)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    // MARK: - Input bar coordination

    func insert(_ text: String, selectAll: Bool = false) {
        insertion = InputInsertion(text: text, selectAll: selectAll)
        focusEditorToken += 1
    }

    func dismissAIGhost() {
        if aiGhost != nil { aiGhost = nil }
    }

    // MARK: - AI

    var aiEnabled: Bool { settings.aiSettings.isEnabled }

    func toggleAttachment(_ id: UUID) {
        withAnimation(Motion.snappy) {
            if let index = attachedBlockIDs.firstIndex(of: id) {
                attachedBlockIDs.remove(at: index)
            } else if block(id) != nil {
                attachedBlockIDs.append(id)
            }
        }
    }

    /// Natural language → one command, placed in the editor (never run).
    func generateCommand(from request: String) {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        generationTask?.cancel()
        withAnimation(Motion.snappy) { generation = .loading(trimmed) }
        let context = makeContext(includeBlocks: true)
        generationTask = Task { [weak self] in
            for await event in AIAssistant.shared.generateCommand(trimmed, context: context) {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .update:
                    break
                case .finished(let text):
                    if let command = CommandSanitizer.command(from: text) {
                        withAnimation(Motion.snappy) { self.generation = .idle }
                        self.insert(command, selectAll: false)
                    } else {
                        withAnimation(Motion.snappy) {
                            self.generation = .failed(AgentFailure(kind: .failed, message: "No command came back for that request.", hint: "Try rephrasing it."))
                        }
                    }
                case .failed(let failure):
                    if failure.kind != .cancelled {
                        withAnimation(Motion.snappy) { self.generation = .failed(failure) }
                    }
                }
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        withAnimation(Motion.snappy) { generation = .idle }
    }

    /// Asks a question; the answer streams into a new AI block.
    func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let provider = settings.aiSettings.provider
        let context = makeContext(includeBlocks: true)
        var block = TerminalBlock(kind: .ai, status: .running, input: trimmed, workingDirectory: workingDirectory, aiProvider: provider)
        block.styledOutput = nil
        let id = block.id
        withAnimation(Motion.smooth) {
            blocks.append(block)
            attachedBlockIDs.removeAll()
        }
        scrollRequest = ScrollRequest(id: id, anchor: .bottom)

        tasks[id] = Task { [weak self] in
            for await event in AIAssistant.shared.ask(trimmed, context: context) {
                guard let self, !Task.isCancelled, let index = self.index(of: id) else { return }
                switch event {
                case .update(let text):
                    self.blocks[index].output = text
                    self.blocks[index].outputVersion += 1
                case .finished(let text):
                    withAnimation(Motion.snappy) {
                        self.blocks[index].output = text
                        self.blocks[index].status = .finished
                        self.blocks[index].success = true
                        self.blocks[index].outputVersion += 1
                    }
                    self.lastExchange = (trimmed, text)
                case .failed(let failure):
                    withAnimation(Motion.snappy) {
                        self.blocks[index].status = .finished
                        self.blocks[index].success = false
                        self.blocks[index].aiError = failure.kind == .cancelled ? "Stopped." : failure.message
                        self.blocks[index].aiHint = failure.hint
                        self.blocks[index].outputVersion += 1
                    }
                }
            }
            self?.tasks[id] = nil
        }
    }

    func stopAI(blockID: UUID) {
        tasks[blockID]?.cancel()
        tasks[blockID] = nil
        guard let index = index(of: blockID), blocks[index].status == .running else { return }
        withAnimation(Motion.snappy) {
            blocks[index].status = .finished
            blocks[index].success = blocks[index].output.isEmpty ? false : true
            if blocks[index].output.isEmpty { blocks[index].aiError = "Stopped." }
        }
    }

    func requestFix(blockID: UUID, automatic: Bool = false) {
        guard let block = block(blockID), block.kind == .command else { return }
        let key = Self.fixTaskKey(blockID)
        tasks[key]?.cancel()
        setFix(.loading, for: blockID)
        let context = makeContext(includeBlocks: false)
        tasks[key] = Task { [weak self] in
            for await event in AIAssistant.shared.suggestFix(command: block.input, exitCode: block.exitCode, output: block.output, context: context) {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .update:
                    break
                case .finished(let text):
                    if let command = CommandSanitizer.command(from: text), command != block.input {
                        self.setFix(.ready(command), for: blockID)
                        if self.blocks.last(where: { $0.kind == .command })?.id == blockID && self.runningBlockID == nil {
                            self.aiGhost = command
                        }
                    } else {
                        self.setFix(.idle, for: blockID)
                    }
                case .failed(let failure):
                    if automatic && (failure.kind == .notInstalled || failure.kind == .notSignedIn) {
                        self.autoFixSuspended = true
                    }
                    self.setFix(failure.kind == .cancelled ? .idle : .failed(failure.hint ?? failure.message), for: blockID)
                }
            }
            self?.tasks[key] = nil
        }
    }

    func explain(blockID: UUID) {
        guard let block = block(blockID), block.kind == .command else { return }
        let key = Self.explainTaskKey(blockID)
        tasks[key]?.cancel()
        setExplanation(.loading, for: blockID)
        let context = makeContext(includeBlocks: false)
        tasks[key] = Task { [weak self] in
            for await event in AIAssistant.shared.explain(command: block.input, exitCode: block.exitCode, output: block.output, context: context) {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .update(let text):
                    self.setExplanation(.ready(text), for: blockID, animated: false)
                case .finished(let text):
                    self.setExplanation(.ready(text), for: blockID)
                case .failed(let failure):
                    self.setExplanation(failure.kind == .cancelled ? .idle : .failed(failure.hint ?? failure.message), for: blockID)
                }
            }
            self?.tasks[key] = nil
        }
    }

    func dismissExplanation(blockID: UUID) {
        tasks[Self.explainTaskKey(blockID)]?.cancel()
        setExplanation(.idle, for: blockID)
    }

    func dismissFix(blockID: UUID) {
        tasks[Self.fixTaskKey(blockID)]?.cancel()
        setFix(.idle, for: blockID)
        aiGhost = nil
    }

    /// Opens an interactive agent in this pane, seeded with a block's context.
    func sendToAgent(_ agent: AgentCLI, blockID: UUID?) {
        guard runningBlockID == nil else { return }
        var prompt: String?
        if let blockID, let block = block(blockID) {
            let output = AIContext.tail(block.output, maxLines: 40, maxCharacters: 2_500)
            let status = block.exitCode.map { " (exit code \($0))" } ?? ""
            prompt = "In \(displayWorkingDirectory) I ran `\(block.input)`\(status). Output:\n\(output)\n\nHelp me with this."
        }
        submit(agent.interactiveCommand(prompt: prompt))
    }

    func launchAgent(_ agent: AgentCLI) {
        sendToAgent(agent, blockID: nil)
    }

    private func setFix(_ state: TerminalBlock.AIState, for id: UUID) {
        guard let index = index(of: id) else { return }
        withAnimation(Motion.smooth) { blocks[index].fix = state }
    }

    private func setExplanation(_ state: TerminalBlock.AIState, for id: UUID, animated: Bool = true) {
        guard let index = index(of: id) else { return }
        if animated {
            withAnimation(Motion.smooth) { blocks[index].explanation = state }
        } else {
            blocks[index].explanation = state
        }
    }

    private static func fixTaskKey(_ id: UUID) -> UUID {
        UUID(uuid: (id.uuid.0 ^ 0xF1, id.uuid.1, id.uuid.2, id.uuid.3, id.uuid.4, id.uuid.5, id.uuid.6, id.uuid.7,
                    id.uuid.8, id.uuid.9, id.uuid.10, id.uuid.11, id.uuid.12, id.uuid.13, id.uuid.14, id.uuid.15))
    }

    private static func explainTaskKey(_ id: UUID) -> UUID {
        UUID(uuid: (id.uuid.0 ^ 0xE2, id.uuid.1, id.uuid.2, id.uuid.3, id.uuid.4, id.uuid.5, id.uuid.6, id.uuid.7,
                    id.uuid.8, id.uuid.9, id.uuid.10, id.uuid.11, id.uuid.12, id.uuid.13, id.uuid.14, id.uuid.15))
    }

    private func makeContext(includeBlocks: Bool) -> AIContext {
        var context = AIContext(shell: session?.shellPath ?? ShellEnvironment.loginShell, workingDirectory: workingDirectory)
        context.gitBranch = gitInfo?.branch
        context.gitDirty = gitInfo?.isDirty ?? false
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: workingDirectory) {
            context.directoryListing = entries.filter { !$0.hasPrefix(".") }.sorted().prefix(40).map { $0 }
        }
        let commandBlocks = blocks.filter { $0.kind == .command && $0.status == .finished }
        context.recentCommands = commandBlocks.suffix(6).map(\.input)
        if includeBlocks {
            var selected: [TerminalBlock] = attachedBlockIDs.compactMap(block(_:))
            if settings.aiSettings.includeOutputContext {
                let recent = commandBlocks.suffix(max(0, settings.aiSettings.contextBlockCount))
                selected += recent.filter { candidate in !selected.contains { $0.id == candidate.id } }
            }
            context.blocks = selected.map {
                let attached = attachedBlockIDs.contains($0.id)
                return AIContext.BlockSummary(command: $0.input, exitCode: $0.exitCode,
                                              output: AIContext.tail($0.output, maxLines: attached ? 120 : 30, maxCharacters: attached ? 5_000 : 1_200))
            }
        }
        context.previousExchange = lastExchange
        return context
    }
}
