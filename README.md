# Tethera Terminal

A modern, high-performance terminal application for macOS built with SwiftUI and SwiftTerm.

## ✨ Features

### Core Terminal Features
- **Multiple Tabs**: Chrome-style tab interface with drag-to-reorder
- **Split Panes**: Horizontal and vertical terminal splitting
- **Smart Autocomplete**: Intelligent command and path completion
- **Metal Rendering**: Hardware-accelerated text rendering for performance
- **Custom Themes**: Dark terminal theme with modern UI design

### User Experience
- **Smooth Animations**: Polished interactions and transitions
- **Keyboard Shortcuts**: Full keyboard navigation support
- **Minimal Rename**: Invisible inline tab renaming
- **Command Palette**: Quick access to terminal functions
- **Font Customization**: JetBrains Mono with multiple weights

## 🏗️ Architecture

```
Sources/Tethera/
├── Core/           # Core terminal functionality
│   ├── TerminalApp.swift
│   ├── TerminalSession.swift
│   ├── TerminalBuffer.swift
│   ├── AutocompleteEngine.swift
│   ├── MetalRenderer.swift
│   └── Shaders.metal
├── UI/             # SwiftUI views and components
│   ├── ContentView.swift
│   ├── TabBarView.swift
│   ├── BlockTerminalView.swift
│   ├── TabbedTerminalView.swift
│   └── AutocompleteSuggestionView.swift
├── Models/         # Data models and managers
│   ├── Tab.swift
│   ├── TabManager.swift
│   ├── TabDropDelegate.swift
│   ├── SplitPane.swift
│   └── TerminalTheme.swift
└── Extensions/     # Utility extensions
    └── FontLoader.swift
```

## 🚀 Getting Started

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later

### Build & Run

```bash
# Build the project
swift build

# Run Tethera
swift run
```

Or open `Tethera.xcodeproj` in Xcode and press ⌘+R.

### Build App Bundle with Icon

To build a proper macOS app bundle (.app) with the custom icon:

```bash
# Build the app bundle
make app

# Run the app bundle
make run-app
```

Or use the build script directly:

```bash
./build_app.sh
open Tethera.app
```

The app bundle will include the custom icon and can be moved to Applications folder or run from anywhere.

**Note**: The build script automatically generates a proper macOS `.icns` icon file from your `icon.png` source file, ensuring the icon displays correctly in the dock, Finder, and throughout the system.

## Usage

- **Type commands** in the input field at the bottom
- **Press Enter** or click the arrow button to execute
- **Use `cd`** to change directories
- **Use `clear`** to clear the terminal
- **All standard shell commands** work as expected

## Architecture

- **SwiftUI**: Modern macOS UI framework
- **Metal**: GPU-accelerated rendering
- **FontLoader**: Custom font management
- **BlockTerminalView**: Main interface component
- **TerminalSession**: Shell process management

## Project Structure

```
Tethera/
├── BlockTerminalView.swift      # Main UI
├── BlockTerminalViewModel.swift # Business logic
├── FontLoader.swift            # Font management
├── TerminalBlock.swift         # Data model
├── TerminalTheme.swift         # UI theming
└── Fonts/                     # JetBrains Mono fonts
```

## License

This is opensource project feel free to contribute
GNU AFFERO GENERAL PUBLIC LICENSE
