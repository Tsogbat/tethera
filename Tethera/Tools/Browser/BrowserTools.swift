import AppKit
import TetheraKit
import WebKit

/// The browser tools agents call through `tethera mcp`. Names and arguments follow Playwright
/// MCP, so agents already know how to use them; actions return a fresh page snapshot.
@MainActor
enum BrowserTools {
    static func register(on server: AppServer) {
        server.register(prefix: "browser_") { request in await handle(request) }
    }

    static func handle(_ request: AppChannel.Request) async -> AppChannel.Response {
        let params = (try? JSONSerialization.jsonObject(with: Data(request.params.utf8))) as? [String: Any] ?? [:]
        let session = request.session.flatMap(UUID.init(uuidString:))
        func reply(_ text: String) -> AppChannel.Response { AppChannel.Response(id: request.id, text: text) }
        func failure(_ text: String) -> AppChannel.Response { AppChannel.Response(id: request.id, error: text) }

        if request.method == "browser_tabs" {
            return reply(await tabs(params, session: session))
        }
        guard let tab = BrowserStore.shared.tabForAgent(session: session) else { return failure("No browser tab.") }
        tab.agentDriving = true
        defer { tab.agentDriving = false }
        let web = tab.webView

        switch request.method {
        case "browser_navigate":
            guard let raw = params["url"] as? String, let url = BrowserTab.resolve(raw) else { return failure("Pass a url.") }
            await tab.loadAndWait(url)
            return reply("Navigated to \(url.absoluteString)\n\n" + (await snapshot(tab)))

        case "browser_navigate_back":
            web.goBack()
            try? await Task.sleep(nanoseconds: 300_000_000)
            await tab.waitForLoad(timeout: 10)
            return reply(await snapshot(tab))

        case "browser_snapshot":
            return reply(await snapshot(tab))

        case "browser_click":
            guard let ref = params["ref"] as? String else { return failure("Pass the element's ref from browser_snapshot.") }
            let double = params["doubleClick"] as? Bool ?? false
            let result = try? await web.callAsyncJavaScript(clickScript, arguments: ["ref": ref, "double": double], in: nil, contentWorld: .page)
            if let message = result as? String, !message.isEmpty { return failure(message) }
            try? await Task.sleep(nanoseconds: 400_000_000)
            await tab.waitForLoad(timeout: 10)
            return reply(await snapshot(tab))

        case "browser_type":
            guard let ref = params["ref"] as? String, let text = params["text"] as? String else { return failure("Pass ref and text.") }
            let submit = params["submit"] as? Bool ?? false
            let result = try? await web.callAsyncJavaScript(typeScript, arguments: ["ref": ref, "text": text, "submit": submit], in: nil, contentWorld: .page)
            if let message = result as? String, !message.isEmpty { return failure(message) }
            try? await Task.sleep(nanoseconds: submit ? 600_000_000 : 150_000_000)
            await tab.waitForLoad(timeout: 10)
            return reply(await snapshot(tab))

        case "browser_press_key":
            guard let key = params["key"] as? String else { return failure("Pass a key, e.g. Enter or ArrowDown.") }
            _ = try? await web.callAsyncJavaScript(keyScript, arguments: ["key": key], in: nil, contentWorld: .page)
            try? await Task.sleep(nanoseconds: 300_000_000)
            return reply(await snapshot(tab))

        case "browser_wait_for":
            if let seconds = params["time"] as? Double {
                try? await Task.sleep(nanoseconds: UInt64(min(seconds, 30) * 1e9))
            }
            for (key, appears) in [("text", true), ("textGone", false)] {
                guard let text = params[key] as? String else { continue }
                let deadline = Date().addingTimeInterval(15)
                while Date() < deadline {
                    let body = (try? await web.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String ?? ""
                    if body.contains(text) == appears { break }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
            return reply(await snapshot(tab))

        case "browser_take_screenshot":
            let configuration = WKSnapshotConfiguration()
            guard let image = try? await web.takeSnapshot(configuration: configuration),
                  let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return failure("Couldn't take a screenshot.") }
            return AppChannel.Response(id: request.id, text: "Screenshot of \(tab.url?.absoluteString ?? "the page")", image: png.base64EncodedString())

        case "browser_evaluate":
            guard let function = params["function"] as? String else { return failure("Pass a function, e.g. () => document.title") }
            do {
                let value = try await web.callAsyncJavaScript("const f = (\(function)); const r = await f(); return JSON.stringify(r === undefined ? null : r);",
                                                              arguments: [:], in: nil, contentWorld: .page)
                return reply(value as? String ?? "null")
            } catch {
                return failure("Script error: \(error.localizedDescription)")
            }

        default:
            return failure("Unknown tool \(request.method).")
        }
    }

    private static func tabs(_ params: [String: Any], session: UUID?) async -> String {
        let store = BrowserStore.shared
        switch params["action"] as? String ?? "list" {
        case "new":
            let tab = store.newTab(url: (params["url"] as? String).flatMap(BrowserTab.resolve))
            store.assign(tab, to: session)
            Workspace.shared.open(.browser(tab.id), besideSession: session)
            return "Opened a new tab.\n" + list(store, current: tab.id)
        case "select":
            let ids = store.tabs.keys.sorted { $0.uuidString < $1.uuidString }
            guard let index = params["index"] as? Int, ids.indices.contains(index), let tab = store.tab(ids[index]) else { return "No tab at that index." }
            store.assign(tab, to: session)
            Workspace.shared.open(.browser(tab.id), besideSession: session)
            return list(store, current: tab.id)
        case "close":
            let ids = store.tabs.keys.sorted { $0.uuidString < $1.uuidString }
            let target = (params["index"] as? Int).flatMap { ids.indices.contains($0) ? ids[$0] : nil }
                ?? store.tabForAgent(session: session, create: false)?.id
            if let target {
                if let pane = Workspace.shared.panes.first(where: { $0.content == .browser(target) }) {
                    Workspace.shared.focus(pane: pane.id)
                    Workspace.shared.closeFocusedPane()
                } else {
                    store.close(target)
                }
            }
            return list(store, current: nil)
        default:
            return list(store, current: store.tabForAgent(session: session, create: false)?.id)
        }
    }

    private static func list(_ store: BrowserStore, current: UUID?) -> String {
        let ids = store.tabs.keys.sorted { $0.uuidString < $1.uuidString }
        if ids.isEmpty { return "No tabs." }
        return ids.enumerated().map { index, id in
            let tab = store.tab(id)
            return "- \(index):\(id == current ? " (current)" : "") [\(tab?.title ?? "")] (\(tab?.url?.absoluteString ?? "about:blank"))"
        }.joined(separator: "\n")
    }

    /// A Playwright-style accessibility snapshot of the page, with refs for elements you can act on.
    static func snapshot(_ tab: BrowserTab) async -> String {
        let outline = (try? await tab.webView.callAsyncJavaScript(snapshotScript, arguments: [:], in: nil, contentWorld: .page)) as? String ?? ""
        return """
        - Page URL: \(tab.url?.absoluteString ?? "about:blank")
        - Page Title: \(tab.title)
        - Page Snapshot:
        ```yaml
        \(outline)
        ```
        """
    }

    // MARK: Page scripts

    static let snapshotScript = #"""
    const MAX = 40000; let size = 0, n = 0; const lines = [];
    document.querySelectorAll('[data-tethera-ref]').forEach(e => e.removeAttribute('data-tethera-ref'));
    const tags = {A:'link',BUTTON:'button',SELECT:'combobox',TEXTAREA:'textbox',NAV:'navigation',MAIN:'main',HEADER:'banner',
      FOOTER:'contentinfo',ASIDE:'complementary',FORM:'form',ARTICLE:'article',DIALOG:'dialog',UL:'list',OL:'list',LI:'listitem',
      TABLE:'table',TR:'row',TD:'cell',TH:'columnheader',IMG:'img',P:'paragraph',H1:'heading',H2:'heading',H3:'heading',
      H4:'heading',H5:'heading',H6:'heading',SUMMARY:'button',LABEL:'label'};
    const actionable = new Set(['link','button','textbox','checkbox','radio','combobox','switch','tab','menuitem','option','slider','searchbox']);
    const leafy = new Set(['link','button','heading','paragraph','textbox','img','cell','columnheader','label','option','menuitem','tab']);
    function role(el) {
      const r = el.getAttribute('role'); if (r) return r;
      if (el.tagName === 'A' && !el.hasAttribute('href')) return null;
      if (el.tagName === 'INPUT') {
        const t = (el.getAttribute('type') || 'text').toLowerCase();
        if (t === 'hidden') return null;
        if (['button','submit','reset','image'].includes(t)) return 'button';
        if (t === 'checkbox' || t === 'radio') return t;
        if (t === 'range') return 'slider';
        return t === 'search' ? 'searchbox' : 'textbox';
      }
      if (el.isContentEditable && el.getAttribute('contenteditable') !== null) return 'textbox';
      return tags[el.tagName] || null;
    }
    function label(el) {
      let s = el.getAttribute('aria-label') || el.getAttribute('alt') || el.getAttribute('title') || '';
      if (!s && el.id) { const l = document.querySelector('label[for="' + CSS.escape(el.id) + '"]'); if (l) s = l.innerText; }
      if (!s && ['INPUT','TEXTAREA'].includes(el.tagName)) s = el.getAttribute('placeholder') || '';
      if (!s && el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA' && el.tagName !== 'SELECT') s = el.innerText || '';
      return s.trim().replace(/\s+/g, ' ').slice(0, 100);
    }
    function shown(el) {
      const s = getComputedStyle(el);
      if (s.display === 'none' || s.visibility === 'hidden' || el.getAttribute('aria-hidden') === 'true') return false;
      const r = el.getBoundingClientRect(); return r.width > 0 || r.height > 0 || s.display === 'contents';
    }
    function emit(depth, text) {
      if (size > MAX) return; const line = '  '.repeat(depth) + text; size += line.length + 1; lines.push(line);
    }
    function walk(node, depth) {
      if (size > MAX) return;
      for (const child of node.childNodes) {
        if (child.nodeType === 3) {
          const t = child.textContent.trim().replace(/\s+/g, ' ');
          if (t) emit(depth, '- text: ' + JSON.stringify(t.slice(0, 200)));
          continue;
        }
        if (child.nodeType !== 1 || ['SCRIPT','STYLE','NOSCRIPT','TEMPLATE','SVG'].includes(child.tagName.toUpperCase())) continue;
        if (!shown(child)) continue;
        const r = role(child);
        if (!r) { walk(child, depth); continue; }
        let line = '- ' + r; const name = label(child);
        if (name) line += ' ' + JSON.stringify(name);
        if (r === 'heading') line += ' [level=' + child.tagName.slice(1) + ']';
        if ((r === 'checkbox' || r === 'radio') && child.checked) line += ' [checked]';
        if (r === 'textbox' && child.value) line += ': ' + JSON.stringify(String(child.value).slice(0, 100));
        if (child.disabled) line += ' [disabled]';
        if (actionable.has(r) || child.onclick || child.tabIndex >= 0 && r !== 'paragraph' && r !== 'list' && r !== 'listitem') {
          n += 1; const ref = 'e' + n; child.setAttribute('data-tethera-ref', ref); line += ' [ref=' + ref + ']';
        }
        if (r === 'link' && child.getAttribute('href')) { emit(depth, line + ':'); emit(depth + 1, '- /url: ' + child.getAttribute('href').slice(0, 200)); }
        else emit(depth, line);
        if (!leafy.has(r)) walk(child, depth + 1);
      }
    }
    if (document.body) walk(document.body, 0);
    if (size > MAX) lines.push('- (snapshot truncated)');
    return lines.join('\n');
    """#

    static let clickScript = #"""
    const el = document.querySelector('[data-tethera-ref="' + ref + '"]');
    if (!el) return 'No element with ref ' + ref + '. Take a new browser_snapshot.';
    el.scrollIntoView({block: 'center', inline: 'center'});
    const r = el.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
    const opts = {bubbles: true, cancelable: true, clientX: x, clientY: y, view: window};
    for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) el.dispatchEvent(new (type.startsWith('pointer') ? PointerEvent : MouseEvent)(type, opts));
    el.click(); if (double) el.dispatchEvent(new MouseEvent('dblclick', opts));
    if (el.focus) el.focus();
    return '';
    """#

    static let typeScript = #"""
    const el = document.querySelector('[data-tethera-ref="' + ref + '"]');
    if (!el) return 'No element with ref ' + ref + '. Take a new browser_snapshot.';
    el.scrollIntoView({block: 'center'}); el.focus();
    if (el.isContentEditable) { el.textContent = text; el.dispatchEvent(new InputEvent('input', {bubbles: true})); }
    else {
      const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : (el.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype);
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
      el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true}));
    }
    if (submit) {
      const down = new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true, cancelable: true});
      const go = el.dispatchEvent(down);
      el.dispatchEvent(new KeyboardEvent('keyup', {key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true}));
      if (go && el.form) el.form.requestSubmit();
    }
    return '';
    """#

    static let keyScript = #"""
    const el = document.activeElement || document.body;
    const codes = {Enter: 13, Tab: 9, Escape: 27, Backspace: 8, ArrowUp: 38, ArrowDown: 40, ArrowLeft: 37, ArrowRight: 39, ' ': 32};
    const init = {key, code: key.length === 1 ? 'Key' + key.toUpperCase() : key, keyCode: codes[key] || key.charCodeAt(0), bubbles: true, cancelable: true};
    const go = el.dispatchEvent(new KeyboardEvent('keydown', init));
    if (key.length === 1 && go && 'value' in el) { el.value += key; el.dispatchEvent(new Event('input', {bubbles: true})); }
    el.dispatchEvent(new KeyboardEvent('keyup', init));
    if (key === 'Enter' && go && el.form) el.form.requestSubmit();
    return '';
    """#
}
