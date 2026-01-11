# Tethera Terminal

A modern, block-based terminal application for macOS built with SwiftUI and Metal.

## Features

### - Modern Block-Based Interface

- **Visual Blocks**: Commands and outputs are organized into distinct blocks, making it easy to track execution history.
- **Rich Interaction**: Edit and rerun commands inline within their blocks.
- **Execution Timing**: Precise duration display for every command.
- **Status Indicators**: Visual cues for command success or failure.

### - Git Integration

- **Branch Display**: Shows current branch in header badge with color coding.
- **Dirty Indicator**: Orange dot when uncommitted changes exist.
- **Fast Detection**: File-based parsing (<1ms) instead of subprocess spawning.

### - Inline Markdown Editing

- **Click-to-Edit**: Edit rendered markdown files directly within the terminal block.
- **Split View**: Side-by-side raw editor and live preview.
- **Seamless Saving**: Save changes directly back to the original file.

### - Image Previews

- **Inline Display**: Preview images directly in terminal blocks.
- **Commands**: `preview <file>` or `show <file>` to display images.
- **Multiple Formats**: PNG, JPG, GIF, WEBP, HEIC, PDF support.
- **Copy Image**: Copy the actual image to clipboard using the block action button.
- **Click to Open**: Click images to open in Preview app.

### - High Performance

- **Metal-Accelerated Rendering**: Uses a custom Metal engine for raw terminal performance, capable of 60fps even under heavy load.
- **Static Command Sets**: Optimized autocomplete with pre-allocated data structures.
- **Efficient Buffering**: Bulk array operations for large outputs.

### - Smart Output

- **Markdown Rendering**: Automatically detects and renders Markdown content (headers, tables, code blocks) in command outputs.
- **Column Formatting**: Smartly aligns tab-separated output for better readability.

### - Intelligent Assistance

- **Ghost Text Autocomplete**: Context-aware suggestions as you type.
- **Dropdown Suggestions**: Interactive menu for command and path completion.
- **Path Resolution**: Smart handling of `~`, relative, and absolute paths.

### - Customization

- **Themes**: Built-in support for multiple color schemes including dark and light and "Liquid Glass" aesthetics.
- **Fonts**: Bundled JetBrains Mono for a premium coding experience.
- **Tabs & Split Panes**: Drag-and-drop tab management and split views for multitasking.

## Quick Start

```bash
git clone https://github.com/Tsogbat/tethera.git
cd tethera
make run
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

## Built-in Commands

| Command          | Description          |
| ---------------- | -------------------- |
| `clear`          | Clear all blocks     |
| `quit`, `exit`   | Quit the application |
| `preview <file>` | Display image inline |
| `show <file>`    | Alias for preview    |

## Architecture

Tethera uses a hybrid architecture combining SwiftUI for the block-based UI and Metal for high-performance rendering.

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed technical documentation.

## License

GNU AFFERO GENERAL PUBLIC LICENSE — See [LICENCE.TXT](LICENCE.TXT)
