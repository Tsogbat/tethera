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
            let sourceCmd = "source '\(path)'\n"
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
    
    // MARK: - OSC 133 Parser
    private func parseOSCByte(_ byte: UInt8) {
        let char = Character(UnicodeScalar(byte))
        
        switch oscState {
        case .normal:
            if byte == 0x1B { // ESC
                oscState = .escape
            } else {
                outputBuffer.append(char)
            }
            
        case .escape:
            if byte == 0x5D { // ]
                oscState = .oscStart
                oscBuffer = ""
            } else {
                // Not an OSC sequence, add ESC + this char to output
                outputBuffer.append("\u{1B}")
                outputBuffer.append(char)
                oscState = .normal
            }
            
        case .oscStart, .oscContent:
            if byte == 0x07 { // BEL - end of OSC
                handleOSCSequence(oscBuffer)
                oscBuffer = ""
                oscState = .normal
            } else if byte == 0x1B { // ESC (might be ST terminator)
                // Check for ESC \ (ST) - just handle BEL for now
                oscBuffer.append(char)
            } else {
                oscBuffer.append(char)
                oscState = .oscContent
            }
        }
    }
    
    private func handleOSCSequence(_ content: String) {
        // Parse OSC 133 semantic prompts
        guard content.hasPrefix("133;") else { return }
        
        let params = String(content.dropFirst(4))
        let parts = params.split(separator: ";", maxSplits: 1)
        guard let marker = parts.first else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch marker {
            case "A": // Prompt start
                self.flushOutputBuffer()
                self.blockDelegate?.terminalDidStartPrompt()
                
            case "B": // Command start (user pressed Enter)
                self.blockDelegate?.terminalDidStartCommand()
                
            case "C": // Output start
                self.outputBuffer = "" // Clear buffer for new output
                
            case "D": // Command end
                self.flushOutputBuffer()
                var exitCode = 0
                if parts.count > 1, let code = Int(parts[1]) {
                    exitCode = code
                }
                self.blockDelegate?.terminalDidEndCommand(exitCode: exitCode)
                
            default:
                break
            }
        }
    }
    
    private func flushOutputBuffer() {
        guard !outputBuffer.isEmpty else { return }
        let output = outputBuffer
        outputBuffer = ""
        blockDelegate?.terminalDidReceiveOutput(output)
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