# Tethera Technical Reference & Architecture Manual

This document serves as the implementation manual for Tethera, detailing its architecture, core subsystems, data flow, and critical implementation details. It combines high-level architectural concepts with low-level engineering specifics.

---

## 1. System Overview

Tethera is a hybrid terminal emulator built on macOS. It eschews the traditional cell-grid-only approach for a **Block-Based Architecture**, where every command is a discrete, interactive entity.

### High-Level Architecture

```text
[User Input]
    │
    ▼
[BlockTerminalViewModel] ────┬──▶ [AutocompleteEngine]
    │                        └──▶ [CommandHistoryManager]
    │
    ▼
┌───────────────────────────────┐
│        Core Execution         │
│                               │
│  [TerminalSession (PTY)]      │
│            │ (writes)         │
│            ▼                  │
│       [Master FD]             │
│            │ (reads)          │
│            ▼                  │
│     [Shell Process]           │
│     (zsh/bash/etc)            │
│            │ (output)         │
│            ▼                  │
│       [Master FD]             │
│            │ (reads)          │
│            ▼                  │
│  [TerminalSession] ──(parses)─▶ [Output Parser]
└───────────────────────────────┘       │
                                        │
                                        ▼
┌───────────────────────────────┐  [TerminalBlock]
│         UI Rendering          │       │
│                               │       ▼
│  [MediaPreviewView] ◀──(media)─ [BlockTerminalView]
│                                       │
│    [MarkdownOutputView] ◀─(markdown)──┤
│             │                         │
│             ▼                         │ (text)
│      [Inline Editor]                  ▼
│                                 [Text Output]
└───────────────────────────────┘
```

---

## 2. Core Subsystems

### 2.1 PTY & Terminal Session (`TerminalSession.swift`)

Tethera uses a genuine Pseudo-Terminal (PTY) to interface with the shell. This ensures full compatibility with interactive CLI tools (vim, htop) and signal handling.

- **Initialization**: Uses `openpty()` to create a Master/Slave file descriptor pair.
- **Process Spawning**: Uses `posix_spawn` with file actions to map `stdin/stdout/stderr` to the Slave FD.
- **IO Loop**: A `DispatchSourceRead` monitors the Master FD. Reads are performed in 4096-byte chunks.
- **UTF-8 Buffering**:
  - **Problem**: Shell output can split multi-byte characters across read chunks.
  - **Solution**: `parseOSCByte()` buffers bytes `>= 0x80` in `utf8Buffer`. Decoding is attempted only when a valid UTF-8 sequence is formed. Invalid or control characters flush the buffer to prevent state corruption.
- **Shell Integration**: Injects a script (`tethera.zsh`) to emit OSC 133 sequences, allowing Tethera to strictly delimit command outputs from prompts.

### 2.2 Terminal Block Lifecycle

A `TerminalBlock` is the atomic unit of history.

1. **Pending**: Created when user hits Return. Sent to `BlockTerminalViewModel`.
2. **Execution**: Command string written to PTY.
3. **Output Streaming**: As the PTY reads data, it is appended to `block.output`.
   - _Optimization_: SwiftUI updates are throttled/batched to prevent main-thread locking during high-volume output (e.g., `cat huge_file.txt`).
4. **Completion**: Detected via exit code (from `waitpid`) or shell integration prompt signal.
5. **Post-Processing**:
   - **Auto-Summary**: Generated if output is too long.
   - **Git Refresh**: Triggered on directory change or command completion.

### 2.3 Metal Rendering Engine (`MetalRenderer.swift`)

For raw terminal mode (full-screen apps), Tethera bypasses SwiftUI for a custom Metal rendering pipeline.

- **Vertex Strategy**: Draws a grid of quads (2 triangles per character cell).
- **Font Atlas**: A single texture contains the entire glyph set (JetBrains Mono). This eliminates texture switching.
- **Batching**: The entire screen is drawn in a single draw call (`drawPrimitives`).
- **Shaders**:
  - _Vertex Shader_: Calculates screen position from grid coordinates.
  - _Fragment Shader_: Samples the font atlas and applies foreground/background colors defined in `TerminalTheme`.

---

## 3. Feature Implementations

### 3.1 Inline Markdown Editing

Tethera transforms static markdown output into a live editor.

- **Detection**: `MarkdownDetector` scans output for headers (`#`), lists, or code fences.
- **View Switching**: Toggles between `MarkdownOutputView` (rendered) and the Split Editor.
- **Split Editor Architecture**:
  - **Container**: `VStack` inside the `TerminalBlockView`.
  - **State**: `editableMarkdown` (binding) vs `originalMarkdown` (reference for dirtiness).
  - **Components**:
    - **Left**: `TextEditor` with monospaced font.
    - **Right**: `MarkdownOutputView` reusing the same rendering logic for 1:1 preview.
  - **Persistence**: Uses `String(contentsOfFile:)` for loading and atomic `write(toFile:)` for saving directly to disk.

### 3.2 Media Preview System (`MediaService.swift`)

Allows `preview image.png` commands to render inline images.

- **Path Resolution**: Handles `~` expansion, relative paths, and glob patterns (`*.png`).
- **Glob Logic**: Manages file system enumeration to find matches for patterns like `images/design_v*.png`.
- **Rendering**: `MediaPreviewView` loads `NSImage` asynchronously.
  - _Feature_: "Copy Image" extracts the `NSImage` to `NSPasteboard` directly, not just the file path.

### 3.3 Fast Git Service (`GitService.swift`)

Provides instant Git status without the latency of spawning `git` processes for every check.

- **Head Parsing**: Reads `.git/HEAD` file directly (<0.5ms) to determine branch/detached state.
- **Dirty Check**: Uses `git status --porcelain` (optimized internal git command) only when necessary.
- **Caching**: Results are cached by directory path and only invalidated on command execution events.

### 3.4 Autocomplete Engine (`AutocompleteEngine.swift`)

A hybrid completion system.

- **Static Registry**: Pre-allocated dictionaries for common commands (`git`, `docker`, `ls`) and their flags.
- **Ghost Text**: Single-line suggestions rendered `gray` ahead of the cursor. Accepted via right-arrow.
- **Dropdown**: Tab-triggered menu for complex path/flag selection.

---

## 4. Data & Persistence

### 4.1 Command History (`CommandHistoryManager.swift`)

- **Storage**: `~/Library/Application Support/Tethera/command_history.json`.
- **Format**: JSON array of `HistoryEntry` objects.
- **Optimization**:
  - _Writes_: Debounced background persistence (every 10 entries or app exit).
  - _Search_: Logic runs on detached priority task loop to prevent UI stutter during search of 10k+ entries.

### 4.2 User Settings

- **Storage**: standard `UserDefaults`.
- **Key**: `userSettings` (JSON encoded).
- **Theme**: Stored as a complete `TerminalTheme` object, allowing custom colors beyond presets.

---

## 5. Project Structure & Key Files

| Directory   | Key Files                  | Responsibility                          |
| :---------- | :------------------------- | :-------------------------------------- |
| **Core/**   | `TerminalSession.swift`    | PTY management, IO loops, UTF-8 parsing |
| **Core/**   | `TerminalBlock.swift`      | Data model for command blocks           |
| **Core/**   | `MetalRenderer.swift`      | GPU rendering logic                     |
| **Core/**   | `GitService.swift`         | File-based Git integration              |
| **UI/**     | `BlockTerminalView.swift`  | Main block list, Interaction handling   |
| **UI/**     | `MarkdownOutputView.swift` | Rendering MD, Inline Editor components  |
| **UI/**     | `MarkdownEditView.swift`   | (Legacy) Popup editor logic             |
| **Models/** | `TerminalTheme.swift`      | Color schemes and font settings         |

---

## 6. Extension Guide

### Adding a New Built-in Command

1. Open `BlockTerminalViewModel.swift`.
2. Locate `runShellCommand`.
3. Add case to the interceptor switch:
   ```swift
   if trimmed == "mycommand" {
       // Perform action
       return
   }
   ```

### Adding a New Theme

1. Open `TerminalTheme.swift`.
2. Add a static constant for the theme.
3. Register it in the `ThemePreset` enum in `UserSettings.swift`.

### Customizing Markdown Rendering

1. Open `MarkdownOutputView.swift`.
2. Modify `parseMarkdownLines` to add new regex detectors.
3. Add corresponding SwiftUI View components in the `body` builder.
