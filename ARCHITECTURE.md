# Tethera Architecture

This document describes the architecture and design of the Tethera Terminal application.

## Overview

Tethera is a block-based terminal emulator built with SwiftUI for macOS. It organizes command inputs and outputs into visual blocks, providing a more structured and navigable terminal experience. It supports rich output rendering including Markdown and images, Git integration, and features a high-performance Metal-based renderer for raw terminal sessions.

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
│   ├── TerminalBuffer.swift          # Terminal output buffer model
│   ├── MetalRenderer.swift           # Metal-based terminal renderer
│   ├── Shaders.metal                 # Metal vertex/fragment shaders
│   ├── AIService.swift               # AI integration service
│   ├── GitService.swift              # Fast Git repo info (branch, status)
│   └── MediaService.swift            # Image/media preview handling
│
├── UI/                        # SwiftUI views
│   ├── BlockTerminalView.swift       # Main terminal block interface
│   ├── TerminalView.swift            # Metal-backed raw terminal view
│   ├── MarkdownOutputView.swift      # Markdown rendering component
│   ├── MarkdownEditView.swift        # Split-pane markdown editor
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
│   ├── TerminalTheme.swift           # Theme configuration
│   └── GitInfo.swift                 # Git status model
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
struct TerminalBlock: Identifiable, Codable {
    let id: UUID
    var input: String           // Command entered
    var output: String          // Command output
    var timestamp: Date         // When executed
    var workingDirectory: String?
    var success: Bool?          // Success/failure status
    var exitCode: Int32?        // Shell exit code
    var durationMs: Int64?      // Execution duration in milliseconds
    var category: CommandCategory  // Auto-detected command type
    var mediaFiles: [String]?   // Image/media paths for preview
    var markdownSourcePath: String? // Path for editable markdown files
}
```

### BlockTerminalViewModel

The main view model that manages:

- Command execution via `TerminalSession` (PTY) or fallback `Process`.
- Block creation and storage.
- Working directory tracking.
- Command history navigation.
- Preview command handling (`preview`, `show`).
- Inline editor state management.

### MetalRenderer & TerminalBuffer

High-performance rendering system:

- **TerminalBuffer**: Manages the grid of characters (cells), lines, and attributes (colors, bold, etc.). Optimized with bulk array operations.
- **MetalRenderer**: Renders the `TerminalBuffer` to an `MTKView` using Metal.
  - Uses a font atlas texture for glyphs.
  - Updates a vertex buffer dynamically based on grid content.
  - Runs custom shaders (`Shaders.metal`) for blending and coloring.

### Markdown Rendering & Editing

Tethera provides a rich markdown experience:

- **Rendering**: Detects and renders Markdown content (headers, code blocks, tables) using `MarkdownOutputView` and `MarkdownDetector`.
- **Inline Editing**: Allows direct editing of markdown files within the terminal block.
  - **Inline Mode**: Replaces rendered view with a split-pane editor (Raw + Preview).
  - **Live Preview**: Updates rendered view as you type.
  - **File Sync**: Saves changes directly back to the original file using `String(contentsOfFile:)` and `write(toFile:)`.

### CommandHistoryManager

Singleton managing global command history:

- Stores all commands across all tabs.
- Persists to `~/Library/Application Support/Tethera/command_history.json`.
- Provides fuzzy search functionality.

### GitService

Fast, file-based Git repository information:

- **File-based parsing**: Reads `.git/HEAD` directly (<1ms) instead of spawning `git` subprocess.
- **Branch detection**: Extracts current branch name from refs.
- **Dirty status**: Uses `git status --porcelain` for accurate uncommitted change detection.
- **Caching**: Background refresh with notification-based updates.
- **UI Integration**: Displays branch badge in header with color coding (green=main, purple=feature).

### MediaService

Image and media preview handling:

- **Format support**: PNG, JPG, JPEG, GIF, WEBP, BMP, HEIC, PDF.
- **Command parsing**: Handles `preview` and `show` commands with glob patterns.
- **Path resolution**: Supports relative, absolute, and `~` prefixed paths.
- **Validation**: Ensures files exist and are valid media types before creating preview blocks.

## Data Flow

### Block Mode

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
│ TerminalSession │
│     (PTY)       │
1. Parse UTF-8    │
2. Fix Output     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ TerminalBlock   │
│   (created)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐       ┌────────────────────┐
│ BlockTerminal   │──────▶│ MarkdownOutputView │
│     View        │       │ (if MD detected)   │
└────────┬────────┘       └─────────┬──────────┘
         │                          │
    ┌────▼──────────┐               │
    │ Inline Editor │◀──────────────┘
    │ (Split View)  │
    └───────────────┘
```

### Raw/Metal Mode (Background/Under-the-hood)

```
┌─────────────────┐
│ TerminalSession │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ TerminalBuffer  │
│  (Data Model)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  MetalRenderer  │
│ (Update Vertex) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    MTKView      │
│     (GPU)       │
└─────────────────┘
```

## Key Design Decisions

### Block-Based Architecture & Rich Output

Instead of a scrolling text buffer, Tethera organizes output into discrete blocks. This enables "Rich Text" features like rendering Markdown directly in the terminal stream, which is handled by `MarkdownOutputView` when detected.

### Inline Markdown Editing

To bridge the gap between terminal and editor, Tethera implements "Click-to-Edit". Instead of opening an external editor, users can toggle an inline split-view editor directly within the command block. This reduces context switching for quick documentation edits.

### GPU Acceleration

For raw terminal rendering (ncurses apps or classic view), Tethera uses a Custom Metal engine (`MetalRenderer`) instead of standard SwiftUI Text views. This provides 60fps performance even with heavy text loads by batching character draws into a single draw call per frame.

### PTY & Async Execution

Commands run via a Pseudo-Terminal (PTY) in `TerminalSession`. This allows accurate shell behavior, interactive commands, and captured exit codes, improving over the initial synchronous `Process` implementation. Input parsing handles UTF-8 multi-byte characters to support modern CLI tools and international text.

### Design System

UI uses SwiftUI's material system heavily (`.ultraThinMaterial`) and custom shaders/gradients ("Liquid Glass" style) to match macOS aesthetics while feeling modern and premium.

## Extension Points

### Adding New Themes

1. Add preset to `ThemePreset` enum in `UserSettings.swift`
2. Define colors in `ThemeConfiguration`

### Custom Renderers

The `TerminalBuffer` is decoupled from the renderer. You can implement new renderers (e.g., specific to other graphics APIs or ASCII export) by consuming the buffer state.

## File Locations

| Data            | Location                                                     |
| --------------- | ------------------------------------------------------------ |
| Command History | `~/Library/Application Support/Tethera/command_history.json` |
| User Settings   | UserDefaults                                                 |
| Bundled Fonts   | App bundle `Resources/Fonts/`                                |
