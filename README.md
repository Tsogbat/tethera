# Tethera Terminal

A modern, block-based terminal application for macOS built with SwiftUI.

## Quick Start

```bash
git clone https://github.com/Tsogbat/tethera.git
cd tethera
swift run
```

## Features

### Core Terminal

- **Block-based UI** — Commands and outputs organized in visual blocks with status indicators
- **Execution timing** — See how long each command takes to run
- **Tab management** — Multiple independent terminal sessions with drag-to-reorder
- **Split panes** — Drag tabs to create side-by-side terminal views
- **Smart autocomplete** — Command and path completion as you type

### Search & History

- **Fuzzy search** (`Cmd+F`) — Search through all command history
- **Persistent history** — Commands saved across app restarts
- **Jump to results** — Navigate search results and jump to specific blocks

### Customization

- **Theme gallery** — Multiple built-in themes (dark and light)
- **Custom fonts** — JetBrains Mono included, or use your own
- **Adjustable settings** — Font size, line spacing, and more

## Keyboard Shortcuts

| Shortcut  | Action                     |
| --------- | -------------------------- |
| `Cmd+T`   | New tab                    |
| `Cmd+F`   | Search history             |
| `Cmd+,`   | Settings                   |
| `↑` / `↓` | Command history navigation |
| `Tab`     | Autocomplete               |
| `Esc`     | Close search / Cancel      |

## Requirements

- macOS 14.0+
- Swift 5.9+

## Development

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run
swift run
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed technical documentation.

## License

GNU AFFERO GENERAL PUBLIC LICENSE — See [LICENCE.TXT](LICENCE.TXT)
