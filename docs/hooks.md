# Hooks, approvals and policies

How agents tell Tethera what they're doing, how Tethera answers their permission requests, and
the file formats involved. This page describes version 1.0; the formats are versioned below and
stay compatible through 1.x.

## Connecting an agent

**Settings → Agents → Connect…** adds Tethera's hooks to an agent's own config, after showing
you the change. Each file is backed up first (`<file>.tethera-backup-<time>`), and **Disconnect**
removes exactly what was added.

| Agent | Where | What runs |
| --- | --- | --- |
| Claude Code | `~/.claude/settings.json` | `tethera hook claude` on its hook events; `tethera statusline claude` as the status line (optional) |
| Codex | `~/.codex/hooks.json` | `tethera hook codex` |
| Antigravity | `~/.gemini/config/hooks.json` | `tethera hook agy <event>`, `tethera title agy` |
| Hermes | `~/.hermes/config.yaml` | `tethera hook hermes` |
| OpenCode | `~/.config/opencode/plugins/tethera.js` | `tethera hook opencode` |

A hook outside a Tethera session (no `TETHERA_SESSION_ID`) does nothing.

## What events mean

| Claude Code event | Agent state |
| --- | --- |
| `UserPromptSubmit`, `PreToolUse` | working (with the prompt or the tool as its message) |
| `PermissionRequest` | needs you: permission |
| `Notification` with `permission_prompt` | needs you: permission |
| `Notification` with `elicitation_dialog` | needs you: question |
| `Notification` with `idle_prompt` | waiting |
| `Stop` | done (with the last message) |
| `StopFailure` | error |
| `SessionStart`, `SessionEnd` | waiting |

The status line adds the model, context use and the running cost. Codex maps the same way.

**Without hooks**, any program can report its state with OSC 7501, and agents that don't have
hooks are tracked from their output (quiet for a while means waiting):

```
ESC ] 7501 ; state=blocked:kind=permission:app=claude:msg=<base64> BEL
```

`state` is `idle`, `working`, `done`, `blocked` or `error`; `kind` is `permission`, `question` or
`auth`; `msg` and `title` are base64 UTF-8.

## Approvals

When Claude Code asks for permission it runs `tethera hook claude` with the `PermissionRequest`
JSON and waits for its output (the hook's timeout is 600 seconds). Tethera then:

1. **Checks your rules.** If a rule allows or denies the request, the hook prints the decision at
   once. This works with the app closed.
2. **Asks you.** Otherwise the hook asks the app over its socket and waits. The request shows in
   the Approvals inbox (<kbd>⌥⌘A</kbd>), as a notification with Allow and Deny, on the phone
   dashboard, and as a push if you've turned that on.
3. **Prints the answer** in Claude Code's format:

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Tethera."}}}
```

"Answer in terminal", no app, or no answer within 590 seconds prints nothing, and Claude Code
shows its own dialog.

## Policies (format 1)

Your rules are `TETHERA_HOME/policies.json`; a team's are `policies.json` at the top of the team
repository (synced to `TETHERA_HOME/team/policies.json`). Both are a JSON array of rules, or an
object `{"rules": [...]}`:

```json
[
  { "id": "1", "tool": "Bash", "pattern": "*git push*--force*", "action": "ask" },
  { "id": "2", "tool": "Bash", "pattern": "*deploy*", "action": "deny", "note": "Deploys go through a person." },
  { "id": "3", "tool": "Bash", "pattern": "npm test*", "action": "allow" },
  { "id": "4", "tool": "Read", "action": "allow" },
  { "id": "5", "agent": "codex", "tool": "Edit", "pattern": "/\\.env(\\.|$)/", "action": "deny" }
]
```

| Field | Meaning |
| --- | --- |
| `id` | Any unique string. |
| `agent` | Optional: `claude`, `codex`, …; any agent when absent. |
| `tool` | The tool's name, or a glob (`mcp__*`); `*` is any tool. |
| `pattern` | Optional glob matched against what the tool acts on: the command, file path or URL. `*` is anything, `?` one character. `/…/` is a regular expression instead. |
| `action` | `allow`, `deny` or `ask`. |
| `note` | Optional; shown when the rule denies, and in the audit log. |

The team's rules come first, then yours, and **the first rule that matches decides**. `ask`, or no
match, brings the request to you. **An allow rule never covers a shell command that chains,
pipes, substitutes or redirects** (`;` `&` `|` `` ` `` `$(` `>` `<` or a newline), so `npm test*`
can't allow `npm test && rm -rf ~`; deny and ask rules still apply to them.

## Journal (format 1)

Everything above is recorded in `TETHERA_HOME/journal/YYYY-MM-DD.jsonl`, one JSON object per
line, on your Mac only. The audit log and the cost dashboard read it.

```json
{"at":"2026-11-20T14:26:20Z","kind":"approval","agent":"claude","tool":"Bash","detail":"npm test","decision":"allow","by":"policy","message":"Bash npm test* → allow"}
```

| Field | Meaning |
| --- | --- |
| `at` | ISO 8601 time. |
| `kind` | `state`, `approval`, `cost`, `budget`, `started` or `ended`. |
| `session`, `sessionName`, `agent`, `repo` | Which session, agent and folder. |
| `state`, `message` | For `state`: the new state and the agent's message. |
| `tool`, `detail`, `decision`, `by` | For `approval`: the tool, what it acted on, `allow`/`deny`/`terminal`, and who answered: `you`, `phone`, `policy` or `team policy`. |
| `costUSD` | For `cost`: the conversation's running total. For `budget`: today's spend. |

New fields may be added in 1.x; readers should ignore fields they don't know.
