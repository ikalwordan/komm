/* kom.js — KOMSTATION EXTRAS web simulator host.
 * Reimplements the `kom` API (see app_lua.c / apps.c) against a 480x272 canvas,
 * WebAudio and keyboard/gamepad, and runs a .lua app via Fengari (Lua-in-JS).
 * Faithful to the PSP look (ported 5x7 font + palette); NOT a perf/RAM model. */
(function (global) {
  const F = global.fengari;
  const { lua, lauxlib, lualib, to_luastring } = F;
  const jstr = F.to_jsstring;

  const SCR_W = 480, SCR_H = 272;

  /* ---- colours: packed 0xAABBGGRR (komstation.h RGBA/RGB) ---- */
  // packed 0xAABBGGRR as an unsigned number (alpha bit makes it > 2^31, so colours
  // are pushed to Lua via lua_pushnumber — this Fengari build has 32-bit integers).
  function pack(r, g, b, a) { return (((a === undefined ? 255 : a) * 16777216) + (b * 65536) + (g * 256) + r) >>> 0; }
  function clampB(x) { x = Math.round(x); return x < 0 ? 0 : x > 255 ? 255 : x; }
  // PSP32_EPS — see _pspsem.js for the full story. pspdev builds Lua with
  // LUA_32BITS, so lua_Integer on the console is 32 BITS, and a colour is always
  // ~4.28 billion (RGB() forces alpha to 0xFF). It does not fit a signed 32-bit
  // integer, so on hardware Lua CANNOT convert a colour and every bitwise operator
  // on one throws "number has no integer representation". fengari's integers are
  // 64-bit and would accept it, hiding the fault — DOOK shipped a `c & 255` that
  // ran 600 clean frames here and died on frame one on the console.
  // There is no knob for fengari's integer width, so the CONSTRAINT is injected
  // instead: a colour comes back as the host's packing plus a half. Arithmetic on
  // it still works (true on the console too — lua_Number there is a 32-bit float);
  // integer conversion fails (also true). Every colour consumer below truncates
  // via `iarg()`/`>>> 0`, so the half never reaches the canvas.
  const PSP32_EPS = 0.5;
  function css(col) { col = col >>> 0; const r = col & 255, g = (col >> 8) & 255, b = (col >> 16) & 255, a = (col >>> 24) & 255; return `rgba(${r},${g},${b},${a / 255})`; }
  function scaleRGB(b, f) { return pack(clampB(b[0] * f), clampB(b[1] * f), clampB(b[2] * f)); }
  function toWhite(b, t) { return pack(clampB(b[0] + (255 - b[0]) * t), clampB(b[1] + (255 - b[1]) * t), clampB(b[2] + (255 - b[2]) * t)); }
  function lerpC(c1, c2, t) { c1 >>>= 0; c2 >>>= 0;
    const r = (c1 & 255) + (((c2 & 255) - (c1 & 255)) * t), g = ((c1 >> 8) & 255) + ((((c2 >> 8) & 255) - ((c1 >> 8) & 255)) * t), b = ((c1 >> 16) & 255) + ((((c2 >> 16) & 255) - ((c1 >> 16) & 255)) * t);
    return pack(clampB(r), clampB(g), clampB(b)); }
  // theme palette derived from a base accent (theme.c deriveFromBase). MUTABLE so the
  // simulator's theme picker can re-derive it live: the chrome re-reads COL every frame,
  // and an app's kom.col is snapshotted per run (re-run to push a new theme into a
  // running app). Default = red terminal base (theme.c palBase[0]).
  const COL = {};
  let BASE = [255, 42, 42];
  function deriveTheme(r, g, b) {
    BASE = [clampB(r), clampB(g), clampB(b)];
    COL.bg = scaleRGB(BASE, 0.028);
    COL.accent = pack(BASE[0], BASE[1], BASE[2]);
    COL.hi = toWhite(BASE, 0.35);
    COL.dim = scaleRGB(BASE, 0.47);     // PAL_DIM — used by the chrome preview
    COL.dark = scaleRGB(BASE, 0.20);
    COL.text = toWhite(BASE, 0.88);
    COL.grey = lerpC(scaleRGB(BASE, 0.55), pack(150, 150, 150), 0.45);
  }
  deriveTheme(255, 42, 42);

  /* ---- render-mode regions (apps.c setRegion) ---- */
  const MODES = { full: [0, 0, 480, 272], inset: [0, 44, 480, 222], window: [40, 30, 400, 212] };

  /* ---- input (keymap is remappable; button->code, mirrored into code->button) ---- */
  const DEFAULT_KEYS = {
    UP: 'ArrowUp', DOWN: 'ArrowDown', LEFT: 'ArrowLeft', RIGHT: 'ArrowRight',
    X: 'KeyZ', O: 'KeyX', SQUARE: 'KeyA', TRIANGLE: 'KeyS',
    L: 'KeyQ', R: 'KeyW', START: 'Enter', SELECT: 'ShiftRight',
  };
  let KEYMAP = {};            // code -> button (rebuilt by setKeymap)
  function rebuildKeymap(bc) {
    KEYMAP = {};
    for (const b in bc) if (bc[b]) KEYMAP[bc[b]] = b;
  }
  let g_keymapBC = Object.assign({}, DEFAULT_KEYS);
  rebuildKeymap(g_keymapBC);
  const PADMAP = { 0: 'X', 1: 'O', 2: 'SQUARE', 3: 'TRIANGLE', 4: 'L', 5: 'R', 8: 'SELECT', 9: 'START', 12: 'UP', 13: 'DOWN', 14: 'LEFT', 15: 'RIGHT' };

  const Sim = {
    canvas: null, ctx: null, L: null, running: false, alive: false, err: '',
    mode: 'full', ox: 0, oy: 0, ow: 480, oh: 272,
    kbHeld: new Set(), held: new Set(), pressed: new Set(), prev: new Set(),
    analogX: 0, analogY: 0, useGamepad: true, anKeys: new Set(),
    images: [], sounds: [], fonts: [], fs: {}, appId: 'app',
    audio: null, last: 0, raf: 0, t0: 0, onStop: null,
    crt: false, frameN: 0, _scan: null, clock12: false, crtPhase: 0,
  };

  // DEPTH RASTER BEGIN — software preview, not a PSP performance model.
  class DepthRaster {
    constructor(w,h) { this.w=w;this.h=h;this.z=new Uint16Array(w*h);this.img=null; }
    reset() { this.z.fill(0);this.img=null; }
    flush(ctx) { if(this.img) { ctx.putImageData(this.img,0,0);this.img=null; } }
    tri(ctx,v,col,clip) {
      if(v.some(p=>p.some(x=>!Number.isFinite(x))||p[2]<=0))return;
      const [a,b,c]=v, area=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
      if(Math.abs(area)<0.001)return;
      if(!this.img)this.img=ctx.getImageData(0,0,this.w,this.h);
      const d=this.img.data;
      const x0=Math.max(0,clip[0],Math.floor(Math.min(a[0],b[0],c[0]))),
        x1=Math.min(this.w,clip[2],Math.ceil(Math.max(a[0],b[0],c[0]))),
        y0=Math.max(0,clip[1],Math.floor(Math.min(a[1],b[1],c[1]))),
        y1=Math.min(this.h,clip[3],Math.ceil(Math.max(a[1],b[1],c[1])));
      for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++) {
        const xx=x+.5,yy=y+.5,u=((b[0]-xx)*(c[1]-yy)-(b[1]-yy)*(c[0]-xx))/area,
          t=((c[0]-xx)*(a[1]-yy)-(c[1]-yy)*(a[0]-xx))/area,w=1-u-t;
        if(u<0||t<0||w<0)continue;
        const z=Math.max(1,Math.min(65535,Math.round((u*a[2]+t*b[2]+w*c[2])*65535))),i=y*this.w+x;
        if(z<this.z[i])continue;
        this.z[i]=z;
        const alpha=(col>>>24)/255;
        for(let k=0;k<3;k++)d[i*4+k]=((col>>>(k*8))&255)*alpha+d[i*4+k]*(1-alpha);
        d[i*4+3]=255;
      }
    }
  }
  // DEPTH RASTER END
  const depthRaster=new DepthRaster(SCR_W,SCR_H);

  /* ---- Fengari helpers ---- */
  function arg(i) { return lua.lua_tonumber(Sim.L, i); }
  function iarg(i) { return Math.trunc(lua.lua_tonumber(Sim.L, i)); }
  function optnum(i, d) { return lua.lua_isnoneornil(Sim.L, i) ? d : lua.lua_tonumber(Sim.L, i); }
  function sarg(i) { return jstr(lauxlib.luaL_checkstring(Sim.L, i)); }
  function reg(tbl, name, fn) { lua.lua_pushcfunction(Sim.L, (name === 'tridepth' || name === 'discdepth') ? fn : (...args) => { depthRaster.flush(Sim.ctx);return fn(...args); }); lua.lua_setfield(Sim.L, tbl, to_luastring(name)); }

  /* ---- audio ---- */
  function ensureAudio() { if (!Sim.audio) { try { Sim.audio = new (global.AudioContext || global.webkitAudioContext)(); } catch (e) { } } if (Sim.audio && Sim.audio.state === 'suspended') Sim.audio.resume(); }
  function noiseBuffer(ac, sec) { const n = Math.ceil(sec * ac.sampleRate), buf = ac.createBuffer(1, n, ac.sampleRate), d = buf.getChannelData(0); for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1; return buf; }
  function tone(freq, ms, wave, vol, freq2) {
    ensureAudio(); const ac = Sim.audio; if (!ac) return;
    freq = Math.max(20, Math.min(8000, freq)); ms = Math.max(10, Math.min(700, ms));
    freq2 = freq2 > 0 ? Math.max(20, Math.min(8000, freq2)) : freq;
    vol = Math.max(0, Math.min(100, vol)); const now = ac.currentTime, dur = ms / 1000;
    const g = ac.createGain(), peak = (vol / 100) * 0.25;
    g.gain.setValueAtTime(0, now); g.gain.linearRampToValueAtTime(peak, now + 0.0045); g.gain.linearRampToValueAtTime(0, now + dur);
    g.connect(ac.destination);
    let src;
    if (wave === 3) { src = ac.createBufferSource(); src.buffer = noiseBuffer(ac, dur); }
    else { src = ac.createOscillator(); src.type = wave === 1 ? 'sine' : wave === 2 ? 'triangle' : wave === 4 ? 'sawtooth' : 'square'; src.frequency.setValueAtTime(freq, now); if (freq2 !== freq) src.frequency.linearRampToValueAtTime(freq2, now + dur); }
    src.connect(g); src.start(now); src.stop(now + dur + 0.02);
  }
  function playBuffer(buf) { ensureAudio(); const ac = Sim.audio; if (!ac || !buf) return; const s = ac.createBufferSource(); const g = ac.createGain(); g.gain.value = 0.6; s.buffer = buf; s.connect(g); g.connect(ac.destination); s.start(); }

  /* ---- region clip helpers ---- */
  function setMode(m) { if (!MODES[m]) m = 'full'; Sim.mode = m; const r = MODES[m]; Sim.ox = r[0]; Sim.oy = r[1]; Sim.ow = r[2]; Sim.oh = r[3]; }

  /* ---- the kom table ---- */
  function buildKom() {
    const L = Sim.L, ctx = Sim.ctx;
    lua.lua_newtable(L); const T = lua.lua_gettop(L);
    reg(T, 'clear', () => { ctx.fillStyle = css(arg(1) >>> 0); ctx.fillRect(0, 0, Sim.ow, Sim.oh); return 0; });
    reg(T, 'rect', () => { ctx.fillStyle = css(iarg(5) >>> 0); ctx.fillRect(iarg(1), iarg(2), iarg(3), iarg(4)); return 0; });
    reg(T, 'frame', () => { const x = iarg(1), y = iarg(2), w = iarg(3), h = iarg(4); ctx.fillStyle = css(iarg(5) >>> 0); ctx.fillRect(x, y, w, 1); ctx.fillRect(x, y + h - 1, w, 1); ctx.fillRect(x, y, 1, h); ctx.fillRect(x + w - 1, y, 1, h); return 0; });
    reg(T, 'pset', () => { ctx.fillStyle = css(iarg(3) >>> 0); ctx.fillRect(iarg(1), iarg(2), 1, 1); return 0; });
    reg(T, 'line', () => { ctx.strokeStyle = css(iarg(5) >>> 0); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(iarg(1) + 0.5, iarg(2) + 0.5); ctx.lineTo(iarg(3) + 0.5, iarg(4) + 0.5); ctx.stroke(); return 0; });
    reg(T, 'tri', () => { ctx.fillStyle = css(iarg(7) >>> 0); ctx.beginPath(); ctx.moveTo(iarg(1), iarg(2)); ctx.lineTo(iarg(3), iarg(4)); ctx.lineTo(iarg(5), iarg(6)); ctx.closePath(); ctx.fill(); return 0; });
    reg(T, 'tridepth', () => {
      const near=optnum(11,.35),v=[];if(!(near>0))return 0;
      for(let i=1;i<=7;i+=3){const z=arg(i+2);if(z<near)return 0;v.push([arg(i)+Sim.ox,arg(i+1)+Sim.oy,near/z]);}
      depthRaster.tri(ctx,v,iarg(10)>>>0,[Sim.ox,Sim.oy,Sim.ox+Sim.ow,Sim.oy+Sim.oh]);return 0;
    });
    reg(T,'discdepth',()=>{
      const x=arg(1)+Sim.ox,y=arg(2)+Sim.oy,r=arg(3),z=arg(4),c=iarg(5)>>>0,n=optnum(6,.35);
      if(![x,y,r,z,n].every(Number.isFinite)||r<=0||n<=0||z<n)return 0;
      for(let i=0;i<32;i++){const a=i*Math.PI/16,b=(i+1)*Math.PI/16,q=n/z;
        depthRaster.tri(ctx,[[x,y,q],[x+Math.cos(a)*r,y+Math.sin(a)*r,q],[x+Math.cos(b)*r,y+Math.sin(b)*r,q]],c,[Sim.ox,Sim.oy,Sim.ox+Sim.ow,Sim.oy+Sim.oh]);}
      return 0;
    });
    reg(T, 'circle', () => { ctx.fillStyle = css(iarg(4) >>> 0); ctx.beginPath(); ctx.arc(iarg(1), iarg(2), Math.abs(iarg(3)), 0, 6.2832); ctx.fill(); return 0; });
    reg(T, 'text', () => { fontDraw(ctx, iarg(1), iarg(2), Math.max(1, Math.trunc(optnum(5, 1))), css(iarg(4) >>> 0), sarg(3)); return 0; });
    reg(T, 'textw', () => { lua.lua_pushinteger(L, fontWidth(sarg(1), Math.max(1, Math.trunc(optnum(2, 1))))); return 1; });
    reg(T, 'rgb', () => { lua.lua_pushnumber(L, pack(clampB(iarg(1)), clampB(iarg(2)), clampB(iarg(3))) + PSP32_EPS); return 1; });
    reg(T, 'btn', () => { lua.lua_pushboolean(L, Sim.held.has(sarg(1)) ? 1 : 0); return 1; });
    reg(T, 'btnp', () => { lua.lua_pushboolean(L, Sim.pressed.has(sarg(1)) ? 1 : 0); return 1; });
    reg(T, 'analog', () => { lua.lua_pushinteger(L, Sim.analogX); lua.lua_pushinteger(L, Sim.analogY); return 2; });
    reg(T, 'time', () => { lua.lua_pushnumber(L, (performance.now() - Sim.t0) / 1000); return 1; });
    reg(T, 'sfx', () => { const id = Math.trunc(optnum(1, 0)); const f = [880, 1100, 660, 440, 1320, 220, 990][id < 0 ? 0 : id > 6 ? 6 : id]; tone(f, 60, id === 5 ? 3 : 0, 35); return 0; });
    reg(T, 'tone', () => { tone(arg(1), arg(2), Math.trunc(optnum(3, 0)), Math.trunc(optnum(4, 80)), Math.trunc(optnum(5, 0))); return 0; });
    // sprites
    reg(T, 'sprite', () => {
      const x = iarg(1), y = iarg(2), scale = Math.max(1, iarg(3)), data = sarg(4); const pal = [];
      lauxlib.luaL_checktype(L, 5, lua.LUA_TTABLE);
      for (let i = 1; i <= 16; i++) { lua.lua_rawgeti(L, 5, i); if (lua.lua_isnil(L, -1)) { lua.lua_pop(L, 1); break; } pal.push(css(lua.lua_tonumber(L, -1) >>> 0)); lua.lua_pop(L, 1); }
      let col = 0, row = 0;
      for (let i = 0; i < data.length; i++) { const c = data[i];
        if (c === '\n') { row++; col = 0; continue; }
        if (c !== ' ' && c !== '.' && c !== '0') { let idx = -1; if (c >= '1' && c <= '9') idx = c.charCodeAt(0) - 49; else if (c >= 'a' && c <= 'f') idx = c.charCodeAt(0) - 97 + 9; else if (c >= 'A' && c <= 'F') idx = c.charCodeAt(0) - 65 + 9; if (idx >= 0 && idx < pal.length) { ctx.fillStyle = pal[idx]; ctx.fillRect(x + col * scale, y + row * scale, scale, scale); } }
        col++;
      }
      return 0;
    });
    // images
    reg(T, 'image', () => { lua.lua_pushinteger(L, imageFromName(sarg(1))); return 1; });
    reg(T, 'imageb64', () => { lua.lua_pushinteger(L, imageFromB64(sarg(1))); return 1; });
    reg(T, 'imgdraw', () => { const h = iarg(1); const im = Sim.images[h - 1]; if (im && im.cv) { const w = Math.trunc(optnum(4, 0)) || im.w, hh = Math.trunc(optnum(5, 0)) || im.h; ctx.drawImage(im.cv, iarg(2), iarg(3), w, hh); } return 0; });
    reg(T, 'imgw', () => { const im = Sim.images[iarg(1) - 1]; lua.lua_pushinteger(L, im && Number.isFinite(im.w) ? im.w : 0); return 1; });
    reg(T, 'imgh', () => { const im = Sim.images[iarg(1) - 1]; lua.lua_pushinteger(L, im && Number.isFinite(im.h) ? im.h : 0); return 1; });
    // sound
    reg(T, 'sound', () => { lua.lua_pushinteger(L, soundFromName(sarg(1))); return 1; });
    reg(T, 'soundb64', () => { lua.lua_pushinteger(L, soundFromB64(sarg(1))); return 1; });
    reg(T, 'play', () => { const s = Sim.sounds[iarg(1) - 1]; if (s && s.buf) playBuffer(s.buf); return 0; });
    // fonts
    reg(T, 'font', () => 0);   // built-in face switching dropped on PSP too
    reg(T, 'loadfont', () => { lua.lua_pushinteger(L, fontDefine(imageFromName(sarg(1)), iarg(2), iarg(3), firstArg(4), Math.trunc(optnum(5, 0)))); return 1; });
    reg(T, 'loadfontb64', () => { lua.lua_pushinteger(L, fontDefine(imageFromB64(sarg(1)), iarg(2), iarg(3), firstArg(4), Math.trunc(optnum(5, 0)))); return 1; });
    reg(T, 'bmtext', () => { bmtext(iarg(1), iarg(2), iarg(3), sarg(4), Math.max(1, Math.trunc(optnum(5, 1))), (optnum(6, 0xFFFFFFFF)) >>> 0); return 0; });
    reg(T, 'bmtextw', () => { const f = Sim.fonts[iarg(1) - 1]; lua.lua_pushinteger(L, f ? sarg(2).length * f.cw * Math.max(1, Math.trunc(optnum(3, 1))) : 0); return 1; });
    // storage
    reg(T, 'save', () => { try { localStorage.setItem('komapp_' + Sim.appId, sarg(1)); lua.lua_pushboolean(L, 1); } catch (e) { lua.lua_pushboolean(L, 0); } return 1; });
    reg(T, 'load', () => { const v = localStorage.getItem('komapp_' + Sim.appId); if (v === null) lua.lua_pushnil(L); else lua.lua_pushstring(L, to_luastring(v)); return 1; });
    // kom.menu(on) / kom.snap(): both are registered in app_lua.c and both were
    // MISSING here, so every app obeying SDK rule 19 — call kom.menu every frame
    // from the top of update — died on frame 0 with
    //     attempt to call a nil value (field 'menu')
    // A simulator gap that reads exactly like an app bug, and it meant this tool
    // could only run apps that BROKE the rule the SDK insists on. Same fault was
    // found and fixed in headless.js long ago; the browser side never got it.
    // No-arg means true, matching lb_menu's lua_isnone check.
    reg(T, 'menu', () => { Sim.menuMode = lua.lua_isnone(L, 1) ? true : !!lua.lua_toboolean(L, 1); return 0; });
    reg(T, 'snap', () => { lua.lua_pushboolean(L, 1); return 1; });
    // constants
    lua.lua_pushinteger(L, Sim.ow); lua.lua_setfield(L, T, to_luastring('W'));
    lua.lua_pushinteger(L, Sim.oh); lua.lua_setfield(L, T, to_luastring('H'));
    lua.lua_newtable(L); const C = lua.lua_gettop(L);
    for (const k of ['bg', 'accent', 'hi', 'dark', 'text', 'grey']) { lua.lua_pushnumber(L, COL[k] + PSP32_EPS); lua.lua_setfield(L, C, to_luastring(k)); }
    lua.lua_setfield(L, T, to_luastring('col'));
    lua.lua_setglobal(L, to_luastring('kom'));
  }
  function firstArg(i) { if (lua.lua_isstring(Sim.L, i) && !lua.lua_isnumber(Sim.L, i)) { const s = sarg(i); return s.length ? s.charCodeAt(0) : 32; } return Math.trunc(optnum(i, 32)); }

  /* ---- image / sound / font helpers (sidecars are pre-decoded before start) ---- */
  function capCanvas(img) { let w = img.naturalWidth || img.width || 1, h = img.naturalHeight || img.height || 1; let tw = w, th = h; if (tw > 256 || th > 256) { const mx = Math.max(tw, th); tw = Math.max(1, Math.round(tw * 256 / mx)); th = Math.max(1, Math.round(th * 256 / mx)); } const cv = document.createElement('canvas'); cv.width = tw; cv.height = th; cv.getContext('2d').drawImage(img, 0, 0, tw, th); return { cv, w: tw, h: th }; }
  function imageFromName(name) { const pre = Sim.fs['_img_' + name]; if (pre) { Sim.images.push(pre); return Sim.images.length; } return 0; }
  function imageFromB64(b64) { const rec = { cv: null, w: 0, h: 0 }; Sim.images.push(rec); const handle = Sim.images.length; const img = new Image(); img.onload = () => { const c = capCanvas(img); rec.cv = c.cv; rec.w = c.w; rec.h = c.h; }; img.src = guessDataUrl(b64, 'image/png'); return handle; }
  function soundFromName(name) { const pre = Sim.fs['_snd_' + name]; if (pre) { Sim.sounds.push(pre); return Sim.sounds.length; } return 0; }
  function soundFromB64(b64) { const rec = { buf: null }; Sim.sounds.push(rec); const handle = Sim.sounds.length; ensureAudio(); if (Sim.audio) { const ab = b64ToArrayBuffer(b64); Sim.audio.decodeAudioData(ab, (buf) => rec.buf = buf, () => { }); } return handle; }
  function fontDefine(imgHandle, cw, ch, first, cols) { const im = Sim.images[imgHandle - 1]; if (!im || !im.cv || cw < 1 || ch < 1) return 0; if (cols <= 0) cols = Math.floor(im.w / cw); if (cols < 1) cols = 1; Sim.fonts.push({ im, cw, ch, first, cols, tint: {} }); return Sim.fonts.length; }
  function bmtext(fh, x, y, str, scale, col) {
    const f = Sim.fonts[fh - 1]; if (!f || !f.im.cv) return; const ctx = Sim.ctx;
    let atlas = f.im.cv;
    if ((col >>> 0) !== 0xFFFFFFFF) { const key = '' + (col >>> 0); if (!f.tint[key]) { const c = document.createElement('canvas'); c.width = f.im.w; c.height = f.im.h; const g = c.getContext('2d'); g.drawImage(f.im.cv, 0, 0); g.globalCompositeOperation = 'source-in'; g.fillStyle = css(col); g.fillRect(0, 0, c.width, c.height); f.tint[key] = c; } atlas = f.tint[key]; }
    let cx = x;
    for (let i = 0; i < str.length; i++) { const idx = str.charCodeAt(i) - f.first; if (idx >= 0) { const gx = (idx % f.cols) * f.cw, gy = Math.floor(idx / f.cols) * f.ch; if (gx + f.cw <= f.im.w && gy + f.ch <= f.im.h) ctx.drawImage(atlas, gx, gy, f.cw, f.ch, cx, y, f.cw * scale, f.ch * scale); } cx += f.cw * scale; }
  }
  function guessDataUrl(b64, mime) { return b64.indexOf('data:') === 0 ? b64 : 'data:' + mime + ';base64,' + b64.replace(/\s+/g, ''); }
  function b64ToArrayBuffer(b64) { const clean = b64.replace(/^data:[^,]+,/, '').replace(/\s+/g, ''); const bin = atob(clean); const len = bin.length; const u8 = new Uint8Array(len); for (let i = 0; i < len; i++) u8[i] = bin.charCodeAt(i); return u8.buffer; }

  /* ---- input polling ---- */
  function poll() {
    const cur = new Set(Sim.kbHeld);
    Sim.analogX = 0; Sim.analogY = 0;
    // KEYBOARD ANALOG FALLBACK (IJKL). Without this the stick reads dead-centre on
    // any machine with no gamepad plugged in, so a game that AIMS with the analog
    // stick simply cannot be tested here -- it looks like the aim is broken when
    // really there was never any input. Diagonals are normalised to ~127 so a
    // two-key press is not sqrt(2) faster than a one-key press.
    let kx = (Sim.anKeys.has('KeyL') ? 1 : 0) - (Sim.anKeys.has('KeyJ') ? 1 : 0);
    let ky = (Sim.anKeys.has('KeyK') ? 1 : 0) - (Sim.anKeys.has('KeyI') ? 1 : 0);
    if (kx || ky) {
      const m = Math.sqrt(kx * kx + ky * ky);
      Sim.analogX = Math.round((kx / m) * 127);
      Sim.analogY = Math.round((ky / m) * 127);
    }
    if (Sim.useGamepad && navigator.getGamepads) {
      const gps = navigator.getGamepads();
      for (const gp of gps) { if (!gp) continue;
        for (let i = 0; i < gp.buttons.length; i++) if (gp.buttons[i] && gp.buttons[i].pressed && PADMAP[i]) cur.add(PADMAP[i]);
        if (gp.axes.length >= 2) { const ax = gp.axes[0], ay = gp.axes[1]; if (Math.abs(ax) > 0.15) Sim.analogX = Math.round(ax * 127); if (Math.abs(ay) > 0.15) Sim.analogY = Math.round(ay * 127); }
        if (gp.buttons[16] && gp.buttons[16].pressed) cur.add('HOME');
        break;
      }
    }
    Sim.pressed = new Set(); for (const n of cur) if (!Sim.prev.has(n)) Sim.pressed.add(n);
    Sim.held = cur; Sim.prev = new Set(cur);
    if (cur.has('HOME')) Sim.stop('HOME pressed');
  }

  /* ---- Lua call helpers ---- */
  function callGlobal(name, nargs) {
    const L = Sim.L; lua.lua_getglobal(L, to_luastring(name));
    if (!lua.lua_isfunction(L, -1)) { lua.lua_pop(L, 1 + nargs); return; }
    if (nargs) lua.lua_insert(L, -1 - nargs);
    if (lua.lua_pcall(L, nargs, 0, 0) !== lua.LUA_OK) { Sim.err = jstr(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); Sim.alive = false; }
  }

  function frame(now) {
    Sim.raf = requestAnimationFrame(frame);
    Sim.frameN++;
    poll();
    let dt = Sim.last ? (now - Sim.last) / 1000 : 1 / 60; Sim.last = now; if (dt > 0.05) dt = 0.05;
    // CRT flicker advances by wall-clock (120 px/s = PSP's 2px/frame @60fps) so it matches
    // the device regardless of the monitor's refresh rate.
    Sim.crtPhase = (Sim.crtPhase + dt * 120) % (SCR_H + 80);
    const ctx = Sim.ctx;
    if (!Sim.running) { ctx.setTransform(1, 0, 0, 1, 0, 0); if (Sim.crt) drawCrt(); return; }
    if (Sim.alive) { lua.lua_pushnumber(Sim.L, dt); callGlobal('update', 1); }
    // backdrop
    ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = '#000'; ctx.fillRect(0, 0, SCR_W, SCR_H);
    if (Sim.mode === 'inset') drawChrome();                     // PSP top/tab/bottom bars frame the inset app
    if (Sim.mode === 'window') { ctx.fillStyle = css(COL.dark); ctx.globalAlpha = 0.5; ctx.fillRect(0, 0, SCR_W, SCR_H); ctx.globalAlpha = 1; ctx.strokeStyle = css(COL.dim); ctx.strokeRect(Sim.ox - 0.5, Sim.oy - 0.5, Sim.ow + 1, Sim.oh + 1); }
    ctx.save(); ctx.beginPath(); ctx.rect(Sim.ox, Sim.oy, Sim.ow, Sim.oh); ctx.clip(); ctx.translate(Sim.ox, Sim.oy);
    ctx.fillStyle = css(COL.bg); ctx.fillRect(0, 0, Sim.ow, Sim.oh);   // host pre-clear to theme bg
    depthRaster.reset();
    if (Sim.alive) callGlobal('draw', 0);
    depthRaster.flush(ctx);
    ctx.restore();
    if (Sim.mode === 'inset') drawChromeBottom();               // now-playing strip draws over the app, like the PSP
    if (!Sim.alive && Sim.err) drawError();
    if (Sim.crt) drawCrt();   // CRT overlays everything, like themeOverlay() on the PSP
  }

  /* PSP chrome preview (theme.c themeStatusBar + themeTabBar) — only shown in INSET,
   * exactly as on the device (FULL/WINDOW suppress chrome). Themed via COL so it
   * re-tints with the theme picker. */
  const CHROME_TABS = ['GAMES', 'AUDIO', 'IMAGES', 'FILES', 'VIDEO', 'READER', 'VAULT', 'EXTRAS'];
  function two(n) { return (n < 10 ? '0' : '') + n; }
  function drawChrome() {
    const ctx = Sim.ctx; ctx.setTransform(1, 0, 0, 1, 0, 0);
    // top status bar (0..16) + dim underline
    ctx.fillStyle = 'rgba(0,0,0,0.90)'; ctx.fillRect(0, 0, SCR_W, 16);
    ctx.fillStyle = css(COL.dim); ctx.fillRect(0, 16, SCR_W, 1);
    fontDraw(ctx, 8, 5, 1, css(COL.accent), 'KOMSTATION');
    fontDraw(ctx, 74, 5, 1, css(COL.dim), 'OS');
    // clock (rightmost) + battery icon
    const d = new Date(); let h = d.getHours(), ap = '';
    if (Sim.clock12) { ap = h >= 12 ? 'PM' : 'AM'; h = h % 12; if (h === 0) h = 12; }
    const ts = two(h) + ':' + two(d.getMinutes()) + (ap ? ap : '');
    const tw = fontWidth(ts, 1); fontDraw(ctx, SCR_W - 8 - tw, 5, 1, css(COL.text), ts);
    const bx = SCR_W - 8 - tw - 8 - 24;
    ctx.strokeStyle = css(COL.dim); ctx.lineWidth = 1; ctx.strokeRect(bx + 0.5, 5.5, 22, 7);
    ctx.fillStyle = css(COL.dim); ctx.fillRect(bx + 22, 7, 2, 4);
    ctx.fillStyle = css(COL.accent); ctx.fillRect(bx + 2, 7, 16, 4);
    // tab bar row (16..44): EXTRAS highlighted with an underline
    let tx = 10; const ty = 24;
    for (const t of CHROME_TABS) {
      const on = t === 'EXTRAS';
      fontDraw(ctx, tx, ty, 1, on ? css(COL.hi) : css(COL.dim), t);
      if (on) { ctx.fillStyle = css(COL.accent); ctx.fillRect(tx, ty + 9, fontWidth(t, 1), 1); }
      tx += fontWidth(t, 1) + 7;
    }
  }
  function drawChromeBottom() {
    const ctx = Sim.ctx; ctx.setTransform(1, 0, 0, 1, 0, 0);
    fontDraw(ctx, 8, SCR_H - 10, 1, css(COL.dim), 'EXTRAS');          // now-playing strip stand-in
    const hint = 'X RUN   O HOME';
    fontDraw(ctx, SCR_W - 8 - fontWidth(hint, 1), SCR_H - 10, 1, css(COL.dim), hint);
  }

  /* CRT overlay — mirrors theme.c themeOverlay() (CRT_FULL): every-other-row scanlines
   * (black @ alpha 56), a top+bottom vignette (black 90->0 over 26px), and a faint
   * accent-tinted flicker band rolling down the screen. */
  function drawCrt() {
    const ctx = Sim.ctx; ctx.setTransform(1, 0, 0, 1, 0, 0);
    if (!Sim._scan) {
      const p = document.createElement('canvas'); p.width = 1; p.height = 2;
      const g = p.getContext('2d'); g.fillStyle = 'rgba(0,0,0,' + (56 / 255) + ')'; g.fillRect(0, 1, 1, 1);
      Sim._scan = ctx.createPattern(p, 'repeat');
    }
    ctx.fillStyle = Sim._scan; ctx.fillRect(0, 0, SCR_W, SCR_H);
    let gr = ctx.createLinearGradient(0, 0, 0, 26);
    gr.addColorStop(0, 'rgba(0,0,0,' + (90 / 255) + ')'); gr.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, SCR_W, 26);
    gr = ctx.createLinearGradient(0, SCR_H - 26, 0, SCR_H);
    gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,' + (90 / 255) + ')');
    ctx.fillStyle = gr; ctx.fillRect(0, SCR_H - 26, SCR_W, 26);
    const yy = (Sim.crtPhase % (SCR_H + 80)) - 40;
    const hi = COL.hi >>> 0, r = hi & 255, g2 = (hi >> 8) & 255, b2 = (hi >> 16) & 255;
    gr = ctx.createLinearGradient(0, yy, 0, yy + 40);
    gr.addColorStop(0, `rgba(${r},${g2},${b2},0)`); gr.addColorStop(1, `rgba(${r},${g2},${b2},0.03)`);
    ctx.fillStyle = gr; ctx.fillRect(0, yy, SCR_W, 40);
  }
  function drawError() {
    const ctx = Sim.ctx; ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = 'rgba(0,0,0,0.85)'; ctx.fillRect(0, 0, SCR_W, SCR_H);
    fontDraw(ctx, 140, 30, 2, css(COL.accent), 'APP ERROR');
    const m = Sim.err.toUpperCase().replace(/[a-z]/g, c => c); const words = m.split(' '); let line = '', y = 70;
    for (const w of words) { if (fontWidth(line + ' ' + w, 1) > 460) { fontDraw(ctx, 12, y, 1, css(COL.text), line); line = w; y += 12; } else line = line ? line + ' ' + w : w; }
    fontDraw(ctx, 12, y, 1, css(COL.text), line);
    fontDraw(ctx, 12, SCR_H - 16, 1, css(COL.grey), 'FIX THE SCRIPT AND PRESS RESTART');
  }

  /* ---- public API ---- */
  Sim.init = function (canvas) {
    Sim.canvas = canvas; Sim.ctx = canvas.getContext('2d'); Sim.ctx.imageSmoothingEnabled = false;
    const ANALOG_KEYS = { KeyI: 1, KeyJ: 1, KeyK: 1, KeyL: 1 };   // stick, see poll()
    window.addEventListener('keydown', e => { if (e.code === 'Escape') { Sim.stop('HOME'); return; } if (ANALOG_KEYS[e.code]) { Sim.anKeys.add(e.code); e.preventDefault(); } const n = KEYMAP[e.code]; if (n) { Sim.kbHeld.add(n); e.preventDefault(); } ensureAudio(); });
    window.addEventListener('keyup', e => { if (ANALOG_KEYS[e.code]) Sim.anKeys.delete(e.code); const n = KEYMAP[e.code]; if (n) Sim.kbHeld.delete(n); });
    window.addEventListener('blur', () => { Sim.kbHeld.clear(); Sim.anKeys.clear(); });   // no keys stuck down on tab-out
    Sim.raf = requestAnimationFrame(frame);
  };
  Sim.setGamepad = function (on) { Sim.useGamepad = on; };
  // live theme: re-derive the palette from a base accent (chrome updates instantly; the
  // running app's kom.col is snapshotted, so the UI re-runs the app to apply it fully).
  Sim.setTheme = function (r, g, b) { deriveTheme(r, g, b); };
  // push the current palette into a RUNNING app's kom.col table so a theme change applies
  // live (no restart). Host chrome already reads COL each frame; this updates the Lua side.
  Sim.refreshThemeColors = function () {
    const L = Sim.L; if (!L || !Sim.running) return;
    lua.lua_getglobal(L, to_luastring('kom'));
    if (lua.lua_istable(L, -1)) {
      lua.lua_getfield(L, -1, to_luastring('col'));
      if (lua.lua_istable(L, -1)) {
        for (const k of ['bg', 'accent', 'hi', 'dark', 'text', 'grey']) { lua.lua_pushnumber(L, COL[k]); lua.lua_setfield(L, -2, to_luastring(k)); }
      }
      lua.lua_pop(L, 1);
    }
    lua.lua_pop(L, 1);
  };
  Sim.theme = function () { return { base: BASE.slice(), accent: css(COL.accent), bg: css(COL.bg), hi: css(COL.hi), text: css(COL.text), dark: css(COL.dark) }; };
  Sim.setCrt = function (on) { Sim.crt = !!on; };
  Sim.setClock12 = function (on) { Sim.clock12 = !!on; };
  // button remapping: bc = { UP:'ArrowUp', X:'KeyZ', ... } (PSP button -> KeyboardEvent.code)
  Sim.setKeymap = function (bc) { g_keymapBC = Object.assign({}, DEFAULT_KEYS, bc || {}); rebuildKeymap(g_keymapBC); };
  Sim.getKeymap = function () { return Object.assign({}, g_keymapBC); };
  Sim.defaultKeymap = function () { return Object.assign({}, DEFAULT_KEYS); };

  let runSerial = 0;
  // load + run an app. fs = { filename: {kind:'image'|'sound'|'text', dataUrl/arrayBuffer/text} }
  Sim.run = async function (code, opts) {
    Sim.stop(''); Sim.err = '';
    const ticket = runSerial;
    opts = opts || {}; Sim.appId = opts.id || 'app';
    setMode(opts.mode || parseDisplay(code) || 'full');
    Sim.images = []; Sim.sounds = []; Sim.fonts = []; Sim.fs = {};
    ensureAudio();
    const decoded = await predecode(opts.fs || {});
    if (ticket !== runSerial) return;
    Sim.fs = decoded;
    // fresh Lua state, sandboxed to base/math/string/table
    Sim.L = lauxlib.luaL_newstate();
    const L = Sim.L;
    lauxlib.luaL_requiref(L, to_luastring('_G'), lualib.luaopen_base, 1); lua.lua_pop(L, 1);
    lauxlib.luaL_requiref(L, to_luastring('math'), lualib.luaopen_math, 1); lua.lua_pop(L, 1);
    lauxlib.luaL_requiref(L, to_luastring('string'), lualib.luaopen_string, 1); lua.lua_pop(L, 1);
    lauxlib.luaL_requiref(L, to_luastring('table'), lualib.luaopen_table, 1); lua.lua_pop(L, 1);
    // strip dangerous globals (mirrors app_lua.c stripGlobals) — also stops a missing
    // app load()/update()/draw() from resolving to the base library's load() etc.
    for (const g of ['dofile', 'loadfile', 'load', 'require', 'collectgarbage', 'print', 'rawset', 'rawget', 'getmetatable', 'setmetatable']) { lua.lua_pushnil(L); lua.lua_setglobal(L, to_luastring(g)); }
    buildKom();
    // Each run owns its source snapshot and cache; no asynchronous disk access
    // from Lua and no cache shared with a previous app.
    const sources = Object.fromEntries(Object.entries(opts.fs || {}).map(([name,f])=>[name,{text:f.text}]));
    const moduleLoader = `
      local source = ...
      local cache, loading = {}, {}
      return function(name)
        if type(name) ~= 'string' or #name == 0 or #name > 95 or
           not name:match('^[%a_][%w_%.]*$') or name:find('%.%.') or
           name:sub(-1) == '.' then error('INVALID MODULE NAME') end
        for part in name:gmatch('[^.]+') do
          if not part:match('^[%a_][%w_]*$') then error('INVALID MODULE NAME') end
        end
        if cache[name] ~= nil then return cache[name] end
        if loading[name] then error('CYCLIC MODULE: '..name) end
        local chunk = source(name:gsub('%.','/')..'.lua')
        loading[name] = true
        local ok, value = pcall(chunk, name)
        loading[name] = nil
        if not ok then error(value) end
        if value == nil then value = true end
        cache[name] = value
        return value
      end`;
    lauxlib.luaL_loadstring(L, to_luastring(moduleLoader));
    lua.lua_pushjsfunction(L, S => {
      const name = jstr(lauxlib.luaL_checkstring(S, 1));
      const file = Object.prototype.hasOwnProperty.call(sources, name) && sources[name];
      if (!file || typeof file.text !== 'string') return lauxlib.luaL_error(S, to_luastring('MODULE NOT FOUND: ' + name));
      const bytes = to_luastring(file.text);
      if (lauxlib.luaL_loadbufferx(S, bytes, bytes.length, to_luastring('@' + name), to_luastring('t')) !== lua.LUA_OK) return lua.lua_error(S);
      return 1;
    });
    if (lua.lua_pcall(L, 1, 1, 0) !== lua.LUA_OK) throw Error(jstr(lua.lua_tostring(L, -1)));
    lua.lua_setglobal(L, to_luastring('require'));
    Sim.t0 = performance.now();
    if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK) { Sim.err = jstr(lua.lua_tostring(L, -1)); Sim.alive = false; Sim.running = true; return; }
    if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) { Sim.err = jstr(lua.lua_tostring(L, -1)); Sim.alive = false; Sim.running = true; return; }
    Sim.alive = true; Sim.running = true; Sim.last = 0;
    callGlobal('load', 0);
    if (Sim.onStop) Sim.onStop(null);
  };
  Sim.stop = function (reason) { runSerial++; Sim.running = false; Sim.alive = false; if(Sim.L)lua.lua_close(Sim.L); Sim.L = null; if (reason && Sim.onStop) Sim.onStop(reason); };

  function parseDisplay(code) { const m = code.match(/@display\s+(\w+)/); return m ? m[1].toLowerCase() : null; }

  async function predecode(fs) {
    const jobs = [];
    const result = {};
    for (const name in fs) {
      const f = fs[name]; const low = name.toLowerCase();
      if (/\.(png|jpg|jpeg|bmp|gif)$/.test(low)) jobs.push(new Promise(res => { const img = new Image(); img.onload = () => { result['_img_' + name] = capCanvas(img); res(); }; img.onerror = res; img.src = f.dataUrl; }));
      else if (/\.wav$/.test(low)) jobs.push(fetch(f.dataUrl).then(r => r.arrayBuffer()).then(ab => new Promise(res => { if (!Sim.audio) { res(); return; } Sim.audio.decodeAudioData(ab, buf => { result['_snd_' + name] = { buf }; res(); }, res); })).catch(() => { }));
    }
    await Promise.all(jobs);
    return result;
  }

  global.KomSim = Sim;
})(window);
