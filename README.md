# Tethera

A modern, high-performance terminal application for macOS built with SwiftUI and Metal.

## Features

- **Modern UI**: Clean, minimalistic design with dark theme
- **High Performance**: Metal-based GPU rendering for smooth 60 FPS
- **Shell Integration**: Runs your default shell with full command support
- **Block-based Interface**: Commands and outputs displayed as clean blocks
- **Custom Fonts**: JetBrains Mono for optimal readability
- **Working Directory**: Tracks and displays current directory

## Quick Start

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

This project is for educational purposes. Free to use and modify as needed.
