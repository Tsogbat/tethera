# Tethera Terminal

<p align="center">
  <strong>A modern, high-performance terminal application for macOS</strong><br>
  Built with SwiftUI and SwiftTerm for the ultimate developer experience.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0+-blue.svg" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift">
</p>

---

## ✨ Features

### 🚀 Core Terminal Features

- **Chrome-Style Tabs**: Fluid drag-to-reorder with smooth spring animations
- **Smart Autocomplete**: Intelligent command and path completion with filtering
- **Split Panes**: Horizontal and vertical terminal splitting for multitasking
- **Metal Rendering**: Hardware-accelerated text rendering for peak performance
- **Custom Themes**: Cohesive dark theme with modern UI design

### 🎨 User Experience

- **Polished Animations**: Spring-based transitions and hover effects
- **Invisible Rename**: Double-click tabs for minimal inline editing
- **Keyboard Navigation**: Full keyboard shortcuts and accessibility
- **Custom Fonts**: JetBrains Mono with multiple weights included
- **Responsive UI**: Adaptive layouts that scale beautifully

## 🚀 Quick Start

### Prerequisites

Before you begin, ensure you have the following installed:

- **macOS 14.0** or later
- **Xcode 15.0** or later
- **Swift 5.9** or later
- **Git** for cloning the repository

### 1. Clone the Repository

```bash
git clone https://github.com/Tsogbat/tethera.git
cd tethera
```

### 2. Build the Project

Use Swift Package Manager to build the application:

```bash
swift build
```

This will:

- Download and resolve all dependencies (SwiftTerm, etc.)
- Compile the source code
- Generate the executable

### 3. Run the Application

Launch Tethera directly from the command line:

```bash
swift run
```

Or use the convenient Makefile:

```bash
make run-app
```

### 4. Development Build

For development with debug symbols:

```bash
swift build -c debug
```

For optimized release builds:

```bash
swift build -c release
```

## 🏗️ Project Architecture

The codebase is organized into a clean, modular structure:

- **SwiftUI**: Modern macOS UI framework
- **Metal**: GPU-accelerated rendering
- **FontLoader**: Custom font management
- **BlockTerminalView**: Main interface component
- **TerminalSession**: Shell process management

## Project Structure

```
Tethera/
├── Package.swift
├── LICENCE.TXT
├── README.md
├── Makefile
├── Tethera/
│   ├── Core/
│   │   ├── TerminalApp.swift          # Main app entry point
│   │   ├── TerminalSession.swift      # Shell session management
│   │   ├── TerminalBuffer.swift       # Terminal buffer handling
│   │   ├── TerminalBlock.swift        # Data model for terminal blocks
│   │   ├── AutocompleteEngine.swift   # Command/path completion
│   │   ├── MetalRenderer.swift        # GPU-accelerated rendering
│   │   └── Shaders.metal             # Metal shader code
│   │
│   ├── UI/
│   │   ├── ContentView.swift          # Root view
│   │   ├── BlockTerminalView.swift    # Main terminal interface
│   │   ├── TabBarView.swift          # Tab management UI
│   │   ├── SplitPaneView.swift       # Split view management
│   │   ├── TerminalView.swift        # Terminal rendering view
│   │   ├── SimpleTerminalView.swift  # Basic terminal view
│   │   ├── CommandPaletteView.swift  # Command palette UI
│   │   ├── TerminalSettingsView.swift # Settings UI
│   │   └── AutocompleteSuggestionView.swift # Completion UI
│   │
│   ├── Models/
│   │   ├── Tab.swift                # Tab data model
│   │   ├── TabManager.swift         # Tab lifecycle management
│   │   ├── SplitPane.swift          # Split pane model
│   │   ├── SplitPaneManager.swift   # Split view management
│   │   ├── TabDropDelegate.swift    # Drag and drop handling
│   │   ├── TabbedTerminalView.swift # Multi-tab container
│   │   └── TerminalTheme.swift      # Theme configuration
│   │
│   ├── Extensions/
│   │   └── FontLoader.swift         # Custom font loading
│   │
│   ├── Fonts/                       # JetBrains Mono font files
│   │   ├── JetBrainsMono-Bold.ttf
│   │   ├── JetBrainsMono-Medium.ttf
│   │   └── JetBrainsMono-Regular.ttf
│   │
│   ├── Assets.xcassets/             # App assets
│   └── Info.plist                   # App configuration
│
└── .build/                         # Build artifacts

## License

This is opensource project feel free to contribute
GNU AFFERO GENERAL PUBLIC LICENSE
```
