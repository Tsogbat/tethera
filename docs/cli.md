# The `tethera` command

`tethera` talks to the same session daemon as the app. It's inside the app at
`Tethera.app/Contents/Helpers/tethera`, and the installer (or connecting an agent) links it at
`~/.local/bin/tethera`. This page describes version 1.0; commands and their output keep working
the same way through 1.x.

## Sessions

| Command | What it does |
| --- | --- |
| `tethera list` (`ls`) | Every session: short id, name, what it's doing, folder. |
| `tethera new [--name N] [--cwd DIR] [--attach] [--] [command…]` | Starts a session. A command is typed into the new shell once its prompt is up; the session outlives it. `--attach` attaches this terminal right away. |
| `tethera attach <name\|id>` (`a`) | Attaches this terminal to a session; <kbd>⌃\</kbd> detaches. Works over SSH. |
| `tethera rename <name\|id> <new name>` | An empty name goes back to following the folder. |
| `tethera close <name\|id>` (`kill`) | Ends a session (hangs up its shell). |
| `tethera shutdown` | Ends every session and stops the daemon. |
| `tethera version` | Prints `tethera <version>`. |

A session can be named by its name or by any unique prefix of its id or name.

## Beside a session

These run inside a Tethera session and act on the pane next to it. They need the app running.

| Command | What it does |
| --- | --- |
| `tethera open <file\|folder\|url>` | Files open in the editor or a viewer, folders in a new session, URLs in a browser tab. Paths are relative to where you run it. |
| `tethera changes` | Opens the live diff of this session's repository. |
| `tethera mcp` | The browser beside this session, as an MCP server on stdin/stdout. See [mcp.md](mcp.md). |

## Other Macs and updates

| Command | What it does |
| --- | --- |
| `tethera bridge` | Relays the daemon's protocol over stdin/stdout, starting the daemon if needed. Another Mac's Tethera runs `ssh <this-mac> tethera bridge`. |
| `tethera handover` | The running daemon becomes this version of `tethera` in the same process: every shell keeps running, screens are carried over, clients reconnect. Prints `daemon <old> → <new> (pid N); K session(s) kept`. The app does this by itself after an update. |
| `tethera daemon` | Runs the daemon in the foreground. You don't need this: every command starts it when it isn't running. |

## For agents

These are what agents' hooks and status lines run. They read JSON on stdin, always exit 0, and
never slow the agent down. See [hooks.md](hooks.md).

| Command | What it does |
| --- | --- |
| `tethera hook <source> [event]` | Reports an agent event to the session it runs in. Sources: `claude`, `codex`, `codex-notify`, `agy`, `hermes`, `opencode`. For a Claude Code `PermissionRequest`, it applies your approval rules and asks the app, then prints Claude's decision. |
| `tethera statusline claude [--format F]` | Reports Claude Code's status line JSON. With `--format`, prints the line from placeholders `{model}` `{context}` `{cost}` `{branch}` `{folder}` `{time}`; otherwise runs your own status line command. |
| `tethera title agy` | Antigravity's title command: reports its state and prints the conversation title. |

## Environment

| Variable | Meaning |
| --- | --- |
| `TETHERA_HOME` | Where the daemon keeps its socket, state and journal. Default `~/Library/Application Support/Tethera`. A different home is a separate set of sessions, and the app gets its own preferences for it. |
| `TETHERA_SESSION_ID` | Set inside every session; hooks and `tethera open` use it to find their session. |
| `TETHERA_CONFIG_HOME` | Where agent config files are looked for, instead of your home folder. For testing. |

## Exit status

`0` on success; `1` with a message on standard error otherwise (no daemon, no such session, a
refused handover). `hook`, `statusline` and `title` always exit 0.
