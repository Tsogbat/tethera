import SwiftUI
import SwiftTerm

struct ContentView: View {
    @StateObject private var terminalSession = TerminalSession()
    var body: some View {
        TerminalWrapper(terminalSession: terminalSession)
            .frame(minWidth: 800, minHeight: 600)
    }
}

struct TerminalWrapper: NSViewRepresentable {
    let terminalSession: TerminalSession
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.startProcess(executable: terminalSession.shellPath, args: terminalSession.shellArgs)
        return terminal
    }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

#Preview {
    ContentView()
}
