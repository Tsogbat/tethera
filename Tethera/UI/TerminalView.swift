import SwiftUI
import MetalKit
import Combine // Added for Combine publishers

struct TerminalView: NSViewRepresentable {
    let terminalSession: TerminalSession
    
    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView(terminalSession: terminalSession)
        return view
    }
    
    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        // Update view if needed
    }
}

class TerminalNSView: NSView {
    private var metalView: MTKView!
    private var renderer: MetalRenderer!
    private var terminalBuffer: TerminalBuffer!
    private var terminalSession: TerminalSession
    
    init(terminalSession: TerminalSession) {
        self.terminalSession = terminalSession
        super.init(frame: .zero)
        setupMetalView()
        setupTerminalBuffer()
        setupInputHandling()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupMetalView() {
        metalView = MTKView()
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.framebufferOnly = false
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        
        renderer = MetalRenderer()
        metalView.delegate = renderer
        
        addSubview(metalView)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    private func setupTerminalBuffer() {
        terminalBuffer = TerminalBuffer()
        
        // Connect buffer to renderer
        renderer.setBuffer(terminalBuffer)
        
        // Observe terminal size changes
        terminalSession.$terminalSize
            .sink { [weak self] size in
                self?.terminalBuffer.resize(columns: size.columns, rows: size.rows)
                self?.renderer.resize(columns: size.columns, rows: size.rows)
            }
            .store(in: &cancellables)
        
        terminalBuffer.$renderVersion
            .sink { [weak self] _ in
                self?.renderer.setNeedsVertexUpdate()
                self?.metalView.setNeedsDisplay(self?.metalView.bounds ?? .zero)
            }
            .store(in: &cancellables)
    }
    
    private func setupInputHandling() {
        // Make the view first responder to receive key events
        window?.makeFirstResponder(self)
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        guard let characters = event.characters else { return }
        
        // Handle special keys
        switch event.keyCode {
        case 36: // Return
            terminalSession.write("\r\n")
        case 51: // Delete/Backspace
            terminalSession.write("\u{08}")
        case 48: // Tab
            terminalSession.write("\t")
        case 53: // Escape
            terminalSession.write("\u{1B}")
        case 123: // Left Arrow
            terminalSession.write("\u{1B}[D")
        case 124: // Right Arrow
            terminalSession.write("\u{1B}[C")
        case 125: // Down Arrow
            terminalSession.write("\u{1B}[B")
        case 126: // Up Arrow
            terminalSession.write("\u{1B}[A")
        default:
            // Regular character
            terminalSession.write(characters)
        }
    }
    
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        
        resizeTerminalToFit()
    }
    
    override func layout() {
        super.layout()
        resizeTerminalToFit()
    }

    private func resizeTerminalToFit() {
        let cellWidth = max(1, renderer.cellSize.width)
        let cellHeight = max(1, renderer.cellSize.height)
        
        let columns = max(1, Int(bounds.width / cellWidth))
        let rows = max(1, Int(bounds.height / cellHeight))
        
        if columns != terminalSession.terminalSize.columns || rows != terminalSession.terminalSize.rows {
            terminalSession.resizeTerminal(columns: columns, rows: rows)
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// Extension to make MetalRenderer conform to MTKViewDelegate
extension MetalRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes if needed
    }
    
    func draw(in view: MTKView) {
        // Render the current buffer
        if let buffer = currentBuffer {
            render(in: view, buffer: buffer)
        }
    }
}
