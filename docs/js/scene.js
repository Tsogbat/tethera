// Tethera — 3D scene: the retro all-in-one, its strangely huge keyboard, the coiled
// cable, floating keycaps beside each section and the Download finale. All geometry
// is procedural. Units: 1 ≈ 10 cm, y up, computer faces +z, origin on the floor.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { createScreen, drawLabel } from './screen.js';
import { createTimeline, damp } from './scroll.js';
import { createKeys } from './keys.js';

const DMG = 'https://github.com/Tsogbat/tethera/releases/latest/download/Tethera-macOS.dmg';
const Q = new URLSearchParams(location.search);
const FIXED_DT = Q.has('fixeddt') ? 1 / 60 : 0; // deterministic springs for slow headless captures
const root = document.documentElement;
const canvas = document.getElementById('stage');
const mReduce = matchMedia('(prefers-reduced-motion: reduce)');
const mDark = matchMedia('(prefers-color-scheme: dark)');
const mSide = matchMedia('(min-width: 900px) and (min-aspect-ratio: 23/20)');
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;

function fallback() {
  root.classList.add('no-webgl');
  const s = document.querySelector('[data-still]');
  if (s && !s.getAttribute('src')) s.src = 'assets/hero-still.png';
}
function hasWebGL2() {
  try { return !!document.createElement('canvas').getContext('webgl2'); } catch (_) { return false; }
}

if (!canvas || Q.has('nogl') || !hasWebGL2()) fallback();
else {
  try { main(); } catch (err) { console.warn('Tethera: 3D unavailable', err); fallback(); }
}

/* ------------------------------------------------------------------ geometry */
function rrShape(w, h, r) {
  const s = new THREE.Shape(), a = w / 2 - r, b = h / 2 - r;
  s.moveTo(-a, -h / 2); s.lineTo(a, -h / 2); s.absarc(a, -b, r, -Math.PI / 2, 0, false);
  s.lineTo(w / 2, b); s.absarc(a, b, r, 0, Math.PI / 2, false);
  s.lineTo(-a, h / 2); s.absarc(-a, b, r, Math.PI / 2, Math.PI, false);
  s.lineTo(-w / 2, -b); s.absarc(-a, -b, r, Math.PI, Math.PI * 1.5, false);
  return s;
}
function ring(hw, hd, r, C) {
  r = Math.min(r, hw * 0.999, hd * 0.999);
  const out = [], cs = [[1, 1], [-1, 1], [-1, -1], [1, -1]];
  for (let q = 0; q < 4; q++) {
    const cx = cs[q][0] * (hw - r), cz = cs[q][1] * (hd - r);
    for (let i = 0; i <= C; i++) { const a = (q + i / C) * Math.PI / 2; out.push(cx + r * Math.cos(a), cz + r * Math.sin(a)); }
  }
  return out;
}
// A sculpted keycap: tapered walls, a rounded top edge and a slightly dished top.
// UVs project the top face onto [0,1]², so a legend canvas maps straight onto it.
function capGeometry(w, d, o = {}) {
  const h = o.h ?? 0.34, skirt = o.skirt ?? 0.12, taper = o.taper ?? 0.035, bev = o.bev ?? 0.075;
  const rc = o.rc ?? 0.17, dish = o.dish ?? 0.026, C = o.C ?? 7, B = 5, T = o.T ?? 6;
  const hw0 = w / 2, hd0 = d / 2, hw1 = hw0 - taper, hd1 = hd0 - taper;
  const rings = [[hw0, hd0, rc, -skirt], [hw1, hd1, rc, h - bev]];
  for (let i = 1; i <= B; i++) {
    const a = (i / B) * Math.PI / 2, ins = bev * (1 - Math.cos(a));
    rings.push([hw1 - ins, hd1 - ins, Math.max(rc - ins, 0.02), h - bev + bev * Math.sin(a)]);
  }
  const hwT = hw1 - bev, hdT = hd1 - bev, rT = Math.max(rc - bev, 0.02);
  for (let i = 1; i < T; i++) { const s = 1 - i / T; rings.push([hwT * s, hdT * s, rT * s, h - dish * (1 - s * s)]); }
  const N = 4 * (C + 1), pos = [], uv = [], idx = [];
  const vert = (x, y, z) => { pos.push(x, y, z); uv.push(0.5 + x / (2 * hwT), 0.5 - z / (2 * hdT)); };
  for (const [hw, hd, r, y] of rings) { const p = ring(hw, hd, r, C); for (let j = 0; j < N; j++) vert(p[2 * j], y, p[2 * j + 1]); }
  const R = rings.length;
  for (let i = 0; i < R - 1; i++) for (let j = 0; j < N; j++) {
    const jn = (j + 1) % N, a = i * N + j, b = i * N + jn, c = (i + 1) * N + jn, e = (i + 1) * N + j;
    idx.push(a, e, b, b, e, c);
  }
  const top = R * N; vert(0, h - dish, 0);
  for (let j = 0; j < N; j++) idx.push((R - 1) * N + j, top, (R - 1) * N + (j + 1) % N);
  const bot = top + 1, p0 = ring(hw0, hd0, rc, C);
  for (let j = 0; j < N; j++) vert(p0[2 * j], -skirt, p0[2 * j + 1]);
  vert(0, -skirt, 0);
  for (let j = 0; j < N; j++) idx.push(bot + j, bot + (j + 1) % N, bot + N);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx); g.computeVertexNormals();
  g.userData.aspect = hwT / hdT;
  return g;
}
// The CRT: a gently bulged rounded rectangle (edges flush, center proud).
function crtGeometry(w, h, r, bulge) {
  const g = new THREE.PlaneGeometry(w, h, 56, 44), p = g.attributes.position, hw = w / 2, hh = h / 2;
  for (let i = 0; i < p.count; i++) {
    let x = p.getX(i), y = p.getY(i);
    if (Math.abs(x) > hw - r && Math.abs(y) > hh - r) {
      const cx = Math.sign(x) * (hw - r), cy = Math.sign(y) * (hh - r), dx = x - cx, dy = y - cy, d = Math.hypot(dx, dy);
      if (d > r) { x = cx + (dx / d) * r; y = cy + (dy / d) * r; }
    }
    const nx = x / hw, ny = y / hh;
    p.setXYZ(i, x, y, bulge * (1 - nx * nx) * (1 - ny * ny));
  }
  g.computeVertexNormals();
  return g;
}
// A coiled cable: a helix wound around a CatmullRom path, swept into a tube.
// Rebuilt in place when the keyboard moves.
function createCable(mat) {
  const SEG = 380, RAD = 8, R = 0.034, TURNS = 15, COIL = 0.075;
  const V = THREE.Vector3, arr = () => Array.from({ length: SEG + 1 }, () => new V());
  const Bp = arr(), Hp = arr(), T1 = arr(), N1 = arr(), B1 = arr(), T2 = arr(), N2 = arr(), B2 = arr();
  const pos = new Float32Array((SEG + 1) * (RAD + 1) * 3), nor = new Float32Array(pos.length), idx = [];
  for (let i = 0; i < SEG; i++) for (let j = 0; j < RAD; j++) {
    const a = i * (RAD + 1) + j, b = a + RAD + 1;
    idx.push(a, a + 1, b, b, a + 1, b + 1);
  }
  const geo = new THREE.BufferGeometry();
  geo.setIndex(idx);
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  const mesh = new THREE.Mesh(geo, mat);
  const up = new V(0, 1, 0), side = new V(1, 0, 0);
  function frames(P, T, Nn, Bn) {
    for (let i = 0; i <= SEG; i++) T[i].subVectors(P[Math.min(SEG, i + 1)], P[Math.max(0, i - 1)]).normalize();
    Nn[0].crossVectors(T[0], Math.abs(T[0].y) < 0.9 ? up : side).normalize();
    for (let i = 1; i <= SEG; i++) Nn[i].copy(Nn[i - 1]).addScaledVector(T[i], -Nn[i - 1].dot(T[i])).normalize();
    for (let i = 0; i <= SEG; i++) Bn[i].crossVectors(T[i], Nn[i]);
  }
  function update(points) {
    const curve = new THREE.CatmullRomCurve3(points, false, 'centripetal');
    for (let i = 0; i <= SEG; i++) curve.getPointAt(i / SEG, Bp[i]);
    frames(Bp, T1, N1, B1);
    for (let i = 0; i <= SEG; i++) {
      const u = i / SEG, env = smooth(0.1, 0.2, u) * (1 - smooth(0.8, 0.9, u)), th = u * TURNS * Math.PI * 2;
      Hp[i].copy(Bp[i]).addScaledVector(N1[i], Math.cos(th) * COIL * env).addScaledVector(B1[i], Math.sin(th) * COIL * env);
    }
    frames(Hp, T2, N2, B2);
    let o = 0;
    for (let i = 0; i <= SEG; i++) for (let j = 0; j <= RAD; j++) {
      const a = (j / RAD) * Math.PI * 2, c = Math.cos(a), s = Math.sin(a);
      const nx = N2[i].x * c + B2[i].x * s, ny = N2[i].y * c + B2[i].y * s, nz = N2[i].z * c + B2[i].z * s;
      pos[o] = Hp[i].x + nx * R; pos[o + 1] = Hp[i].y + ny * R; pos[o + 2] = Hp[i].z + nz * R;
      nor[o] = nx; nor[o + 1] = ny; nor[o + 2] = nz; o += 3;
    }
    geo.attributes.position.needsUpdate = true; geo.attributes.normal.needsUpdate = true;
    geo.computeBoundingSphere();
    return { a: Hp[0], ta: T2[0], b: Hp[SEG], tb: T2[SEG] };
  }
  return { mesh, update };
}

/* ------------------------------------------------------------------ main */
function main() {
  const mSmall = matchMedia('(max-width: 760px), (max-height: 500px)');
  const small = () => mSmall.matches;
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setClearColor(0x000000, 0);
  renderer.autoClear = false;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.VSMShadowMap;
  root.classList.add('has-3d'); // pins the hero (300vh) before anything is measured
  const ANISO = Math.min(8, renderer.capabilities.getMaxAnisotropy());

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  pmrem.dispose();

  const heroCam = new THREE.PerspectiveCamera(30, 1, 0.1, 100);
  const pageCam = new THREE.PerspectiveCamera(30, 1, 1, 60);
  pageCam.position.set(0, 0, 20);
  const PAGE_H = 2 * 20 * Math.tan(Math.PI / 12);

  /* materials */
  const COL = { cream: '#E9E3D3', plinth: '#DCD4C2', bezel: '#DED6C4', slot: '#2A2826', graphite: '#2B2B2E', bone: '#F2F0ED', ink: '#1A1A1A', vent: '#C9C1AF' };
  const plastic = (color, o = {}) => new THREE.MeshPhysicalMaterial({ color, roughness: 0.55, clearcoat: 0.25, clearcoatRoughness: 0.6, ...o });
  const flush = { polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 };
  const M = {
    cream: plastic(COL.cream),
    body: plastic(COL.cream),
    plinth: plastic(COL.plinth, { roughness: 0.6 }),
    bezel: plastic(COL.bezel, { side: THREE.BackSide, roughness: 0.62 }),
    deck: plastic(COL.bezel, { roughness: 0.62, ...flush }),
    slot: new THREE.MeshStandardMaterial({ color: COL.slot, roughness: 0.85, ...flush }),
    vent: new THREE.MeshStandardMaterial({ color: COL.vent, roughness: 0.8, ...flush }),
    graphite: plastic(COL.graphite, { roughness: 0.45, clearcoat: 0.3, clearcoatRoughness: 0.4 }),
    led: new THREE.MeshStandardMaterial({ color: COL.bone, emissive: COL.bone, emissiveIntensity: 0.4, roughness: 0.3, ...flush }),
  };
  // The bezel is a real recess: the body's front face is cut away inside it (SDF discard)
  // and a back-faced tray shows the inside walls and floor.
  M.body.onBeforeCompile = (s) => {
    s.uniforms.uHole = { value: new THREE.Vector4(0, 1.98 - 1.54, 0.98, 0.8) };
    s.vertexShader = s.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vObj;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvObj = position;');
    s.fragmentShader = s.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vObj;\nuniform vec4 uHole;')
      .replace('void main() {', `void main() {
        if (vObj.z > 1.0) {
          vec2 q = abs(vObj.xy - uHole.xy) - uHole.zw + 0.16;
          if (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.16 < 0.0) discard;
        }`);
  };
  const mesh = (geo, mat, cast = true) => { const m = new THREE.Mesh(geo, mat); m.castShadow = cast; return m; };

  /* legends drawn into canvases */
  const legends = [];
  function legendMaterial(label, o) {
    const res = small() ? 256 : 512;
    const cv = document.createElement('canvas');
    cv.height = res; cv.width = Math.min(2048, Math.round(res * o.aspect));
    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = ANISO;
    const draw = () => {
      const g = cv.getContext('2d');
      g.fillStyle = o.bg; g.fillRect(0, 0, cv.width, cv.height);
      drawLabel(g, label, cv.width / 2, cv.height / 2, cv.height * o.size, o.fg, 500);
      tex.needsUpdate = true;
    };
    draw(); legends.push(draw);
    return new THREE.MeshPhysicalMaterial({ map: tex, roughness: 0.42, clearcoat: 0.32, clearcoatRoughness: 0.32 });
  }

  /* ---------------- the computer ---------------- */
  const rig = new THREE.Group();
  scene.add(rig);
  const computer = new THREE.Group();
  rig.add(computer);
  const plinth = mesh(new RoundedBoxGeometry(2.2, 0.14, 2.0, 3, 0.05), M.plinth);
  plinth.position.y = 0.07;
  const body = mesh(new RoundedBoxGeometry(2.4, 2.8, 2.2, 7, 0.26), M.body);
  body.position.y = 1.54;
  const tray = mesh(new THREE.ExtrudeGeometry(rrShape(1.96, 1.6, 0.16), { depth: 0.075, bevelEnabled: false, curveSegments: 12 }), M.bezel, false);
  tray.position.set(0, 1.98, 1.035);
  computer.add(plinth, body, tray);

  const screen = createScreen(small() ? 1024 : 2048);
  const screenTexture = () => {
    const t = new THREE.CanvasTexture(screen.canvas);
    t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = ANISO;
    return t;
  };
  let screenTex = screenTexture();
  M.screen = new THREE.MeshPhysicalMaterial({
    color: '#0E0E0F', map: screenTex, emissive: 0xffffff, emissiveMap: screenTex, emissiveIntensity: 1,
    roughness: 0.3, metalness: 0, specularIntensity: 0.6, clearcoat: 0.6, clearcoatRoughness: 0.16,
    envMap: scene.environment, envMapIntensity: 0.12, toneMapped: false, // own envMap so the intensity applies
  });
  const crt = mesh(crtGeometry(1.64, 1.26, 0.12, 0.035), M.screen, false);
  crt.position.set(0, 1.98, 1.04);
  computer.add(crt);

  const front = 1.1 + 0.0015;
  const slot = new THREE.Mesh(new THREE.ShapeGeometry(rrShape(0.72, 0.07, 0.033), 6), M.slot);
  slot.position.set(0.48, 0.72, front);
  const ventGeo = new THREE.ShapeGeometry(rrShape(0.3, 0.024, 0.012), 4);
  for (let i = 0; i < 5; i++) { const v = new THREE.Mesh(ventGeo, M.vent); v.position.set(-0.62, 0.6 + i * 0.06, front); computer.add(v); }
  const led = new THREE.Mesh(new THREE.CircleGeometry(0.03, 24), M.led);
  led.position.set(-0.9, 0.72, front);
  const port = new THREE.Mesh(new THREE.ShapeGeometry(rrShape(0.22, 0.13, 0.04), 4), M.slot);
  port.position.set(-1.2015, 0.45, 0.3); port.rotation.y = -Math.PI / 2;
  computer.add(slot, led, port);

  /* ---------------- the keyboard ---------------- */
  const kbAnchor = new THREE.Group(); kbAnchor.position.set(0, 0, 2.75);
  const kbTilt = new THREE.Group(); kbTilt.position.set(0, 0, 1.0); kbTilt.rotation.x = THREE.MathUtils.degToRad(4);
  const kbBody = new THREE.Group(); kbBody.position.set(0, 0, -1.0);
  kbAnchor.add(kbTilt); kbTilt.add(kbBody); rig.add(kbAnchor);
  const slabGeo = new RoundedBoxGeometry(3.8, 0.34, 2.0, 5, 0.14);
  const deckGeo = new THREE.ShapeGeometry(rrShape(3.58, 1.8, 0.2), 8);
  const footGeo = new RoundedBoxGeometry(0.5, 0.14, 0.22, 2, 0.05);
  const slab = mesh(slabGeo, M.cream); slab.position.y = 0.17;
  const deck = new THREE.Mesh(deckGeo, M.deck); deck.rotation.x = -Math.PI / 2; deck.position.y = 0.3415;
  kbBody.add(slab, deck);
  for (const x of [-1.45, 1.45]) { const f = mesh(footGeo, M.graphite); f.position.set(x, -0.057, -0.82); kbBody.add(f); }

  const cap1 = capGeometry(0.8, 0.8);
  const capRet = capGeometry(2.56, 0.8, { C: 8 });
  const KEYS = [
    { id: 'esc', label: 'esc', x: -1.32, z: -0.44, size: 0.21 },
    { id: 'cmd', label: '⌘', x: -0.44, z: -0.44, size: 0.5 },
    { id: 'k', label: 'K', x: 0.44, z: -0.44, size: 0.36 },
    { id: 'd', label: 'D', x: 1.32, z: -0.44, size: 0.36 },
    { id: 't', label: 't', x: -1.32, z: 0.44, size: 0.38 },
    { id: 'return', label: 'return', x: 0.44, z: 0.44, size: 0.22, wide: true },
  ];
  const mainKeyMeshes = [];

  /* ---------------- the cable ---------------- */
  const cable = createCable(M.graphite);
  cable.mesh.castShadow = true;
  rig.add(cable.mesh);
  const plugGeo = new THREE.CylinderGeometry(0.055, 0.06, 0.17, 18);
  const plugA = mesh(plugGeo, M.graphite), plugB = mesh(plugGeo, M.graphite);
  rig.add(plugA, plugB);
  const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
  const REST = [V3(-1.72, 0.13, 1.18), V3(-1.88, 0.13, 0.74), V3(-1.72, 0.2, 0.36)];
  const C_END = [V3(-1.47, 0.43, 0.3), V3(-1.25, 0.45, 0.3)];
  const kbM = new THREE.Matrix4(), yAxis = V3(0, 1, 0);
  let cableDrop = -1;
  function updateCable(drop) {
    if (Math.abs(drop - cableDrop) < 1e-4) return;
    cableDrop = drop;
    kbAnchor.updateMatrix(); kbTilt.updateMatrix(); kbBody.updateMatrix();
    kbM.copy(kbAnchor.matrix).multiply(kbTilt.matrix).multiply(kbBody.matrix);
    const a0 = V3(-1.5, 0.21, -1.02).applyMatrix4(kbM), a1 = V3(-1.5, 0.15, -1.3).applyMatrix4(kbM);
    const mid = REST.map((p, i) => {
      const f = (i + 1) / 4, hang = a1.clone().lerp(C_END[0], f);
      hang.y -= Math.sin(f * Math.PI) * 0.9;
      return p.clone().lerp(hang, drop);
    });
    const e = cable.update([a0, a1, ...mid, ...C_END]);
    plugA.position.copy(e.a).addScaledVector(e.ta, 0.06); plugA.quaternion.setFromUnitVectors(yAxis, e.ta);
    plugB.position.copy(e.b).addScaledVector(e.tb, -0.06); plugB.quaternion.setFromUnitVectors(yAxis, e.tb);
  }

  /* ---------------- floor, light ---------------- */
  const floorMat = new THREE.ShadowMaterial({ color: '#2B2620', opacity: 0.2 });
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), floorMat);
  floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true;
  scene.add(floor);
  const key = new THREE.DirectionalLight(0xffffff, 2.8);
  key.position.set(-6, 7, 3); key.target.position.set(0, 0.8, 1.2);
  key.castShadow = true; key.shadow.mapSize.set(1024, 1024);
  Object.assign(key.shadow.camera, { left: -5.5, right: 5.5, top: 5.5, bottom: -5.5, near: 1, far: 26 });
  key.shadow.radius = 14; key.shadow.blurSamples = 20; key.shadow.bias = -0.0004;
  scene.add(key, key.target);

  /* ---------------- props: floating keycaps + the Download finale ---------------- */
  const pageRoot = new THREE.Group(); scene.add(pageRoot);
  const PROP_LABEL = { palette: '⌘K', overview: '⇧⌘A', home: '⇧⌘H', split: '⌘D' };
  const PROP_BONE = { overview: true, split: true };
  const props = [];
  const propCap = capGeometry(0.8, 0.8, { skirt: 0.1 });

  /* ---------------- keys ---------------- */
  const reduced = () => mReduce.matches;
  let lastInput = performance.now();
  const keys = createKeys({ THREE, canvas, request: () => request(), reduced, soundButton: document.querySelector('[data-sound]') });
  const kbWob = keys.wobble();
  const live = document.getElementById('live');
  const say = (t) => { if (live) live.textContent = t; };
  const ACT = {
    t: () => { screen.show('boot'); say('Screen: tethera boot screen'); },
    esc: () => { screen.show('home'); say('Screen: Home'); },
    return: () => { screen.show('session'); say('Screen: starting Claude Code. After a moment it needs you.'); },
    cmd: () => screen.cmd(),
    k: () => { screen.palette(); say('Screen: command palette'); },
    d: () => { screen.split(); say('Screen: split into two panes'); },
  };
  for (const k of KEYS) {
    const geo = k.wide ? capRet : cap1;
    const mat = legendMaterial(k.label, {
      aspect: geo.userData.aspect, size: k.size,
      bg: k.wide ? COL.bone : COL.graphite, fg: k.wide ? COL.ink : COL.bone,
    });
    const m = mesh(geo, mat);
    m.position.set(k.x, 0.34, k.z);
    kbBody.add(m); mainKeyMeshes.push(m);
    keys.add({
      id: k.id, mesh: m, base: 0.34, travel: 0.238, wob: kbWob, wx: k.x / 1.9, wz: k.z / 0.9, mass: k.wide ? 1.4 : 1,
      sound: { pitch: k.wide ? 0.82 : 1 }, onPress: () => { lastInput = performance.now(); ACT[k.id](); },
    });
  }
  document.querySelectorAll('[data-key]').forEach((b) => b.addEventListener('click', () => keys.tap(b.dataset.key)));

  document.querySelectorAll('[data-prop]').forEach((el, i) => {
    const name = el.dataset.prop;
    const group = new THREE.Group();
    group.visible = false;
    pageRoot.add(group);
    const wob = keys.wobble();
    if (name === 'download') {
      const inner = new THREE.Group(); inner.position.y = -0.3; group.add(inner);
      const s = new THREE.Mesh(slabGeo, M.cream); s.position.y = 0.17;
      const dk = new THREE.Mesh(deckGeo, M.deck); dk.rotation.x = -Math.PI / 2; dk.position.y = 0.3415;
      const giantGeo = capGeometry(3.44, 1.68, { h: 0.4, rc: 0.3, bev: 0.1, dish: 0.03, C: 10, T: 8 });
      const giant = new THREE.Mesh(giantGeo, legendMaterial('↓Download', { aspect: giantGeo.userData.aspect, size: 0.3, bg: COL.bone, fg: COL.ink }));
      giant.position.y = 0.34;
      inner.add(s, dk, giant);
      props.push({ name, el, group, wob, mesh: giant, finale: true, phase: 0 });
      keys.add({
        id: 'download', mesh: giant, base: 0.34, travel: 0.27, wob, wx: 0.25, wz: 0.5, mass: 2, minHold: 170,
        sound: { pitch: 0.66, vel: 1.15 }, onPress: startDownload,
      });
      return;
    }
    const m = new THREE.Mesh(propCap, legendMaterial(PROP_LABEL[name] || '', {
      aspect: 1, size: 0.3, bg: PROP_BONE[name] ? COL.bone : COL.graphite, fg: PROP_BONE[name] ? COL.ink : COL.bone,
    }));
    m.position.y = -0.12;
    group.add(m);
    props.push({ name, el, group, wob, mesh: m, phase: i * 1.7, flip: !!el.closest('.sec-flip') });
    keys.add({ id: 'prop:' + name, mesh: m, base: -0.12, travel: 0.2, wob, wx: 0.6, wz: 0.8, sound: { pitch: 1.08 }, onPress: () => { lastInput = performance.now(); } });
  });
  const propByName = Object.fromEntries(props.map((p) => [p.name, p]));
  keys.setRoute((id) => {
    const ids = [id];
    if (id === 'k' && propByName.palette && propByName.palette.vis) ids.push('prop:palette');
    if (id === 'd' && propByName.split && propByName.split.vis) ids.push('prop:split');
    return ids;
  });

  let dlTimer = 0;
  function startDownload() {
    lastInput = performance.now();
    say('Starting the download of Tethera for Mac.');
    clearTimeout(dlTimer);
    dlTimer = setTimeout(() => { if (!Q.has('nodl')) location.href = DMG; }, 420);
  }

  /* ---------------- timeline ---------------- */
  const heroEl = document.querySelector('[data-hero]');
  const tl = createTimeline({
    hero: heroEl, copy: document.querySelector('[data-hero-copy]'), shot: document.querySelector('[data-hero-shot]'),
    cue: document.querySelector('[data-cue]'), reduced, side: () => mSide.matches,
  });
  const poseOut = {};
  function applyPose(cam, pose) {
    cam.position.set(pose.pos[0], pose.pos[1], pose.pos[2]);
    cam.lookAt(pose.tgt[0], pose.tgt[1], pose.tgt[2]);
    cam.updateProjectionMatrix();
    const e = cam.projectionMatrix.elements;
    e[8] = -pose.sx; e[9] = -pose.sy;
    cam.projectionMatrixInverse.copy(cam.projectionMatrix).invert();
  }

  /* ---------------- theme ---------------- */
  function theme() {
    const dark = mDark.matches;
    renderer.toneMappingExposure = dark ? 0.95 : 0.9;
    scene.environmentIntensity = dark ? 0.68 : 0.72;
    floorMat.color.set(dark ? '#000000' : '#2B2620'); // a shadow must never be lighter than the backdrop
    floorMat.opacity = dark ? 0.55 : 0.2;
  }
  theme();

  /* ---------------- sizing ---------------- */
  let W = 1, H = 1;
  function resize() {
    W = canvas.clientWidth || innerWidth; H = canvas.clientHeight || innerHeight;
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, small() ? 1.5 : 2));
    renderer.setSize(W, H, false);
    heroCam.aspect = pageCam.aspect = W / H;
    pageCam.updateProjectionMatrix();
    const res = small() ? 1024 : 2048;
    if (screen.canvas.width !== res) { // immutable GPU storage: a new size needs a new texture
      screen.resize(res);
      const old = screenTex;
      screenTex = screenTexture();
      M.screen.map = M.screen.emissiveMap = screenTex;
      old.dispose();
    }
    tl.measure();
    request();
  }

  /* ---------------- page props placement ---------------- */
  function placeProps(dt, t, amp) {
    const u = PAGE_H / H, rm = reduced();
    let any = false, moving = false;
    for (const p of props) {
      const r = p.el.getBoundingClientRect();
      const vis = r.width > 0 && r.bottom > -80 && r.top < H + 80;
      p.vis = vis; p.group.visible = vis;
      if (!vis) { p.init = false; continue; }
      any = true;
      const cy = r.top + r.height / 2;
      const tx = (r.left + r.width / 2 - W / 2) * u, ty = -(cy - H / 2) * u;
      if (!p.init || rm) { p.x = tx; p.y = ty; p.init = true; }
      else {
        p.x = damp(p.x, tx, 14, dt); p.y = damp(p.y, ty, 14, dt);
        if (Math.abs(p.x - tx) + Math.abs(p.y - ty) > 0.002) moving = true;
      }
      const prog = clamp(1 - cy / H, -0.4, 1.4);
      const g = p.group;
      if (p.finale) {
        const px = Math.min(W * (W < 760 ? 0.78 : 0.5), 700, r.height * 1.45);
        const s = (px * u) / 3.8;
        const enter = rm ? 1 : smooth(0, 0.62, prog);
        g.scale.setScalar(s);
        g.position.set(p.x, p.y - (1 - enter) * 1.2 * s + p.wob.y * s, 0);
        g.rotation.set(lerp(1.4, 0.64, enter) + p.wob.rx, lerp(0.6, -0.36, enter), lerp(-0.2, 0.05, enter) + p.wob.rz);
      } else {
        const px = W < 760 ? 112 : clamp(W * 0.12, 130, 190);
        const s = (px * u) / 0.8, f = rm ? 0 : amp;
        const dir = p.flip ? -1 : 1;
        g.scale.setScalar(s);
        g.position.set(p.x, p.y + Math.sin(t * 1.25 + p.phase) * 0.05 * s * f + p.wob.y * s, 0);
        g.rotation.set(
          0.92 + (rm ? 0 : (0.5 - prog) * 0.35) + Math.sin(t * 0.9 + p.phase) * 0.05 * f + p.wob.rx,
          dir * -0.42 + (rm ? 0 : (prog - 0.5) * 0.6 * dir) + Math.sin(t * 0.7 + p.phase) * 0.06 * f,
          dir * 0.07 + p.wob.rz,
        );
      }
    }
    return { any, moving };
  }

  /* ---------------- loop: render on demand ---------------- */
  let raf = 0, last = performance.now(), wake = 0, frames = 0, ready = false, lastChapter = '';
  let canvasOp = -1;
  const targets = [];
  function request() { if (!raf && !document.hidden) raf = requestAnimationFrame(frame); }

  function frame(now) {
    raf = 0; clearTimeout(wake);
    const dt = FIXED_DT || clamp((now - last) / 1000, 0.001, 0.05); last = now;
    const t = now / 1000;
    const amp = reduced() ? 0 : clamp(1 - (now - lastInput - 15000) / 1500);
    let active = tl.update(dt);
    const st = tl.st;

    // hero rig
    const heroOn = st.heroVis && st.canvasOp > 0.002;
    if (heroOn) {
      applyPose(heroCam, tl.pose(W / H, poseOut));
      const fl = amp * st.float;
      rig.position.y = fl * (0.035 + 0.035 * Math.sin(t * 1.1));
      rig.rotation.y = fl * 0.03 * Math.sin(t * 0.7);
      if (fl > 0.001) active = true;
      const d = st.drop;
      kbAnchor.position.set(0, -2.6 * d, 2.75 + 1.3 * d);
      kbAnchor.rotation.x = 0.7 * d;
      updateCable(d);
      if (st.chapter !== lastChapter) {
        if (lastChapter || st.chapter !== 'boot') screen.show(st.chapter);
        lastChapter = st.chapter;
      }
      if (screen.update(now)) screenTex.needsUpdate = true;
      // the display goes dark just before it becomes the real screenshot
      M.screen.emissiveIntensity = 1 - smooth(0.82, 0.9, st.pd);
    }
    kbBody.rotation.set(kbWob.rx, 0, kbWob.rz); kbBody.position.y = kbWob.y;

    const pg = placeProps(dt, t, amp);
    if (pg.moving) active = true;
    if (pg.any && amp > 0.001) active = true;

    // raycast targets for this frame
    targets.length = 0;
    if (heroOn && st.drop < 0.4 && st.pd < 0.4) targets.push({ cam: heroCam, list: mainKeyMeshes });
    if (pg.any) targets.push({ cam: pageCam, list: props.filter((p) => p.vis).map((p) => p.mesh) });
    keys.setTargets(targets);

    if (keys.tick(dt, now)) active = true;

    // render
    const op = heroOn ? st.canvasOp : 1;
    if (Math.abs(op - canvasOp) > 0.001) { canvasOp = op; canvas.style.opacity = op.toFixed(3); }
    renderer.clear();
    if (heroOn) {
      rig.visible = floor.visible = true; pageRoot.visible = false;
      renderer.render(scene, heroCam);
    }
    if (pg.any) {
      rig.visible = floor.visible = false; pageRoot.visible = true;
      if (heroOn) renderer.clearDepth();
      renderer.render(scene, pageCam);
    }
    frames++;
    if (!ready) { ready = true; root.classList.add('stage-on'); }

    if (active) request();
    else if (heroOn) wake = setTimeout(request, screen.nextWake(performance.now()));
  }

  /* ---------------- events ---------------- */
  const input = () => { lastInput = performance.now(); request(); };
  addEventListener('scroll', input, { passive: true });
  addEventListener('pointermove', input, { passive: true });
  addEventListener('pointerdown', input, { passive: true });
  addEventListener('keydown', input);
  addEventListener('resize', resize);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { last = performance.now(); request(); } });
  mDark.addEventListener('change', () => { theme(); request(); });
  mReduce.addEventListener('change', () => { tl.measure(); request(); });
  mSide.addEventListener('change', resize);

  const refreshText = () => { legends.forEach((f) => f()); screen.invalidate(); request(); };
  if (document.fonts) {
    document.fonts.load('500 64px "Geist Mono"').then(refreshText, () => {});
    document.fonts.ready.then(refreshText, () => {});
  }

  resize();
  updateCable(0);
  // ?p=0.4 jumps to that point of the hero timeline (for captures and debugging)
  if (Q.has('p') && !reduced()) {
    const p = clamp(parseFloat(Q.get('p')) || 0);
    scrollTo(0, tl.st.top + p * (tl.st.h - tl.st.vh));
    tl.st.snap = true;
  }
  request();

  /* ---------------- debug / capture hooks ---------------- */
  const tmpV = new THREE.Vector3();
  window.__tethera = {
    get frames() { return frames; },
    get state() { const s = tl.st; return { p: s.p, pd: s.pd, heroVis: s.heroVis, screen: screen.mode, settled: s.p === s.pd }; },
    press: (id) => keys.tap(id),
    keyPoint(id) {
      const k = keys.keys.get(id);
      if (!k) return null;
      const cam = id.startsWith('prop:') || id === 'download' ? pageCam : heroCam;
      k.mesh.localToWorld(tmpV.set(0, 0.3, 0)).project(cam);
      return { x: (tmpV.x + 1) / 2 * W, y: (1 - tmpV.y) / 2 * H };
    },
    snapshot(w, h) {
      const pr = renderer.getPixelRatio();
      renderer.setPixelRatio(1); renderer.setSize(w, h, false);
      heroCam.aspect = w / h;
      const T = Math.tan(Math.PI / 12), tg = [0.08, 1.12, 1.55], az = 0.6, el = 0.33;
      const d = Math.max(3.9 / (2 * T * 0.6), 5.1 / (2 * T * heroCam.aspect * 0.6));
      applyPose(heroCam, { tgt: tg, sx: 0, sy: 0, pos: [tg[0] + d * Math.sin(az) * Math.cos(el), tg[1] + d * Math.sin(el), tg[2] + d * Math.cos(az) * Math.cos(el)] });
      rig.position.y = 0; rig.rotation.y = 0; rig.visible = floor.visible = true; pageRoot.visible = false;
      screen.invalidate(); screen.update(Math.floor(performance.now() / 1060) * 1060 + 20); screenTex.needsUpdate = true;
      renderer.clear(); renderer.render(scene, heroCam);
      const url = canvas.toDataURL('image/png');
      renderer.setPixelRatio(pr); resize();
      return url;
    },
  };
}
