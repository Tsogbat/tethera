───────────────────────────────────────────

# Stage 1 — Local-First Baseline (No AI Safety Hazards)

Before introducing AI, you lock down:

- Fast PTY rendering
- Zero-lag input
- Command blocks
- Tabs & splits
- History metadata
- Persistence
- Keyboard power UX
- Scrollback + ANSI correctness

**AI must NEVER degrade baseline performance.**

AI layer stays opt-in, asynchronous, cancellable.

───────────────────────────────────────────

# Stage 2 — AI Layer 1: “Augmented Terminal”, Not “Chatbot”

This is the **first useful and low-risk AI layer** .

## Feature: Inline Command Help (Instant Explanation)

User highlights a command → press shortcut → AI returns:

- what it does
- most common flags
- safety concerns
- examples

Rules:

- **never auto-execute**
- **never “guess” filesystem paths**
- AI output displayed read-only in a side panel

## Feature: Flag & Parameter Explanation

Trigger on `grep -rin`:

- show meaning of `-r`, `-n`, `-i`

Local man-page parsing fallback when offline.

## Feature: Error Explanation + Fix Path

If a command fails (non-zero exit):

- AI summarizes failure
- suggests next logical commands (safe)
- does **not** auto-run anything

This is a **diagnostic assistant** , not a “take over my machine.”

## UX:

- side panel
- no popup boxes
- no network calls without approval

───────────────────────────────────────────

# Stage 3 — AI Layer 2: Workflow Intelligence (Still Safe)

Goal: speed up debugging and authoring without creating “AI-runs-my-OS” behavior.

## Feature: Generate Commands with Guardrails

User prompt:

> “Find all .swift files containing ‘Renderer’ and show line numbers.”

AI proposes:

<pre class="overflow-visible! px-0!" data-start="1944" data-end="1980"><div class="contain-inline-size rounded-2xl corner-superellipse/1.1 relative bg-token-sidebar-surface-primary"><div class="@w-xl/main:top-9 sticky top-[calc(--spacing(9)+var(--header-height))]"><div class="absolute end-0 bottom-0 flex h-9 items-center pe-2"><div class="bg-token-bg-elevated-secondary text-token-text-secondary flex items-center gap-4 rounded-sm px-2 font-sans text-xs"></div></div></div><div class="overflow-y-auto p-4" dir="ltr"><code class="whitespace-pre!"><span><span>grep</span><span> -RIn </span><span>"Renderer"</span><span></span><span>*.swift</span><span>
</span></span></code></div></div></pre>

User must hit **ENTER to apply** .

Never self-execute.

## Feature: Recent Working Directory Context

When suggesting commands, AI sees:

- current directory name
- filtered file list (optional)
- recent commands

No file contents, no uploads.

## Feature: Commit-Message Generator (Optional)

You run `git commit`, AI proposes a message from `git diff`.

Offline setting allowed.

## Feature: Block Summaries

Block context summary on demand:

- what command did
- key output lines
- exit code

Never replaces output.

## Feature: History Semantic Search

Search:

> “restart redis and check logs”

AI maps to:

- redis-cli
- systemctl
- tail commands

(This is where semantic search beats regex.)

───────────────────────────────────────────

# Stage 4 — AI Layer 3: Code-Aware Power-Tools (Developer-Grade)

Now the AI earns its keep.

## Feature: Code-Context Suggestions

When user sits inside a project folder:

- AI can scan file tree names
- optionally read a file the user selects

Still user-approval before execution.

Never recursive scan without permission.

## Feature: Script Refactoring (Explicit)

User pastes bash/python script into a block:

> “Make this script error-handled and POSIX-safe.”

AI returns a patch.

User manually applies.

## Feature: Query-to-Script Expansion

User prompt:

> “Write a one-liner to kill zombie processes.”

AI output:

<pre class="overflow-visible! px-0!" data-start="3335" data-end="3395"><div class="contain-inline-size rounded-2xl corner-superellipse/1.1 relative bg-token-sidebar-surface-primary"><div class="@w-xl/main:top-9 sticky top-[calc(--spacing(9)+var(--header-height))]"><div class="absolute end-0 bottom-0 flex h-9 items-center pe-2"><div class="bg-token-bg-elevated-secondary text-token-text-secondary flex items-center gap-4 rounded-sm px-2 font-sans text-xs"></div></div></div><div class="overflow-y-auto p-4" dir="ltr"><code class="whitespace-pre!"><span><span>ps aux | </span><span>grep</span><span> Z | awk </span><span>'{ print $2 }'</span><span> | xargs </span><span>kill</span><span> -</span><span>9</span><span>
</span></span></code></div></div></pre>

User executes manually.

## Feature: Package Manager Suggestions

Based on an error:

> missing `libssh2`
>
> AI suggests:

<pre class="overflow-visible! px-0!" data-start="3515" data-end="3543"><div class="contain-inline-size rounded-2xl corner-superellipse/1.1 relative bg-token-sidebar-surface-primary"><div class="@w-xl/main:top-9 sticky top-[calc(--spacing(9)+var(--header-height))]"><div class="absolute end-0 bottom-0 flex h-9 items-center pe-2"><div class="bg-token-bg-elevated-secondary text-token-text-secondary flex items-center gap-4 rounded-sm px-2 font-sans text-xs"></div></div></div><div class="overflow-y-auto p-4" dir="ltr"><code class="whitespace-pre!"><span><span>brew</span><span> install libssh2
</span></span></code></div></div></pre>

Never runs brew automatically.

───────────────────────────────────────────

# Stage 5 — AI Layer 4: Project Automation (Trusted Mode)

Only after months of stable usage and guardrails do you allow deeper workflows.

## Feature: AI Task Mode (Optional)

Example task:

> “Migrate this folder into a new Swift Package.”

AI:

- proposes edits
- shows file diff
- user approves per file

This is **AI as a code-patch generator** , not an OS operator.

## Feature: AI-Assisted Command Blocks

A block can attach:

- explanation
- sample follow-ups
- grep filters
- safety notes
- man-page references

## Feature: Project-Memory (Per Repo)

AI stores:

- commands used most in that repo
- environment heuristics
- recommended workflows

Everything local.

───────────────────────────────────────────

# Stage 6 — AI Layer 5: Hyper Productivity (Trust + Guardrails)

This is “Warp-like AI”—but sane.

## Feature: LLM-Assisted Shell Session (Manual Commit)

User asks:

> “Create a bash script that monitors Metal GPU usage and logs to CSV.”

AI generates script → user approves → assigns permissions.

## Feature: GPT-style Agent Mode (Restricted)

Agent only:

- navigates directories
- reads specific files
- outputs command sequence

User executes manually.

**No direct system calls.** This avoids catastrophic damage.

───────────────────────────────────────────

# Stage 7 — Safety Enforcement (No Compromise)

Before anything:

### Execution Rule 1

**AI never auto-executes.**

### Rule 2

**User sees the command before execution.**

### Rule 3

**AI output is advisory, not authoritative.**

### Rule 4

**No rm, sudo, destructive ops without explicit warnings.**

### Rule 5

**AI is cancellable instantly and offline-capable.**

───────────────────────────────────────────

# What You Do NOT Build (Good Discipline)

- No “chatbot on your terminal”
- No remote telemetry
- No cloud-forced features
- No phoning home logs
- No rewriting commands silently
- No AI replacing TUI flows (like nvim)

You are not Warp.

You are **Tethera: developer-grade, zero-bullshit AI assistance.**

───────────────────────────────────────────

# Integration Targets (Simple First)

- Local toggle switch (🟢 AI on / 🔴 AI off)
- Local model toggle (Claude / OpenAI / Gemini)
- Offline fallback (man-based suggestions)
- Strict permissions boundary

───────────────────────────────────────────

# Final Vision

A terminal that:

- runs at Metal speed
- renders blocks fast
- treats AI as a **“knowledge prosthetic”**
- gives developers leverage
- never steals control
- never slows down the render loop
- stays private and local-first
