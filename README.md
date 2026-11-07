<p align="center">
  <img src="Tethera/Resources/Brand/AppIcon.png" width="112" alt="Tethera icon">
</p>

<h1 align="center">Tethera</h1>

<p align="center">
  A terminal for running and supervising AI coding agents.<br>
  Your shell, persistent sessions, and one place to see what every agent is doing.
</p>

<p align="center">
  <a href="https://github.com/Tsogbat/tethera/releases/latest/download/Tethera-macOS.dmg"><b>Download for Mac</b></a> ·
  <a href="https://tsogbat.github.io/tethera/">Website</a> ·
  <a href="https://github.com/Tsogbat/tethera/releases">Releases</a>
</p>

<p align="center">
  <img src="docs/assets/screens/v05-hero.png" alt="Tethera's Home: a small 3D retro computer above lists to start an agent, recent folders, connected agents and running sessions">
</p>

## Why

Coding agents run in terminals, and you end up with five of them in five tabs, checking each one to see if it's waiting on you. Tethera is a terminal built for that:

- **Sessions persist.** Every session lives in a small background daemon, so your shells — and the agents running in them — keep going when you quit the app, and come back exactly as they were. After a reboot they return with their history and folder.
- **Agent-aware.** The sidebar shows which agent runs in which session and what it's doing: working, waiting, **needs you**, done, error. You get a notification and a Dock badge when one needs you, and ⇧⌘U takes you there.
- **A real terminal.** Your own zsh or bash, exactly as you configured it, in fast GPU-rendered panes (SwiftTerm with Metal). TUIs, `vim`, `ssh`, Nerd Font prompts — everything works.
- **Home.** Where Tethera opens: start any agent, pick up a recent folder, see which integrations are connected and who's running — with a little 3D computer whose keys you can press.
- **Your tools, beside the agent.** The repo's changes as they happen, a preview of the app it's building, a browser it can drive, an editor and viewers for the files it makes, and your music.

## Tools

Tools open as panes beside the session that needs them.

| Tool | What it does |
| --- | --- |
| **Changes** (⇧⌘E) | The session's repository, live: files newest-first, the diff of the selected one; stage, open or discard. |
| **Preview** | When a dev server starts in a session, **Preview :PORT** appears in the title bar; one click opens it beside the session. ⌘-click a localhost link does the same. |
| **Browser** (⌘L) | A real browser tab. Settings → Agents → *Browser for agents* adds `tethera mcp` to Claude Code, Codex, OpenCode, Hermes or Gemini, so the agent can open pages, read them, click, type and take screenshots (Playwright MCP's tool names) while you watch. |
| **Editor** | Your terminal font, line numbers, highlighting, find, ⌃G go to line, ⌘S. When an agent changes a file you have open, it reloads — or asks, if you've edited it too. |
| **Viewers** | Images, PDFs, video and audio, rendered Markdown, and Quick Look for everything else. |
| **Music** | What's playing in Music or Spotify, in the status bar, with play/pause and skip. |

Open anything with ⌘O, the palette, or `tethera open <file|folder|url>` from a session.

<p align="center">
  <img src="docs/assets/screens/v06-preview.png" width="49%" alt="A dev server with its preview open beside it">
  <img src="docs/assets/screens/v06-changes.png" width="49%" alt="The Changes pane">
</p>

## Agents

| Agent | Works out of the box | With Connect (Settings → Agents) |
| --- | --- | --- |
| Claude Code | state from its own status reports (OSC 7501) | tool calls, permission requests, finished turns; model, context and cost from your status line (which keeps working unchanged) |
| Codex | detected, working/waiting | approvals, finished turns (trust the hooks once in `/hooks`) |
| OpenCode | detected, working/waiting | permission requests, finished turns (a small plugin) |
| Hermes | detected, working/waiting | tool calls, approvals, turn results (approve the hooks once) |
| Antigravity (`agy`) | detected, working/waiting | tool confirmation, cost, finished turns |
| Gemini CLI, Aider, … | detected, working/waiting | — |
| Ollama | `ollama launch claude/codex/opencode` from **+** runs agents on local models | — |

Connect shows the exact change to each config file before writing it, saves a backup, and Disconnect removes only Tethera's entries. Agents always run with your own logins — Tethera has no accounts or API keys.

Agents start inside a shell, so when one exits, the session (and its scrollback) stays.

## The window

- **Home** (⇧⌘H) — start a shell or any agent (⌥⌘1…4), recent folders, integrations, and every running session, needs-you first.
- **Sidebar** — every session, named after its folder until you rename it (double-click). A solid dot and bold name mark a session that needs you; a spinner, one that's working. The look is monochrome: red only ever means an error.
- **Panes** — ⌘D / ⇧⌘D split; ⌘W closes a pane but the session keeps running.
- **Inspector** (⌥⌘I) — the agent's state, message, current tool, model / context / cost, and Interrupt; a Git tab to stage, commit, fetch, pull and push.
- **Agents overview** (⇧⌘A) — one table of every session, sorted by what needs you.
- **Command palette** (⌘K) — sessions, new agent sessions, splits, settings.

<p align="center">
  <img src="docs/assets/screens/v05-overview.png" width="49%" alt="Agents overview">
  <img src="docs/assets/screens/v05-light.png" width="49%" alt="Paper (light) theme">
</p>

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⇧⌘H | Home |
| ⌘T | New shell session |
| ⌥⌘1…⌥⌘4 | New Claude Code, Codex, OpenCode or Hermes session |
| ⇧⌘O | New shell in a folder |
| ⌘O | Open a file |
| ⌘L | New browser tab |
| ⇧⌘E | Changes |
| ⌘S · ⌃G | Save · go to line (editor) |
| ⌘K / ⌘P | Command palette |
| ⇧⌘A | Agents overview |
| ⇧⌘U | Go to the session that needs you |
| ⌘] / ⌘[ · ⌘1…⌘9 | Next / previous session · session by position |
| ⌘D / ⇧⌘D | Split right / down |
| ⌘W | Close pane (the session keeps running) |
| ⌥⌘W | End session |
| ⇧⌘R | Rename session |
| ⌥⌘I | Inspector |
| ⌘+ / ⌘- / ⌘0 | Font size |
| ⌘Q | Quit — sessions keep running |
| ⌥⌘Q | Quit and end all sessions |

## The `tethera` command

The session daemon is also a CLI (linked at `~/.local/bin/tethera` once you connect an agent):

```bash
tethera list                         # sessions, their agents and state
tethera new --name api --attach      # a new session, attached to this terminal
tethera attach api                   # attach from any terminal (⌃\ detaches) — also over SSH
tethera close api
tethera open src/app.ts              # open a file (or folder, or URL) beside this session
tethera changes                      # this session's live diff
tethera mcp                          # the browser, as an MCP server for agents
```

## Install

1. [Download **Tethera-macOS.dmg**](https://github.com/Tsogbat/tethera/releases/latest/download/Tethera-macOS.dmg), open it, and drag Tethera to Applications.
2. The build isn't notarized yet, so the first time, right-click Tethera.app → **Open** → **Open**, or:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Tethera.app
   ```

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

### Build from source

```bash
git clone https://github.com/Tsogbat/tethera.git
cd tethera
make run          # debug build
make test         # unit, protocol, daemon and real-shell tests
make app          # dist/Tethera.app and dist/Tethera-macOS.dmg (universal)
```

Needs Xcode 26 (Swift 6.2). The icon is rendered from the same SceneKit model as Home: `scripts/render_icon.sh icon`.

## What's next

- Agent workflows: run, monitor and debug agents across git worktrees
- Git and Homebrew panels
- Remote control of your sessions

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md).

## License

GNU Affero General Public License v3 — see [LICENCE.TXT](LICENCE.TXT). Bundled fonts: Geist Mono, IBM Plex Mono and JetBrains Mono (SIL OFL 1.1); Symbols Nerd Font (MIT).
