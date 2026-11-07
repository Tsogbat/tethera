// Tethera — keys: pointer raycasting, damped springs, a synthesized "thock",
// and your real keyboard mapped onto the 3D one.

const INTERACTIVE = 'a,button,input,textarea,select,label,summary,[role="button"],[contenteditable],.nav';
const KEYMAP = { k: 'k', d: 'd', t: 't', escape: 'esc', enter: 'return', meta: 'cmd' };

/* ---------- sound: filtered noise burst + short low sine, no files ---------- */
function createSound(button) {
  let on = true, ctx = null, out = null, noise = null, armed = false;
  try { on = localStorage.getItem('tethera.sound') !== 'off'; } catch (_) { /* storage blocked */ }
  const sync = () => button && button.setAttribute('aria-pressed', String(on));
  sync();
  if (button) button.addEventListener('click', () => {
    on = !on; sync();
    try { localStorage.setItem('tethera.sound', on ? 'on' : 'off'); } catch (_) { /* ignore */ }
  });
  function ensure() {
    if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return ctx; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
    out = ctx.createGain(); out.gain.value = 0.5; out.connect(ctx.destination);
    noise = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.1), ctx.sampleRate);
    const d = noise.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / d.length, 3);
    return ctx;
  }
  function burst(t, freq, gain, dur) {
    const src = ctx.createBufferSource(); src.buffer = noise; src.playbackRate.value = 0.85 + Math.random() * 0.3;
    const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = freq; f.Q.value = 0.9;
    const g = ctx.createGain(); g.gain.setValueAtTime(gain, t); g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
    src.connect(f).connect(g).connect(out); src.start(t); src.stop(t + dur + 0.02);
  }
  return {
    gesture() { armed = true; },
    // kind: 'down' | 'up'; o.pitch scales the body tone (bigger keys sound lower)
    play(kind, o = {}) {
      if (!on || !armed || !ensure() || ctx.state !== 'running' && ctx.state !== 'suspended') return;
      const t = ctx.currentTime + 0.005, p = o.pitch || 1, v = o.vel || 1;
      if (kind === 'up') { burst(t, 2600 * p, 0.12 * v, 0.035); return; }
      burst(t, 1500 * p, 0.42 * v, 0.06);
      const osc = ctx.createOscillator(), g = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(175 * p, t); osc.frequency.exponentialRampToValueAtTime(68 * p, t + 0.1);
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.55 * v, t + 0.006); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
      osc.connect(g).connect(out); osc.start(t); osc.stop(t + 0.17);
    },
  };
}

export function createKeys({ THREE, canvas, request, reduced, soundButton }) {
  const keys = new Map();
  const wobbles = new Set();
  const ray = new THREE.Raycaster();
  const ndc = new THREE.Vector2();
  const sound = createSound(soundButton);
  const pointers = new Map();
  let pairs = [], hoverXY = null, hovered = null, route = (id) => [id];

  const spring = () => (reduced() ? { k: 1100, c: 66 } : { k: 520, c: 16 });

  /* registry */
  function add(spec) {
    const key = { x: 0, v: 0, target: 0, held: false, hover: false, downAt: 0, releaseAt: 0, travel: 0.238, base: 0, wx: 0, wz: 0, ...spec };
    spec.mesh.userData.keyId = spec.id;
    keys.set(spec.id, key);
    return key;
  }
  function wobble() {
    const w = { rx: 0, rz: 0, y: 0, vrx: 0, vrz: 0, vy: 0 };
    wobbles.add(w);
    return w;
  }

  /* press / release */
  function press(id) {
    const k = keys.get(id);
    if (!k || k.held) return;
    k.held = true; k.target = 1; k.downAt = performance.now(); k.releaseAt = 0;
    sound.play('down', k.sound);
    if (k.wob && !reduced()) { k.wob.vrx += 0.3 * k.wz; k.wob.vrz -= 0.3 * k.wx; k.wob.vy -= 0.05 * (k.mass || 1); }
    if (k.onPress) k.onPress();
    request();
  }
  function release(id) {
    const k = keys.get(id);
    if (!k || !k.held) return;
    k.held = false; k.releaseAt = k.downAt + (k.minHold || 110);
    request();
  }
  function tap(id) { press(id); setTimeout(() => release(id), 150); }
  function releaseAll() { for (const k of keys.values()) if (k.held) release(k.id); pointers.clear(); }

  /* physics: semi-implicit Euler, substepped */
  function tick(dt, now) {
    let active = false;
    const { k: K, c: D } = spring();
    const n = Math.max(1, Math.ceil(dt * 240)), h = dt / n;
    for (const key of keys.values()) {
      if (!key.held && key.target === 1 && now >= key.releaseAt) { key.target = 0; sound.play('up', key.sound); }
      const goal = key.target === 1 ? 1 : key.hover ? -0.09 : 0;
      for (let i = 0; i < n; i++) { const a = K * (goal - key.x) - D * key.v; key.v += a * h; key.x += key.v * h; }
      if (Math.abs(goal - key.x) < 2e-4 && Math.abs(key.v) < 2e-3) { key.x = goal; key.v = 0; } else active = true;
      if (key.target === 1 && !key.held) active = true;
      const m = key.mesh, x = key.x;
      m.position.y = key.base - x * key.travel;
      const sq = Math.max(0, x) * 0.04, st = Math.max(0, -x) * 0.05;
      m.scale.set(1 + sq * 0.45, 1 - sq + st, 1 + sq * 0.45);
    }
    const WK = 230, WD = 7.5;
    for (const w of wobbles) {
      for (let i = 0; i < n; i++) {
        w.vrx += (-WK * w.rx - WD * w.vrx) * h; w.rx += w.vrx * h;
        w.vrz += (-WK * w.rz - WD * w.vrz) * h; w.rz += w.vrz * h;
        w.vy += (-WK * 1.6 * w.y - WD * 1.4 * w.vy) * h; w.y += w.vy * h;
      }
      if (Math.abs(w.rx) + Math.abs(w.rz) + Math.abs(w.y) + Math.abs(w.vrx) + Math.abs(w.vrz) + Math.abs(w.vy) > 1e-4) active = true;
      else w.rx = w.rz = w.y = w.vrx = w.vrz = w.vy = 0;
    }
    if (hoverXY) { updateHover(); }
    return active;
  }

  /* raycasting */
  function hit(x, y) {
    if (!pairs.length) return null;
    const r = canvas.getBoundingClientRect();
    if (!r.width || !r.height) return null;
    ndc.set(((x - r.left) / r.width) * 2 - 1, -((y - r.top) / r.height) * 2 + 1);
    for (const { cam, list } of pairs) {
      if (!list.length) continue;
      ray.setFromCamera(ndc, cam);
      const hits = ray.intersectObjects(list, false);
      if (hits.length) return hits[0].object.userData.keyId;
    }
    return null;
  }
  function updateHover() {
    const id = hoverXY.blocked ? null : hit(hoverXY.x, hoverXY.y);
    if (id === hovered) return;
    if (hovered && keys.get(hovered)) keys.get(hovered).hover = false;
    hovered = id;
    if (id) keys.get(id).hover = true;
    document.documentElement.classList.toggle('over-key', !!id);
    request();
  }

  addEventListener('pointerdown', (e) => {
    sound.gesture();
    if (e.button !== 0 || (e.target.closest && e.target.closest(INTERACTIVE))) return;
    const id = hit(e.clientX, e.clientY);
    if (!id) return;
    if (e.pointerType === 'mouse') e.preventDefault();
    pointers.set(e.pointerId, id);
    press(id);
  });
  const up = (e) => { const id = pointers.get(e.pointerId); if (id) { pointers.delete(e.pointerId); release(id); } };
  addEventListener('pointerup', up);
  addEventListener('pointercancel', up);
  addEventListener('pointermove', (e) => {
    if (e.pointerType !== 'mouse') return;
    hoverXY = { x: e.clientX, y: e.clientY, blocked: !!(e.target.closest && e.target.closest(INTERACTIVE)) };
    request();
  }, { passive: true });
  document.addEventListener('pointerleave', () => { hoverXY = { x: -1e4, y: -1e4 }; request(); });

  /* your keyboard → the 3D keyboard */
  const held = new Map();
  addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') sound.gesture();
    if (e.repeat || e.altKey || e.ctrlKey) return;
    const a = document.activeElement;
    if (a && a !== document.body && a.matches && a.matches('input,textarea,select,[contenteditable],a,button,summary')) return;
    const id = KEYMAP[(e.key || '').toLowerCase()];
    if (!id) return;
    if (id === 'k' && e.metaKey) e.preventDefault();
    const ids = route(id);
    held.set(id, ids);
    ids.forEach(press);
  });
  addEventListener('keyup', (e) => {
    const id = KEYMAP[(e.key || '').toLowerCase()];
    // macOS swallows keyup for other keys while ⌘ is down: releasing ⌘ releases everything
    if (id === 'cmd') { for (const ids of held.values()) ids.forEach(release); held.clear(); return; }
    if (id && held.has(id)) { held.get(id).forEach(release); held.delete(id); }
  });
  addEventListener('blur', () => { releaseAll(); held.clear(); });

  return {
    add, wobble, press, release, tap, tick, keys,
    setTargets(p) { pairs = p; },
    setRoute(fn) { route = fn; },
  };
}
