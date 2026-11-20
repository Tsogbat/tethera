# Tethera Architecture

Tethera has two processes:

- **The app** (`Tethera`, SwiftUI + AppKit) renders sessions and the agent UI.
- **The session daemon** (`tethera daemon`, bundled as `Contents/Helpers/tethera`) owns every PTY.

Sessions live in the daemon, so they keep running when the app quits. The app attaches to them over a Unix socket.

```text
 Tethera.app                                            tethera daemon (one per user)
 ┌──────────────────────────────┐   framed protocol    ┌─────────────────────────────────────────┐
 │ Sidebar · Panes · Inspector  │◀──── d.sock 0600 ───▶│ SessionHost × N                         │
 │ DaemonClient ─ sessions[]    │  control: JSON       │   forkpty(login shell)  ◀── input       │
 │ SessionTerminal (SwiftTerm,  │  data: output frames │   headless SwiftTerm Terminal  (record) │
 │   Metal) per session         │  snapshot on attach  │   QueryFilter → clients                 │
 └──────────────────────────────┘                      │   PromptScanner (OSC 133)               │
        ▲                                              │   ProcessInspector (foreground agent)   │
        │ tethera hook <agent>  (agent hooks, stdin)   │   OSC 7501 / hooks → AgentInfo          │
        └──────────────────────────────────────────────│ sessions.json + snapshots/ (cold restore)│
                                                       └─────────────────────────────────────────┘
```

## Packages

| Target | Role |
| --- | --- |
| `TetheraKit` | Wire protocol (`Frame`, `FrameDecoder`, `ControlMessage`), models (`SessionInfo`, `AgentInfo`, `AgentKind`), `FramedSocket`/`UnixSocket`/`DaemonLauncher`, `ShellLaunch` (login shell + OSC 133 integration via `ZDOTDIR` / `--rcfile`), `HookMapper`, `AgentIntegrations` (hooks and the browser MCP server), `AppChannel`. |
| `CPTY` | `forkpty` + exec in C: resets every signal and the signal mask, and closes inherited fds in the child. Swift can't run safely between fork and exec. |
| `TetheraDaemon` | `Daemon` (socket server, routing, timers, persistence), `SessionHost`, `VTSnapshot`, `QueryFilter`, `PromptScanner`, `ProcessInspector`. |
| `TetheraCLI` → `tethera` | `daemon`, `list`, `new`, `attach`, `rename`, `close`, `shutdown`, `hook`, `statusline`, `title`, `open`, `changes`, `mcp`. |
| `Tethera` | The app: `DaemonClient`, `Workspace` (panes, focus, layout), `SessionTerminal` (SwiftTerm view per session), Home, views. |

## The daemon is the terminal of record

Each session feeds its output into a headless SwiftTerm `Terminal`. That emulator:

- **Answers every query** a program sends: DA, DSR, DECRQM, color queries, kitty keyboard, and the OSC 7501 probe. `QueryFilter` strips those queries from what clients receive, so a client never answers too. Without this, the program would read duplicate replies as typed input.
- **Serves snapshots.** On attach, `VTSnapshot` serializes the scrollback, screen, SGR attributes, cursor, scroll region and input modes (alt screen, bracketed paste, mouse, application cursor, kitty flags; cursor visibility via DECRQM) as VT sequences. A fresh client replays them and shows the same screen. Then a brief size nudge makes full-screen agents redraw.
- **Keeps PTYs drained.** PTYs are drained even with no client attached, so a slow client never blocks a shell. A client that falls 32 MB behind is dropped and reattaches with a snapshot.

## Protocol

Each frame is `[u32 length][u8 kind][payload]`. The kinds are:

- **control:** a JSON `ControlMessage`
- **output:** session id, sequence number, bytes
- **snapshot:** same layout as output
- **input:** session id, bytes

Control messages: `hello`/`welcome` (protocol version), `list`/`sessions`, `subscribe`, `create`/`created`, `attach`, `detach`, `resize`, `signal`, `rename`, `reorder`, `close`, `hook`, `updated`, `removed`, `shutdown`, `error`.

**Security.** The socket is `~/Library/Application Support/Tethera/d.sock`, mode 0600, and the daemon checks every caller with `getpeereid`. There is no TCP listener. Remote access will reuse the same protocol over SSH stdio: `tethera attach` already works from any terminal.

**Lifecycle.**
- The app starts the daemon detached (`posix_spawn` with `POSIX_SPAWN_SETSID`) when the socket is missing. A lock file keeps it to one daemon per user.
- ⌘Q leaves the daemon running. ⌥⌘Q sends `shutdown`.
- Every 5 s the daemon saves `sessions.json` and a VT snapshot of each changed session. After a reboot, sessions come back *cold* and revive on attach with their history and folder.

## Agent awareness

`SessionInfo.agent` is driven by these sources, strongest first:

1. **Hooks.** `tethera hook <source> [event]` runs inside the agent's process tree. It reads the session from `TETHERA_SESSION_ID`/`TETHERA_SOCKET`, timestamps the event (background hooks can arrive out of order), and forwards it. `HookMapper` turns Claude Code, Codex, Antigravity, Hermes and OpenCode payloads into `AgentUpdate`s: working, needs you (permission/question/auth), done, error, tool, model, context %, cost.
2. **OSC 7501 Program Status.** Claude Code reports `idle|working|blocked|done|error` itself once the terminal answers its probe; the daemon's emulator answers it.
3. **OSC 9/99/777 and BEL.** These bump `attention` for notifications.
4. **The foreground process.** `tcgetpgrp` on the PTY, then `proc_pidpath` and `KERN_PROCARGS2`, identify the agent, including Node and Python agents by their arguments. Output activity marks it working; two seconds of quiet means waiting. The agent is forgotten only when the shell itself is back in front.

`AgentIntegrations` writes the hooks:

| Agent | What it writes |
| --- | --- |
| Claude Code | `~/.claude/settings.json` hooks; background hooks, except an in-line permission hook that prints nothing. Optionally wraps the status line: the wrapper reports the JSON, then runs the user's saved command. |
| Codex | `~/.codex/hooks.json` |
| Antigravity | `~/.gemini/config/hooks.json`, plus a `title` command for live state |
| Hermes | A marked block appended to `~/.hermes/config.yaml`, never rewritten |
| OpenCode | A plugin file Tethera owns |

Every change is previewed as a diff, backed up, and reversible. Hooks point at `~/.local/bin/tethera`, a stable link with no spaces, because Hermes runs hook commands without a shell.

## Shell support

Sessions run the user's login shell:

- **zsh:** loaded through a `ZDOTDIR` shim that sources the user's own files.
- **bash:** loaded with `--rcfile`.

Tethera's script only emits OSC 133 prompt marks and OSC 7 cwd; the user's rc files are never edited. The PTY environment adds `TERM_PROGRAM=Tethera`, `TETHERA_SESSION_ID` and `TETHERA_SOCKET`, and drops session markers inherited from a parent agent, such as `CLAUDECODE`.

## Rendering

The renderer is SwiftTerm 1.99.1, pinned, on its 2.0 track with Metal enabled. It sits behind `TerminalSurface`, so libghostty can be benchmarked later. Each session's view stays attached while it's on screen and for the six most recently used sessions; the rest detach and reattach from a snapshot. Other details:

- **Nerd Font icons** fall back to the bundled Symbols Nerd Font through SwiftTerm's glyph-fallback provider.
- **Ligatures** are off: a terminal draws one character per cell.

## Panes and Home

A pane shows a `PaneContent`: `.home`, `.session(id)`, `.file(path)`, `.browser(tab)` or `.changes(session)`. Tools open beside the session that asked for them (`Workspace.open(_:besideSession:)`), up to four panes. The layout (panes, axis, focus) is saved in the app's defaults; layouts from 0.4, which only had a session id, migrate on read. With no sessions the window shows Home, rather than starting a shell on its own.

Home is SwiftUI lists, plus `RetroComputerView`: an `SCNView` of the model in `Views/Retro/RetroComputer.swift` (plain SceneKit, built from boxes and a swept tube). It renders only while its window is key and visible, floats once when it appears, and then holds still, so an idle Home costs nothing. The same model renders the app icon (`scripts/render_icon.sh`), and the website's three.js scene uses the same dimensions.

## Tools

| Tool | How |
| --- | --- |
| Editor | `NSTextView` (TextKit 1) with a line-number gutter beside the scroll view; `SyntaxHighlighter` colors with a few regexes per language as temporary attributes. `EditorDocument` watches the file (`DispatchSource`, re-armed after atomic renames): a clean buffer reloads, a dirty one shows Reload / Keep Mine / Compare. |
| Viewers | ImageIO, PDFKit, AVKit, `AttributedString(markdown:)`, and `QLPreviewView` for the rest. |
| Changes | `git status`/`git diff` re-run on FSEvents from the repo (git's own bookkeeping ignored), files sorted by modification time. |
| Browser | `WKWebView` tabs in `BrowserStore`, with a non-persistent data store. `PreviewDetector` spots dev-server URLs in session output (colors stripped first). |
| Music | Music and Spotify post their state as distributed notifications; controls and artwork go through AppleScript. |

**The app channel.** Things only the app can do (open a pane, drive a browser tab) go over a second socket, `app.sock` (0600, `getpeereid`), with one JSON object per line: `AppChannel` in TetheraKit, `AppServer` in the app. `tethera open` and `tethera mcp` use it. The daemon isn't involved, so it works whatever version of the daemon is running.

**Approvals.** Claude Code's `PermissionRequest` hook (`tethera hook claude`, timeout 600 s) asks the app over `app.sock` (`approval.request`) and blocks. `ApprovalCenter` holds the request until it gets an answer from the inbox, a notification action (category `tethera.approval`) or, later, the phone. The CLI then prints Claude's decision (`ApprovalDecision.claude`). "Answer in terminal", no app, or a timeout at 590 s prints nothing, and Claude shows its own dialog. If the hook process goes away first (Claude answered in its own dialog), the connection closes and the request leaves the inbox.

**Worktrees.** `WorktreeService` runs `git worktree add -b tethera/<agent>-N <repo>.worktrees/<agent>-N <base>` and remembers the base in `branch.<name>.tetheraBase`. Merge is `--no-ff` in the main checkout, refused if either side has uncommitted work, and aborted on conflicts. `WorktreeMonitor` caches each folder's repository and worktree, for grouping and labels.

**Journal.** The app appends one JSON line per event to `TETHERA_HOME/journal/YYYY-MM-DD.jsonl`: agent state changes (with the last message), costs (Claude's running total from its status line), approvals, budgets, sessions starting and ending. "While you were away" (`AwayTracker`, after 15 minutes in the background or asleep) and `BudgetWatcher` read it. Spend is how far each session's running total grew, and a total that drops counts as a new conversation.

**Transcripts.** `TranscriptParser` reads Claude Code logs (`~/.claude/projects/<cwd, non-alphanumerics as ->/*.jsonl`) and Codex logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, matched by `cwd`) into steps, skipping anything it doesn't recognize. Both formats are the agents' own and can change. The pane tails the file while it's open.

**Status line.** `tethera statusline claude --format '…'` renders `{model} {context} {cost} {branch} {folder} {time}` from the JSON Claude Code sends; a placeholder with no value drops with its separator. The branch is read from `.git/HEAD` directly so it stays fast.

**`tethera mcp`** is a stdio MCP server (JSON-RPC, protocol `2025-06-18`) exposing Playwright MCP's browser tools. Each call goes to the app, which acts in the tab beside the calling session (`TETHERA_SESSION_ID`). Snapshots are an accessibility-style outline with `ref`s, built by a script injected into the page. Settings → Agents adds it to each agent's config with the same preview/backup/undo as hooks (Claude Code through its own `claude mcp add`).

**Other Macs.** `DaemonClient` holds one connection per daemon: this Mac's over the Unix socket, and one per remote Mac over `ssh -T -o BatchMode=yes <address> '<find tethera> bridge'`, with ssh's stdin and stdout on one end of a `socketpair` and a `FramedSocket` on the other. `tethera bridge` on the far side just copies bytes between its stdin/stdout and its own daemon's socket (starting it if needed), so the protocol is the same everywhere. Sessions arriving from a remote connection get `SessionInfo.host` set to the host's id (daemons never set it), and every command goes to the connection that owns the session. A session two connections both report (the same Mac added twice) is listed once. Remote sessions stay listed while their connection retries (backing off to a minute), and anything that reads files (Changes, Git, transcripts, worktrees, previews) only uses sessions on this Mac (`SessionInfo.localFolder`).

**Phone.** `PhoneServer` is a small HTTP/1.1 server on Network.framework, off until it's turned on. It binds the Tailscale address (100.64.0.0/10, found with `getifaddrs`), or every interface for "Local network". The page (`PhoneDashboard`, plain HTML and JS) is public; everything under `/api` needs `Authorization: Bearer <pairing token>`. The token reaches the phone in the URL's fragment (the QR code), which browsers never send to a server, and the page keeps it in `localStorage`. `GET /api/state` lists agents and pending approvals; `POST /api/approvals/<id>/<allow|deny>` answers through `ApprovalCenter`; `POST /api/sessions/<id>/reply` types one line into a session only when its agent is asking a question (not a permission prompt, not a shell). **Push** (`PushNotifier`) posts ntfy's JSON format to `ntfy.sh` or your own server on a random topic, only after two minutes without keyboard or mouse input. Its Allow and Deny buttons are one-time links (`/a/<nonce>`) for that approval, so the pairing token never passes through ntfy.

A custom `TETHERA_HOME` also gets its own defaults suite (`AppDefaults`), so test runs never touch the layout or preferences of the Tethera you use.

## Building and releasing

```bash
make run      # debug build
make test     # protocol, filters, snapshot round-trips, hook mapping, config merges, a real daemon + zsh session
make app      # dist/Tethera.app + dist/Tethera-macOS.dmg
```

`scripts/render_icon.sh icon` regenerates the app icon set, the bundled brand icon and the website icons from the 3D model; `preview <png>` renders a contact sheet at every size.

`scripts/package.sh` builds arm64 and x86_64 separately with SwiftPM's native build system and merges them with `lipo`. It copies `tethera-cli` to `Contents/Helpers/tethera`, signs the helper and then the app, and creates the DMG.

Pushing a `v*` tag runs `.github/workflows/release.yml`, which tests, packages and publishes to the GitHub Release. It publishes `Tethera-macOS.dmg` and its `.sha256`. The website is `docs/` on GitHub Pages, including `install.sh` (the one-line installer). A Homebrew cask lives in `Tsogbat/homebrew-tap`.

**Updates.** `Updater` checks `releases/latest` daily and only offers a release that has `Tethera-macOS.dmg.sig`. That is an Ed25519 signature of the DMG, checked against the public key built into the app. It then mounts the DMG, checks the bundle id and version, and hands a detached helper the swap: wait for the app to quit, replace the bundle (restoring the old one if the copy fails), reopen. The daemon isn't touched, so sessions keep running. Releases are signed on the maintainer's Mac, so the private key never leaves it: `scripts/sign_release.sh vX.Y.Z` (key in `~/.config/tethera/update-signing.key`; `scripts/sign_update.swift` does the cryptography). CI signs instead if a `TETHERA_UPDATE_KEY` secret is set.

Debug builds include `DebugHooks` (`TETHERA_SNAPSHOT_DIR`, `TETHERA_SCRIPT`) for scripted runs and window captures. `TETHERA_HOME` points the app and daemon at an isolated session store for tests.
