// Tethera — scroll timeline. Reads native scroll (no hijacking), damps it, and
// turns hero progress p ∈ [0, 1] into a camera pose, keyboard drop, DOM fades.

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };
const inOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
export const damp = (a, b, rate, dt) => lerp(a, b, 1 - Math.exp(-rate * dt));

const TAN = Math.tan((30 / 2) * Math.PI / 180); // both cameras use a 30° vertical fov

// Keyframes. fit: contain a w×h box inside fw×fh of the viewport. cover: fill the viewport with the screen.
// s: lens shift in NDC (moves the subject without rotating the camera).
const SIDE = [
  { p: 0, az: 0.6, el: 0.4, t: [0.08, 1.1, 1.55], fit: [5.1, 3.9, 0.47, 0.72], s: [0.46, -0.04] },
  { p: 0.15, same: true },
  { p: 0.55, az: 0, el: 0.06, t: [0, 1.6, 1.1], fit: [3.0, 3.3, 0.9, 0.9], s: [0, 0] },
  { p: 0.9, az: 0, el: 0, t: [0, 1.98, 1.07], cover: 0.9, s: [0, 0] },
  { p: 1, az: 0, el: 0, t: [0, 1.98, 1.07], cover: 0.84, s: [0, 0] },
];
const STACK = [
  { p: 0, az: 0.55, el: 0.4, t: [0.05, 1.1, 1.55], fit: [5.6, 4.3, 0.9, 0.44], s: [0.07, -0.47] },
  { p: 0.12, same: true },
  { p: 0.55, az: 0, el: 0.06, t: [0, 1.62, 1.1], fit: [2.9, 3.2, 0.92, 0.8], s: [0, 0] },
  { p: 0.88, az: 0, el: 0, t: [0, 1.98, 1.07], fitW: 0.86, s: [0, 0] },
  { p: 1, az: 0, el: 0, t: [0, 1.98, 1.07], fitW: 0.8, s: [0, 0] },
];
for (const K of [SIDE, STACK]) K.forEach((f, i) => { if (f.same) Object.assign(f, K[i - 1], { p: f.p, same: false }); });

function distance(f, aspect) {
  if (f.cover) return Math.min(1.64 / (2 * TAN * aspect), 1.26 / (2 * TAN)) * f.cover;
  if (f.fitW) return (1.64 * f.fitW) / (2 * TAN * aspect);
  const [w, h, fw, fh] = f.fit;
  return Math.max(h / (2 * TAN * fh), w / (2 * TAN * aspect * fw));
}

export function createTimeline({ hero, copy, shot, cue, reduced, side }) {
  const st = {
    p: 0, pd: 0, top: 0, h: 1, vh: 1, layout: 'side', snap: true,
    heroVis: true, canvasOp: 1, drop: 0, float: 1, chapter: 'boot', offsetY: 0,
  };
  const dom = { copyOp: -1, copyY: -1, shotOp: -1, shotS: -1, cueOp: -1 };

  function measure() {
    const r = hero.getBoundingClientRect();
    st.top = r.top + scrollY; st.h = hero.offsetHeight; st.vh = innerHeight;
    st.layout = side() ? 'side' : 'stack';
    st.snap = true;
  }
  function raw() {
    if (reduced()) return 0;
    return clamp((scrollY - st.top) / Math.max(1, st.h - st.vh));
  }
  function set(el, prop, key, v, fmt) {
    if (Math.abs(dom[key] - v) < 0.002) return;
    dom[key] = v; el.style[prop] = fmt(v);
  }

  function update(dt) {
    st.p = raw();
    if (st.snap) { st.pd = st.p; st.snap = false; }
    else st.pd = damp(st.pd, st.p, 7.5, dt);
    if (Math.abs(st.pd - st.p) < 0.0005) st.pd = st.p;
    const p = st.pd;

    if (reduced()) {
      const y = scrollY;
      st.heroVis = y < st.top + st.h; st.offsetY = (y - st.top) / st.vh * 2; st.canvasOp = 1;
      st.drop = 0; st.float = 0;
    } else {
      st.heroVis = p < 0.975; st.offsetY = 0;
      st.canvasOp = st.heroVis ? 1 - smooth(0.9, 0.965, p) : 1;
      st.drop = Math.pow(clamp((p - 0.17) / 0.32), 2.2);
      st.float = 1 - smooth(0.12, 0.4, p);
      set(copy, 'opacity', 'copyOp', 1 - smooth(0.07, 0.22, p), (v) => v.toFixed(3));
      set(copy, 'transform', 'copyY', p * 90, (v) => `translate3d(0, ${(-v).toFixed(1)}px, 0)`);
      copy.style.visibility = p > 0.24 ? 'hidden' : '';
      set(shot, 'opacity', 'shotOp', smooth(0.9, 0.965, p), (v) => v.toFixed(3));
      set(shot, 'transform', 'shotS', 1.06 - 0.06 * smooth(0.9, 1, p), (v) => `scale(${v.toFixed(4)})`);
      if (cue) set(cue, 'opacity', 'cueOp', 1 - smooth(0, 0.04, p), (v) => v.toFixed(3));
    }
    if (p >= 0.26 && st.chapter !== 'live') st.chapter = 'live';
    else if (p < 0.2 && st.chapter !== 'boot') st.chapter = 'boot';
    return st.pd !== st.p;
  }

  // Camera pose for the current damped progress.
  function pose(aspect, out) {
    const K = st.layout === 'side' ? SIDE : STACK;
    const p = st.pd;
    let i = 0;
    while (i < K.length - 2 && p > K[i + 1].p) i++;
    const A = K[i], B = K[i + 1];
    const u = inOut(clamp((p - A.p) / Math.max(1e-6, B.p - A.p)));
    const az = lerp(A.az, B.az, u), el = lerp(A.el, B.el, u);
    const d = Math.exp(lerp(Math.log(distance(A, aspect)), Math.log(distance(B, aspect)), u));
    const t = A.t.map((v, j) => lerp(v, B.t[j], u));
    out.tgt = t;
    out.pos = [t[0] + d * Math.sin(az) * Math.cos(el), t[1] + d * Math.sin(el), t[2] + d * Math.cos(az) * Math.cos(el)];
    out.sx = lerp(A.s[0], B.s[0], u);
    out.sy = lerp(A.s[1], B.s[1], u) + st.offsetY;
    return out;
  }

  return { st, measure, update, pose };
}
