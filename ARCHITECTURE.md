# Tethera Architecture

This document describes the architecture and design of the Tethera Terminal application.

## Overview

Tethera is a block-based terminal emulator built with SwiftUI for macOS. It organizes command inputs and outputs into visual blocks, providing a more structured and navigable terminal experience.

## Project Structure

```
Tethera/
├── Core/                      # Core business logic
│   ├── TerminalApp.swift      # App entry point and menu configuration
│   ├── TerminalBlock.swift    # Data model for command blocks
│   ├── BlockTerminalViewModel.swift  # Main view model for terminal
│   ├── CommandHistoryManager.swift   # Global command history and search
│   ├── AutocompleteEngine.swift      # Command/path completion logic
│   ├── TerminalSession.swift         # PTY session management
│   ├── TerminalBuffer.swift          # Terminal output buffer
│   └── AIService.swift               # AI integration service
│
├── UI/                        # SwiftUI views
│   ├── BlockTerminalView.swift       # Main terminal block interface
│   ├── TabBarView.swift              # Tab bar with drag support
│   ├── SplitPaneView.swift           # Split view management
│   ├── SearchOverlayView.swift       # Fuzzy search overlay
│   ├── NativeSettingsView.swift      # Settings interface
│   ├── AutocompleteSuggestionView.swift  # Autocomplete dropdown
│   └── CommandPaletteView.swift      # Command palette
│
├── Models/                    # Data models and managers
│   ├── Tab.swift                     # Tab data model
│   ├── TabManager.swift              # Tab lifecycle management
│   ├── SplitPane.swift               # Split pane data model
│   ├── SplitPaneManager.swift        # Split view state
│   ├── TabbedTerminalView.swift      # Root tabbed container
│   ├── TabDropDelegate.swift         # Drag-drop handling
│   ├── UserSettings.swift            # User preferences
│   └── TerminalTheme.swift           # Theme configuration
│
├── Extensions/                # Utility extensions
│   └── FontLoader.swift              # Custom font loading
│
└── Fonts/                     # Bundled fonts
    └── JetBrainsMono-*.ttf
```

## Core Components

### TerminalBlock

The fundamental data unit representing a single command execution:

```swift
struct TerminalBlock: Identifiable {
    let id: UUID
    var input: String           // Command entered
    var output: String          // Command output
    var timestamp: Date         // When executed
    var workingDirectory: String?
    var success: Bool?          // Success/failure status
    var executionDuration: TimeInterval?  // How long it took
    var exitCode: Int32?        // Shell exit code
}
```

### BlockTerminalViewModel

The main view model that manages:

- Command execution via shell subprocess
- Block creation and storage
- Working directory tracking
- Command history navigation (up/down arrows)

### CommandHistoryManager

Singleton managing global command history:

- Stores all commands across all tabs
- Persists to `~/Library/Application Support/Tethera/command_history.json`
- Provides fuzzy search functionality
- Supports keyboard navigation through results

### TabManager

Handles tab lifecycle:

- Creating/closing tabs
- Tab selection and activation
- Tab reordering via drag-and-drop
- Settings tab management

### SplitPaneManager

Manages split view state:

- Tree structure of split panes
- Horizontal/vertical splitting
- Tab assignment to panes
- Pane resizing

## Data Flow

```
┌─────────────────┐
│   User Input    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────────┐
│ BlockTerminal   │────▶│ CommandHistoryManager│
│   ViewModel     │     │    (persistence)     │
└────────┬────────┘     └──────────────────────┘
         │
         ▼
┌─────────────────┐
│  Process.run()  │
│  (shell exec)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ TerminalBlock   │
│   (created)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ SwiftUI View    │
│   (updated)     │
└─────────────────┘
```

## Key Design Decisions

### Block-Based Architecture

Instead of a scrolling terminal buffer, Tethera organizes output into discrete blocks. This allows:

- Visual separation of commands
- Easy copying of specific command outputs
- Status indicators per command
- Execution time display

### Synchronous Command Execution

Commands run synchronously with `Process.waitUntilExit()` for simplicity. This means:

- No streaming output during execution
- Full output captured after completion
- Simple timing measurement

For long-running or interactive commands, consider the PTY-based `TerminalSession`.

### Singleton History Manager

`CommandHistoryManager.shared` provides global access to command history:

- Enables search across all tabs
- Centralizes persistence logic
- Allows menu bar integration

### SwiftUI Materials for Styling

UI uses SwiftUI's material system (`.ultraThinMaterial`, etc.) for:

- Consistent with macOS design language
- Automatic dark/light mode adaptation
- Blur effects without manual implementation

## Extension Points

### Adding New Themes

1. Add preset to `ThemePreset` enum in `UserSettings.swift`
2. Define colors in `ThemeConfiguration`
3. Theme will appear in Settings gallery

### Custom Commands

Extend `BlockTerminalViewModel.runShellCommand()` to handle:

- Built-in commands (like `clear`)
- Custom aliases
- Integration with external tools

### AI Integration

`AIService.swift` provides hooks for:

- Command suggestions
- Output explanations
- Error diagnosis

## File Locations

| Data            | Location                                                     |
| --------------- | ------------------------------------------------------------ |
| Command History | `~/Library/Application Support/Tethera/command_history.json` |
| User Settings   | UserDefaults                                                 |
| Bundled Fonts   | App bundle `Resources/Fonts/`                                |
