# Foundation - The Basic Terminal

A blazingly fast, bare-bones terminal application for macOS built with SwiftUI and Metal.

## Project Overview

This terminal application demonstrates the fundamentals of terminal emulation, including:

- **PTY Management**: Creates pseudo-terminal pairs and manages shell processes
- **Terminal Emulation**: Handles terminal state, cursor positioning, and character processing
- **High-Performance Rendering**: Uses Metal for GPU-accelerated text rendering
- **Modern UI**: Built with SwiftUI for a native macOS experience

## Architecture

### Core Components

1. **TerminalSession** (`TerminalSession.swift`)

   - Manages PTY creation and shell process lifecycle
   - Handles non-blocking I/O with DispatchQueue
   - Processes terminal resize events

2. **TerminalBuffer** (`TerminalBuffer.swift`)

   - Maintains terminal state and character grid
   - Processes incoming data and handles control characters
   - Manages scrollback buffer

3. **MetalRenderer** (`MetalRenderer.swift`)

   - Creates font atlas texture for character rendering
   - Manages Metal pipeline and vertex buffers
   - Renders terminal cells with GPU acceleration

4. **TerminalView** (`TerminalView.swift`)

   - SwiftUI wrapper around Metal view
   - Handles user input (keyboard events)
   - Manages view lifecycle and resizing

5. **Metal Shaders** (`Shaders.metal`)
   - Vertex and fragment shaders for text rendering
   - Handles texture sampling and color blending

## Features

- **Fast Rendering**: Metal-based GPU rendering for smooth performance
- **Shell Integration**: Automatically launches user's default shell ($SHELL)
- **Resizable**: Dynamic terminal sizing based on window dimensions
- **Input Handling**: Full keyboard support including arrow keys and special characters
- **Scrollback**: Maintains history of previous terminal output

## Building and Running

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later
- Metal-compatible GPU

### Build Steps

1. Open the project in Xcode
2. Select the "Terminal" target
3. Choose your development team for code signing
4. Build and run (⌘+R)

### Project Structure

```
Terminal/
├── TerminalApp.swift          # Main app entry point
├── ContentView.swift          # Root SwiftUI view
├── TerminalSession.swift      # PTY and shell management
├── TerminalBuffer.swift       # Terminal state and emulation
├── TerminalView.swift         # Metal view integration
├── MetalRenderer.swift        # Metal rendering engine
├── Shaders.metal             # Metal shaders
├── Info.plist                # App configuration
└── Assets.xcassets/          # App resources
```

## Technical Details

### PTY Management

The application creates a pseudo-terminal pair using `openpty()` and launches the user's shell as a child process. The master PTY is used for reading/writing, while the slave PTY becomes the controlling terminal for the shell.

### Rendering Pipeline

1. **Font Atlas**: A texture containing all printable characters
2. **Vertex Buffer**: Dynamic buffer containing quad positions and texture coordinates
3. **Metal Pipeline**: GPU-accelerated rendering with custom shaders
4. **Frame Updates**: Only updates changed cells for optimal performance

### Performance Optimizations

- **Vertex Buffer Updates**: Only updates vertices for changed cells
- **Indexed Rendering**: Uses index buffers for efficient quad rendering
- **Texture Atlas**: Single texture lookup for all characters
- **Metal Integration**: Direct GPU rendering without CPU bottlenecks

## Future Enhancements

- **True Font Rendering**: Integration with Core Text for proper font metrics
- **ANSI Escape Sequences**: Full terminal control sequence support
- **Color Palettes**: Configurable color schemes
- **Split Views**: Multiple terminal sessions in one window
- **Copy/Paste**: Clipboard integration
- **Settings**: User-configurable preferences

## Dependencies

- **Foundation**: Core system functionality
- **SwiftUI**: Modern UI framework
- **Metal**: GPU rendering framework
- **Darwin**: Low-level system calls
- **Combine**: Reactive programming

## License

This project is for educational purposes. Feel free to use and modify as needed.

## Contributing

This is a learning project demonstrating terminal emulation fundamentals. Contributions and improvements are welcome!
