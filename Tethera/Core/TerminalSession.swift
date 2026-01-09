import Foundation
import Darwin

// MARK: - Block Event Protocol
protocol TerminalBlockDelegate: AnyObject {
    func terminalDidStartPrompt()
    func terminalDidStartCommand()
    func terminalDidReceiveOutput(_ output: String)
    func terminalDidEndCommand(exitCode: Int)
}

// MARK: - OSC Parser State
enum OSCParserState {
    case normal
    case escape           // After ESC
    case oscStart         // After ESC ]
    case oscContent       // Reading OSC content
    case oscST            // OSC ST terminator (ESC \)
    case csi              // CSI sequence (ESC [) - ANSI codes
    case charSet          // Character set (ESC ( or ESC ))
}

class TerminalSession: ObservableObject {
    // For SwiftTerm integration
    public let shellPath: String
    public let shellArgs: [String]
    @Published var isConnected = false
    @Published var terminalSize = TerminalSize(columns: 80, rows: 24)
    
    // Block delegate for semantic events
    weak var blockDelegate: TerminalBlockDelegate?
    
    // OSC parser state
    private var oscState: OSCParserState = .normal
    private var oscBuffer = ""
    private var outputBuffer = ""
    
    // Skip the first command (shell integration injection)
    private var skipNextCommand = true
    
    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var shellPID: pid_t = -1
    private var readQueue = DispatchQueue(label: "terminal.read", qos: .userInteractive)
    private var writeQueue = DispatchQueue(label: "terminal.write", qos: .userInteractive)
    
    private var readSource: DispatchSourceRead?
    private var isRunning = false
    
    // Shell integration script path
    private var shellIntegrationPath: String? {
        Bundle.main.path(forResource: "tethera", ofType: "zsh", inDirectory: "shell")
    }
    
    init() {
        let envShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellPath = envShell
        if envShell.contains("zsh") || envShell.contains("bash") {
            self.shellArgs = ["-l", "-i"]
        } else {
            self.shellArgs = []
        }
        setupTerminal()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupTerminal() {
        // Create PTY pair
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        
        let result = openpty(&masterFD, &slaveFD, nil, nil, nil)
        guard result == 0 else {
            print("Failed to create PTY: \(String(cString: strerror(errno)))")
            return
        }
        
        self.masterFD = masterFD
        self.slaveFD = slaveFD
        
        // Set non-blocking mode for master
        let flags = fcntl(masterFD, F_GETFL, 0)
        let _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)
        
        // Launch shell
        launchShell()
        
        // Start I/O handling
        startIOHandling()
    }
    
    private func launchShell() {
        // Get the user's default shell from environment
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        
        // Prepare arguments - use both -l (login) and -i (interactive) for zsh and bash
        let args: [String]
        if shellPath.contains("zsh") || shellPath.contains("bash") {
            args = [shellPath, "-l", "-i"]
        } else {
            args = [shellPath]
        }
        
        // Convert to C strings
        let cArgs = args.map { strdup($0) } + [nil]
        defer {
            cArgs.forEach { free($0) }
        }
        
        // Prepare environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLUMNS"] = String(terminalSize.columns)
        env["LINES"] = String(terminalSize.rows)
    // Force PATH to a standard value to ensure all commands are found
    let defaultPath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    env["PATH"] = defaultPath
        
        var cEnv: [UnsafeMutablePointer<Int8>?] = env.map { strdup("\($0.key)=\($0.value)") }
        cEnv.append(nil)
        defer {
            cEnv.forEach { free($0) }
        }
        
        // Set up file actions
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }
        
        // Redirect stdin, stdout, stderr to the slave PTY
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, slaveFD)
        
        // Spawn the shell process
        var pid: pid_t = 0
        let result = posix_spawn(&pid, shellPath, &fileActions, nil, cArgs, cEnv)
        
        if result == 0 {
            shellPID = pid
            close(slaveFD) // Close slave FD in parent process
            isConnected = true
            print("Shell launched successfully with PID: \(pid)")
            
            // Inject shell integration after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.injectShellIntegration(shellPath: shellPath)
            }
        } else {
            print("Failed to launch shell: \(String(cString: strerror(result)))")
            isConnected = false
        }
    }
    
    private func injectShellIntegration(shellPath: String) {
        // Find the appropriate integration script
        let scriptName: String
        if shellPath.contains("zsh") {
            scriptName = "tethera.zsh"
        } else if shellPath.contains("bash") {
            scriptName = "tethera.bash"
        } else {
            print("No shell integration available for: \(shellPath)")
            return
        }
        
        // Try multiple bundle lookup methods
        var scriptPath: String? = nil
        
        // Method 1: Bundle.module (SPM resources)
        #if SWIFT_PACKAGE
        scriptPath = Bundle.module.path(forResource: scriptName, ofType: nil, inDirectory: "shell")
        #endif
        
        // Method 2: Bundle.main with shell subdirectory
        if scriptPath == nil {
            scriptPath = Bundle.main.path(forResource: scriptName, ofType: nil, inDirectory: "shell")
        }
        
        // Method 3: Bundle.main resourcePath + shell
        if scriptPath == nil, let resourcePath = Bundle.main.resourcePath {
            let fullPath = (resourcePath as NSString).appendingPathComponent("shell/\(scriptName)")
            if FileManager.default.fileExists(atPath: fullPath) {
                scriptPath = fullPath
            }
        }
        
        if let path = scriptPath {
            // Source silently: redirect output and clear line
            // The \\r\\033[K clears the current line after sourcing
            let sourceCmd = "source '\(path)' >/dev/null 2>&1; clear\n"
            write(sourceCmd)
            print("Injected shell integration: \(path)")
        } else {
            print("Shell integration script not found in bundle: \(scriptName)")
            // Debug: print available resources
            if let resourcePath = Bundle.main.resourcePath {
                print("Bundle resourcePath: \(resourcePath)")
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                    print("Bundle contents: \(contents)")
                }
            }
        }
    }
    
    private func startIOHandling() {
        guard masterFD >= 0 else { return }
        
        isRunning = true
        
        // Create dispatch source for reading from PTY
        readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: readQueue)
        
        readSource?.setEventHandler { [weak self] in
            self?.handleRead()
        }
        
        readSource?.setCancelHandler { [weak self] in
            self?.handleCancel()
        }
        
        readSource?.resume()
    }
    
    private func handleRead() {
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        let bytesRead = read(masterFD, &buffer, bufferSize)
        if bytesRead > 0 {
            let data = Data(buffer.prefix(bytesRead))
            
            // Parse bytes for OSC sequences
            for byte in data {
                parseOSCByte(byte)
            }
            
            // Also broadcast raw data for SwiftTerm/traditional terminal
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                NotificationCenter.default.post(
                    name: .terminalDataReceived,
                    object: data
                )
            }
        } else if bytesRead == 0 {
            DispatchQueue.main.async {
                self.isConnected = false
            }
        }
    }
    
    // MARK: - OSC 133 Parser (also strips ANSI/CSI sequences)
    private func parseOSCByte(_ byte: UInt8) {
        switch oscState {
        case .normal:
            if byte == 0x1B { // ESC
                oscState = .escape
            } else if byte >= 0x20 && byte < 0x7F { // Printable ASCII
                outputBuffer.append(Character(UnicodeScalar(byte)))
            } else if byte == 0x0A || byte == 0x0D || byte == 0x09 { // LF, CR, TAB
                outputBuffer.append(Character(UnicodeScalar(byte)))
            }
            // Ignore other control characters
            
        case .escape:
            if byte == 0x5D { // ] - OSC sequence
                oscState = .oscStart
                oscBuffer = ""
            } else if byte == 0x5B { // [ - CSI sequence (ANSI codes)
                oscState = .csi
            } else if byte == 0x28 || byte == 0x29 { // ( or ) - character set
                oscState = .charSet
            } else {
                // Single-char escape sequence, return to normal
                oscState = .normal
            }
            
        case .oscStart, .oscContent:
            if byte == 0x07 { // BEL - end of OSC
                handleOSCSequence(oscBuffer)
                oscBuffer = ""
                oscState = .normal
            } else if byte == 0x1B { // ESC (might be ST terminator ESC \)
                oscState = .oscST
            } else {
                oscBuffer.append(Character(UnicodeScalar(byte)))
                oscState = .oscContent
            }
            
        case .oscST:
            // ESC \ is the String Terminator for OSC
            if byte == 0x5C { // backslash
                handleOSCSequence(oscBuffer)
                oscBuffer = ""
            }
            oscState = .normal
            
        case .csi:
            // CSI sequences end with a letter (0x40-0x7E)
            if byte >= 0x40 && byte <= 0x7E {
                oscState = .normal
            }
            // Stay in CSI state for parameters (0x30-0x3F) and intermediates (0x20-0x2F)
            
        case .charSet:
            // Character set designation is single byte after ESC ( or ESC )
            oscState = .normal
        }
    }
    
    private func handleOSCSequence(_ content: String) {
        // Parse OSC 133 semantic prompts
        guard content.hasPrefix("133;") else { return }
        
        let params = String(content.dropFirst(4))
        let parts = params.split(separator: ";", maxSplits: 1)
        guard let marker = parts.first else { return }
        
        print("[OSC] Marker: \(marker), buffered output length: \(outputBuffer.count)")
        
        switch marker {
        case "A": // Prompt start - clear buffer, notify delegate
            outputBuffer = ""
            DispatchQueue.main.async { [weak self] in
                self?.blockDelegate?.terminalDidStartPrompt()
            }
            
        case "B": // Command start - clear any prompt text that was captured
            outputBuffer = ""
            DispatchQueue.main.async { [weak self] in
                self?.blockDelegate?.terminalDidStartCommand()
            }
            
        case "C": // Output start - actual command output begins now
            outputBuffer = ""
            
        case "D": // Command end - send captured output
            // Skip the first command (shell integration injection)
            if skipNextCommand {
                skipNextCommand = false
                outputBuffer = ""
                print("[OSC] Skipping injection command output")
                return
            }
            
            let capturedOutput = outputBuffer
            outputBuffer = ""
            
            // Clean output: remove % prompt markers and trim
            var cleanedOutput = capturedOutput
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove trailing % (zsh prompt marker)
            while cleanedOutput.hasSuffix("%") {
                cleanedOutput = String(cleanedOutput.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Remove leading % 
            while cleanedOutput.hasPrefix("%") {
                cleanedOutput = String(cleanedOutput.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            var exitCode = 0
            if parts.count > 1, let code = Int(parts[1]) {
                exitCode = code
            }
            print("[OSC] Command end with exit code: \(exitCode), output: \(cleanedOutput.prefix(100))...")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !cleanedOutput.isEmpty {
                    self.blockDelegate?.terminalDidReceiveOutput(cleanedOutput)
                }
                self.blockDelegate?.terminalDidEndCommand(exitCode: exitCode)
            }
            
        default:
            break
        }
    }
    
    private func flushOutputBuffer() {
        // Not used - see handleOSCSequence
    }
    
    private func handleCancel() {
        // Handle read source cancellation
    }
    
    func write(_ data: Data) {
        guard masterFD >= 0 && isConnected else { return }
        
        writeQueue.async { [weak self] in
            guard let self = self else { return }
            _ = data.withUnsafeBytes { bytes in
                Darwin.write(self.masterFD, bytes.baseAddress, data.count)
            }
        }
    }
    
    func write(_ string: String) {
        write(Data(string.utf8))
    }
    
    func resizeTerminal(columns: Int, rows: Int) {
        terminalSize = TerminalSize(columns: columns, rows: rows)
        
        guard masterFD >= 0 else { return }
        
        var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        let _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }
    
    private func cleanup() {
        isRunning = false
        
        readSource?.cancel()
        readSource = nil
        
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        
        if shellPID > 0 {
            kill(shellPID, SIGTERM)
            waitpid(shellPID, nil, 0)
            shellPID = -1
        }
        
        isConnected = false
    }
}

struct TerminalSize {
    let columns: Int
    let rows: Int
}

extension Notification.Name {
    static let terminalDataReceived = Notification.Name("terminalDataReceived")
}