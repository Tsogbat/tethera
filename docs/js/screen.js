// Tethera — the CRT. A tiny, monochrome Tethera drawn with Canvas2D into the
// computer's screen texture. Logical canvas: 1000 × 768 (the screen is 1.64 × 1.26).

export const LW = 1000, LH = 768;
export const MONO = '"Geist Mono", ui-monospace, "SF Mono", Menlo, monospace';
const C = {
  bg: '#0E0E0F', side: '#121214', row: '#1D1D20', pop: '#17171A', line: '#26262A', line2: '#3A3A3F',
  text: '#F2F0ED', dim: '#9A9792', faint: '#5E5B55',
};
const SPIN = [...'⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'];
const ICON = {
  claude: 'M8 1.75v12.5M1.75 8h12.5M3.6 3.6l8.8 8.8M12.4 3.6l-8.8 8.8',
  codex: 'm2.75 4.25 3.75 3.75-3.75 3.75M8.75 12h4.5',
  opencode: 'M3.25 2.25h9.5v11.5h-9.5zM6 7h4v4.25H6z',
  shell: 'M3.25 2.75h9.5a1.5 1.5 0 0 1 1.5 1.5v7.5a1.5 1.5 0 0 1-1.5 1.5h-9.5a1.5 1.5 0 0 1-1.5-1.5v-7.5a1.5 1.5 0 0 1 1.5-1.5zM4.5 6.25l2 1.75-2 1.75M8 10h3',
};
const P2D = {};
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const ease = (t) => 1 - Math.pow(1 - t, 3);

/* ---------- glyphs shared with the keycaps ---------- */
export function cmdGlyph(g, cx, cy, s, lw) {
  const H = s / 2, r = H * 0.36, a = H - 2 * r, c = a + r;
  g.save(); g.translate(cx, cy); g.lineWidth = lw; g.lineCap = 'round';
  g.beginPath();
  g.moveTo(-c, -a); g.lineTo(c, -a); g.moveTo(-c, a); g.lineTo(c, a);
  g.moveTo(-a, -c); g.lineTo(-a, c); g.moveTo(a, -c); g.lineTo(a, c);
  g.stroke();
  for (const [sx, sy] of [[1, 1], [-1, 1], [-1, -1], [1, -1]]) {
    g.save(); g.scale(sx, sy); g.beginPath(); g.arc(c, c, r, -Math.PI / 2, Math.PI); g.stroke(); g.restore();
  }
  g.restore();
}
export function shiftGlyph(g, cx, cy, s, lw) {
  const H = s / 2, w = H * 0.42, m = H * 0.08;
  g.save(); g.translate(cx, cy); g.lineWidth = lw; g.lineJoin = 'round';
  g.beginPath();
  g.moveTo(0, -H); g.lineTo(H, m); g.lineTo(w, m); g.lineTo(w, H); g.lineTo(-w, H); g.lineTo(-w, m); g.lineTo(-H, m);
  g.closePath(); g.stroke(); g.restore();
}
export function arrowGlyph(g, cx, cy, s, lw) {
  const H = s / 2;
  g.save(); g.translate(cx, cy); g.lineWidth = lw; g.lineCap = 'round'; g.lineJoin = 'round';
  g.beginPath(); g.moveTo(0, -H); g.lineTo(0, H * 0.92); g.moveTo(-H * 0.62, H * 0.3); g.lineTo(0, H * 0.92); g.lineTo(H * 0.62, H * 0.3);
  g.stroke(); g.restore();
}
const GLYPH = { '⌘': cmdGlyph, '⇧': shiftGlyph, '↓': arrowGlyph };

// Draws a label centered at (cx, cy); ⌘ ⇧ ↓ are drawn as vector glyphs so every
// platform shows the same shapes. Returns its width.
export function drawLabel(g, label, cx, cy, size, color, weight = 500, align = 'center') {
  g.font = `${weight} ${size}px ${MONO}`;
  g.fillStyle = g.strokeStyle = color; g.textBaseline = 'middle'; g.textAlign = 'left';
  const toks = [];
  for (const ch of label) {
    if (GLYPH[ch]) toks.push({ g: ch, w: size * 0.74 });
    else if (toks.length && toks[toks.length - 1].t != null) toks[toks.length - 1].t += ch;
    else toks.push({ t: ch });
  }
  for (const t of toks) if (t.t != null) t.w = g.measureText(t.t).width;
  const gap = size * 0.12;
  const total = toks.reduce((s, t) => s + t.w, 0) + gap * (toks.length - 1);
  let x = align === 'center' ? cx - total / 2 : align === 'right' ? cx - total : cx;
  for (const t of toks) {
    if (t.t != null) g.fillText(t.t, x, cy + size * 0.04);
    else GLYPH[t.g](g, x + t.w / 2, cy, size * 0.6, Math.max(1, size * 0.075));
    x += t.w + gap;
  }
  return total;
}

/* ---------- the screen ---------- */
export function createScreen(px = 2048) {
  const cv = document.createElement('canvas');
  const g = cv.getContext('2d');
  let k = 1, fx = null;
  const S = { mode: 'boot', at: 0, split: false, splitAt: -1e9, pal: false, cmdAt: -1e9, flashAt: -1e9 };
  let sig = '', force = true;

  function size(w) {
    cv.width = w; cv.height = Math.round(w * LH / LW); k = w / LW;
    fx = document.createElement('canvas'); fx.width = cv.width; fx.height = cv.height;
    const f = fx.getContext('2d');
    // faint scanlines + vignette: the only "CRT" effects, kept subtle
    f.fillStyle = 'rgba(0,0,0,0.05)';
    for (let y = 0; y < fx.height; y += 3 * k) f.fillRect(0, y, fx.width, Math.max(1, k * 0.9));
    const v = f.createRadialGradient(fx.width / 2, fx.height / 2, fx.height * 0.35, fx.width / 2, fx.height / 2, fx.width * 0.68);
    v.addColorStop(0, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,0,0.42)');
    f.fillStyle = v; f.fillRect(0, 0, fx.width, fx.height);
    force = true;
  }
  size(px);

  /* helpers (logical units) */
  const font = (s, w = 400) => { g.font = `${w} ${s}px ${MONO}`; };
  function text(str, x, y, s, col, w = 400, align = 'left') {
    font(s, w); g.fillStyle = col; g.textAlign = align; g.textBaseline = 'alphabetic'; g.fillText(str, x, y);
  }
  function rr(x, y, w, h, r) { g.beginPath(); g.roundRect(x, y, w, h, r); }
  function hline(x0, x1, y, col = C.line) { g.fillStyle = col; g.fillRect(x0, y, x1 - x0, 1); }
  function vline(x, y0, y1, col = C.line) { g.fillStyle = col; g.fillRect(x, y0, 1, y1 - y0); }
  function icon(name, x, y, s, col) {
    const p = P2D[name] || (P2D[name] = new Path2D(ICON[name]));
    g.save(); g.translate(x, y); g.scale(s / 16, s / 16);
    g.strokeStyle = col; g.lineWidth = 1.5; g.lineCap = 'round'; g.lineJoin = 'round'; g.stroke(p);
    if (name === 'opencode') { g.fillStyle = col; g.fillRect(6, 7, 4, 4.25); }
    g.restore();
  }
  function braille(ch, x, y, s, col) { // x, y: cell top-left; s: cell height
    const bits = ch.codePointAt(0) - 0x2800;
    const pos = [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2], [0, 3], [1, 3]];
    g.fillStyle = col;
    for (let i = 0; i < 8; i++) if (bits & (1 << i)) {
      g.beginPath(); g.arc(x + s * 0.18 + pos[i][0] * s * 0.3, y + s * 0.14 + pos[i][1] * s * 0.24, s * 0.075, 0, 7); g.fill();
    }
  }
  function stateMark(st, x, y, now) { // centered at x, y
    if (st === 'working') braille(SPIN[Math.floor(now / 80) % 10], x - 7, y - 9, 18, C.text);
    else if (st === 'needs') { g.fillStyle = C.text; g.beginPath(); g.arc(x, y, 4.5, 0, 7); g.fill(); }
    else if (st === 'waiting') { g.strokeStyle = C.dim; g.lineWidth = 1.4; g.beginPath(); g.arc(x, y, 4.2, 0, 7); g.stroke(); }
  }

  /* chrome */
  const TOP = 34, BOT = 30, SB = 254;
  function chrome(status, right = '4 sessions') {
    g.fillStyle = C.bg; g.fillRect(0, 0, LW, LH);
    g.strokeStyle = C.line2; g.lineWidth = 1.3;
    for (let i = 0; i < 3; i++) { g.beginPath(); g.arc(20 + i * 18, TOP / 2, 5, 0, 7); g.stroke(); }
    hline(0, LW, TOP);
    hline(0, LW, LH - BOT);
    text(status, 18, LH - 10, 12, C.faint);
    if (S.cmdAt > 0 && performance.now() - S.cmdAt < 1600) {
      rr(LW - 210, LH - BOT + 6, 22, 18, 4); g.strokeStyle = C.dim; g.lineWidth = 1; g.stroke();
      drawLabel(g, '⌘', LW - 199, LH - BOT + 15, 12, C.text);
      text('then K for the palette', LW - 180, LH - 10, 12, C.dim);
    } else {
      const w = drawLabel(g, '⌘K', LW - 18, LH - 15, 12, C.faint, 400, 'right');
      text(right, LW - 34 - w, LH - 10, 12, C.faint, 400, 'right');
    }
  }
  function sidebar(rows, sel, now) {
    g.fillStyle = C.side; g.fillRect(0, TOP + 1, SB, LH - TOP - BOT - 1);
    vline(SB, TOP, LH - BOT);
    text('SESSIONS', 20, TOP + 30, 11, C.faint, 500);
    text(String(rows.length), SB - 20, TOP + 30, 11, C.faint, 500, 'right');
    rows.forEach((r, i) => {
      const y = TOP + 46 + i * 58;
      if (i === sel) { g.fillStyle = C.row; rr(10, y, SB - 20, 52, 7); g.fill(); }
      icon(r.icon, 22, y + 10, 15, i === sel ? C.text : C.dim);
      text(r.name, 50, y + 22, 15, C.text, 500);
      text(r.sub, 50, y + 41, 12, C.dim);
      stateMark(r.st, SB - 24, y + 27, now);
    });
  }
  function paneHead(x0, x1, name, path, right) {
    hline(x0, x1, TOP + 34);
    text(name, x0 + 16, TOP + 23, 13, C.text, 500);
    font(13, 500); const w = g.measureText(name).width;
    text(path, x0 + 26 + w, TOP + 23, 13, C.faint);
    if (right && x1 - x0 > 520) text(right, x1 - 16, TOP + 23, 12, C.dim, 400, 'right');
  }
  function lines(x, y, list, now) {
    list.forEach((l, i) => {
      if (l == null) return;
      const yy = y + i * 23;
      if (typeof l === 'string') { text(l, x, yy, 14, C.text); return; }
      if (l.spin) { braille(SPIN[Math.floor(now / 80) % 10], x - 2, yy - 15, 18, C.text); text(l.t, x + 22, yy, 14, C.dim); return; }
      if (l.icon) { icon(l.icon, x, yy - 13, 15, C.text); text(l.t, x + 24, yy, 14, C.text, 500); return; }
      text(l.t, x, yy, 14, l.c || C.text, l.w || 400);
      if (l.cur) caret(x + measure(l.t, 14, l.w) + 2, yy, now);
    });
  }
  function measure(s, size, w = 400) { font(size, w); return g.measureText(s).width; }
  function caret(x, y, now, h = 16) { if (Math.floor(now / 530) % 2 === 0) { g.fillStyle = C.text; g.fillRect(x, y - h + 3, 8.4, h); } }

  /* session data */
  const ROWS = () => [
    { icon: 'shell', name: 'tethera', sub: '~/Projects/tethera', st: '' },
    { icon: 'opencode', name: 'website', sub: 'OpenCode · working', st: 'working' },
    { icon: 'claude', name: 'release-notes', sub: 'Claude Code · needs you', st: 'needs' },
    { icon: 'codex', name: 'api', sub: 'Codex · waiting', st: 'waiting' },
  ];
  function sessionPhase(t) { return t < 900 ? 'type' : t < 3300 ? 'working' : 'needs'; }

  /* modes */
  function drawBoot(now) {
    g.fillStyle = C.bg; g.fillRect(0, 0, LW, LH);
    const s = 132; font(s, 500);
    const w = g.measureText('tethera').width, cw = g.measureText('_').width;
    const x = (LW - w - cw * 1.1) / 2, y = LH / 2 + s * 0.28;
    text('tethera', x, y, s, C.text, 500);
    if (Math.floor(now / 530) % 2 === 0) { g.fillStyle = C.text; g.fillRect(x + w + cw * 0.12, y - 8, cw * 0.92, 13); }
    drawLabel(g, 'esc · return · ⌘K · d', LW / 2, LH - 98, 17, C.faint, 400);
  }

  function drawMain(now, kind) {
    const t = now - S.at;
    const rows = ROWS();
    let sel = 1, status = '1 working · 1 needs you';
    if (kind === 'session') {
      const ph = sessionPhase(t);
      sel = 2;
      rows[2].sub = ph === 'type' ? '~/Projects/tethera' : ph === 'working' ? 'Claude Code · working' : 'Claude Code · needs you';
      rows[2].st = ph === 'type' ? '' : ph === 'working' ? 'working' : 'needs';
      status = ph === 'needs' ? '1 working · 1 needs you' : ph === 'working' ? '2 working' : '1 working';
    }
    chrome(status);
    sidebar(rows, kind === 'home' ? -1 : sel, now);

    const x0 = SB + 1, x1 = LW;
    if (kind === 'home') return drawHome(now, x0, x1);

    const sp = S.split ? ease(clamp((now - S.splitAt) / 300)) : 1 - ease(clamp((now - S.splitAt) / 260));
    const mid = Math.round(x1 - (x1 - x0) / 2 * sp);
    g.save(); g.beginPath(); g.rect(x0, TOP + 1, mid - x0, LH - TOP - BOT - 1); g.clip();
    if (kind === 'session') drawClaude(now, t, x0, mid); else drawOpenCode(now, x0, mid);
    g.restore();
    if (sp > 0.001) {
      g.fillStyle = C.bg; g.fillRect(mid, TOP + 1, x1 - mid, LH - TOP - BOT - 1);
      vline(mid, TOP, LH - BOT, C.line2);
      g.save(); g.beginPath(); g.rect(mid + 1, TOP + 1, x1 - mid, LH - TOP - BOT); g.clip();
      paneHead(mid + 1, mid + 1 + (x1 - x0) / 2, 'tethera', '~/Projects/tethera');
      lines(mid + 18, TOP + 66, [{ t: '~/Projects/tethera', c: C.dim }, { t: '❯ ', cur: true }], now);
      g.restore();
    }
  }
  function drawOpenCode(now, x0, x1) {
    paneHead(x0, x1, 'website', '~/Projects/tethera', 'OpenCode · working');
    lines(x0 + 18, TOP + 66, [
      { t: '~/Projects/tethera', c: C.dim },
      { t: '❯ opencode', c: C.text },
      '',
      { icon: 'opencode', t: 'OpenCode' },
      '',
      { t: '> Tighten the hero copy on the website', c: C.text },
      '',
      { t: '• Read  docs/index.html', c: C.dim },
      { t: '• Edit  docs/site.css   +12 −4', c: C.dim },
      { t: '• Edit  docs/index.html  +3 −3', c: C.dim },
      '',
      { spin: true, t: 'Working…' },
    ], now);
  }
  function drawClaude(now, t, x0, x1) {
    const ph = sessionPhase(t);
    paneHead(x0, x1, 'release-notes', '~/Projects/tethera', ph === 'type' ? '' : ph === 'working' ? 'Claude Code · working' : 'Claude Code · needs you');
    const typed = 'claude'.slice(0, clamp(Math.floor((t - 200) / 80), 0, 6));
    const L = [{ t: '~/Projects/tethera', c: C.dim }, { t: '❯ ' + typed, cur: ph === 'type' }];
    if (ph !== 'type') {
      L.push('', { icon: 'claude', t: 'Claude Code' }, { t: '  cwd ~/Projects/tethera', c: C.faint }, '');
      if (t > 1150) L.push({ t: '> Tidy up the release notes', c: C.text }, '');
      if (t > 1350) L.push({ t: '• Read  docs/release-notes.md', c: C.dim });
      if (ph === 'working' && t > 1350) L.push('', { spin: true, t: 'Working…' });
      if (ph === 'needs') L.push({ t: '• Edit  docs/release-notes.md', c: C.text }, '', { t: '  Allow this edit?', c: C.text, w: 500 }, { t: '  ❯ 1. Yes', c: C.text }, { t: '    2. No', c: C.dim });
    }
    lines(x0 + 18, TOP + 66, L, now);
  }
  function drawHome(now, x0, x1) {
    const x = x0 + 40;
    text('Home', x, TOP + 74, 28, C.text, 500);
    text('Start something, or pick up where you left off.', x, TOP + 104, 13, C.dim);
    const col = (title, cx, items) => {
      text(title.toUpperCase(), cx, TOP + 160, 11, C.faint, 500);
      items.forEach((it, i) => {
        const y = TOP + 176 + i * 48;
        hline(cx, cx + 320, y);
        icon(it.icon, cx + 2, y + 15, 16, C.text);
        text(it.name, cx + 30, y + 29, 15, C.text, 500);
        if (it.hint) drawLabel(g, it.hint, cx + 320, y + 25, 12, C.faint, 400, 'right');
        if (it.st) { text(it.sub, cx + 296, y + 29, 12, C.dim, 400, 'right'); stateMark(it.st, cx + 310, y + 25, now); }
      });
      hline(cx, cx + 320, TOP + 176 + items.length * 48);
    };
    col('Start', x, [
      { icon: 'shell', name: 'Shell', hint: '⌘T' }, { icon: 'claude', name: 'Claude Code' },
      { icon: 'codex', name: 'Codex' }, { icon: 'opencode', name: 'OpenCode' },
    ]);
    col('Running', x + 362, [
      { icon: 'opencode', name: 'website', sub: 'working', st: 'working' },
      { icon: 'claude', name: 'release-notes', sub: 'needs you', st: 'needs' },
      { icon: 'codex', name: 'api', sub: 'waiting', st: 'waiting' },
    ]);
  }
  function drawPalette(now) {
    g.fillStyle = 'rgba(8,8,9,0.62)'; g.fillRect(0, 0, LW, LH);
    const w = 560, x = (LW - w) / 2, y = 110, rowH = 40;
    const items = [
      ['claude', 'release-notes', 'needs you'], ['opencode', 'website', 'working'],
      ['claude', 'New Claude Code session', ''], ['codex', 'New Codex session', ''],
      ['shell', 'Split right', '⌘D'], ['shell', 'Agents overview', '⇧⌘A'],
    ];
    const h = 58 + items.length * rowH + 12;
    rr(x, y, w, h, 10); g.fillStyle = C.pop; g.fill(); g.strokeStyle = C.line2; g.lineWidth = 1; g.stroke();
    text('›', x + 20, y + 37, 18, C.dim);
    text('Search sessions and commands', x + 44, y + 36, 15, C.faint);
    caret(x + 42, y + 37, now, 18);
    hline(x, x + w, y + 56);
    items.forEach(([ic, label, right], i) => {
      const yy = y + 62 + i * rowH;
      if (i === 0) { g.fillStyle = C.row; rr(x + 6, yy, w - 12, rowH - 4, 6); g.fill(); }
      icon(ic, x + 20, yy + 10, 15, i === 0 ? C.text : C.dim);
      text(label, x + 48, yy + 24, 14, C.text, i === 0 ? 500 : 400);
      if (right && right.startsWith('needs')) { text(right, x + w - 40, yy + 24, 12, C.dim, 400, 'right'); stateMark('needs', x + w - 24, yy + 19, now); }
      else if (right === 'working') { text(right, x + w - 40, yy + 24, 12, C.dim, 400, 'right'); stateMark('working', x + w - 24, yy + 19, now); }
      else if (right) drawLabel(g, right, x + w - 22, yy + 18, 12, C.faint, 400, 'right');
    });
  }

  function draw(now) {
    g.setTransform(k, 0, 0, k, 0, 0);
    g.globalAlpha = 1;
    if (S.mode === 'boot') drawBoot(now); else drawMain(now, S.mode);
    if (S.pal) drawPalette(now);
    const fl = 1 - clamp((now - S.flashAt) / 220);
    if (fl > 0) { g.fillStyle = `rgba(14,14,15,${(fl * 0.92).toFixed(3)})`; g.fillRect(0, 0, LW, LH); }
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.drawImage(fx, 0, 0);
  }

  /* change detection: only redraw (and re-upload the texture) when a pixel would change */
  function animating(now) {
    const t = now - S.at;
    const spin = S.mode === 'live' || S.mode === 'home' || S.pal || (S.mode === 'session' && sessionPhase(t) !== 'type');
    return {
      spin,
      type: S.mode === 'session' && t < 1500,
      flash: now - S.flashAt < 240,
      split: now - S.splitAt < 320,
      cmd: now - S.cmdAt < 1650,
    };
  }
  function signature(now) {
    const a = animating(now), t = now - S.at;
    return [S.mode, S.pal, S.split, Math.floor(now / 530) % 2, a.spin ? Math.floor(now / 80) % 10 : 0,
      S.mode === 'session' ? Math.min(60, Math.floor(t / 50)) + sessionPhase(t) : 0,
      a.flash ? Math.floor(now / 16) : 0, a.split ? Math.floor(now / 16) : 0, a.cmd ? 1 : 0].join('|');
  }

  return {
    canvas: cv,
    get mode() { return S.mode; },
    resize(w) { if (w !== cv.width) size(w); },
    invalidate() { force = true; },
    // Returns true if the canvas changed and the texture needs an upload.
    update(now) {
      const s = signature(now);
      if (!force && s === sig) return false;
      sig = s; force = false; draw(now); return true;
    },
    // Milliseconds until the next visual change.
    nextWake(now) {
      const a = animating(now);
      if (a.flash || a.split || a.type) return 16;
      let w = 530 - (now % 530);
      if (a.spin) w = Math.min(w, 80 - (now % 80));
      if (a.cmd) w = Math.min(w, 1650 - (now - S.cmdAt));
      if (S.mode === 'session') { const t = now - S.at; if (t < 3300) w = Math.min(w, 3300 - t); }
      return Math.max(8, w);
    },
    show(mode) {
      const now = performance.now();
      S.mode = mode; S.at = now; S.pal = false; S.split = false; S.splitAt = -1e9; S.flashAt = now; force = true;
    },
    palette() {
      const now = performance.now();
      if (S.mode === 'boot') { S.mode = 'live'; S.at = now; S.flashAt = now; }
      S.pal = !S.pal; force = true;
    },
    split() {
      const now = performance.now();
      if (S.mode === 'boot' || S.mode === 'home') { S.mode = 'live'; S.at = now; S.flashAt = now; }
      S.pal = false; S.split = !S.split; S.splitAt = now; force = true;
    },
    cmd() { S.cmdAt = performance.now(); force = true; },
  };
}
