# Browser tools for agents (MCP)

`tethera mcp` is an MCP server, over stdin/stdout, that gives an agent the browser tab beside its
session. You watch everything it does in the pane. This page describes version 1.0.

## Adding it

**Settings → Agents → Browser for agents → Add…** writes it into an agent's MCP config, after
showing you the change: Claude Code (through its own `claude mcp add`), Codex
(`~/.codex/config.toml`), Antigravity (`~/.gemini/settings.json`), Hermes
(`~/.hermes/config.yaml`) and OpenCode (`~/.config/opencode/opencode.json`). By hand:

```bash
claude mcp add --scope user tethera -- ~/.local/bin/tethera mcp
```

```json
{ "mcpServers": { "tethera": { "command": "/Users/you/.local/bin/tethera", "args": ["mcp"] } } }
```

It must run inside a Tethera session (it finds its tab through `TETHERA_SESSION_ID`), with the
app open.

## Protocol

JSON-RPC 2.0, protocol version `2025-06-18`, tools only. The names and arguments follow Playwright
MCP's, so prompts written for it work here.

## Tools

| Tool | Arguments | Does |
| --- | --- | --- |
| `browser_navigate` | `url` | Opens a URL in the tab beside the session (opening the tab if needed). |
| `browser_navigate_back` | | Goes back. |
| `browser_snapshot` | | An accessibility-style outline of the page, with a `ref` for each element you can act on. |
| `browser_click` | `element`, `ref`, `doubleClick?` | Clicks an element from the last snapshot. |
| `browser_type` | `element`, `ref`, `text`, `submit?` | Types into an editable element; `submit` presses Enter after. |
| `browser_press_key` | `key` | Presses a key: `Enter`, `Escape`, `ArrowDown`, or a character. |
| `browser_wait_for` | `text?`, `textGone?`, `time?` | Waits for text to appear or disappear, or for a number of seconds. |
| `browser_take_screenshot` | | A PNG of the visible page. |
| `browser_evaluate` | `function` | Runs `() => { … }` in the page and returns the JSON result. |
| `browser_tabs` | `action` (`list`, `new`, `select`, `close`), `index?`, `url?` | Manages the session's tabs. |

`element` is a human-readable description, for you; `ref` is what identifies the element. Refs
change when the page does, so take a new snapshot after navigating.

## Privacy

Browser tabs use a non-persistent data store: no cookies or storage survive the tab. Nothing is
sent anywhere but the pages the agent opens.
