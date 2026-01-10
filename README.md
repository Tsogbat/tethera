# Tethera Terminal

A modern, block-based terminal application for macOS built with SwiftUI and Metal.

## Features

### 🚀 Modern Block-Based Interface

- **Visual Blocks**: Commands and outputs are organized into distinct blocks, making it easy to track execution history.
- **Rich Interaction**: Edit, rerun, and copy commands directly from their blocks.
- **Execution Timing**: Precise duration display for every command.
- **Status Indicators**: Visual cues for command success or failure.

### ⚡️ High Performance

- **Metal-Accelerated Rendering**: Uses a custom Metal engine for raw terminal performance, capable of 60fps even under heavy load.
- **Efficient Buffering**: Optimized data handling for large outputs.

### 📝 Smart Output

- **Markdown Rendering**: Automatically detects and renders Markdown content (headers, tables, code blocks) in command outputs.
- **Column Formatting**: Smartly aligns tab-separated output for better readability.

### 🧠 Intelligent Assistance

- **Ghost Text Autocomplete**: Context-aware suggestions as you type.
- **Dropdown Suggestions**: Interactive menu for command and path completion.

### 🎨 Customization

- **Themes**: Built-in support for multiple color schemes including dark and light and "Liquid Glass" aesthetics.
- **Fonts**: Bundled JetBrains Mono for a premium coding experience.
- **Tabs & Split Panes**: Drag-and-drop tab management and split views for multitasking.

## Quick Start

```bash
git clone https://github.com/Tsogbat/tethera.git
cd tethera
swift run
```

## Keyboard Shortcuts

| Shortcut  | Action                     |
| --------- | -------------------------- |
| `Cmd+T`   | New tab                    |
| `Cmd+D`   | Split pane                 |
| `Cmd+F`   | Search history             |
| `Cmd+,`   | Settings                   |
| `↑` / `↓` | Command history navigation |
| `Tab`     | Autocomplete / Dropdown    |

## Architecture

Tethera uses a hybrid architecture combining SwiftUI for the block-based UI and Metal for high-performance rendering.

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed technical documentation.

## License

GNU AFFERO GENERAL PUBLIC LICENSE — See [LICENCE.TXT](LICENCE.TXT)
