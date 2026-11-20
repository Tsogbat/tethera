import AppKit
import Foundation
import TetheraKit

/// The phone dashboard's page and the state it polls.
@MainActor
enum PhoneDashboard {
    /// Agents first, needs-you first; approvals oldest first. Shells only as a count.
    static func state() -> [String: Any] {
        let client = DaemonClient.shared
        let iso = ISO8601DateFormatter()
        let agents = client.sessions.filter { $0.agent != nil }
            .sorted { ($0.agent!.state.attentionRank, $0.order) < ($1.agent!.state.attentionRank, $1.order) }
        let sessions: [[String: Any]] = agents.map { session in
            let agent = session.agent!
            var row: [String: Any] = [
                "id": session.id.uuidString,
                "name": session.name,
                "agent": agent.kind.displayName,
                "state": agent.state.rawValue,
                "line": session.stateLine.text,
                "since": iso.string(from: agent.since),
            ]
            if let host = client.host(session.host) { row["mac"] = host.name }
            if let message = agent.message { row["message"] = message }
            if PhoneServer.takesReplies(session) { row["replies"] = true }
            if let cost = agent.costUSD { row["cost"] = cost }
            if let context = agent.contextPercent { row["context"] = context }
            return row
        }
        let approvals: [[String: Any]] = ApprovalCenter.shared.pending.map { approval in
            [
                "id": approval.id.uuidString,
                "agent": approval.agent.displayName,
                "tool": approval.tool,
                "summary": approval.summary,
                "session": client.session(approval.session)?.name ?? "",
                "since": iso.string(from: approval.since),
            ]
        }
        return [
            "mac": Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            "sessions": sessions,
            "shells": client.sessions.count - agents.count,
            "approvals": approvals,
            "spentToday": BudgetWatcher.shared.todaySpend,
        ]
    }

    static let icon: Data = {
        guard let image = BrandAssets.appIcon else { return Data() }
        let size = NSSize(width: 180, height: 180)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let bitmap else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }()

    static let manifest = """
    {"name":"Tethera","short_name":"Tethera","start_url":"/","display":"standalone",
     "background_color":"#111111","theme_color":"#111111","icons":[{"src":"/icon.png","sizes":"180x180","type":"image/png"}]}
    """

    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="theme-color" content="#111111">
    <link rel="manifest" href="/manifest.webmanifest">
    <link rel="apple-touch-icon" href="/icon.png">
    <title>Tethera</title>
    <style>
    :root {
      --bg: #F4F3F0; --surface: #FFFFFF; --ink: #1A1A1A; --ink-2: #4A4844; --ink-3: #66635D;
      --line: rgba(26,26,26,.10); --accent: #1A1A1A; --on-accent: #F4F3F0; --danger: #C8372D;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #111111; --surface: #1A1A1A; --ink: #F2F0ED; --ink-2: #BDBAB4; --ink-3: #87857F;
        --line: rgba(242,240,237,.10); --accent: #F2F0ED; --on-accent: #111111; --danger: #FF6B5E;
      }
    }
    * { box-sizing: border-box; margin: 0; }
    html { -webkit-text-size-adjust: 100%; }
    body {
      background: var(--bg); color: var(--ink);
      font: 15px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
      padding: max(16px, env(safe-area-inset-top)) 16px max(24px, env(safe-area-inset-bottom));
      max-width: 560px; margin: 0 auto;
    }
    header { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; padding: 8px 2px 18px; }
    h1 { font-size: 22px; font-weight: 650; letter-spacing: -.01em; }
    .meta { color: var(--ink-3); font-size: 13px; text-align: right; }
    h2 { font-size: 13px; font-weight: 600; color: var(--ink-3); margin: 22px 2px 8px; }
    .card { background: var(--surface); border: 1px solid var(--line); border-radius: 14px; padding: 14px; margin-bottom: 10px; }
    .who { font-size: 13px; color: var(--ink-3); }
    .what { font-weight: 600; margin: 2px 0 8px; }
    code { display: block; font: 13px/1.45 ui-monospace, "SF Mono", Menlo, monospace; color: var(--ink-2);
           white-space: pre-wrap; word-break: break-word; max-height: 9.5em; overflow: auto; }
    .actions { display: flex; gap: 8px; margin-top: 12px; }
    button { flex: 1; min-height: 44px; border-radius: 10px; font: 600 15px/1 inherit; font-family: inherit;
             border: 1px solid var(--line); background: transparent; color: var(--ink); }
    button.primary { background: var(--accent); color: var(--on-accent); border-color: var(--accent); }
    button:disabled { opacity: .45; }
    .row { display: flex; gap: 12px; align-items: flex-start; padding: 12px 2px; border-bottom: 1px solid var(--line); }
    .row:last-child { border-bottom: 0; }
    .mark { width: 10px; height: 10px; border-radius: 50%; margin-top: 6px; flex: none; border: 1.5px solid var(--ink-3); }
    .mark.working { border-color: var(--ink); border-right-color: transparent; animation: spin 1s linear infinite; }
    .mark.needsInput { background: var(--accent); border-color: var(--accent); }
    .mark.done { border-color: var(--ink-2); }
    .mark.error { background: var(--danger); border-color: var(--danger); }
    @keyframes spin { to { transform: rotate(360deg); } }
    @media (prefers-reduced-motion: reduce) { .mark.working { animation: none; border-right-color: var(--ink); } }
    .grow { flex: 1; min-width: 0; }
    .name { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .line { color: var(--ink-2); font-size: 14px; }
    .line.needsInput { color: var(--ink); font-weight: 600; }
    .line.error { color: var(--danger); }
    .side { color: var(--ink-3); font-size: 13px; text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
    .message { color: var(--ink-2); font-size: 14px; margin-top: 4px; }
    form { display: flex; gap: 8px; margin-top: 10px; }
    input { flex: 1; min-width: 0; min-height: 44px; border-radius: 10px; border: 1px solid var(--line);
            background: var(--bg); color: var(--ink); padding: 0 12px; font: inherit; }
    form button { flex: none; padding: 0 16px; }
    .empty { color: var(--ink-3); padding: 28px 2px; text-align: center; }
    .note { color: var(--ink-3); font-size: 13px; padding: 10px 2px; }
    .note.problem { color: var(--danger); }
    </style>
    </head>
    <body>
    <header><h1>Tethera</h1><div class="meta" id="meta"></div></header>
    <div id="status" class="note" hidden></div>
    <div id="needs"></div>
    <div id="agents"></div>
    <script>
    const params = new URLSearchParams(location.hash.slice(1));
    if (params.get("t")) { try { localStorage.setItem("tethera.token", params.get("t")); } catch (e) {} history.replaceState(null, "", "/"); }
    let token = params.get("t");
    try { token = token || localStorage.getItem("tethera.token"); } catch (e) {}
    const $ = (id) => document.getElementById(id);
    const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
    const ago = (iso) => {
      const s = Math.max(0, (Date.now() - new Date(iso)) / 1000);
      return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + "m" : s < 86400 ? Math.floor(s / 3600) + "h" : Math.floor(s / 86400) + "d";
    };
    let busy = false, drafts = {};

    function show(text, problem) { const el = $("status"); el.hidden = !text; el.textContent = text || ""; el.className = "note" + (problem ? " problem" : ""); }

    async function call(method, path, body) {
      const response = await fetch(path, { method, headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
                                           body: body ? JSON.stringify(body) : undefined, cache: "no-store" });
      if (response.status === 401) throw new Error("pair");
      if (!response.ok) throw new Error(await response.text());
      return response.json();
    }

    function render(state) {
      $("meta").textContent = state.mac + (state.spentToday > 0 ? " · $" + state.spentToday.toFixed(2) + " today" : "");
      const waiting = state.sessions.filter((s) => s.state === "needsInput" && !state.approvals.some((a) => a.session === s.name));
      let needs = "";
      if (state.approvals.length || waiting.length) needs += "<h2>Needs you</h2>";
      for (const a of state.approvals) {
        needs += `<div class="card"><div class="who">${esc(a.agent)} · ${esc(a.session)} · ${ago(a.since)}</div>
          <div class="what">Run ${esc(a.tool)}?</div><code>${esc(a.summary)}</code>
          <div class="actions"><button data-deny="${a.id}">Deny</button><button class="primary" data-allow="${a.id}">Allow</button></div></div>`;
      }
      for (const s of waiting) {
        needs += `<div class="card"><div class="who">${esc(s.agent)} · ${esc(s.name)}${s.mac ? " · " + esc(s.mac) : ""} · ${ago(s.since)}</div>
          <div class="what">${esc(s.message || (s.replies ? "Waiting for your answer" : "Waiting for permission"))}</div>
          ${s.replies ? `<form data-reply="${s.id}"><input name="text" placeholder="Answer" autocomplete="off" value="${esc(drafts[s.id] || "")}"><button class="primary">Send</button></form>`
                      : `<div class="message">Answer it on your Mac.</div>`}</div>`;
      }
      const active = document.activeElement;
      if (!(active && active.tagName === "INPUT")) $("needs").innerHTML = needs;

      let rows = state.sessions.map((s) => `<div class="row"><span class="mark ${s.state}"></span>
        <div class="grow"><div class="name">${esc(s.name)}</div>
        <div class="line ${s.state}">${esc(s.agent)} · ${esc(s.line)}${s.mac ? " · " + esc(s.mac) : ""}</div>
        ${s.message && s.state !== "needsInput" ? `<div class="message">${esc(s.message)}</div>` : ""}</div>
        <div class="side">${s.cost != null ? "$" + s.cost.toFixed(2) : ""}${s.context != null ? "<br>" + Math.round(s.context) + "%" : ""}</div></div>`).join("");
      if (!state.sessions.length) rows = `<div class="empty">No agents running.${state.shells ? " " + state.shells + (state.shells === 1 ? " shell" : " shells") + " open." : ""}</div>`;
      else if (state.shells) rows += `<div class="note">${state.shells} ${state.shells === 1 ? "shell" : "shells"} without an agent.</div>`;
      $("agents").innerHTML = "<h2>Agents</h2>" + rows;
    }

    async function refresh() {
      if (!token) { show("Open this page from the QR code in Tethera's Settings → Remote.", true); return; }
      if (busy) return;
      try { render(await call("GET", "/api/state")); show(""); }
      catch (e) { show(e.message === "pair" ? "This phone isn't paired anymore. Scan the QR code in Tethera's Settings → Remote again." : "Can't reach your Mac. It may be asleep or off the network.", true); }
    }

    document.addEventListener("click", async (event) => {
      const button = event.target.closest("button[data-allow], button[data-deny]");
      if (!button) return;
      const id = button.dataset.allow || button.dataset.deny;
      button.closest(".actions").querySelectorAll("button").forEach((b) => b.disabled = true);
      busy = true;
      try { await call("POST", `/api/approvals/${id}/${button.dataset.allow ? "allow" : "deny"}`); } catch (e) { show(e.message, true); }
      busy = false; refresh();
    });
    document.addEventListener("input", (event) => { const form = event.target.closest("form[data-reply]"); if (form) drafts[form.dataset.reply] = event.target.value; });
    document.addEventListener("submit", async (event) => {
      const form = event.target.closest("form[data-reply]");
      if (!form) return;
      event.preventDefault();
      const text = form.text.value.trim();
      if (!text) return;
      form.querySelector("button").disabled = true;
      try { await call("POST", `/api/sessions/${form.dataset.reply}/reply`, { text }); delete drafts[form.dataset.reply]; form.text.blur(); }
      catch (e) { show(e.message, true); }
      refresh();
    });
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
    refresh();
    setInterval(() => { if (!document.hidden) refresh(); }, 3000);
    </script>
    </body>
    </html>
    """#
}
