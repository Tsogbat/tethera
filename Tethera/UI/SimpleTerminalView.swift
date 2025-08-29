import SwiftUI
import AppKit

struct SimpleTerminalView: NSViewRepresentable {
    let terminalSession: TerminalSession
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        
        // Create a simple text view that will definitely be visible
        let textView = NSTextView()
        textView.string = "Foundation Terminal - Ready!\n\n$ "
        textView.backgroundColor = NSColor.black
        textView.textColor = NSColor.green
        textView.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        
        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        
        // Add to main view
        view.addSubview(scrollView)
        
        // Set up constraints
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Store references for the coordinator
        context.coordinator.textView = textView
        context.coordinator.terminalSession = terminalSession
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var textView: NSTextView!
        var terminalSession: TerminalSession!
        var currentText = "Foundation Terminal - Ready!\n\n$ "
        
        override init() {
            super.init()
        }
        
        func handleKeyPress(_ characters: String) {
            currentText += characters
            textView.string = currentText
            textView.scrollToEndOfDocument(nil)
        }
        
        func handleReturn() {
            currentText += "\n$ "
            textView.string = currentText
            textView.scrollToEndOfDocument(nil)
            terminalSession.write("\r\n")
        }
        
        func handleBackspace() {
            if currentText.count > 0 {
                currentText = String(currentText.dropLast())
                textView.string = currentText
            }
            terminalSession.write("\u{08}")
        }
    }
}

// Create a wrapper view that handles key events
struct TerminalKeyHandler: NSViewRepresentable {
    let coordinator: SimpleTerminalView.Coordinator
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        // Make this view the first responder to receive key events
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(coordinator: coordinator)
    }
    
    class Coordinator: NSObject {
        let coordinator: SimpleTerminalView.Coordinator
        
        init(coordinator: SimpleTerminalView.Coordinator) {
            self.coordinator = coordinator
        }
        
        var acceptsFirstResponder: Bool { return true }
        
        func keyDown(with event: NSEvent) {
            guard let characters = event.characters else { return }
            
            switch event.keyCode {
            case 36: // Return
                coordinator.handleReturn()
            case 51: // Backspace
                coordinator.handleBackspace()
            case 48: // Tab
                coordinator.handleKeyPress("    ")
                coordinator.terminalSession.write("\t")
            default:
                coordinator.handleKeyPress(characters)
                coordinator.terminalSession.write(characters)
            }
        }
    }
}
