-- @name TALLY
-- @display fullscreen
-- Tally counter, up to 8 units. Design: docs/design/TALLY-UPGRADES.html
-- (rounds 1-6, 2026-10-25).
--
--   ONE UNIT   your ADD / SUBTRACT buttons count (X / SQUARE by default)
--              SELECT overview, TRIANGLE unit menu, START app menu
--   OVERVIEW   D-pad moves, X adds, SQUARE subtracts (the bindings are set
--              aside here), SELECT opens the unit, TRIANGLE / START as above
--
-- Everything is saved one second after the last change and again on exit,
-- never while nothing has changed.
--
-- DRAW BUDGET (APP_SDK perf rules): <=400 kom calls and <=600 GE draws a
-- frame. Every segment is drawn ONCE, lit or ghost, never ghost-then-lit; the
-- big digits keep V1's hex ends (rect + 2 tris), the overview's small digits
-- are plain bars (the 1-2 px tips cost 3x the draws). A sprite costs one GE
-- draw per row run, so a sprite digit was 260 draws and the stripes 550:
-- measured with simulator/_drawprof.js and abandoned.

local MAXN = 999999
local NDIG = 6
local DIMK = 0.28            -- the band behind a modal, redrawn darker (no alpha)

-- ---- schemes: main colour, unlit ghost, dim, background ------------------
local SCH = {
  { name = "ORANGE",    fg = {255,112,0},   gh = {44,18,4},  dm = {120,52,6},  bg = {10,7,6} },
  { name = "UNIT-01",   fg = {132,255,64},  gh = {20,40,12}, dm = {60,100,36}, bg = {9,6,14} },
  { name = "NEON LIME", fg = {166,232,0},   gh = {24,36,2},  dm = {74,106,4},  bg = {6,8,3} },
  { name = "CYAN",      fg = {0,212,255},   gh = {2,30,40},  dm = {8,88,108},  bg = {3,7,10} },
  { name = "RED",       fg = {255,46,38},   gh = {42,8,6},   dm = {118,24,20}, bg = {10,4,4} },
  { name = "MAGENTA",   fg = {255,50,190},  gh = {40,6,30},  dm = {115,24,88}, bg = {9,4,8} },
  { name = "ICE",       fg = {200,236,255}, gh = {24,30,38}, dm = {78,98,118}, bg = {5,7,10} },
}
local DEF_SCH = { 1, 4, 5, 3, 6, 2, 7, 1 }   -- new unit i starts in this scheme
local K = {}                                  -- fixed colours, built in load()
local dim = false                              -- true while drawing the band behind a modal

-- colour lookups honour `dim`; the tables hold kom.rgb values built in load()
local function c(s, k) return dim and s.d[k] or s.c[k] end
local function kc(k) return dim and K.d[k] or K.c[k] end

-- ---- state ----------------------------------------------------------------
local U = {}                 -- units: name, n, s (scheme), t (target, 0 off), st (step), base, hist, hh
local NU = 4
local focus = 1
local base = "full"          -- "full" | "over": the screen under any modal
local state = "full"         -- + "splash" "umenu" "amenu" "bmenu" "kbd" "confirm"
-- TRIANGLE, SELECT and START open screens, so they cannot be bound
local KEYS = { "X", "O", "SQUARE", "UP", "DOWN", "LEFT", "RIGHT", "L", "R", "NONE" }
local bind = { add = "X", sub = "SQUARE" }
local opt = { snd = true, spl = true }
local dirty, save_t, save_ok = false, 0, true
local rep = { 0, 0 }
local msel = 1
local cfm = { sel = 2, msg = "", yes = nil, back = "full" }
local kb = { x = 1, y = 2, txt = "" }
local spl_t = 0
local TARGETS = { 0, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000,
                  10000, 20000, 25000, 50000, 100000, 250000, 500000, 999999 }
local STEPS = { 1, 2, 5, 10, 20, 25, 50, 100, 1000 }

-- ---- sound ----------------------------------------------------------------
local function sfx(id) if opt.snd then kom.sfx(id) end end
local function tone(f, ms) if opt.snd then kom.tone(f, ms, 1, 40) end end

-- ---- save -----------------------------------------------------------------
local function clean_name(s, i)
  s = (s or ""):upper():gsub("[^A-Z0-9%- ]", ""):sub(1, 10)
  if s:match("^%s*$") then s = string.format("UNIT-%02d", i) end
  return s
end
local function new_unit(i)
  return { name = string.format("UNIT-%02d", i), n = 0, s = DEF_SCH[i], t = 0, st = 1,
           base = 0, hist = {}, hh = 1 }
end
local function save_now()
  local p = {}
  for i = 1, NU do
    local u = U[i]
    p[i] = u.name .. ":" .. u.n .. ":" .. u.s .. ":" .. u.t .. ":" .. u.st
  end
  local s = "v=2;b=" .. bind.add .. "," .. bind.sub .. ";snd=" .. (opt.snd and 1 or 0) ..
            ";spl=" .. (opt.spl and 1 or 0) .. ";f=" .. focus .. ";m=" .. (base == "over" and 1 or 0) ..
            ";u=" .. table.concat(p, "/")
  save_ok = kom.save(s) and true or false
  dirty = false
end
local function touch() dirty, save_t = true, 1.0 end
local function valid_key(k)
  for _, v in ipairs(KEYS) do if v == k then return k end end
  return nil
end
local function load_state()
  local s = kom.load() or ""
  for i = 1, 8 do U[i] = new_unit(i) end
  NU = 4
  if s:find("v=2", 1, true) then
    local a, b = s:match("b=(%u+),(%u+)")
    bind.add = valid_key(a) or "X"
    bind.sub = valid_key(b) or "SQUARE"
    opt.snd = s:match("snd=(%d)") ~= "0"
    opt.spl = s:match("spl=(%d)") ~= "0"
    local list, n = s:match("u=([^;]*)"), 0
    for item in (list or ""):gmatch("[^/]+") do
      local nm, cnt, sc, tg, st = item:match("^([^:]*):(%d+):(%d+):(%d+):(%d+)$")
      if nm and n < 8 then
        n = n + 1
        local u = U[n]
        u.name = clean_name(nm, n)
        u.n = math.min(MAXN, tonumber(cnt) or 0)
        u.s = math.max(1, math.min(#SCH, tonumber(sc) or 1))
        u.t = math.min(MAXN, tonumber(tg) or 0)
        u.st = math.max(1, math.min(1000, tonumber(st) or 1))
      end
    end
    NU = (n > 4) and 8 or 4
    focus = math.max(1, math.min(NU, tonumber(s:match("f=(%d+)")) or 1))
    base = (s:match("m=(%d)") == "1") and "over" or "full"
  else
    -- V1 save "n=123;a=X;s=SQUARE": unit 1 keeps the count and the bindings
    U[1].n = math.min(MAXN, tonumber(s:match("n=(%d+)")) or 0)
    bind.add = valid_key(s:match("a=(%u+)")) or "X"
    bind.sub = valid_key(s:match("s=(%u+)")) or "SQUARE"
  end
  if bind.add == bind.sub and bind.add ~= "NONE" then bind.sub = "NONE" end
  for i = 1, 8 do U[i].base = U[i].n end
end

-- ---- counting -------------------------------------------------------------
-- presses in the last 60 s; hist is append-only with a moving head
local function rate_of(u, now)
  local h, i = u.hist, u.hh
  while h[i] and now - h[i] > 60 do i = i + 1 end
  if i > 64 then                               -- compact now and then, never per press
    local t = {}
    for j = i, #h do t[#t + 1] = h[j] end
    u.hist, i = t, 1
  end
  u.hh = i
  return #u.hist - i + 1
end
local function step(i, d)
  local u = U[i]
  local n = u.n + d * u.st
  if n < 0 then n = 0 elseif n > MAXN then n = MAXN end
  if n == u.n then sfx(5); return end
  u.n = n
  u.hist[#u.hist + 1] = kom.time()
  touch()
  tone(d > 0 and 880 or 520, 30)
end

-- ---- digits, stripes, icons -------------------------------------------
local SIZES = {
  B = { w = 52, h = 104, t = 10, gap = 14, hex = true },
  M = { w = 20, h = 40,  t = 4,  gap = 6 },
  S = { w = 12, h = 24,  t = 3,  gap = 4 },
}
local SEGS = { [0] = "abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc", "abc", "abcdefg", "abcdfg" }
local LIT = {}               -- LIT[v][seg] = true, built once
for v = 0, 9 do
  LIT[v] = {}
  for k in SEGS[v]:gmatch(".") do LIT[v][k] = true end
end
LIT[10] = {}                 -- a blank slot: all ghost
local ORDER = { "a", "b", "c", "d", "e", "f", "g" }

-- hex: V1's rect + 2 tris; plain: one full-length bar (tips filled square)
local function hseg(x0, x1, yc, t, col, hex)
  local h = t // 2
  if not hex then kom.rect(x0, yc - h, x1 - x0, t, col); return end
  kom.rect(x0 + h, yc - h, x1 - x0 - t, t, col)
  do
    kom.tri(x0, yc, x0 + h, yc - h, x0 + h, yc + h, col)
    kom.tri(x1, yc, x1 - h, yc - h, x1 - h, yc + h, col)
  end
end
local function vseg(xc, y0, y1, t, col, hex)
  local h = t // 2
  if not hex then kom.rect(xc - h, y0, t, y1 - y0, col); return end
  kom.rect(xc - h, y0 + h, t, y1 - y0 - t, col)
  do
    kom.tri(xc, y0, xc - h, y0 + h, xc + h, y0 + h, col)
    kom.tri(xc, y1, xc - h, y1 - h, xc + h, y1 - h, col)
  end
end
-- one digit: each of the 7 segments once, in lit or ghost; ghost nil = lit only
local function digit(v, x, y, D, lit, ghost)
  local h = D.t // 2
  local e = D.t > 6 and 2 or 1
  local l, r = x + h, x + D.w - h
  local t, m, b = y + h, y + D.h // 2, y + D.h - h
  local L, hex = LIT[v], D.hex
  for _, k in ipairs(ORDER) do
    local col = L[k] and lit or ghost
    if not col then -- skip
    elseif k == "a" then hseg(l + e, r - e, t, D.t, col, hex)
    elseif k == "g" then hseg(l + e, r - e, m, D.t, col, hex)
    elseif k == "d" then hseg(l + e, r - e, b, D.t, col, hex)
    elseif k == "f" then vseg(l, t + e, m - e, D.t, col, hex)
    elseif k == "b" then vseg(r, t + e, m - e, D.t, col, hex)
    elseif k == "e" then vseg(l, m + e, b - e, D.t, col, hex)
    else vseg(r, m + e, b - e, D.t, col, hex) end
  end
end

local ICON = {
  name    = ".....11\n....111\n...111.\n..111..\n.111...\n11.....\n1......",
  colour  = "1111111\n1..1..1\n1..1..1\n1111111\n1..1..1\n1..1..1\n1111111",
  target  = "...1...\n.11111.\n.1...1.\n11.1.11\n.1...1.\n.11111.\n...1...",
  step    = ".1.....\n111....\n.1.....\n.......\n...111.\n.......\n.......",
  reset   = "..111.1\n.1...11\n1...111\n1......\n1.....1\n.1...1.\n..111..",
  units   = "111.111\n111.111\n111.111\n.......\n111.111\n111.111\n111.111",
  resume  = "1......\n111....\n11111..\n1111111\n11111..\n111....\n1......",
  buttons = ".......\n1111111\n1.1...1\n111.1.1\n1.1...1\n1111111\n.......",
  sound   = "...1...\n..11.1.\n1111..1\n1111..1\n1111..1\n..11.1.\n...1...",
  splash  = "...1...\n...1...\n1111111\n..111..\n.11.11.\n11...11\n.......",
  quit    = "1111...\n1......\n1...1..\n1..1111\n1...1..\n1......\n1111...",
  plus    = "...1...\n...1...\n...1...\n1111111\n...1...\n...1...\n...1...",
  minus   = ".......\n.......\n.......\n1111111\n.......\n.......\n.......",
}

-- ---- drawing helpers ------------------------------------------------------
-- hazard band: parallelograms 10 px wide on a 22 px pitch (V1 geometry);
-- reveal < 480 covers the right part in black (the splash slide-in)
local function hazard(y, s, reveal)
  kom.rect(0, y, kom.W, 12, K.c.black)
  local col = s.c.fg
  local x = -12
  while x < (reveal or 480) do
    kom.tri(x, y + 12, x + 12, y, x + 22, y, col)
    kom.tri(x, y + 12, x + 22, y, x + 10, y + 12, col)
    x = x + 22
  end
  if reveal and reveal < 480 then kom.rect(reveal, y, 480 - reveal, 12, K.c.black) end
end
local function label(x, y, str, fg, bg)
  local w = kom.textw(str, 1)
  kom.rect(x, y, w + 10, 13, bg)
  kom.text(x + 5, y + 3, str, fg, 1)
  return w + 10
end
local function labelR(rx, y, str, fg, bg) return label(rx - kom.textw(str, 1) - 10, y, str, fg, bg) end
local function brackets(x, y, w, h, col, k)
  kom.rect(x, y, k, 2, col); kom.rect(x, y, 2, k, col)
  kom.rect(x + w - k, y, k, 2, col); kom.rect(x + w - 2, y, 2, k, col)
  kom.rect(x, y + h - 2, k, 2, col); kom.rect(x, y + h - k, 2, k, col)
  kom.rect(x + w - k, y + h - 2, k, 2, col); kom.rect(x + w - 2, y + h - k, 2, k, col)
end
-- six slots with unlit 8s behind
local function number(n, cx, y, key, lit, ghost)
  local D = SIZES[key]
  local tot = NDIG * D.w + (NDIG - 1) * D.gap
  local x0 = cx - tot // 2
  local str = tostring(n)
  local lead = NDIG - #str
  for i = 1, NDIG do
    local v = 10
    if i > lead then v = str:byte(i - lead) - 48 end
    digit(v, x0 + (i - 1) * (D.w + D.gap), y, D, lit, ghost)
  end
  return x0, tot
end
local function bar(x, y, w, h, frac, back, fill)
  if frac > 1 then frac = 1 end
  kom.rect(x, y, w, h, back)
  local f = math.floor(w * frac + 0.5)
  if f > 0 then kom.rect(x, y, f, h, fill) end
end

-- status strings, rebuilt only when their value changes (allocation budget)
local stc = { u = nil, rate = -1, sess = nil, rs = "", ss = "" }
local function status_strings(u)
  if stc.u ~= u then stc.u, stc.rate, stc.sess = u, -1, nil end
  local r = rate_of(u, kom.time())
  if r ~= stc.rate then stc.rate, stc.rs = r, "RATE " .. r .. " / MIN" end
  local d = u.n - u.base
  if d ~= stc.sess then stc.sess, stc.ss = d, "SESSION " .. (d >= 0 and "+" or "") .. d end
  return stc.rs, stc.ss
end
local function base_title()
  if base == "over" then return NU == 8 and "TALLY // UNITS 1-8" or "TALLY // UNITS 1-4" end
  return "TALLY // " .. U[focus].name
end

-- the bars: drawn after the body and never dimmed
local function chrome(s, u)
  hazard(0, s)
  local x = 8 + label(8, 20, "KOMMANDER", K.c.black, s.c.fg) + 4
  label(x, 20, base_title(), K.c.ink, K.c.black)
  local mem = (not save_ok) and "MEMORY FAULT" or (dirty and "MEMORY WRITE" or "MEMORY SAVED")
  labelR(472, 20, mem, save_ok and K.c.ink or K.c.warn, K.c.black)
  kom.rect(8, 37, 464, 1, s.c.dm)
  kom.rect(8, 234, 464, 1, s.c.dm)
  local rs, ss = status_strings(u)
  label(8, 239, rs, K.c.ink, K.c.black)
  labelR(472, 239, ss, K.c.ink, K.c.black)
  hazard(260, s)
end

local function body_full(u, s, n)
  local D = SIZES.B
  local y0 = 84
  if u.t > 0 then y0 = y0 - 10 end
  local x0, tot = number(n or u.n, kom.W // 2, y0, "B", c(s, "fg"), c(s, "gh"))
  brackets(x0 - 18, y0 - 18, tot + 36, D.h + 36, c(s, "dm"), 10)
  if u.t > 0 then
    local bx, bw, by = x0 - 18, tot + 36, y0 + D.h + 26
    kom.text(bx, by, "TARGET " .. u.t, kc("ink"), 1)
    local p = string.format("%.1f%%", (n or u.n) * 100 / u.t)
    kom.text(bx + bw - kom.textw(p, 1), by, p, kc("ink"), 1)
    bar(bx, by + 11, bw, 6, (n or u.n) / u.t, c(s, "gh"), c(s, "fg"))
  end
end

-- 4 units: 2 x 2 with mid digits; 8 units: 4 x 2 with small digits.
-- The highlighted unit's colour paints them all; only it is lit (round 6).
local function body_over(F)
  local cols = NU == 8 and 4 or 2
  local qw = NU == 8 and 110 or 228
  local key = NU == 8 and "S" or "M"
  local D = SIZES[key]
  for i = 1, NU do
    local u, on = U[i], i == focus
    local own = SCH[u.s]
    local qh = 88
    local qx = 8 + ((i - 1) % cols) * (qw + 8)
    local qy = 44 + ((i - 1) // cols) * 96
    if on then label(qx + 6, qy + 6, u.name, kc("black"), c(own, "fg"))
    else label(qx + 6, qy + 6, u.name, kc("inkdim"), kc("black")) end
    local blk = D.h + (u.t > 0 and 11 or 0)
    local ny = qy + 19 + (qh - 19 - blk) // 2
    local x0, tot
    if on then x0, tot = number(u.n, qx + qw // 2, ny, key, c(own, "fg"), c(own, "gh"))
    -- with 8 units the dimmed units drop their unlit 8s: ~220 draws, nearly
    -- invisible at ghost-on-background, and the frame was over 400 kom calls
    else x0, tot = number(u.n, qx + qw // 2, ny, key, c(F, "dm"), NU < 8 and c(F, "gh") or nil) end
    if u.t > 0 then
      bar(x0, ny + D.h + 8, tot, 3, u.n / u.t, c(F, "gh"), on and c(own, "fg") or c(F, "dm"))
    end
    brackets(qx, qy, qw, qh, on and c(own, "fg") or c(F, "gh"), 8)
  end
end

-- the base screen; with dimmed = true the body is redrawn darker behind a
-- modal while the bars stay bright (the PSP Lua API has no alpha)
local function draw_base(dimmed)
  local u = U[focus]
  local s = SCH[u.s]
  dim = dimmed
  kom.clear(c(s, "bg"))
  if base == "over" then body_over(s) else body_full(u, s) end
  dim = false
  chrome(s, u)
end

-- ---- menus ----------------------------------------------------------------
-- rows: { icon, label, value or nil, swatch scheme or nil, cycles with LEFT/RIGHT }
local function draw_menu(s, title, rows, sel)
  local lw = kom.textw(title, 1)
  for _, r in ipairs(rows) do
    local w = 22 + kom.textw(r[2], 1) + 24
    if r[3] then w = w + kom.textw("< " .. r[3] .. " >", 1) + (r[4] and 12 or 0) end
    if w > lw then lw = w end
  end
  local pw = math.max(200, lw + 20)
  local ph = 18 + #rows * 22 + 4
  local px, py = kom.W // 2 - pw // 2, kom.H // 2 - ph // 2
  kom.rect(px - 4, py - 4, pw + 8, ph + 8, K.c.black)
  kom.rect(px, py, pw, ph, s.c.bg)
  kom.frame(px, py, pw, ph, s.c.fg)
  kom.rect(px, py, pw, 14, s.c.fg)
  kom.text(px + 6, py + 4, title, K.c.black, 1)
  for i, r in ipairs(rows) do
    local y = py + 18 + (i - 1) * 22
    local on = i == sel
    if on then kom.rect(px + 3, y, pw - 6, 20, s.c.fg) end
    kom.sprite(px + 9, y + 6, 1, ICON[r[1]], on and K.c.p1black or s.c.p1)
    kom.text(px + 22, y + 7, r[2], on and K.c.black or K.c.ink, 1)
    if r[3] then
      local v = (on and r[5]) and ("< " .. r[3] .. " >") or r[3]
      local vx = px + pw - 10 - kom.textw(v, 1)
      if r[4] then kom.rect(vx - 12, y + 6, 7, 7, on and K.c.black or SCH[r[4]].c.fg) end
      kom.text(vx, y + 7, v, on and K.c.black or s.c.fg, 1)
    end
  end
end

local function unit_rows()
  local u = U[focus]
  return {
    { "name",   "NAME",   u.name },
    { "colour", "COLOUR", SCH[u.s].name, u.s, true },
    { "target", "TARGET", u.t > 0 and tostring(u.t) or "OFF", nil, true },
    { "step",   "STEP",   tostring(u.st), nil, true },
    { "reset",  "RESET UNIT" },
    { "units",  NU == 8 and "REMOVE UNITS 5-8" or "ADD 4 UNITS" },
  }
end
local function app_rows()
  return {
    { "resume",  "RESUME" },
    { "buttons", "BUTTONS", bind.add .. " / " .. bind.sub },
    { "sound",   "SOUND",   opt.snd and "ON" or "OFF", nil, true },
    { "splash",  "SPLASH",  opt.spl and "ON" or "OFF", nil, true },
    { "reset",   "RESET ALL" },
    { "quit",    "QUIT" },
  }
end
local function button_rows()
  return { { "plus", "ADD", bind.add, nil, true }, { "minus", "SUBTRACT", bind.sub, nil, true } }
end

local function draw_confirm(s)
  local w1, w2 = kom.textw("YES", 2), kom.textw("NO", 2)
  local bw = math.max(kom.textw(cfm.msg, 1) + 20, w1 + w2 + 120)
  local bh = 15 + 10 + 28 + 10
  local bx, by = kom.W // 2 - bw // 2, kom.H // 2 - bh // 2
  kom.rect(bx - 4, by - 4, bw + 8, bh + 8, K.c.black)
  kom.rect(bx, by, bw, bh, s.c.bg)
  kom.frame(bx, by, bw, bh, s.c.fg)
  kom.rect(bx, by, bw, 15, s.c.fg)
  kom.text(bx + 8, by + 4, cfm.msg, K.c.black, 1)
  local ans = { "YES", "NO" }
  for i = 1, 2 do
    local w = kom.textw(ans[i], 2)
    local x = kom.W // 2 + (i == 1 and -1 or 1) * 40 - w // 2
    local y = by + 32
    local on = i == cfm.sel
    if on then kom.rect(x - 10, y - 7, w + 20, 28, s.c.fg) end
    kom.text(x, y, ans[i], on and K.c.black or K.c.inkdim, 2)
  end
end

-- QWERTY grid: 10 columns, the last row ends SPC DEL OK
local KB = {
  { "1","2","3","4","5","6","7","8","9","0" },
  { "Q","W","E","R","T","Y","U","I","O","P" },
  { "A","S","D","F","G","H","J","K","L","-" },
  { "Z","X","C","V","B","N","M","SPC","DEL","OK" },
}
local function draw_kbd(s)
  local cw, ch, gap = 24, 18, 2
  local gw = 10 * (cw + gap) - gap
  local bw, bh = gw + 28, 15 + 10 + 26 + 10 + 4 * (ch + gap) - gap + 10
  local bx, by = kom.W // 2 - bw // 2, kom.H // 2 - bh // 2 + 1
  kom.rect(bx - 4, by - 4, bw + 8, bh + 8, K.c.black)
  kom.rect(bx, by, bw, bh, s.c.bg)
  kom.frame(bx, by, bw, bh, s.c.fg)
  kom.rect(bx, by, bw, 15, s.c.fg)
  kom.text(bx + 8, by + 4, string.format("NAME // UNIT %02d", focus), K.c.black, 1)
  local fx, fy = bx + 14, by + 25
  kom.rect(fx, fy, gw, 26, K.c.black)
  kom.frame(fx, fy, gw, 26, s.c.dm)
  kom.text(fx + 8, fy + 6, kb.txt, K.c.ink, 2)
  if #kb.txt < 10 then kom.rect(fx + 8 + kom.textw(kb.txt, 2) + 3, fy + 5, 10, 16, s.c.fg) end
  local cnt = #kb.txt .. " / 10"
  kom.text(fx + gw - kom.textw(cnt, 1) - 8, fy + 10, cnt, K.c.inkdim, 1)
  for r = 1, 4 do
    for i = 1, 10 do
      local k = KB[r][i]
      local x, y = fx + (i - 1) * (cw + gap), fy + 36 + (r - 1) * (ch + gap)
      local on = r == kb.y and i == kb.x
      if on then kom.rect(x, y, cw, ch, s.c.fg)
      else kom.rect(x, y, cw, ch, s.c.dm); kom.rect(x + 1, y + 1, cw - 2, ch - 2, K.c.black) end
      local tc = on and K.c.black or (#k > 1 and s.c.fg or K.c.ink)
      kom.text(x + cw // 2 - kom.textw(k, 1) // 2, y + 6, k, tc, 1)
    end
  end
end

-- ---- splash: stripes slide, labels scramble and lock, digits count up ----
local GLY = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%&*+=/<>"
local SPL_LEN = 1.25
local function scramble(str, t, t0)
  if t < t0 - 0.08 then return nil end
  local out = {}
  for i = 1, #str do
    local ch = str:sub(i, i)
    if t >= t0 + (i - 1) * 0.025 or ch == " " then out[i] = ch
    else local j = math.random(#GLY); out[i] = GLY:sub(j, j) end
  end
  return table.concat(out)
end
local function ease(k) if k < 0 then k = 0 elseif k > 1 then k = 1 end return 1 - (1 - k) ^ 3 end
local function draw_splash()
  local t = kom.time() - spl_t
  local u = U[focus]
  local s = SCH[u.s]
  kom.clear(s.c.bg)
  local rv = math.floor(480 * ease(t / 0.3))
  hazard(0, s, rv); hazard(260, s, rv)
  local k = ease((t - 0.15) / 0.3)
  if k > 0 then
    local w = math.floor(464 * k)
    kom.rect(8, 37, w, 1, s.c.dm)
    kom.rect(472 - w, 234, w, 1, s.c.dm)
  end
  local a = scramble("KOMMANDER", t, 0.2)
  if a then label(8, 20, a, K.c.black, s.c.fg) end
  a = scramble(base_title(), t, 0.3)
  if a then label(8 + kom.textw("KOMMANDER", 1) + 14, 20, a, K.c.ink, K.c.black) end
  a = scramble("MEMORY SAVED", t, 0.4)
  if a then labelR(472, 20, a, K.c.ink, K.c.black) end
  local rs, ss = status_strings(u)
  a = scramble(rs, t, 0.5)
  if a then label(8, 239, a, K.c.ink, K.c.black) end
  a = scramble(ss, t, 0.55)
  if a then labelR(472, 239, a, K.c.ink, K.c.black) end
  if t > 0.3 then
    -- count up into the screen the app opens on; the overview's units roll together
    local f = ease((t - 0.3) / 0.8)
    if base == "over" then
      local saved = {}
      for i = 1, NU do saved[i] = U[i].n; U[i].n = math.floor(saved[i] * f + 0.5) end
      body_over(s)
      for i = 1, NU do U[i].n = saved[i] end
    else
      body_full(u, s, math.floor(u.n * f + 0.5))
    end
  end
end

-- ---- callbacks ------------------------------------------------------------
local function mk(rgb, k)
  return kom.rgb(math.floor(rgb[1] * k), math.floor(rgb[2] * k), math.floor(rgb[3] * k))
end
function load()
  for _, s in ipairs(SCH) do
    s.c, s.d = {}, {}
    for _, k in ipairs({ "fg", "gh", "dm", "bg" }) do
      s.c[k] = mk(s[k], 1); s.d[k] = mk(s[k], DIMK)
    end
    s.c.p1, s.d.p1 = { s.c.fg }, { s.d.fg }
  end
  local fixed = { black = { 0, 0, 0 }, ink = { 236, 238, 240 }, inkdim = { 136, 140, 146 }, warn = { 214, 24, 24 } }
  K.c, K.d = {}, {}
  for k, v in pairs(fixed) do K.c[k] = mk(v, 1); K.d[k] = mk(v, DIMK) end
  K.c.p1black = { K.c.black }
  math.randomseed(math.floor(kom.time() * 1000))
  load_state()
  if opt.spl then state, spl_t = "splash", kom.time() else state = base end
end

function unload()
  if dirty then save_now() end
end

local ANY = { "X", "O", "SQUARE", "TRIANGLE", "UP", "DOWN", "LEFT", "RIGHT", "L", "R", "START", "SELECT" }
local function press(k) return k ~= "NONE" and kom.btnp(k) end
local function down(k) return k ~= "NONE" and kom.btn(k) end
-- edge press, then repeat after 0.4 s every 0.06 s while held
local function held_step(slot, k, i, d, dt)
  if press(k) then step(i, d); rep[slot] = 0.40
  elseif down(k) then
    rep[slot] = rep[slot] - dt
    if rep[slot] <= 0 then step(i, d); rep[slot] = 0.06 end
  end
end

local function open_confirm(msg, yes, back)
  cfm.msg, cfm.yes, cfm.back, cfm.sel = msg, yes, back, 2
  state = "confirm"; sfx(1)
end

local function cycle_list(list, cur, d)
  local idx = 1
  for i, v in ipairs(list) do if v == cur then idx = i end end
  return list[(idx - 1 + d) % #list + 1]
end
-- two actions on one button would cancel out, so the other's button is skipped
local function cycle_bind(which, d)
  local other = which == "add" and bind.sub or bind.add
  local cur = bind[which]
  repeat cur = cycle_list(KEYS, cur, d) until cur == "NONE" or cur ~= other
  bind[which] = cur
  touch()
end

local function upd_full(dt)
  held_step(1, bind.add, focus, 1, dt)
  held_step(2, bind.sub, focus, -1, dt)
  if kom.btnp("SELECT") then base, state = "over", "over"; touch(); sfx(3)
  elseif kom.btnp("TRIANGLE") then state, msel = "umenu", 1; sfx(3)
  elseif kom.btnp("START") then state, msel = "amenu", 1; sfx(3) end
end

local function upd_over(dt)
  local cols = NU == 8 and 4 or 2
  local f = focus
  if kom.btnp("LEFT") and (f - 1) % cols > 0 then f = f - 1 end
  if kom.btnp("RIGHT") and (f - 1) % cols < cols - 1 and f < NU then f = f + 1 end
  if kom.btnp("UP") and f - cols >= 1 then f = f - cols end
  if kom.btnp("DOWN") and f + cols <= NU then f = f + cols end
  if f ~= focus then focus = f; rep[1], rep[2] = 0, 0; touch(); sfx(0) end
  held_step(1, "X", focus, 1, dt)
  held_step(2, "SQUARE", focus, -1, dt)
  if kom.btnp("SELECT") then base, state = "full", "full"; touch(); sfx(3)
  elseif kom.btnp("TRIANGLE") then state, msel = "umenu", 1; sfx(3)
  elseif kom.btnp("START") then state, msel = "amenu", 1; sfx(3) end
end

local function menu_nav(n)
  if kom.btnp("UP") then msel = (msel - 2) % n + 1; sfx(0) end
  if kom.btnp("DOWN") then msel = msel % n + 1; sfx(0) end
end

local function upd_umenu()
  local u = U[focus]
  menu_nav(6)
  if kom.btnp("O") or kom.btnp("TRIANGLE") then state = base; sfx(2); return end
  local d = 0
  if kom.btnp("LEFT") then d = -1 elseif kom.btnp("RIGHT") then d = 1 end
  local x = kom.btnp("X")
  if x and msel >= 2 and msel <= 4 then d = 1 end
  if d ~= 0 then
    if msel == 2 then u.s = (u.s - 1 + d) % #SCH + 1; touch(); sfx(0)
    elseif msel == 3 then u.t = cycle_list(TARGETS, u.t, d); touch(); sfx(0)
    elseif msel == 4 then u.st = cycle_list(STEPS, u.st, d); touch(); sfx(0) end
  end
  if not x then return end
  if msel == 1 then
    kb.txt = u.name:match("^UNIT%-%d%d$") and "" or u.name
    kb.x, kb.y = 1, 2
    state = "kbd"; sfx(1)
  elseif msel == 5 then
    open_confirm("RESET " .. u.name .. "?", function()
      u.n, u.base, u.hist, u.hh = 0, 0, {}, 1
      save_now()
      if opt.snd then kom.tone(400, 220, 1, 42, 140) end
    end, "umenu")
  elseif msel == 6 then
    if NU == 4 then
      NU = 8
      for i = 5, 8 do U[i] = new_unit(i) end
      touch(); sfx(1)
    else
      open_confirm("REMOVE UNITS 5-8?", function()
        NU = 4
        if focus > 4 then focus = 1 end
        save_now()
      end, "umenu")
    end
  end
end

local function upd_amenu()
  menu_nav(6)
  if kom.btnp("O") or kom.btnp("START") then state = base; sfx(2); return end
  local lr = kom.btnp("LEFT") or kom.btnp("RIGHT")
  local x = kom.btnp("X")
  if (lr or x) and msel == 3 then opt.snd = not opt.snd; touch(); sfx(0); return end
  if (lr or x) and msel == 4 then opt.spl = not opt.spl; touch(); sfx(0); return end
  if not x then return end
  if msel == 1 then state = base; sfx(2)
  elseif msel == 2 then state, msel = "bmenu", 1; sfx(1)
  elseif msel == 5 then
    open_confirm("RESET ALL UNITS?", function()
      for i = 1, 8 do local u = U[i]; u.n, u.base, u.hist, u.hh = 0, 0, {}, 1 end
      save_now()
      if opt.snd then kom.tone(400, 220, 1, 42, 140) end
    end, "amenu")
  elseif msel == 6 then
    if dirty then save_now() end
    if kom.quit then kom.quit() else state = base end
  end
end

local function upd_bmenu()
  menu_nav(2)
  if kom.btnp("O") or kom.btnp("START") then state, msel = "amenu", 2; sfx(2); return end
  local d = 0
  if kom.btnp("LEFT") then d = -1 elseif kom.btnp("RIGHT") or kom.btnp("X") then d = 1 end
  if d ~= 0 then cycle_bind(msel == 1 and "add" or "sub", d); sfx(0) end
end

local function upd_kbd()
  if kom.btnp("LEFT") then kb.x = (kb.x - 2) % 10 + 1; sfx(0) end
  if kom.btnp("RIGHT") then kb.x = kb.x % 10 + 1; sfx(0) end
  if kom.btnp("UP") then kb.y = (kb.y - 2) % 4 + 1; sfx(0) end
  if kom.btnp("DOWN") then kb.y = kb.y % 4 + 1; sfx(0) end
  if kom.btnp("O") then state = "umenu"; sfx(2); return end
  local k = nil
  if kom.btnp("X") then k = KB[kb.y][kb.x] end
  if kom.btnp("SQUARE") then k = "DEL" end
  if kom.btnp("START") then k = "OK" end
  if not k then return end
  if k == "DEL" then kb.txt = kb.txt:sub(1, -2); sfx(2)
  elseif k == "OK" then
    U[focus].name = clean_name(kb.txt, focus); touch()
    state = "umenu"; sfx(1)
  elseif #kb.txt < 10 then
    kb.txt = kb.txt .. (k == "SPC" and " " or k); sfx(0)
  else sfx(5) end
end

local function upd_confirm()
  if kom.btnp("LEFT") or kom.btnp("RIGHT") then cfm.sel = 3 - cfm.sel; sfx(0) end
  if kom.btnp("O") then state = cfm.back; sfx(2); return end
  if kom.btnp("X") then
    if cfm.sel == 1 then
      if cfm.yes then cfm.yes() end
      state = base
    else
      state = cfm.back; sfx(2)
    end
  end
end

function update(dt)
  kom.menu(state ~= "full" and state ~= "over")
  if dirty then
    save_t = save_t - dt
    if save_t <= 0 then save_now() end
  end
  if state == "splash" then
    local skip = kom.time() - spl_t > SPL_LEN
    for _, k in ipairs(ANY) do if kom.btnp(k) then skip = true end end
    if skip then state = base end
  elseif state == "full" then upd_full(dt)
  elseif state == "over" then upd_over(dt)
  elseif state == "umenu" then upd_umenu()
  elseif state == "amenu" then upd_amenu()
  elseif state == "bmenu" then upd_bmenu()
  elseif state == "kbd" then upd_kbd()
  elseif state == "confirm" then upd_confirm() end
end

function draw()
  if state == "splash" then draw_splash(); return end
  draw_base(state ~= "full" and state ~= "over")
  local s = SCH[U[focus].s]
  if state == "umenu" then draw_menu(s, string.format("UNIT %02d // %s", focus, U[focus].name), unit_rows(), msel)
  elseif state == "amenu" then draw_menu(s, "TALLY // MENU", app_rows(), msel)
  elseif state == "bmenu" then draw_menu(s, "TALLY // BUTTONS", button_rows(), msel)
  elseif state == "kbd" then draw_kbd(s)
  elseif state == "confirm" then draw_confirm(s) end
end
