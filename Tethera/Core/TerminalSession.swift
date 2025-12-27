import Foundation
import Darwin

class TerminalSession: ObservableObject {
    // For SwiftTerm integration
    public let shellPath: String
    public let shellArgs: [String]
    @Published var isConnected = false
    @Published var terminalSize = TerminalSize(columns: 80, rows: 24)
    
    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var shellPID: pid_t = -1
    private var readQueue = DispatchQueue(label: "terminal.read", qos: .userInteractive)
    private var writeQueue = DispatchQueue(label: "terminal.write", qos: .userInteractive)
    
    private var readSource: DispatchSourceRead?
    private var isRunning = false
    
    init() {
        // Set up shell path and args for SwiftTerm
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
        } else {
            print("Failed to launch shell: \(String(cString: strerror(result)))")
            isConnected = false
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
            DispatchQueue.main.async {
                // Send data to terminal buffer for processing
                NotificationCenter.default.post(
                    name: .terminalDataReceived,
                    object: data
                )
            }
        } else if bytesRead == 0 {
            // EOF - shell process ended
            DispatchQueue.main.async {
                self.isConnected = false
            }
        }
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