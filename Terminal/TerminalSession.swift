import Foundation
import Darwin

class TerminalSession: ObservableObject {
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
        fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)
        
        // Launch shell
        launchShell()
        
        // Start I/O handling
        startIOHandling()
    }
    
    private func launchShell() {
        // For now, we'll simulate a shell connection
        // In a real implementation, you'd use posix_spawn or similar
        print("Shell simulation: Would launch \(ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")")
        
        // Simulate successful connection
        shellPID = 12345 // Dummy PID
        close(slaveFD)
        isConnected = true
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
                unistd.write(self.masterFD, bytes.baseAddress, data.count)
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
        ioctl(masterFD, TIOCSWINSZ, &ws)
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
