# Tethera Architecture

Tethera is a SwiftUI macOS app (SwiftPM, no Xcode project). Each tab runs the user's login shell in a real pseudo-terminal. Shell integration marks command boundaries with OSC 133, and Tethera turns each command into a block. While a command runs, its bytes feed a live SwiftTerm emulator. When it ends, the screen is captured as styled text and the emulator is reused for the next command.

AI features run the coding CLIs the user is already signed in to (OpenCode, Claude Code, Codex, Hermes, Gemini, Ollama) as headless subprocesses. There are no API keys and no network code in the app.

## Data flow

```text
 keys / paste                                         OSC 133 A·B·C·D, OSC 7
 ───────────────┐                                    ┌──────────────────────────┐
                ▼                                    │                          │
  InputBarView ─▶ BlockTerminalViewModel ─submit──▶ ShellSession (forkpty) ─▶ zsh/bash
                     ▲        │                      │  bytes
                     │        │                      ▼
                     │        │               OSC133Splitter ── events ──┐
                     │        │                      │ output bytes      │
                     │        ▼                      ▼                   │
                     │   blocks: [TerminalBlock]   KittyKeyboardFilter   │
                     │        ▲                      ▼                   │
                     │        │ snapshot      LiveTerminal (SwiftTerm) ◀─┘ keys while running
                     │        └──── StyledText ◀─────┘
                     │
                     └── AIAssistant ─▶ AgentRunner ─▶ opencode / claude / codex / … (headless)
```

1. **Submit.** The view model appends a running block at once and sends the line to the shell (`⌃U` + text + `↩`, bracketed paste for multi-line).
2. **Split.** `OSC133Splitter` is a byte-level state machine. It drops the prompt and echo (A→C), emits events for C (output starts), D (exit code) and OSC 7 (cwd), and passes every other escape sequence through untouched. It handles sequences split across reads.
3. **Render live.** Output bytes go to `LiveTerminal`, a SwiftTerm `TerminalView` sized to the pane, so colors, `\r` progress bars and cursor movement behave like any terminal. Keys typed while a command runs go straight to the PTY.
4. **Full-pane.** Known TUIs and agents (`vim`, `htop`, `less`, `ssh`, `claude`, `codex`, `opencode` …), or any program that switches to the alternate screen, take over the pane.
5. **Snapshot.** On D, `StyledText.capture` reads scrollback and screen into a run-length list of styled spans. The block keeps that plus plain text for search, copy and AI context.

## Source layout

```text
Tethera/
├── Core/
│   ├── TerminalApp.swift          App, menu commands and shortcuts, window setup
│   ├── BlockTerminalViewModel     One session: shell, emulator, blocks, history, AI
│   ├── TerminalBlock.swift        Block model (command / AI / system), Codable
│   ├── Shell/
│   │   ├── ShellSession           forkpty via SwiftTerm LocalProcess, resize, non-blocking exit
│   │   ├── ShellEnvironment       Login-shell env capture (PATH from Finder launches)
│   │   └── OSC133Splitter         Byte stream → semantic events
│   ├── Terminal/
│   │   ├── LiveTerminal           SwiftTerm view, geometry, focus, scroll routing
│   │   ├── KittyKeyboardFilter    Drops kitty keyboard CSI-u sequences (see below)
│   │   ├── StyledText             Emulator buffer → styled spans → AttributedString
│   │   └── TerminalPalette        16-color ANSI palettes
│   ├── AI/
│   │   ├── AgentCLI               Providers: argv, login command, models, interactive programs
│   │   ├── AgentDetector          Finds installed CLIs and versions
│   │   ├── AgentRunner            Process + output parsers → AsyncStream<AgentEvent>
│   │   └── AIAssistant            Prompts, context, command extraction, destructive warnings
│   ├── AutocompleteEngine         Ghost text and the completion menu
│   ├── CommandHistoryManager      History (+ ~/.zsh_history), search, debounced saves
│   ├── GitService                 Branch, dirty, ahead/behind in one `git status`
│   └── MediaService               `preview <file>`
├── Models/                        Tabs, splits, settings (themes, terminal, AI)
├── UI/
│   ├── Blocks/                    BlockView, AIBlockView, LiveTerminalHost
│   ├── Input/                     InputBarView, CommandEditor (NSTextView)
│   ├── Design/                    Tokens, typography, motion, glass, AgentBadge
│   ├── TerminalPaneView           Block list, full-pane view, welcome
│   └── TabBarView, CommandPaletteView, SearchOverlayView, NativeSettingsView …
└── Resources/
    ├── shell/                     tethera.zsh, tethera.bash
    └── Brand/                     App icon
```

## Shell integration

zsh starts with `ZDOTDIR` pointing at generated shims in `~/Library/Application Support/Tethera/shell/zsh`. Each shim sources the user's real file, then `.zshrc` loads `tethera.zsh` and restores the user's `ZDOTDIR`. Bash uses `--rcfile` with a shim that mimics login startup. Nothing is typed into the shell, so there is no startup race. The scripts:

- emit OSC 133 A/B/C/D (exit code on D) and OSC 7 with `$HOST`
- guard against double loading
- turn off `PROMPT_SP`, since blocks are separate and the `%` marker would leak into output

The PTY gets `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=Tethera` and a UTF-8 `LANG`. Session markers inherited from a parent agent (for example `CLAUDECODE` when launched from Claude Code) are removed, so a `claude` run inside Tethera isn't treated as nested.

## Terminal emulator notes

- **PTY size.** The emulator is sized to the pane: the full pane height, so programs see a real screen. Inline blocks clip to the rows in use. SwiftTerm's `sizeChanged` drives `TIOCSWINSZ`, and the initial PTY size is read from the emulator, so the two never disagree.
- **Kitty keyboard protocol.** SwiftTerm 1.5 treats every `CSI … u` as "restore cursor" and ignores the `?`/`>`/`<`/`=` marker. Claude Code, Codex and OpenCode send `CSI ? u` at startup and then redraw with relative cursor moves, so their screens tore. `KittyKeyboardFilter` drops these sequences, and apps fall back to legacy keys.
- **Interrupts.** Exit codes 130/137/143 count as interrupted, and so does leaving an interactive program. Neither triggers ✦ Fix.

## AI

`AIAssistant` builds a prompt with OS, shell, cwd, git state and the tail of recent blocks (plus any attached blocks). `AgentRunner` runs the selected CLI with the user's login environment, `NO_COLOR=1` and stdin from `/dev/null`, then streams `.update` and `.finished`/`.failed` events. Tools are always off or read-only:

| Provider | Headless call |
| --- | --- |
| OpenCode | `opencode run --format json --agent plan [-m model]` |
| Claude Code | `claude -p --tools "" --output-format stream-json --verbose --include-partial-messages --no-session-persistence` |
| Codex | `codex exec --json --ephemeral --skip-git-repo-check -s read-only -C <cwd>` |
| Hermes | `hermes -z <prompt> --ignore-rules` |
| Gemini | `gemini -o stream-json` |
| Ollama | `ollama run <model>` |

Failures map to hints (not installed, signed out, rate-limited). Settings → AI has Sign in buttons that open the CLI's login in a new tab.

- **`#` generate.** Puts one command in the editor, never runs it, and flags destructive commands.
- **`?` ask.** Streams an AI block rendered as Markdown, with Insert/Run on code blocks.
- **✦ Fix.** Runs once after a failure, if enabled. It shows a suggestion row and ghost text, and is cancelled when the user types.

## Building and releasing

```bash
make run     # debug build
make test    # unit tests + real-shell tests
make app     # dist/Tethera.app + dist/Tethera-macOS.dmg (universal, ad-hoc signed)
```

`scripts/package.sh` puts the SwiftPM resource bundle in `Contents/Resources`. `Bundle.tethera` looks there first, because SwiftPM's generated `Bundle.module` only checks the `.app` root (which code signing forbids) and the build folder.

Pushing a `v*` tag runs `.github/workflows/release.yml`. It tests, packages, and publishes `Tethera-macOS.dmg` to the GitHub Release, using `.github/release-notes/<tag>.md` as the body. The website in `docs/` is served by GitHub Pages and links to `releases/latest/download/Tethera-macOS.dmg`.

Debug builds include `DebugHooks` (`TETHERA_SNAPSHOT_DIR`, `TETHERA_SCRIPT`). These script the app and capture its own window for screenshots, without needing Screen Recording permission.
