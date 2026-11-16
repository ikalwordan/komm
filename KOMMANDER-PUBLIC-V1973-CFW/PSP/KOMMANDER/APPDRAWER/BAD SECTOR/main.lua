-- @name BAD SECTOR
-- @display fullscreen
--
-- Sling STORAGE MEDIA at stacks of FILES and delete the corrupt ones. Sibling of
-- FLAPPY DRIVE: retro-machine eras (green CRT, amber, BIOS blue, silver metal),
-- drifting data bits, and every impact sprays BITS and NUMBERS.
--
-- Physics: bodies are AABBs that rest until something disturbs them, then fall,
-- tumble and crush. A support pass re-checks what is holding what, so towers
-- collapse instead of hanging in the air. Rotation is visual (two kom.tri per
-- quad, ship rule 18); collision stays axis-aligned, which is what keeps 34
-- bodies inside the frame budget.

local W, H, GY                  -- canvas + ground top (world y)
local SX, SY                    -- sling anchor (world)
local GRAV, BGRAV = 520, 760

-- ---- KOMSTATION game kit (shared convention: options + save + sound gate) ----
local opts = { sound = true, guide = 2, native = true }  -- guide: 0 off, 1 short, 2 full; native: kom.boxstep
local ktone, ksfx = kom.tone, kom.sfx
local function snd(f,ms,w,v,f2) if opts.sound then ktone(f,ms,w,v,f2) end end
local function blip(id)         if opts.sound then ksfx(id) end end

-- ---- palette ---------------------------------------------------------------
-- Colours are WRITE-ONLY on this console (SDK COLOURS), so every surface keeps
-- its r,g,b and builds the shades it needs at load time.
local function C(r,g,b) return kom.rgb(r,g,b) end
local function mix(r,g,b, r2,g2,b2, t)
  return C(r+(r2-r)*t, g+(g2-g)*t, b+(b2-b)*t)
end

local THEMES = {
  { name="GREEN CRT", sr=8,sg=20,sb=10,    fr=16,fg=44,fb=22,  gr=20,gg=50,gb=25,
    rr=60,rg=160,rb=70,   br=80,bg=200,bb=100,  ir=210,ig=255,ib=215 },
  { name="AMBER CRT", sr=24,sg=14,sb=4,    fr=56,fg=34,fb=10,  gr=60,gg=40,gb=12,
    rr=200,rg=130,rb=30,  br=230,bg=160,bb=50,  ir=255,ig=232,ib=200 },
  { name="BIOS BLUE", sr=4,sg=10,sb=60,    fr=14,fg=26,fb=92,  gr=20,gg=30,gb=90,
    rr=90,rg=120,rb=220, br=150,bg=180,bb=255, ir=232,ig=240,ib=255 },
  { name="BRUSHED SILVER", sr=72,sg=84,sb=100,fr=108,fg=122,fb=138,gr=46,gg=57,gb=72,
    rr=160,rg=182,rb=202, br=118,bg=188,bb=208, ir=224,ig=232,ib=240 },
  { name="GUNMETAL", sr=30,sg=40,sb=52, fr=60,fg=76,fb=90, gr=36,gg=46,gb=58,
    rr=112,rg=150,rb=174, br=100,bg=190,bb=204, ir=216,ig=228,ib=236 },
  { name="TITANIUM", sr=88,sg=99,sb=112, fr=120,fg=133,fb=147, gr=52,gg=64,gb=78,
    rr=184,rg=200,rb=216, br=136,bg=202,bb=218, ir=232,ig=238,ib=244 },
}
local th, TH                     -- active theme (table) and its packed colours

local function pack_theme(t)
  -- Silver uses a restrained blue-grey sky and dark panels. Retain contrasting
  -- panel derivation for any future light palette as well.
  local lum = (t.sr + t.sg + t.sb) / 3
  local light = lum > 120
  local pr, pg, pb = 0, 0, 0
  if light then pr, pg, pb = 255, 255, 255 end
  return {
    sky   = C(t.sr,t.sg,t.sb),
    far   = C(t.fr,t.fg,t.fb),
    far2  = mix(t.fr,t.fg,t.fb, t.sr,t.sg,t.sb, 0.45),
    ground= C(t.gr,t.gg,t.gb),
    rim   = C(t.rr,t.rg,t.rb),
    bit   = C(t.br,t.bg,t.bb),
    ink   = C(t.ir,t.ig,t.ib),
    light = light,
    dim   = mix(t.ir,t.ig,t.ib, t.sr,t.sg,t.sb, light and 0.38 or 0.55),
    panel = mix(t.sr,t.sg,t.sb, pr,pg,pb, light and 0.40 or 0.45),
  }
end

-- ---- materials: the blocks are FILES -----------------------------------------
local MAT = {
  -- dens/e/mu are the FEEL of a material: a .TMP scrap is light, skitters and
  -- bounces, a .ISO is a dense slab that lands where it lands. .TXT is the
  -- reference at density 1.0, so the balance the winnability bot was tuned
  -- against does not move under the rest of them.
  { ext=".TMP", hp=1,  kb=4,    dens=0.80, e=0.34, mu=0.55, r=64, g=150,b=192, lr=156,lg=228,lb=248, dr=26, dg=76, db=112 },
  { ext=".TXT", hp=3,  kb=16,   dens=1.00, e=0.18, mu=1.10, r=198,g=170,b=112, lr=240,lg=222,lb=172, dr=118,dg=94, db=52  },
  { ext=".SYS", hp=5,  kb=64,   dens=1.28, e=0.10, mu=1.30, r=120,g=126,b=136, lr=182,lg=190,lb=202, dr=62, dg=66, db=74  },
  { ext=".ISO", hp=9,  kb=1024, dens=1.60, e=0.05, mu=1.45, r=96, g=72, b=126, lr=160,lg=130,lb=200, dr=48, dg=34, db=68  },
}
for _, m in ipairs(MAT) do
  m.c  = C(m.r,m.g,m.b); m.cl = C(m.lr,m.lg,m.lb); m.cd = C(m.dr,m.dg,m.db)
  m.ch = mix(m.r,m.g,m.b, 255,255,255, 0.55)
end

-- ---- the targets: corrupt files ----------------------------------------------
local TGT = {
  { name="POPUP.HTM",  ext="HTM", hp=1, kb=64,   r=228,g=146,b=56  },
  { name="TRACKER.JS", ext="JS",  hp=1, kb=192,  r=110,g=196,b=118 },
  { name="ADWARE.DLL", ext="DLL", hp=2, kb=256,  r=198,g=92, b=192 },
  { name="VIRUS.EXE",  ext="EXE", hp=2, kb=512,  r=218,g=66, b=66  },
  { name="ROOTKIT.SYS",ext="SYS", hp=3, kb=1024, r=96, g=116,b=210 },
}
for _, t in ipairs(TGT) do
  t.c  = C(t.r,t.g,t.b)
  t.cl = mix(t.r,t.g,t.b, 255,255,255, 0.42)
  t.cd = mix(t.r,t.g,t.b, 0,0,0, 0.55)
end

-- ---- the ammunition: storage media -------------------------------------------
-- ab = the SQUARE/X ability fired mid-flight. Every medium behaves differently
-- in the air, which is the whole reason to bring more than one.
local MED = {
  { key="FLOPPY", name="FLOPPY",   ab=nil,      abn="",       r=8, mass=1.00 },
  { key="CD",     name="CD-ROM",   ab="split",  abn="SPLIT",  r=9, mass=0.80 },
  { key="ZIP",    name="ZIP DISK", ab="slam",   abn="SLAM",   r=9, mass=1.65 },
  { key="TAPE",   name="TAPE",     ab="spool",  abn="SPOOL",  r=8, mass=0.90 },
  { key="HDD",    name="PLATTER",  ab="demag",  abn="DEMAG",  r=9, mass=1.45 },
  { key="USB",    name="USB STICK",ab="inject", abn="INJECT", r=7, mass=0.70 },
}
local M_FLOPPY, M_CD, M_ZIP, M_TAPE, M_HDD, M_USB = 1,2,3,4,5,6

-- ---- level construction helpers ---------------------------------------------
-- Levels are built as data at level-start, not stored as literal tables: a hut is
-- five numbers here and twenty-four in a table. EVERY builder returns the TOP it
-- leaves behind, and levels stack by passing that value on -- hand-computing the
-- next storey is how the first draft ended up with a dozen structures that
-- intersected themselves and detonated on frame one (_bsecprobe.js catches it).
local function blk(b, x, y, w, h, m) b[#b + 1] = { x = x, y = y, w = w, h = h, m = m } end
local function slab(b, x, base, w, h, m)         -- a beam whose BOTTOM sits at base
  blk(b, x, base - h, w, h, m); return base - h
end
local function hut(b, x, base, m, w, h)          -- two posts + a lid across them
  blk(b, x, base - h, 8, h, m)
  blk(b, x + w - 8, base - h, 8, h, m)
  blk(b, x - 4, base - h - 8, w + 8, 8, m)
  return base - h - 8
end
-- A hut with a post on BOTH sides seals whatever is inside it away from any shot
-- that starts left of it -- the winnability bot's survivors were, almost without
-- exception, a file on the ground under a full lid. A KIOSK is a lid on ONE
-- CENTRAL pillar: open from both sides, and its centre of mass sits over the
-- pillar, so it stands up honestly (a lid on an END post would now tip, and
-- should). Take the pillar out and the whole thing comes down on what is under it.
local function kiosk(b, x, base, m, w, h)
  blk(b, x + math.floor(w / 2) - 4, base - h, 8, h, m)
  blk(b, x - 4, base - h - 8, w + 8, 8, m)
  return base - h - 8
end
local function stack(b, x, base, m, n, w, hh)
  for i = 1, n do blk(b, x, base - i * hh, w, hh, m) end
  return base - n * hh
end
local function wall(b, x, base, m, cols, rows, w, hh)
  for c = 0, cols - 1 do for r = 1, rows do blk(b, x + c * w, base - r * hh, w, hh, m) end end
  return base - rows * hh
end
local function tgt(t, x, base, k) t[#t + 1] = { x = x, y = base - 24, k = k } end

local TMP, TXT, SYS, ISO = 1, 2, 3, 4
local POPUP, JS, ADWARE, VIRUS, ROOTKIT = 1, 2, 3, 4, 5

-- ---- 24 sectors: SYSTEM REPAIR, DEEP SCAN, SILVER RECOVERY, COLD STORAGE ------
-- era indexes THEMES. ammo lists MED indexes, fired in order.
local LEVELS = {
  { name="COLD BOOT", era=1, w=480, ammo={1,1,1}, build=function(b,t)
      tgt(t, 312, GY, POPUP)                       -- out in the open: aim, fire
      blk(b, 348, GY - 18, 18, 18, TMP)
      blk(b, 348, GY - 36, 18, 18, TMP)
      local r = hut(b, 392, GY, TXT, 56, 34)
      tgt(t, 408, r, POPUP)                        -- on the roof, not sealed in
    end },

  { name="TEMP FILES", era=1, w=520, ammo={1,1,1,1,1}, build=function(b,t)
      local r1 = hut(b, 288, GY, TXT, 60, 44); tgt(t, 306, GY, POPUP)
      local r2 = hut(b, 384, GY, TXT, 60, 44); tgt(t, 402, GY, JS)
      blk(b, 300, r1 - 16, 16, 16, TMP); blk(b, 328, r1 - 16, 16, 16, TMP)
      tgt(t, 402, r2, POPUP)
    end },

  { name="STACK OVERFLOW", era=1, w=560, ammo={1,2,1,1}, build=function(b,t)
      local a = stack(b, 300, GY, TXT, 4, 10, 26)
      stack(b, 384, GY, TXT, 4, 10, 26)
      local s1 = slab(b, 296, a, 98, 8, SYS)
      tgt(t, 332, s1, JS)
      tgt(t, 336, GY, POPUP)
      blk(b, 316, GY - 16, 16, 16, TMP)
      blk(b, 360, GY - 16, 16, 16, TMP)
    end },

  { name="AMBER ALERT", era=2, w=600, ammo={2,1,3,1,1}, build=function(b,t)
      local w1 = wall(b, 300, GY, TXT, 4, 2, 18, 18)
      local s1 = slab(b, 296, w1, 80, 8, SYS)
      hut(b, 312, s1, TMP, 48, 34)
      tgt(t, 328, s1, ADWARE)
      hut(b, 404, GY, TXT, 52, 30); tgt(t, 420, GY, JS)
      stack(b, 470, GY, TXT, 3, 10, 24)
    end },

  { name="REGISTRY ROT", era=2, w=640, ammo={1,3,2,1,2}, build=function(b,t)
      local a = stack(b, 300, GY, SYS, 3, 12, 28)
      stack(b, 396, GY, SYS, 3, 12, 28)
      local s1 = slab(b, 292, a, 124, 10, SYS)
      hut(b, 320, s1, TXT, 60, 36)
      tgt(t, 338, s1, VIRUS)
      wall(b, 316, GY, TMP, 2, 2, 16, 16)
      tgt(t, 352, GY, JS)
      hut(b, 452, GY, TXT, 60, 30); tgt(t, 470, GY, POPUP)
    end },

  { name="DISK THRASH", era=2, w=680, ammo={3,4,2,1,4,1}, build=function(b,t)
      local w1 = wall(b, 296, GY, SYS, 2, 3, 16, 20)
      kiosk(b, 340, GY, TXT, 70, 52); tgt(t, 344, GY, ADWARE)
      wall(b, 424, GY, SYS, 2, 3, 16, 20)
      local s1 = slab(b, 292, w1, 168, 10, ISO)
      hut(b, 330, s1, TMP, 56, 30)
      tgt(t, 346, s1, JS)
      tgt(t, 410, s1, POPUP)
      stack(b, 504, GY, SYS, 1, 12, 26); stack(b, 552, GY, SYS, 1, 12, 26)
      slab(b, 500, GY - 26, 68, 8, TXT)
      tgt(t, 520, GY, VIRUS)
    end },

  { name="BLUE SCREEN", era=3, w=700, ammo={4,2,5,1,2,1}, build=function(b,t)
      local a = stack(b, 300, GY, SYS, 4, 12, 26)
      stack(b, 392, GY, SYS, 4, 12, 26)
      local s1 = slab(b, 294, a, 116, 10, ISO)
      hut(b, 316, s1, TXT, 66, 40)
      tgt(t, 338, s1, VIRUS)
      tgt(t, 340, GY, JS); tgt(t, 366, GY, POPUP)
      local h2 = kiosk(b, 486, GY, SYS, 74, 40); tgt(t, 492, GY, ADWARE)
      blk(b, 492, h2 - 20, 20, 20, TMP)
    end },

  { name="KERNEL PANIC", era=3, w=740, ammo={5,3,2,4,3,1,2}, build=function(b,t)
      local w1 = wall(b, 300, GY, ISO, 2, 4, 18, 18)
      hut(b, 348, GY, SYS, 80, 64); tgt(t, 374, GY, VIRUS)
      wall(b, 440, GY, ISO, 2, 4, 18, 18)
      local s1 = slab(b, 296, w1, 180, 10, SYS)
      local h2 = hut(b, 340, s1, TXT, 60, 34)
      tgt(t, 356, s1, ADWARE); tgt(t, 420, s1, JS)
      local s2 = slab(b, 336, h2, 96, 8, TMP)
      tgt(t, 372, s2, POPUP)
      hut(b, 560, GY, TXT, 56, 34); tgt(t, 576, GY, JS)
    end },

  { name="MEMORY LEAK", era=3, w=780, ammo={6,2,3,5,2,6,1}, build=function(b,t)
      local a = stack(b, 306, GY, SYS, 5, 12, 24)
      stack(b, 398, GY, SYS, 5, 12, 24)
      local s1 = slab(b, 300, a, 116, 10, ISO)
      hut(b, 322, s1, TMP, 66, 38)
      tgt(t, 344, s1, VIRUS)
      local w1 = wall(b, 324, GY, TMP, 2, 1, 18, 18)
      tgt(t, 330, w1, ADWARE)
      local h3 = kiosk(b, 496, GY, SYS, 66, 44); tgt(t, 500, GY, JS)
      local s3 = slab(b, 492, h3, 76, 10, ISO)
      tgt(t, 518, s3, POPUP)
      stack(b, 620, GY, TXT, 2, 14, 22); tgt(t, 646, GY, POPUP)
    end },

  { name="SILVER TOWER", era=4, w=800, ammo={3,5,6,2,1,3,2}, build=function(b,t)
      local w1 = wall(b, 300, GY, ISO, 3, 2, 18, 20)
      local s1 = slab(b, 296, w1, 62, 10, SYS)
      local w2 = wall(b, 306, s1, SYS, 2, 3, 16, 20)
      local s2 = slab(b, 300, w2, 58, 10, SYS)
      hut(b, 310, s2, TXT, 44, 30)
      tgt(t, 322, s2, VIRUS)
      local h2 = kiosk(b, 404, GY, SYS, 52, 40); tgt(t, 404, GY, ADWARE)
      local s3 = slab(b, 400, h2, 60, 10, ISO)
      tgt(t, 420, s3, JS)
      stack(b, 630, GY, TXT, 3, 12, 24); tgt(t, 656, GY, ADWARE)
    end },

  { name="FRAGMENT HELL", era=4, w=840, ammo={2,6,3,5,4,2,3,5,6}, build=function(b,t)
      local top
      for i = 0, 2 do
        local x = 300 + i * 130
        local a = stack(b, x, GY, SYS, 3, 12, 26)
        stack(b, x + 56, GY, SYS, 3, 12, 26)
        local s = slab(b, x - 4, a, 84, 10, ISO)
        top = hut(b, x + 8, s, TXT, 60, 28)
        tgt(t, x + 22, s, (i == 1) and ADWARE or JS)
        tgt(t, x - 34, GY, POPUP)
      end
      local long = slab(b, 296, top, 300, 8, TMP)
      tgt(t, 430, long, VIRUS)
    end },

  { name="BAD SECTOR", era=4, w=880, ammo={5,3,6,2,4,1,3,5}, build=function(b,t)
      local w1 = wall(b, 300, GY, ISO, 2, 5, 18, 20)
      kiosk(b, 348, GY, SYS, 72, 92)
      tgt(t, 258, GY, VIRUS)           -- out front: the ISO wall sealed the lane
                                       -- under the kiosk at every angle the sling has
      wall(b, 424, GY, ISO, 2, 5, 18, 20)
      local s1 = slab(b, 294, w1, 172, 12, ISO)
      local w3 = wall(b, 320, s1, SYS, 2, 2, 16, 22)
      wall(b, 410, s1, SYS, 2, 2, 16, 22)
      local s2 = slab(b, 314, w3, 132, 10, ISO)
      hut(b, 340, s2, TXT, 66, 34)
      tgt(t, 358, s2, ADWARE)
      tgt(t, 370, s1, JS)
      local c = stack(b, 560, GY, ISO, 4, 14, 24)
      stack(b, 660, GY, ISO, 4, 14, 24)
      local s3 = slab(b, 552, c, 130, 12, ISO)
      kiosk(b, 578, s3, SYS, 76, 44)
      tgt(t, 584, s3, ROOTKIT)
      tgt(t, 512, GY, VIRUS)
      tgt(t, 662, s3, ADWARE)          -- on the ledge, not behind the compound
    end },

  -- ---- the DEEP SCAN set (v2, operator: "needs more stages") -----------------
  -- Appended, never inserted: prog.st is keyed by level INDEX, so slotting these
  -- in front of BAD SECTOR would silently re-label every stored best. Each one is
  -- built from the same helpers as the twelve above. _bsecprobe.js checks layout
  -- and ballistic reach; the separate gameplay bot checks demolition outcomes.
  { name="SWAP FILE", era=4, w=900, ammo={4,2,6,3,5,1,4}, build=function(b,t)
      -- two towers with a long deck slung between them: the deck comes down when
      -- either tower goes, and what is under it goes with the deck
      local l = wall(b, 300, GY, ISO, 2, 4, 18, 20)
      local r = wall(b, 470, GY, ISO, 2, 4, 18, 20)
      local deck = slab(b, 296, l, 214, 12, SYS)
      tgt(t, 380, GY, VIRUS)                 -- underneath, in the open lane
      hut(b, 330, deck, TXT, 56, 30)
      tgt(t, 348, deck, ADWARE)
      tgt(t, 452, deck, JS)
      local k = kiosk(b, 620, GY, SYS, 70, 46)
      tgt(t, 626, GY, POPUP)
      slab(b, 616, k, 80, 10, ISO)
      tgt(t, 700, GY, JS)
      -- r is load-bearing for the deck; naming it keeps the intent readable
      return r
    end },

  { name="CHECKSUM", era=4, w=940, ammo={2,5,3,6,2,4,1,3}, build=function(b,t)
      -- a stepped pyramid: every storey is narrower, so the top comes off easily
      -- and the base has to be dug out. A tgt() IS A BODY (20x24 sitting on the
      -- given base), so every one of these is placed clear of the storey above it
      -- -- the first draft buried three of them inside their own walls.
      local a = wall(b, 300, GY, ISO, 5, 3, 18, 20)      -- x 300..390
      local s1 = slab(b, 296, a, 108, 10, SYS)           -- x 296..404
      tgt(t, 262, GY, POPUP)                             -- in front of the base
      local c = wall(b, 316, s1, SYS, 3, 3, 18, 20)      -- x 316..370, on s1
      tgt(t, 376, s1, JS)                                -- s1, clear to the right
      local s2 = slab(b, 312, c, 76, 10, SYS)            -- x 312..388
      local d = wall(b, 318, s2, TXT, 2, 2, 16, 20)      -- x 318..350, on s2
      tgt(t, 358, s2, ADWARE)                            -- s2, clear to the right
      local s3 = slab(b, 314, d, 56, 8, ISO)             -- x 314..370
      hut(b, 316, s3, TXT, 48, 24)                       -- posts 316..324, 356..364
      tgt(t, 330, s3, VIRUS)                             -- inside, between the posts
      local k = kiosk(b, 560, GY, SYS, 80, 52)
      tgt(t, 512, GY, ROOTKIT)                           -- beside the kiosk, in the open
      slab(b, 556, k, 90, 10, ISO)
      tgt(t, 700, GY, POPUP)
    end },

  { name="DEFRAG", era=4, w=980, ammo={6,3,5,2,4,6,1,3,5}, build=function(b,t)
      -- a row of thin stacks with a single beam across all of them: knock one out
      -- and the beam rolls the rest of the way down the line
      local tops = {}
      for i = 0, 4 do
        local x = 300 + i * 74
        tops[i] = stack(b, x, GY, ISO, 4, 14, 22)
        if i % 2 == 0 then tgt(t, x + 32, GY, (i == 2) and VIRUS or POPUP) end
      end
      local run = slab(b, 296, tops[0], 372, 8, TMP)
      tgt(t, 360, run, JS)
      tgt(t, 520, run, ADWARE)
      local k = kiosk(b, 720, GY, SYS, 66, 44)
      tgt(t, 726, GY, JS)
      slab(b, 716, k, 76, 10, ISO)
    end },

  { name="FORMAT C:", era=4, w=1020, ammo={5,2,6,3,4,1,5,2,6,3}, build=function(b,t)
      -- The finale: a compound that LOOKS sealed and is not, plus an outbuilding
      -- you have to get over rather than through. Heights are budgeted from the
      -- top down -- the first draft put the hut lid at y=14, under the HUD, and
      -- the right-hand compound past the sling's range at 700+.
      local l = wall(b, 300, GY, ISO, 2, 5, 18, 20)      -- top 142
      wall(b, 430, GY, ISO, 2, 5, 18, 20)
      tgt(t, 262, GY, VIRUS)                             -- out front, always reachable
      kiosk(b, 348, GY, SYS, 74, 80)                     -- lid 154..162, under the deck
      tgt(t, 356, GY, ROOTKIT)                           -- under the lid, open both sides
      local deck = slab(b, 296, l, 176, 12, ISO)         -- 130..142
      local u = wall(b, 322, deck, SYS, 2, 2, 16, 22)    -- top 86
      wall(b, 412, deck, SYS, 2, 2, 16, 22)
      tgt(t, 372, deck, JS)                              -- between the two uprights
      local top = slab(b, 316, u, 136, 10, ISO)          -- 76..86
      hut(b, 342, top, TXT, 68, 30)                      -- lid tops out at y=38
      tgt(t, 360, top, ADWARE)
      local c = stack(b, 560, GY, ISO, 5, 14, 24)
      stack(b, 666, GY, ISO, 5, 14, 24)
      local s3 = slab(b, 552, c, 138, 12, ISO)           -- 552..690
      kiosk(b, 580, s3, SYS, 80, 46)
      tgt(t, 586, s3, ROOTKIT)
      tgt(t, 512, GY, VIRUS)
      tgt(t, 664, s3, ADWARE)
    end },
  -- SILVER RECOVERY (17-20): short chains, offset decks and split lanes.
  -- Append only: saves store clip awards by sector index.
  { name="CACHE LINE", era=4, w=760, ammo={2,4,1,3,2,6,5,2}, build=function(b,t)
      for i=0,2 do
        local x=292+i*116
        local roof=kiosk(b,x,GY,TXT,64,36+i*16)
        tgt(t,x+4,GY,POPUP);tgt(t,x+20,roof,JS)
        if i~=1 then
          local a=stack(b,x+4,roof,TXT,2,12,18)
          stack(b,x+48,roof,(i==0) and TMP or SYS,2,12,18)
          local cap=slab(b,x,a,64,8,SYS);tgt(t,x+22,cap,ADWARE)
        else wall(b,x+76,GY,TMP,2,3,10,14) end
      end
    end },
  { name="MIRROR ARRAY", era=5, w=800, ammo={5,2,3,6,4,2,1,5,3}, build=function(b,t)
      for i=0,1 do
        local x=300+i*208
        local top=stack(b,x,GY,SYS,3,14,24)
        stack(b,x+92,GY,TXT,3,14,24)
        local deck=slab(b,x-4,top,114,8,SYS)
        tgt(t,x+42,GY,ADWARE);tgt(t,x+42,deck,JS)
        stack(b,x+8,deck,TXT,2,12,24)
        stack(b,x+80,deck,TXT,2,12,24)
      end
      local link=slab(b,304,GY-128,308,8,TMP)
      tgt(t,340,link,JS);tgt(t,450,link,VIRUS);tgt(t,560,link,JS)
    end },
  { name="FRAGMENT CHAIN", era=4, w=820, ammo={3,4,2,5,6,1,2}, build=function(b,t)
      for i=0,3 do
        local x=292+i*104
        local top=stack(b,x,GY,TXT,2+i%2,16,26)
        local deck=slab(b,x-16,top,48,8,TMP)
        tgt(t,x-2,deck,JS)
        if i<3 then
          tgt(t,x+46,GY,POPUP)
          wall(b,x+72,GY,(i==1) and SYS or TMP,2,2,10,16)
        end
      end
    end },
  { name="RECOVERY POINT", era=6, w=840, ammo={5,3,2,6,4,5,2,1}, build=function(b,t)
      local a=kiosk(b,304,GY,SYS,112,54)
      tgt(t,308,GY,VIRUS);tgt(t,388,GY,JS)
      local r=hut(b,324,a,TXT,64,38);tgt(t,344,r,ADWARE)
      local c=stack(b,520,GY,SYS,4,16,24)
      stack(b,616,GY,TXT,4,16,24)
      local d=slab(b,514,c,126,10,SYS)
      tgt(t,558,GY,ROOTKIT);tgt(t,562,d,JS)
      local upper=hut(b,540,d,TXT,72,36);tgt(t,562,upper,ADWARE)
      wall(b,450,GY,TMP,2,2,14,18)
    end },
  -- COLD STORAGE (21-24): tall relays, roof targets and a two-part vault.
  { name="COLD STORAGE", era=5, w=800, ammo={6,3,5,2,4,6,1,2,3}, build=function(b,t)
      for i=0,2 do
        local x=300+i*124
        local r=hut(b,x,GY,(i==1) and SYS or TXT,72,40+i*18)
        tgt(t,x+26,r,(i==2) and ADWARE or JS)
        tgt(t,x+26,GY,POPUP)
        if i<2 then local upper=hut(b,x+10,r,TXT,52,28);tgt(t,x+26,upper,JS) end
      end
      wall(b,658,GY,TMP,2,2,12,18)
    end },
  { name="BUS CASCADE", era=6, w=820, ammo={4,2,3,5,6,2,3,1}, build=function(b,t)
      local a=stack(b,300,GY,TXT,4,16,22)
      stack(b,456,GY,TXT,4,16,22)
      local d=slab(b,296,a,180,8,SYS)
      tgt(t,338,GY,JS);tgt(t,402,GY,VIRUS)
      local r=kiosk(b,336,d,TXT,88,38);tgt(t,368,r,ADWARE)
      local u=stack(b,340,r,TXT,2,12,12);stack(b,408,r,TMP,2,12,12)
      local cap=slab(b,336,u,88,8,SYS);tgt(t,368,cap,JS)
      local e=kiosk(b,566,GY,SYS,80,58)
      tgt(t,570,GY,POPUP);tgt(t,594,e,JS)
      local upper=hut(b,576,e,TXT,60,32);tgt(t,596,upper,ADWARE)
    end },
  { name="QUARANTINE", era=5, w=860, ammo={5,6,3,2,4,5,6,1}, build=function(b,t)
      local a=wall(b,300,GY,SYS,2,3,18,22)
      local d=slab(b,296,a,52,8,ISO);tgt(t,310,d,ROOTKIT)
      local cap=hut(b,298,d,TXT,52,30);tgt(t,310,cap,ADWARE)
      local r=kiosk(b,400,GY,TXT,84,50)
      tgt(t,404,GY,VIRUS);tgt(t,430,r,ADWARE)
      local u=stack(b,404,r,TMP,2,12,13);stack(b,468,r,TXT,2,12,13)
      local lid=slab(b,400,u,84,8,SYS);tgt(t,430,lid,JS)
      local c=stack(b,566,GY,TXT,5,16,24)
      local e=slab(b,550,c,48,8,SYS);tgt(t,564,e,JS)
      tgt(t,640,GY,VIRUS)
      wall(b,602,GY,TMP,2,3,10,16)
    end },
  { name="LAST GOOD COPY", era=6, w=900, ammo={5,3,6,2,4,5,3,6,2,1}, build=function(b,t)
      local a=kiosk(b,300,GY,SYS,128,64)
      tgt(t,308,GY,VIRUS);tgt(t,396,GY,ADWARE)
      local r=hut(b,328,a,TXT,72,42)
      tgt(t,352,a,JS);tgt(t,352,r,ROOTKIT)
      local u=stack(b,336,r,TXT,2,8,12);stack(b,380,r,SYS,2,8,12)
      local crown=slab(b,332,u,64,8,SYS);tgt(t,352,crown,JS)
      local c=kiosk(b,532,GY,TXT,112,48)
      tgt(t,538,GY,JS);tgt(t,614,GY,VIRUS)
      local d=kiosk(b,552,c,TXT,72,36)
      blk(b,616,r,8,d-r,TXT)
      local link=slab(b,396,r,232,8,TMP);tgt(t,576,link,ADWARE)
      wall(b,454,GY,TMP,2,2,14,18)
    end },
}

-- ---- state -------------------------------------------------------------------
local state                     -- title select help opts intro aim fly settle pause win lose
local sel, hsel, osel, psel, wsel   -- per-screen cursors
local lvl, LV, worldW           -- current level index / def / world width
local bodies, shots, parts, props, dbits
parts = { n = 0 }
ghost = nil            -- set to { x = {}, y = {}, n = 0 } on the first reset
local left                      -- corrupt files still alive
local ammo, ammo_i
local ghost                     -- where the LAST shot went, kept on screen to aim by
local score, shown, level_total, star2, star3, stars_got, bonus
local camx, camtx, shake_t, shake_m, intro_t
local aim_a, aim_p, tick_t, settle_t, turn_t, moving
local banner, banner_t, end_t
local prog = { unl = 1, st = {} }
local cfm, cfm_sel = false, 2   -- reset confirm; NO is the default highlight
local chk_t = 0                 -- seconds of support-checking still owed
local title_t = 0
local audio_at = { kill=0, debris=0, hit=0, blast=0 }
local mbits                     -- menu backdrop bits, banded away from the text

local hurt_body, destroy_body, blast, next_turn, start_level
local wake_body, tip_impulse

-- The menu bit field rains down the EDGES. Bits scattered over the whole canvas
-- put a stray 1 through the middle of the wordmark, which reads as a glitch in
-- the font rather than atmosphere.
local function mkbit()
  local x
  if math.random(1, 2) == 1 then x = math.random() * 40 else x = W - 42 + math.random() * 40 end
  return { x = x, y = 6 + math.random() * (H - 46), b = math.random(0, 1),
           s = 8 + math.random() * 22 }
end

local function draw_mbits()
  for i = 1, #mbits do
    local b = mbits[i]
    kom.text(math.floor(b.x), math.floor(b.y), (b.b == 1) and "1" or "0", TH.bit, 1)
  end
end

-- ---- save / load -------------------------------------------------------------
local function save_state()
  local s = ""
  for i = 1, #LEVELS do s = s .. tostring(prog.st[i] or 0) end
  kom.save("v1;u=" .. prog.unl .. ";s=" .. s .. ";snd=" .. (opts.sound and 1 or 0)
           .. ";g=" .. opts.guide .. ";nat=" .. (opts.native and 1 or 0))
end
local function load_state()
  local d = kom.load() or ""
  prog.unl = tonumber(d:match("u=(%d+)")) or 1
  local s = d:match("s=(%d*)") or ""
  for i = 1, #LEVELS do prog.st[i] = tonumber(s:sub(i, i)) or 0 end
  opts.sound = (d:match("snd=(%d)") ~= "0")
  opts.guide = tonumber(d:match("g=(%d)")) or 2
  opts.native = (d:match("nat=(%d)") ~= "0")    -- an older save has no key: native
  if prog.unl < 1 then prog.unl = 1 end
  if prog.unl > #LEVELS then prog.unl = #LEVELS end
  -- A completed old finale should open the appended chapter immediately.
  while prog.unl < #LEVELS and (prog.st[prog.unl] or 0)>0 do prog.unl=prog.unl+1 end
end

-- ---- numbers -----------------------------------------------------------------
local function kbs(kb)
  if kb >= 1048576 then return string.format("%.1f GB", kb / 1048576) end
  if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
  return math.floor(kb) .. " KB"
end
local function kbshort(kb)
  if kb >= 1024 then return string.format("+%.1fM", kb / 1024) end
  return "+" .. math.floor(kb) .. "K"
end

-- ---- particles: BITS and NUMBERS ---------------------------------------------
local HEXD = "0123456789ABCDEF"
local function hex2()
  local i, j = math.random(1, 16), math.random(1, 16)
  return HEXD:sub(i, i) .. HEXD:sub(j, j)
end
-- PARTICLES ARE A POOL (operator: "hits and launches cause the game to lag").
-- Every particle used to be a FRESH TABLE and every death used to be a
-- table.remove, which shifts the whole tail down. Destroying one body spawns 21
-- particles in a single frame, so a hit meant 21 allocations plus, over the next
-- second, up to 86 O(n) shifts -- allocation churn the console pays for in GC
-- pauses that the simulator's instruction counter cannot see at all (BAD SECTOR
-- profiles at a mild 5.3k steps a frame and still stuttered on every hit).
-- The pool is allocated once and never grows; removal swaps the last live entry
-- into the hole. The live count lives on the table as `parts.n` rather than in a
-- new local, because this chunk is at 199 of Lua's 200 top-level local slots
-- (lua-200-local-ceiling -- BAD SECTOR is the app that found that ceiling).
local function part(k, x, y, vx, vy, life, col, s)
  local n = (parts.n or 0)
  if n >= 86 then return end
  n = n + 1
  parts.n = n
  local p = parts[n]
  if not p then p = {}; parts[n] = p end
  p.k = k; p.x = x; p.y = y; p.vx = vx; p.vy = vy
  p.life = life; p.max = life; p.c = col; p.s = s
end
local function bits_at(x, y, n, col, pw)
  for _ = 1, n do
    local a = math.random() * 6.2832
    local sp = 30 + math.random() * pw
    part("bit", x, y, math.cos(a) * sp, math.sin(a) * sp - 45,
         0.45 + math.random() * 0.45, col, (math.random() < 0.5) and "0" or "1")
  end
end
local function shake(m, t)
  if m > shake_m then shake_m = m end
  if t > shake_t then shake_t = t end
end

-- ---- damage ------------------------------------------------------------------
function destroy_body(b)
  if b.dead then return end
  b.dead = true
  chk_t = 0.7
  destroy_fx(b, b.x, b.y, b.w, b.h)
end

-- WHAT A DELETION LOOKS AND SOUNDS LIKE, apart from the deletion itself. Split out in
-- V1078 so the native solver (kom.boxstep) can apply hp/dead INSIDE its step, where a
-- dead body must stop colliding, and replay these afterwards in the same order from
-- the position the body had at that moment. Global functions, not locals: this chunk
-- is at 199 of Lua's 200 local slots.
function destroy_fx(b, x, y, w, h)
  local kb, col
  if b.t then
    kb, col = b.t.kb, b.t.c
    left = left - 1
    bits_at(x + 10, y + 12, 12, b.t.cl, 170)
    for _ = 1, 5 do
      part("hex", x + 10, y + 12, (math.random() - 0.5) * 200,
           (math.random() - 0.5) * 160 - 50, 0.7, TH.ink, hex2())
    end
    part("kill", x + 10, y + 4, 0, -20, 1.0, b.t.c, "DELETED")
    shake(5, 0.28)
    -- A collapsing tower may delete many files in one update. One deletion
    -- accent per 90ms carries that event without synthesizing a choir at once.
    if title_t >= audio_at.kill then
      audio_at.kill = title_t + 0.09
      snd(880, 90, 1, 62, 1320); snd(520, 170, 1, 48, 240)
    end
  else
    kb, col = b.m.kb, b.m.cl
    bits_at(x + w / 2, y + h / 2, 6, b.m.cl, 120)
    for _ = 1, 3 do
      part("chip", x + w / 2, y + h / 2, (math.random() - 0.5) * 150,
           -40 - math.random() * 90, 0.6, b.m.c)
    end
    shake(2, 0.12)
    if title_t >= audio_at.debris then
      audio_at.debris = title_t + 0.07
      snd(240 + b.m.hp * 60, 70, 3, 34)
    end
  end
  score = score + kb
  part("num", x + w / 2, y, (math.random() - 0.5) * 16, -30, 0.85, col, kbshort(kb))
  moving = true
end

function hurt_body(b, dmg)
  if b.dead or dmg < 1 then return end
  b.hp = b.hp - dmg
  b.flash = 0.11
  hurt_fx(b, dmg, b.x, b.y, b.w)
  if b.hp <= 0 then destroy_body(b) end
end

function hurt_fx(b, dmg, x, y, w)
  part("num", x + w / 2, y + 2, (math.random() - 0.5) * 22, -34, 0.5,
       TH.ink, "-" .. math.floor(dmg))
end

function blast(x, y, rad, dmg)
  shake(8, 0.36)
  for i = 1, #bodies do
    local b = bodies[i]
    if not b.dead then
      local dx, dy = (b.x + b.w / 2) - x, (b.y + b.h / 2) - y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < rad then
        local f = 1 - d / rad
        local inv = (d > 1) and (1 / d) or 0
        hurt_body(b, math.floor(dmg * f + 0.5))
        if not b.dead then
          b.piv = nil; wake_body(b)
          local jx = dx * inv * 300 * f
          local jy = dy * inv * 240 * f - 50 * f * b.mass
          b.vx = b.vx + jx / b.mass
          b.vy = b.vy + jy / b.mass
          -- the blast pushes on the FACE nearest the charge, not through the
          -- centre, so a post beside a detonation goes over instead of sliding
          tip_impulse(b, jx, jy, x, y)
        end
      end
    end
  end
  bits_at(x, y, 16, TH.bit, 190)
  for _ = 1, 6 do
    part("hex", x, y, (math.random() - 0.5) * 240, (math.random() - 0.5) * 220 - 40,
         0.7, TH.ink, hex2())
  end
  part("ring", x, y, 0, 0, 0.35, TH.bit, rad)
  if title_t >= audio_at.blast then
    audio_at.blast = title_t + 0.10
    snd(430, 190, 3, 68, 205); snd(760, 150, 1, 52, 260)
  end
end

-- ---- physics: bodies ---------------------------------------------------------
-- SOLVER v2. Semi-implicit (symplectic) Euler, SUBSTEPPED off the fastest awake
-- body, an ITERATIVE IMPULSE contact solver with restitution and Coulomb
-- friction, and a topple that swings about the contact CORNER on the body's real
-- moment of inertia.
--
-- Everything the solver touches is PREALLOCATED and reused -- the awake list, the
-- contact pool, the broadphase grid. Building a table per contact is the single
-- most expensive thing a Lua physics loop can do on this console, and the cost
-- does not show up until the frame the whole tower comes down, which is the one
-- frame that matters.
--
-- WHY EACH PIECE IS HERE. Every one of these was a defect a probe could see:
--  * SUBSTEPS + a velocity cap. One 1/60 step let an 8px block flung by a DEMAG
--    blast at 900 px/s cross an 8px post between two frames and come out the far
--    side untouched (_bsecphys.js "tunnel").
--  * IMPULSES, not a positional shove. The old resolver teleported the box out of
--    the deepest overlap and reflected one axis, so a body wedged between two
--    others was answered by whichever pair happened to be tested last, and the
--    full positional correction pumped energy back into the pile every frame.
--  * SLEEP on linear AND angular velocity, and the turn ends when the awake list
--    is EMPTY, not when a magic speed sum drops under 14.
--  * A REAL PIVOT:  alpha = g * r * cos(theta) / (k^2 + r^2)  about the support
--    corner, theta being the polar angle of the centre of mass about that corner.
--    Mass cancels. ONE formula, and it is RESTORING while the centre of mass is
--    still over the support (cos < 0) and DRIVING once it is past (cos > 0), so a
--    block nudged to the edge leans and comes back while a block pushed past goes
--    over slowly and then faster. The old code kicked va to a flat 0.7 rad/s and
--    added a constant 7 rad/s^2, so EVERY topple took the same 28 frames whatever
--    the overhang was, and a block could never settle back.
--  * TORQUE FROM IMPACT. A ZIP disk hitting a 12x70 pole near the top used to move
--    it five pixels sideways and leave it standing, because a body on the ground
--    was exempt from the support test and its spin was damped to nothing. An
--    off-centre impulse now becomes angular momentum about the base corner and the
--    pole goes over.
--  * MOMENTUM OUT OF A TOPPLE. A toppling beam used to stop dead against its
--    neighbour; it now hands its contact-point momentum on, which is what makes a
--    stack come down as a stack instead of as separate pieces.

local VCAP   = 1000        -- px/s. Also the tunnelling bound, with the substepper
local SUBPX  = 5.0         -- px of travel allowed per substep
local MAXSUB = 3
local ITER   = 3           -- impulse iterations; simultaneous contacts need > 1
local SLOP   = 0.30        -- penetration we simply allow (px)
local BIAS   = 0.60        -- fraction of the excess corrected per substep
local MAXCOR = 4.0         -- px of position correction per substep
local RESTV  = 46          -- closing speed under which restitution is zero
local SLEEPV = 15          -- px/s
local CREEPV = 26          -- px/s of downward drift a supported body just stops
local SLEEPW = 0.20        -- rad/s
local SLEEPT = 0.26        -- seconds under both before a body sleeps
local WAKEJ  = 24          -- contact impulse that wakes a sleeping neighbour
local IMPACTV= 60          -- px/s of CLOSING speed before a contact counts as a hit
local DMGJ   = 145         -- impulse per point of crush damage
local PIVDMP = 1.0         -- rotational friction at the pivot corner (1/s)
local TIPMIN = 0.22        -- rad/s of spin worth testing a topple for
local TIPFRAC= 0.42        -- fraction of the tipping barrier that starts a lean
local GCELL  = 64

-- preallocated pools: nothing below this line allocates per frame
local AW, nAW = {}, 0
local CT, nCT = {}, 0
for i = 1, 192 do
  CT[i] = { a = 0, b = 0, nx = 0, ny = 0, pen = 0, e = 0, mu = 0, j = 0, px = 0, py = 0 }
end
-- kom.boxstep's damage events, 7 numbers each, reused every frame. A field on CT and
-- not a new local, for the 200-local ceiling.
CT.ev = { n = 0 }
local GRID, GN = {}, 1
for i = 1, 20 do GRID[i] = { n = 0 } end
local PA, PB, nPR = {}, {}, 0     -- broadphase pairs, as two flat index arrays

function wake_body(b)
  if b.dead then return end
  if not b.loose then b.loose = true; chk_t = 0.7 end
  b.rest_t = 0
end

-- An impulse (jx,jy) landing at (px,py) is angular momentum about the bottom
-- CORNER the impulse pushes toward: tau = rx*Fy - ry*Fx with +y down, so a
-- rightward push above the base turns the body clockwise. Mass cancels out of
-- alpha but NOT out of an impulse, hence the 1/(m*(k^2+r^2)).
function tip_impulse(b, jx, jy, px, py)
  if b.dead or b.piv then return end
  local dir = (jx >= 0) and 1 or -1
  local pvx = (dir > 0) and (b.x + b.w) or b.x
  local pvy = b.y + b.h
  local cx, cy = b.x + b.w * 0.5, b.y + b.h * 0.5
  local dx, dy = cx - pvx, cy - pvy
  local r2 = dx * dx + dy * dy
  local L = (px - pvx) * jy - (py - pvy) * jx
  b.va = b.va + L / (b.mass * (b.k2 + r2))
  if b.va > 7 then b.va = 7 elseif b.va < -7 then b.va = -7 end
end

-- Can this body get its centre of mass up over the corner it would turn on? The
-- barrier is the RISE of the centre of mass to the top of the arc; a tall thin
-- pole barely has to lift its centre at all and a flat slab has to lift it half
-- its own width, which is why one topples and the other does not, with no special
-- case written for either.
local function try_pivot(a, dir, pvx, pvy)
  pvx = pvx or ((dir > 0) and (a.x + a.w) or a.x)
  pvy = pvy or (a.y + a.h)
  local cx, cy = a.x + a.w * 0.5, a.y + a.h * 0.5
  local dx, dy = cx - pvx, cy - pvy
  local r = math.sqrt(dx * dx + dy * dy)
  if r < 0.5 then return false end
  -- The barrier is the RISE of the centre of mass to the top of the arc. If the
  -- centre is ALREADY past the corner in the tipping direction there is no
  -- barrier at all: gravity is on the tipping side from the first frame, which is
  -- exactly the overhang case, and it starts from a standing va of zero.
  local barrier = 0
  if dx * dir <= 0 then
    barrier = BGRAV * (r + dy)                   -- dy is negative: rise = r - |dy|
    if barrier < 0 then barrier = 0 end
  end
  local ke = 0.5 * (a.k2 + r * r) * a.va * a.va
  if ke < barrier * TIPFRAC then return false end
  a.piv    = true
  a.piv_x, a.piv_y = pvx, pvy
  a.piv_r  = r
  a.piv_th = math.atan(dy, dx)
  a.piv_t0 = a.piv_th
  a.piv_a0 = a.ang
  a.piv_d  = dir
  a.piv_n  = 0
  a.piv_b  = nil
  local c0 = math.floor((pvx - 92) / GCELL) + 1
  local c1 = math.floor(pvx / GCELL) + 1
  if c0 < 1 then c0 = 1 end
  if c1 > GN then c1 = GN end
  for c = c0, c1 do                              -- what it turns ON, so the swept
    local g = GRID[c]                            -- test can ignore it
    for gi = 1, g.n do
      local b = bodies[g[gi]]
      if b ~= a and not b.dead then
        local gap = b.y - pvy
        if gap <= 3 and gap >= -4 and b.x - 2 <= pvx and pvx <= b.x + b.w + 2 then
          a.piv_b = b; break
        end
      end
    end
    if a.piv_b then break end
  end
  a.vx, a.vy, a.rest_t = 0, 0, 0
  return true
end

-- A BOX TURNED A QUARTER TURN *IS* THE BOX WITH W AND H SWAPPED, drawn at an
-- angle a quarter turn smaller -- the same pixels either way, so committing the
-- turn is invisible. It has to be committed, because the collision box is axis
-- aligned: a pole that has gone over is LYING DOWN, and if the box stays upright
-- the body keeps finding its own base corner under itself and re-enters the pivot
-- for ever. That is exactly what it did -- the trace showed a pole re-pivoting
-- every single frame, sliding sideways instead of falling.
local function normalise_box(a)
  for _ = 1, 3 do
    if a.ang < 1.4 and a.ang > -1.4 then break end
    local sgn = (a.ang > 0) and 1 or -1
    local cx, cy = a.x + a.w * 0.5, a.y + a.h * 0.5
    a.w, a.h = a.h, a.w
    a.x, a.y = cx - a.w * 0.5, cy - a.h * 0.5
    a.ang = a.ang - sgn * 1.5708
  end
end

-- Hand a swinging body over to free fall with the linear velocity its centre
-- actually has: v = omega x r.
local function pivot_release(a)
  local th, r = a.piv_th, a.piv_r
  a.vx = a.vx - math.sin(th) * r * a.va
  a.vy = a.vy + math.cos(th) * r * a.va
  a.piv = nil
  a.piv_cd = 0.14                -- no re-entry for a moment, or it never lands
  a.rest_t = 0
  normalise_box(a)
end

local function pivot_step(a, dt)
  local r  = a.piv_r
  local th = a.piv_th
  a.va = a.va + BGRAV * r * math.cos(th) / (a.k2 + r * r) * dt
  a.va = a.va - a.va * PIVDMP * dt
  if a.va > 7 then a.va = 7 elseif a.va < -7 then a.va = -7 end
  th = th + a.va * dt
  a.piv_th = th
  a.ang = a.piv_a0 + (th - a.piv_t0)
  local cx = a.piv_x + math.cos(th) * r
  local cy = a.piv_y + math.sin(th) * r
  a.x, a.y = cx - a.w * 0.5, cy - a.h * 0.5

  -- it came back past where it started, and slowly: that was a LEAN, not a topple
  if (th - a.piv_t0) * a.piv_d <= 0 and a.va * a.piv_d <= 0 then
    a.piv_th = a.piv_t0
    a.ang = a.piv_a0
    local c2x = a.piv_x + math.cos(a.piv_t0) * r
    local c2y = a.piv_y + math.sin(a.piv_t0) * r
    a.x, a.y = c2x - a.w * 0.5, c2y - a.h * 0.5
    a.va, a.vx, a.vy = 0, 0, 0
    a.piv = nil
    return
  end
  -- Release on the CENTRE OF MASS reaching the floor, never on the axis-aligned
  -- box bottom: a body pivoting on a ground corner has its box bottom on the
  -- floor for the whole swing, so that test fired on the first frame, every
  -- frame, and the pole never actually went anywhere.
  if a.ang - a.piv_a0 > 1.50 or a.piv_a0 - a.ang > 1.50 or cy >= GY - 1
     or (a.piv_b and a.piv_b.dead) then
    pivot_release(a); return
  end
  -- what it swings INTO takes the momentum. This is the domino: without it a
  -- toppling beam simply stopped against its neighbour, and the tower came apart
  -- into pieces that each fell on their own.
  local mvx = -math.sin(th) * r * a.va
  local mvy =  math.cos(th) * r * a.va
  local q0 = math.floor((a.x - 92) / GCELL) + 1
  local q1 = math.floor((a.x + a.w) / GCELL) + 1
  if q0 < 1 then q0 = 1 end
  if q1 > GN then q1 = GN end
  for qc = q0, q1 do
   local gg = GRID[qc]
   for gj = 1, gg.n do
    local b = bodies[gg[gj]]
    if b ~= a and b ~= a.piv_b and not b.dead
       and a.x < b.x + b.w - 1.5 and b.x < a.x + a.w - 1.5
       and a.y < b.y + b.h - 1.5 and b.y < a.y + a.h - 1.5 then
      local jx = a.mass * mvx * 0.72
      local jy = a.mass * mvy * 0.72
      local hx = (a.x + a.w * 0.5 + b.x + b.w * 0.5) * 0.5
      local hy = (a.y + a.h * 0.5 + b.y + b.h * 0.5) * 0.5
      wake_body(b)
      b.vx = b.vx + jx * b.inv_m
      b.vy = b.vy + jy * b.inv_m
      tip_impulse(b, jx, jy, hx, hy)
      local jm = math.sqrt(jx * jx + jy * jy)
      local d = math.floor(jm / DMGJ)
      if d > 0 then
        if b.t then d = d + 1 end
        hurt_body(b, d)
        hurt_body(a, math.floor(d * 0.4))
      end
      -- The reaction is the SAME impulse the other way, about this body's own
      -- pivot -- not a flat 0.55 haircut on va. With the haircut a domino gave
      -- away most of its swing on the first touch and stood back up; conserving
      -- it is what lets the first one keep going over while the second starts.
      local Lr = (hx - a.piv_x) * jy - (hy - a.piv_y) * jx
      a.va = a.va - Lr / (a.mass * (a.k2 + r * r))
      -- a victim that is AWAKE is getting out of the way; only something that
      -- refuses to move counts as a wall worth giving up against
      if not b.loose then a.piv_n = a.piv_n + 3 else a.piv_n = a.piv_n + 1 end
      if a.piv_n > 11 or a.dead then pivot_release(a) end
      return
    end
   end
  end
end

-- ---- support -------------------------------------------------------------------
-- SUPPORT IS A CENTRE-OF-MASS TEST, and it runs round-robin.
--
-- The first version accepted any single supporter, so a slab whose left post had
-- been knocked out went on hanging in the air off the right one. A beam is stable
-- only while its centre sits over the SPAN of what is holding it up; outside that
-- it tips toward the overhang, which is the whole appeal of knocking a leg away.
--
-- Round-robin because the answer only changes when something breaks: a fixed slice
-- of the bodies each frame is flat, bounded work (no 54x54 spike on the frame a
-- sector loads) and a collapse still propagates upward within a few frames, which
-- at 60Hz nobody can see. Bodies already on the ground are skipped: their own
-- footprint is their support, so gravity alone can never tip one -- only an impact
-- can, and that arrives through tip_impulse.
local check_i = 0

local function support_step(n)
  -- NATIVE (V1078): the same round-robin in boxphys.c, which also owns the grid that
  -- try_pivot reads, so the two paths can never consult different grids.
  if opts.native and kom.boxsupport then
    local chk = kom.boxsupport(bodies, n, GY, worldW)
    if chk ~= nil then
      if chk then chk_t = 0.7 end
      return
    end
  end
  local nb = #bodies
  if nb == 0 then return end
  for _ = 1, n do
    check_i = check_i + 1
    if check_i > nb then check_i = 1 end
    local a = bodies[check_i]
    if not a.dead and not a.loose and a.y + a.h < GY - 1 then
      local ab = a.y + a.h
      local l, r, found = 1e9, -1e9, false
      for j = 1, nb do
        local b = bodies[j]
        if b ~= a and not b.dead and not b.loose then
          local gap = b.y - ab
          if gap <= 3 and gap >= -4 then
            local ol = (a.x > b.x) and a.x or b.x
            local orr = (a.x + a.w < b.x + b.w) and (a.x + a.w) or (b.x + b.w)
            if orr - ol > 1 then
              found = true
              if ol < l then l = ol end
              if orr > r then r = orr end
            end
          end
        end
      end
      local cx = a.x + a.w / 2
      local tol = a.w * 0.20
      if tol > 3.5 then tol = 3.5 end
      if not found then
        wake_body(a)
        a.piv = nil
      elseif cx < l - tol or cx > r + tol then
        -- IT TOPPLES ABOUT THE EDGE IT IS STILL ON, from a standing start. The
        -- gravity torque is already positive there (the centre of mass is past the
        -- corner) so it accelerates on its own -- no kick, and the further past it
        -- is, the faster it goes.
        wake_body(a)
        a.va = 0
        local dir = (cx < l) and -1 or 1
        if not try_pivot(a, dir, (dir < 0) and l or r, a.y + a.h) then
          a.va = dir * 0.6                       -- barrier too high: it just slumps
        end
        a.tip = 1.0
      end
    end
  end
end

-- ---- broadphase ------------------------------------------------------------------
-- One uniform 64px grid, rebuilt once a frame and reused across the substeps.
-- Sector 12 has 52 bodies; testing every awake body against all of them, three
-- substeps deep, is thousands of pair tests on a collapse frame. Bucketed it is a
-- few hundred, and the rebuild is 52 stores.
local function grid_build()
  GN = math.floor(worldW / GCELL) + 2
  if GN > 20 then GN = 20 elseif GN < 1 then GN = 1 end
  for c = 1, GN do GRID[c].n = 0 end
  for i = 1, #bodies do
    local b = bodies[i]
    if not b.dead then
      local c = math.floor(b.x / GCELL) + 1
      if c < 1 then c = 1 elseif c > GN then c = GN end
      local g = GRID[c]
      local n = g.n + 1
      g.n = n; g[n] = i
    end
  end
end

local function ct_add(ia, ib, nx, ny, pen, e, mu, px, py)
  if nCT >= 192 then return end
  nCT = nCT + 1
  local c = CT[nCT]
  c.a, c.b, c.nx, c.ny, c.pen = ia, ib, nx, ny, pen
  c.e, c.mu, c.j, c.px, c.py = e, mu, 0, px, py
  c.vn0 = 0
end

-- BROADPHASE ONCE A FRAME, NARROWPHASE PER SUBSTEP. Walking the grid once per
-- substep was the biggest single line in the collapse spike; nothing moves more
-- than about 20px in a frame, so a pair list built once with that much margin is
-- the same set of pairs, found at a third of the price.
local PMARGIN = 24

local function broadphase()
  nPR = 0
  for k = 1, nAW do
    local ia = AW[k]
    local a = bodies[ia]
    if not a.dead then
      local ax0, ax1 = a.x - PMARGIN, a.x + a.w + PMARGIN
      local ay0, ay1 = a.y - PMARGIN, a.y + a.h + PMARGIN
      local c0 = math.floor((ax0 - 88) / GCELL) + 1
      local c1 = math.floor(ax1 / GCELL) + 1
      if c0 < 1 then c0 = 1 end
      if c1 > GN then c1 = GN end
      for c = c0, c1 do
        local g = GRID[c]
        for gi = 1, g.n do
          local ib = g[gi]
          -- an awake PAIR is listed once, from the lower index
          if ib ~= ia then
            local b = bodies[ib]
            if not b.dead and (not b.loose or ib > ia)
               and ax0 < b.x + b.w and b.x < ax1
               and ay0 < b.y + b.h and b.y < ay1 then
              nPR = nPR + 1; PA[nPR] = ia; PB[nPR] = ib
            end
          end
        end
      end
    end
  end
end

local function contacts_build()
  nCT = 0
  for k = 1, nAW do
    local ia = AW[k]
    local a = bodies[ia]
    if not a.dead and a.loose and not a.piv then
      if a.y + a.h > GY then
        ct_add(ia, 0, 0, -1, a.y + a.h - GY, a.e, a.mu, a.x + a.w * 0.5, GY)
        a.sup = true
      end
      if a.x < 0 then ct_add(ia, 0, 1, 0, -a.x, a.e, a.mu, 0, a.y + a.h * 0.5) end
      if a.x + a.w > worldW then
        ct_add(ia, 0, -1, 0, a.x + a.w - worldW, a.e, a.mu, worldW, a.y + a.h * 0.5)
      end
    end
  end
  for k = 1, nPR do
    local ia, ib = PA[k], PB[k]
    local a, b = bodies[ia], bodies[ib]
    if not a.dead and not b.dead and not a.piv and not b.piv and (a.loose or b.loose) then
      local r1, r2 = a.x + a.w, b.x + b.w
      local xl = (a.x > b.x) and a.x or b.x
      local xr = (r1 < r2) and r1 or r2
      local ox = xr - xl
      if ox > 0 then
        local t1, t2 = a.y + a.h, b.y + b.h
        local yt = (a.y > b.y) and a.y or b.y
        local yb = (t1 < t2) and t1 or t2
        local oy = yb - yt
        if oy > 0 then
          local e = (a.e < b.e) and a.e or b.e
          local mu = (a.mu + b.mu) * 0.5
          local px, py = (xl + xr) * 0.5, (yt + yb) * 0.5
          if ox < oy then
            ct_add(ia, ib, (a.x + a.w * 0.5 < b.x + b.w * 0.5) and -1 or 1, 0, ox, e, mu, px, py)
          else
            local sgn = (a.y + a.h * 0.5 < b.y + b.h * 0.5) and -1 or 1
            ct_add(ia, ib, 0, sgn, oy, e, mu, px, py)
            if sgn < 0 then a.sup = true else b.sup = true end
          end
        end
      end
    end
  end
end

local function contacts_solve()
  for it = 1, ITER do
    local changed = false
    for k = 1, nCT do
      local c = CT[k]
      local a = bodies[c.a]
      local b = (c.b ~= 0) and bodies[c.b] or nil
      local nx, ny = c.nx, c.ny
      local bvx, bvy, imb = 0, 0, 0
      if b then
        bvx, bvy = b.vx, b.vy
        if b.loose then imb = b.inv_m end
      end
      local vn = (a.vx - bvx) * nx + (a.vy - bvy) * ny
      if it == 1 then c.vn0 = vn end
      if vn < 0 then
        local ima = a.inv_m
        local kk = ima + imb
        if kk > 0 then
          changed = true
          local e = c.e
          if -vn < RESTV then e = 0 end
          local jn = -(1 + e) * vn / kk
          c.j = c.j + jn
          a.vx = a.vx + jn * nx * ima
          a.vy = a.vy + jn * ny * ima
          if imb > 0 then
            b.vx = b.vx - jn * nx * imb
            b.vy = b.vy - jn * ny * imb
          end
          local tx, ty = -ny, nx
          local vt = (a.vx - bvx) * tx + (a.vy - bvy) * ty
          local jt = -vt / kk
          local lim = c.mu * jn
          if jt > lim then jt = lim elseif jt < -lim then jt = -lim end
          a.vx = a.vx + jt * tx * ima
          a.vy = a.vy + jt * ty * ima
          if imb > 0 then
            b.vx = b.vx - jt * tx * imb
            b.vy = b.vy - jt * ty * imb
          end
        end
      end
    end
    -- An impulse-free pass leaves every velocity unchanged. Subsequent passes
    -- would test exactly the same contacts; vn0 was already recorded on pass 1.
    if not changed then break end
  end
end

-- Position is corrected with a BIAS and a SLOP, never by teleporting the box out
-- of the overlap. A full correction every frame is what made a settled pile hum:
-- the push and the bounce fed each other and the stack never stopped moving.
local function contacts_correct()
  for k = 1, nCT do
    local c = CT[k]
    local pen = c.pen - SLOP
    if pen > 0 then
      local a = bodies[c.a]
      local b = (c.b ~= 0) and bodies[c.b] or nil
      local ima = a.inv_m
      local imb = (b and b.loose) and b.inv_m or 0
      local kk = ima + imb
      if kk > 0 then
        if pen > a.pen then a.pen = pen end
        if b and pen > b.pen then b.pen = pen end
        local p = BIAS * pen
        if p > MAXCOR then p = MAXCOR end
        p = p / kk
        a.x = a.x + p * c.nx * ima
        a.y = a.y + p * c.ny * ima
        if imb > 0 then
          b.x = b.x - p * c.nx * imb
          b.y = b.y - p * c.ny * imb
        end
      end
    end
  end
end

-- DAMAGE COMES OFF THE IMPULSE, not off a speed. A heavy slab arriving slowly
-- carries more momentum than a light chip arriving fast and it should be the one
-- that crushes; the old rule gated on vy > 150 and let a light fast block out-hit
-- a slab settling onto a hut.
local function contacts_react()
  for k = 1, nCT do
    local c = CT[k]
    local j = c.j
    -- an IMPACT, not the weight of a stack being carried
    if j > WAKEJ and c.vn0 < -IMPACTV then
      local a = bodies[c.a]
      local b = (c.b ~= 0) and bodies[c.b] or nil
      local d = math.floor(j / DMGJ)
      if b then
        if not b.loose and j > WAKEJ * 1.6 then wake_body(b) end
        tip_impulse(b, -c.nx * j, -c.ny * j, c.px, c.py)
        tip_impulse(a,  c.nx * j,  c.ny * j, c.px, c.py)
        if d > 0 then
          hurt_body(b, b.t and (d + 1) or d)
          hurt_body(a, math.floor(d * 0.5))
        end
      else
        tip_impulse(a, c.nx * j, c.ny * j, c.px, c.py)
        if d > 1 then hurt_body(a, d - 1) end
      end
    end
  end
end

local function sleep_body(a)
  a.loose = false
  a.vx, a.vy, a.va, a.rest_t = 0, 0, 0, 0
  a.piv = nil
  -- THE BOX THAT COLLIDES IS THE BOX THAT IS DRAWN: a body that came to rest on
  -- its end swaps w/h, but only into space nothing else is using.
  local q = math.floor(a.ang / 1.5708 + 0.5)
  if q % 2 ~= 0 and math.abs(a.w - a.h) > 5 then
    local cx2, cy2 = a.x + a.w / 2, a.y + a.h / 2
    local nw, nh = a.h, a.w
    local nx, ny = cx2 - nw / 2, cy2 - nh / 2
    if ny + nh > GY then ny = GY - nh end
    local clear = (nx >= 0 and nx + nw <= worldW)
    if clear then
      for j = 1, #bodies do
        local b = bodies[j]
        if b ~= a and not b.dead
           and nx < b.x + b.w - 1 and b.x < nx + nw - 1
           and ny < b.y + b.h - 1 and b.y < ny + nh - 1 then
          clear = false; break
        end
      end
    end
    if clear then a.w, a.h, a.x, a.y = nw, nh, nx, ny end
  end
  a.ang = 0
  chk_t = 0.7
end

local function step_bodies(dt)
  -- NATIVE (V1078): this whole function, in boxphys.c, bit-identical
  -- (tools/boxphys/run_parity.sh). Damage is applied inside the step; its effects
  -- replay here, in order, from where each body was when it was hit.
  if opts.native and kom.boxstep then
    local ev = CT.ev
    local mv, chk = kom.boxstep(bodies, dt, GY, worldW, ev)
    if mv ~= nil then
      moving = mv
      if chk then chk_t = 0.7 end
      for k = 0, ev.n - 1 do
        local o = k * 7
        local b = bodies[ev[o + 1]]
        hurt_fx(b, ev[o + 2], ev[o + 3], ev[o + 4], ev[o + 5])
        if ev[o + 7] == 1 then destroy_fx(b, ev[o + 3], ev[o + 4], ev[o + 5], ev[o + 6]) end
      end
      return
    end
  end
  moving = false
  -- THE AWAKE LIST IS THE WHOLE POINT: a settled sector walks it and finds it
  -- empty, so a world at rest costs one pass over #bodies and nothing else.
  nAW = 0
  local vmax = 0
  for i = 1, #bodies do
    local a = bodies[i]
    if not a.dead then
      if a.flash > 0 then a.flash = a.flash - dt end
      if a.loose then
        nAW = nAW + 1; AW[nAW] = i
        local sp
        if a.piv then sp = math.abs(a.va) * a.piv_r
        else
          sp = math.abs(a.vx)
          local sy = math.abs(a.vy)
          if sy > sp then sp = sy end
        end
        if sp > vmax then vmax = sp end
      end
    end
  end
  if nAW == 0 then return end

  grid_build()
  broadphase()
  local nsub = math.floor(vmax * dt / SUBPX) + 1
  if nsub > MAXSUB then nsub = MAXSUB end
  local sdt = dt / nsub

  for _ = 1, nsub do
    for k = 1, nAW do
      local a = bodies[AW[k]]
      if not a.dead and a.loose then
        if a.piv then
          pivot_step(a, sdt)
        else
          a.vy = a.vy + BGRAV * sdt
          if a.vx > VCAP then a.vx = VCAP elseif a.vx < -VCAP then a.vx = -VCAP end
          if a.vy > VCAP then a.vy = VCAP elseif a.vy < -VCAP then a.vy = -VCAP end
          a.x = a.x + a.vx * sdt
          a.y = a.y + a.vy * sdt
          a.ang = a.ang + a.va * sdt
          a.sup = false
          a.pen = 0
        end
      end
    end
    contacts_build()
    contacts_solve()
    contacts_correct()
    contacts_react()
    -- rest, topple or damp: one pass, after the contacts are known
    for k = 1, nAW do
      local a = bodies[AW[k]]
      if not a.dead and a.loose and not a.piv then
        if a.sup then
          local vv = a.va
          if (vv > TIPMIN or vv < -TIPMIN) and (not a.piv_cd or a.piv_cd <= 0)
             and try_pivot(a, (vv > 0) and 1 or -1) then
            a.tip = 1.0
          else
            a.va = a.va - a.va * 5.0 * sdt          -- rotational friction on contact
            local q = math.floor(a.ang / 1.5708 + 0.5) * 1.5708
            local t = 9 * sdt
            a.ang = a.ang + (q - a.ang) * ((t < 1) and t or 1)
          end
        end
        if not a.piv then
          if a.sup and a.vy > 0 and a.vy < CREEPV then a.vy = 0 end
          if a.sup and a.pen < 2.6 and a.vx * a.vx + a.vy * a.vy < SLEEPV * SLEEPV
             and a.va < SLEEPW and a.va > -SLEEPW then
            a.rest_t = a.rest_t + sdt
            if a.rest_t > SLEEPT then sleep_body(a) end
          else
            a.rest_t = 0
          end
        end
      end
    end
  end

  -- who is STILL awake after the step is what "the world is moving" means now
  local live = 0
  for k = 1, nAW do
    local a = bodies[AW[k]]
    if a.tip > 0 then a.tip = a.tip - dt end
    if a.piv_cd and a.piv_cd > 0 then a.piv_cd = a.piv_cd - dt end
    if not a.dead and a.loose then live = live + 1 end
  end
  nAW = live
  if live > 0 then moving = true end
end

-- ---- physics: the shot -------------------------------------------------------
local function hit_fx(s, b, sp)
  local col = b.t and b.t.cl or b.m.cl
  bits_at(s.x, s.y, (sp > 320) and 5 or 3, col, 90)
  if sp > 260 then shake(3, 0.14) end
  local f = 260 + (b.t and 180 or (b.m.hp * 34))
  if title_t >= audio_at.hit then
    audio_at.hit = title_t + 0.055
    snd(f, 55, 0, math.min(60, 20 + sp / 12))
  end
end

local function step_shot(s, dt)
  if s.stuck then                               -- USB STICK plugged in, fusing
    local b = s.stuck
    if b.dead then s.stuck = nil
    else s.x, s.y = b.x + b.w / 2 + s.sox, b.y + b.h / 2 + s.soy end
    s.fuse = s.fuse - dt
    s.blink = (math.floor(s.fuse * 12) % 2 == 0)
    if s.fuse <= 0 then blast(s.x, s.y, 52, 9); s.dead = true end
    return
  end

  s.vy = s.vy + GRAV * dt
  local speed = math.sqrt(s.vx * s.vx + s.vy * s.vy)
  local n = 1 + math.floor(speed * dt / 4)
  if n > 4 then n = 4 end
  local sdt = dt / n

  for _ = 1, n do
    s.x = s.x + s.vx * sdt
    s.y = s.y + s.vy * sdt
    s.spin = s.spin + (s.vx * 0.020 + 2.5) * sdt

    if s.y + s.r > GY then
      s.y = GY - s.r
      if s.vy > 170 then bits_at(s.x, GY - 2, 3, TH.bit, 70); snd(320, 55, 3, 30) end
      s.vy = -s.vy * 0.30; s.vx = s.vx * 0.74
      if math.abs(s.vy) < 60 then s.vy = 0 end
    end

    for i = 1, #bodies do
      local b = bodies[i]
      if not b.dead then
        local cx = math.max(b.x, math.min(s.x, b.x + b.w))
        local cy = math.max(b.y, math.min(s.y, b.y + b.h))
        local dx, dy = s.x - cx, s.y - cy
        local d2 = dx * dx + dy * dy
        if d2 < s.r * s.r then
          local d = math.sqrt(d2)
          local nx, ny
          if d > 0.5 then nx, ny = dx / d, dy / d
          else
            local l, r2 = s.x - b.x, b.x + b.w - s.x
            local t2, bo = s.y - b.y, b.y + b.h - s.y
            local mn = math.min(l, r2, t2, bo)
            if mn == l then nx, ny = -1, 0
            elseif mn == r2 then nx, ny = 1, 0
            elseif mn == t2 then nx, ny = 0, -1
            else nx, ny = 0, 1 end
            d = 0
          end
          local sp = math.sqrt(s.vx * s.vx + s.vy * s.vy)

          if s.sticky then                       -- INJECT armed: plug in and fuse
            s.stuck = b; s.sox = s.x - (b.x + b.w / 2); s.soy = s.y - (b.y + b.h / 2)
            s.fuse = 0.80; s.vx, s.vy = 0, 0; s.sticky = false
            snd(1180, 70, 0, 42); snd(1560, 50, 1, 34)
            return
          end

          hit_fx(s, b, sp)
          hurt_body(b, math.floor(sp * s.mass / 105))
          if not b.dead then
            b.piv = nil; wake_body(b)
            local jx = s.vx * 0.30 * s.mass
            local jy = s.vy * 0.20 * s.mass
            b.vx = b.vx + jx / b.mass
            b.vy = b.vy + jy / b.mass
            -- WHERE it lands decides whether the block slides or goes over. A ZIP
            -- disk into the top of a pole used to shove it five pixels sideways
            -- and leave it standing, because the spin was a random number that the
            -- ground contact then damped away.
            tip_impulse(b, jx, jy, cx, cy)
          end
          s.x = s.x + nx * (s.r - d + 0.5)
          s.y = s.y + ny * (s.r - d + 0.5)
          local vn = s.vx * nx + s.vy * ny
          s.vx = (s.vx - 1.34 * vn * nx) * 0.66
          s.vy = (s.vy - 1.34 * vn * ny) * 0.66
          s.hits = s.hits + 1
          if s.hits > 9 then s.dead = true end
          break
        end
      end
    end
    if s.dead then return end
  end

  s.life = s.life + dt
  if s.x < -24 or s.x > worldW + 24 or s.life > 10 then s.dead = true end
  if math.abs(s.vx) < 16 and math.abs(s.vy) < 34 and s.y + s.r >= GY - 1.5 then
    s.rest = s.rest + dt
    if s.rest > 0.55 then s.dead = true end
  else
    s.rest = 0
  end
  s.tt = s.tt + dt
  if s.tt > 0.035 then
    s.tt = 0
    s.trail[#s.trail + 1] = { s.x, s.y }
    if #s.trail > 9 then table.remove(s.trail, 1) end
    -- the aim ghost used to allocate a two-slot table EVERY FRAME of every
    -- flight; it is a pair of flat arrays with a count now
    local gn = ghost.n or 0
    if not s.shard and gn < 30 then
      gn = gn + 1; ghost.n = gn; ghost.x[gn] = s.x; ghost.y[gn] = s.y
    end
    if s.spool then part("bit", s.x, s.y, -s.vx * 0.05, 20, 0.5, TH.bit, "1") end
  end
end

-- ---- abilities: one per medium, fired mid-flight with X ----------------------
local function use_ability(s)
  if s.used or not s.m.ab then return end
  s.used = true
  local ab = s.m.ab
  if ab == "split" then
    local sp = math.sqrt(s.vx * s.vx + s.vy * s.vy) * 0.94
    local a = math.atan(s.vy, s.vx)
    for _, d in ipairs({ -0.32, 0.32 }) do
      shots[#shots + 1] = { x = s.x, y = s.y, vx = math.cos(a + d) * sp,
        vy = math.sin(a + d) * sp, r = 6, m = s.m, mass = 0.62, spin = s.spin,
        life = 0, hits = 0, rest = 0, tt = 0, used = true, shard = true, trail = {} }
    end
    s.mass, s.r, s.shard = 0.62, 6, true
    bits_at(s.x, s.y, 6, TH.bit, 120)
    snd(940, 70, 1, 55, 1500); snd(1320, 60, 1, 38)
  elseif ab == "slam" then
    s.vy = s.vy + 400; s.vx = s.vx * 1.10; s.mass = 2.7
    bits_at(s.x, s.y, 5, TH.bit, 80)
    snd(260, 130, 4, 66, 210); snd(420, 90, 0, 40)
  elseif ab == "spool" then
    s.vx = s.vx * 1.85; s.vy = s.vy * 0.28; s.mass = 1.05; s.spool = true
    snd(700, 120, 4, 50, 1500); snd(1400, 70, 1, 34)
  elseif ab == "demag" then
    blast(s.x, s.y, 62, 10); s.dead = true
  elseif ab == "inject" then
    s.sticky = true; s.vx = s.vx * 1.15
    snd(1500, 60, 1, 40, 900)
  end
end

-- ---- level start -------------------------------------------------------------
local peek = 0
local BANNER_T = 2.6            -- how long the sector plate holds

function start_level(n)
  audio_at.kill, audio_at.debris, audio_at.hit, audio_at.blast = 0, 0, 0, 0
  lvl = n; LV = LEVELS[n]
  th = THEMES[LV.era]; TH = pack_theme(th); worldW = LV.w
  bodies, shots = {}, {}
  parts = parts or {}; parts.n = 0        -- keep the pool, drop the live count
  local bl, tl = {}, {}
  LV.build(bl, tl)
  level_total, left = 0, 0
  for _, s in ipairs(bl) do
    local m = MAT[s.m]
    local mass = (s.w * s.h) * m.dens / 460 + m.hp * 0.18
    bodies[#bodies + 1] = { x = s.x, y = s.y, w = s.w, h = s.h, m = m,
      hp = m.hp, mhp = m.hp, vx = 0, vy = 0, ang = 0, va = 0, loose = false,
      rest_t = 0, flash = 0, tip = 0, piv = nil, sup = false, pen = 0,
      mass = mass, inv_m = 1 / mass, e = m.e, mu = m.mu,
      -- k2 is the radius of gyration SQUARED, (w^2+h^2)/12: the real moment of
      -- inertia with the mass divided out, which is all the pivot needs. It is
      -- symmetric in w and h, so a body that comes to rest on its end keeps it.
      k2 = (s.w * s.w + s.h * s.h) / 12 }
    level_total = level_total + m.kb
  end
  for _, s in ipairs(tl) do
    local k = TGT[s.k]
    local tmass = 0.85 + k.hp * 0.12
    bodies[#bodies + 1] = { x = s.x, y = s.y, w = 20, h = 24, t = k,
      hp = k.hp, mhp = k.hp, vx = 0, vy = 0, ang = 0, va = 0, loose = false,
      rest_t = 0, flash = 0, tip = 0, piv = nil, sup = false, pen = 0,
      mass = tmass, inv_m = 1 / tmass, e = 0.24, mu = 0.95,
      k2 = (20 * 20 + 24 * 24) / 12,
      bob = math.random() * 6.28 }
    level_total = level_total + k.kb
    left = left + 1
  end
  ammo = {}
  for i, a in ipairs(LV.ammo) do ammo[i] = a end
  ammo_i, score, shown, bonus, stars_got = 1, 0, 0, 0, 0
  ghost = ghost or { x = {}, y = {} }; ghost.n = 0
  star2 = math.floor(level_total * 0.45)
  star3 = math.floor(level_total * 0.72)
  aim_a, aim_p, tick_t = 0.72, 0.70, 0
  camx = math.max(0, worldW - W); camtx = camx
  intro_t, peek = 1.25, 0
  shake_t, shake_m = 0, 0
  settle_t, turn_t, moving = 0, 0, false
  chk_t = 1.1
  banner, banner_t = LV.name, BANNER_T

  props = {}
  local x = 14
  while x < worldW do
    props[#props + 1] = { k = math.random(1, 3), x = x, w = math.random(26, 58),
      h = math.random(14, 30), r = math.random(5, 8), n = math.random(3, 6) }
    x = x + math.random(54, 106)
  end
  dbits = {}
  for i = 1, 18 do
    dbits[i] = { x = math.random() * worldW, y = 8 + math.random() * (GY - 60),
                 b = math.random(0, 1), s = 6 + math.random() * 16 }
  end
  state = "intro"
end

-- ---- turn flow ---------------------------------------------------------------
-- ONE launch equation. The aim guide and the shot have to agree exactly or the
-- dots are a lie, so neither of them owns a copy of these numbers.
local function launch_v()
  local sp = 200 + aim_p * 420
  return math.cos(aim_a) * sp, -math.sin(aim_a) * sp
end

local function fire()
  local med = MED[ammo[ammo_i]]
  local ca, sa = math.cos(aim_a), math.sin(aim_a)
  local vx, vy = launch_v()
  shots = { { x = SX + ca * 11, y = SY - sa * 11, vx = vx, vy = vy,
    r = med.r, m = med, mass = med.mass, spin = 0, life = 0, hits = 0,
    rest = 0, tt = 0, used = false, trail = {} } }
  state = "fly"; turn_t = 0; peek = 0
  ghost = ghost or { x = {}, y = {} }; ghost.n = 0
  snd(330, 95, 4, 58, 840); snd(900, 55, 1, 38)
end

function next_turn()
  if left <= 0 then
    bonus = (#ammo - ammo_i) * math.max(16, math.floor(level_total * 0.10))
    score = score + bonus
    stars_got = 1
    if score >= star2 then stars_got = 2 end
    if score >= star3 then stars_got = 3 end
    if (prog.st[lvl] or 0) < stars_got then prog.st[lvl] = stars_got end
    if lvl < #LEVELS and prog.unl < lvl + 1 then prog.unl = lvl + 1 end
    save_state()
    state, wsel, end_t = "win", 1, 0
    for i = 1, 24 do                            -- a sweep of freed bits, on screen
      part("bit", camx + math.random() * W, 20 + math.random() * (GY - 40),
           (math.random() - 0.5) * 60, -40 - math.random() * 90,
           0.7 + math.random() * 0.5, TH.bit, (math.random() < 0.5) and "0" or "1")
    end
    snd(523, 90, 1, 66); snd(659, 90, 1, 70); snd(880, 180, 1, 74)
  elseif ammo_i >= #ammo then
    state, wsel, end_t = "lose", 1, 0
    snd(430, 210, 1, 44, 250); snd(330, 300, 1, 34, 215)
  else
    ammo_i = ammo_i + 1
    state = "aim"
    blip(0)
  end
end

-- ---- particles ---------------------------------------------------------------
local function step_parts(dt)
  local i = 1
  local n = parts.n or 0
  while i <= n do
    local p = parts[i]
    p.life = p.life - dt
    if p.life <= 0 then
      -- swap the last live particle into the hole. Swapping the REFERENCES keeps
      -- both tables in the pool, so nothing is allocated and nothing is freed.
      parts[i], parts[n] = parts[n], parts[i]
      n = n - 1
    else
      if p.k == "num" or p.k == "kill" then
        p.y = p.y + p.vy * dt; p.vy = p.vy * 0.95
      elseif p.k ~= "ring" then
        p.x = p.x + p.vx * dt; p.y = p.y + p.vy * dt; p.vy = p.vy + 300 * dt
      end
      i = i + 1
    end
  end
  parts.n = n
end

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

local function update_cam(dt)
  local maxc = math.max(0, worldW - W)
  if state == "intro" then
    intro_t = intro_t - dt
    camtx = (intro_t > 0.55) and maxc or 0
    if intro_t <= 0 then state = "aim" end
  elseif state == "fly" or state == "settle" then
    local f
    for i = 1, #shots do
      local s = shots[i]
      if not s.dead and (not f or s.x > f) then f = s.x end
    end
    if f then camtx = f - W * 0.42
    elseif moving then camtx = camtx
    else camtx = 0 end
  else
    camtx = peek
  end
  camtx = clamp(camtx, 0, maxc)
  camx = camx + (camtx - camx) * math.min(1, 5.5 * dt)
end

-- ---- update ------------------------------------------------------------------
local playing = { intro = true, aim = true, fly = true, settle = true }
-- X remains the ability button until all media have expired. Once the remaining
-- motion is quiet, skipping advances the SAME physics in bounded batches: it
-- never freezes an unsupported tower or throws away pending damage.
function playing.can_skip()
  return state=="settle" and settle_t>=0.5 and (playing.quiet or 0)>=0.2
end
function playing.settle(dt)
  if kom.btnp("X") and playing.can_skip() then playing.skip=true end
  for step=1,(playing.skip and 8 or 1) do
    if step>1 and chk_t>0 then chk_t=chk_t-dt;support_step(5) end
    settle_t=settle_t+dt;step_bodies(dt)
    local quiet=true
    for _,b in ipairs(bodies) do
      if not b.dead and b.loose then
        local spin=math.abs(b.va)*(b.piv and b.piv_r or math.max(b.w,b.h)*0.5)
        if math.abs(b.vx)>55 or math.abs(b.vy)>55 or spin>55 then quiet=false;break end
      end
    end
    playing.quiet=quiet and ((playing.quiet or 0)+dt) or 0
    if (not moving and chk_t<=0 and settle_t>0.35) or settle_t>6 then
      playing.skip=false;next_turn();break
    end
  end
end

function update(dt)
  kom.menu(not playing[state])
  title_t = title_t + dt
  if not playing[state] and state ~= "pause" then
    for i = 1, #mbits do
      local b = mbits[i]
      b.y = b.y + b.s * dt
      if b.y > H - 26 then
        local n = mkbit(); b.x, b.y, b.b, b.s = n.x, 6, n.b, n.s
      end
    end
  end
  if shake_t > 0 then
    shake_t = shake_t - dt
    if shake_t <= 0 then shake_m = 0 end
  end
  step_parts(dt)

  if state == "title" then
    local n = 4
    if kom.btnp("UP") then sel = (sel - 2) % n + 1; blip(0) end
    if kom.btnp("DOWN") then sel = sel % n + 1; blip(0) end
    if kom.btnp("X") then
      blip(1)
      if sel == 1 then start_level(prog.unl)
      elseif sel == 2 then state = "select"; hsel = prog.unl
      elseif sel == 3 then state = "help"; psel = 1
      else state = "opts"; osel = 1 end
    end
    return
  end

  if state == "select" then
    local n = #LEVELS
    if kom.btnp("LEFT") then hsel = (hsel - 2) % n + 1; blip(0) end
    if kom.btnp("RIGHT") then hsel = hsel % n + 1; blip(0) end
    if kom.btnp("UP") then hsel = ((hsel - 1 - ((#LEVELS > 12) and 8 or 6)) % n) + 1; blip(0) end
    if kom.btnp("DOWN") then hsel = ((hsel - 1 + ((#LEVELS > 12) and 8 or 6)) % n) + 1; blip(0) end
    if kom.btnp("X") then
      if hsel <= prog.unl then blip(4); start_level(hsel) else blip(5) end
    end
    if kom.btnp("O") then state = "title"; blip(2) end
    return
  end

  if state == "help" then
    if kom.btnp("LEFT") or kom.btnp("UP") then psel = (psel == 1) and 2 or 1; blip(0) end
    if kom.btnp("RIGHT") or kom.btnp("DOWN") then psel = (psel == 1) and 2 or 1; blip(0) end
    if kom.btnp("O") or kom.btnp("X") then state = "title"; blip(2) end
    return
  end

  if state == "opts" then
    if cfm then                       -- wiping progress asks first, and asks NO
      if kom.btnp("LEFT") or kom.btnp("RIGHT") then cfm_sel = 3 - cfm_sel; blip(0) end
      if kom.btnp("O") then cfm = false; blip(2) end
      if kom.btnp("X") then
        if cfm_sel == 1 then
          prog.unl = 1
          for i = 1, #LEVELS do prog.st[i] = 0 end
          save_state()
        end
        cfm = false; blip(2)
      end
      return
    end
    local n = 5
    if kom.btnp("UP") then osel = (osel - 2) % n + 1; blip(0) end
    if kom.btnp("DOWN") then osel = osel % n + 1; blip(0) end
    local hit = kom.btnp("X") or kom.btnp("LEFT") or kom.btnp("RIGHT")
    if hit then
      if osel == 1 then opts.sound = not opts.sound; save_state(); blip(1)
      elseif osel == 2 then opts.guide = (opts.guide + 1) % 3; save_state(); blip(1)
      elseif osel == 3 then
        if kom.boxstep then opts.native = not opts.native; save_state(); blip(1) else blip(5) end
      elseif osel == 4 then cfm, cfm_sel = true, 2; blip(3)
      else state = "title"; blip(2) end
    end
    if kom.btnp("O") then state = "title"; blip(2) end
    return
  end

  if state == "pause" then
    local n = 4
    if kom.btnp("UP") then psel = (psel - 2) % n + 1; blip(0) end
    if kom.btnp("DOWN") then psel = psel % n + 1; blip(0) end
    if kom.btnp("START") or kom.btnp("O") then state = "aim"; blip(2) end
    if kom.btnp("X") then
      blip(1)
      if psel == 1 then state = "aim"
      elseif psel == 2 then start_level(lvl)
      elseif psel == 3 then state = "select"; hsel = lvl
      else state = "title"; sel = 1 end
    end
    return
  end

  if state == "win" or state == "lose" then
    end_t = end_t + dt
    local items = (state == "win") and ((lvl < #LEVELS) and 3 or 2) or 2
    if kom.btnp("UP") then wsel = (wsel - 2) % items + 1; blip(0) end
    if kom.btnp("DOWN") then wsel = wsel % items + 1; blip(0) end
    if kom.btnp("X") then
      blip(1)
      if state == "win" and lvl < #LEVELS then
        if wsel == 1 then start_level(lvl + 1)
        elseif wsel == 2 then start_level(lvl)
        else state = "select"; hsel = math.min(#LEVELS, lvl + 1) end
      else
        if wsel == 1 then start_level(lvl)
        else state = "select"; hsel = lvl end
      end
    end
    if kom.btnp("O") then state = "select"; hsel = lvl; blip(2) end
    return
  end

  -- ---- in play --------------------------------------------------------------
  if chk_t > 0 then chk_t = chk_t - dt; support_step(5) end
  if banner_t > 0 then banner_t = banner_t - dt end
  shown = shown + (score - shown) * math.min(1, 7 * dt)
  if math.abs(score - shown) < 1 then shown = score end

  if kom.btnp("START") then state = "pause"; psel = 1; blip(3); return end
  if kom.btnp("TRIANGLE") then start_level(lvl); return end

  if state == "aim" then
    local ax, ay = kom.analog()
    local da, dp = 0, 0
    if kom.btn("UP") or ay < -48 then da = da + 1 end
    if kom.btn("DOWN") or ay > 48 then da = da - 1 end
    if kom.btn("RIGHT") or ax > 48 then dp = dp + 1 end
    if kom.btn("LEFT") or ax < -48 then dp = dp - 1 end
    if da ~= 0 then aim_a = clamp(aim_a + da * 0.80 * dt, 0.06, 1.44) end
    if dp ~= 0 then aim_p = clamp(aim_p + dp * 0.52 * dt, 0.25, 1.00) end
    if da ~= 0 or dp ~= 0 then
      tick_t = tick_t - dt
      if tick_t <= 0 then tick_t = 0.10; snd(1600, 16, 0, 12) end
    end
    if kom.btn("R") then peek = peek + 320 * dt end
    if kom.btn("L") then peek = peek - 320 * dt end
    peek = clamp(peek, 0, math.max(0, worldW - W))
    if kom.btnp("X") then fire() end

  elseif state == "fly" then
    turn_t = turn_t + dt
    if kom.btnp("X") then
      for i = 1, #shots do
        local s = shots[i]
        if not s.dead and not s.shard then use_ability(s); break end
      end
    end
    local alive = false
    for i = 1, #shots do
      local s = shots[i]
      if not s.dead then step_shot(s, dt) end
      if not s.dead then alive = true end
    end
    step_bodies(dt)
    if not alive or turn_t > 13 then
      state = "settle"; settle_t = 0; shots = {}
      playing.skip=false;playing.quiet=0
    end

  elseif state == "settle" then
    playing.settle(dt)

  elseif state == "intro" then
    if kom.btnp("X") then intro_t = 0 end     -- START is the pause menu, above
  end

  update_cam(dt)
end

-- ==============================================================================
-- DRAWING
-- ==============================================================================
local WHITE, BLACK = C(255,255,255), C(0,0,0)
local MC = {
  navy = C(44,48,64),   shut = C(175,180,190), lab  = C(232,232,220),
  silver=C(200,206,216),plat = C(160,168,184), dark = C(28,30,38),
  zip  = C(46,66,150),  zipl = C(124,152,236), tape = C(56,56,64),
  tapel= C(208,208,198),usb  = C(36,38,46),    usbm = C(188,194,206),
  led  = C(240,84,60),  cd1  = C(120,222,242), cd2  = C(232,142,222),
  hole = C(96,102,116), rust = C(150,60,50),
}
local CX, CY = 0, 0
local function wx(x) return math.floor(x - CX) end
local function wy(y) return math.floor(y - CY) end

-- ship rule 18: a rotated quad is two triangles about the sprite centre, never
-- offset horizontal slices (that reads as stretching, not rotation).
local rquad
do -- scope the cache below Lua's 200 simultaneously-live locals limit
local rq_angle, rq_ca, rq_sa
rquad = function(cx, cy, x0, y0, w, h, a, col)
  -- All face details share an angle. No closure/upvalue allocation per quad,
  -- and only one sine/cosine pair for a body's consecutive layers.
  if a ~= rq_angle then rq_angle, rq_ca, rq_sa = a, math.cos(a), math.sin(a) end
  local ca, sa = rq_ca, rq_sa
  local xw, yh = x0+w, y0+h
  local x1,y1 = cx+x0*ca-y0*sa, cy+x0*sa+y0*ca
  local x2,y2 = cx+xw*ca-y0*sa, cy+xw*sa+y0*ca
  local x3,y3 = cx+xw*ca-yh*sa, cy+xw*sa+yh*ca
  local x4,y4 = cx+x0*ca-yh*sa, cy+x0*sa+yh*ca
  kom.tri(x1,y1,x2,y2,x3,y3, col)
  kom.tri(x1,y1,x3,y3,x4,y4, col)
end
end

-- The shell theme's HI is a bright accent tuned for a DARK background; on the
-- BEIGE BOX era it lands on light grey and all but disappears. Headline text asks
-- for it through hic() so one era cannot quietly go unreadable.
local function hic() return TH.light and TH.ink or kom.col.hi end

local function ctext(y, s, col, sc)
  kom.text(W/2 - kom.textw(s, sc)/2, y, s, col, sc)
end

-- ---- the media ---------------------------------------------------------------
-- An unrotated medium is drawn with rects: rquad costs a cos, a sin and four
-- closure calls per quad, and six of those in the ammo rack is ~2k VM steps a
-- frame spent rotating things by zero.
local function draw_media(x, y, m, a)
  local k = m.key
  local flat = (a > -0.02 and a < 0.02)
  local function q(x0, y0, w, h, col)
    if flat then kom.rect(x + x0, y + y0, w, h, col)
    else rquad(x, y, x0, y0, w, h, a, col) end
  end
  if k == "FLOPPY" then
    q(-8,-8, 16,16, MC.navy)
    q(-1,-8,  9, 5, MC.shut)
    q( 4,-7,  2, 3, MC.navy)
    q(-6, 1, 12, 6, MC.lab)
    q(-6, 1, 12, 2, kom.col.accent)
  elseif k == "CD" then
    kom.circle(x, y, 9, MC.silver)
    kom.circle(x, y, 8, MC.plat)
    for s = 0, 1 do
      local aa = a + s * 2.09
      kom.line(x + math.cos(aa)*3, y + math.sin(aa)*3,
               x + math.cos(aa)*8, y + math.sin(aa)*8, s == 0 and MC.cd1 or MC.cd2)
    end
    kom.circle(x, y, 3, MC.silver)
    kom.circle(x, y, 2, MC.hole)
  elseif k == "ZIP" then
    q(-10,-7, 20,14, MC.zip)
    q(-10,-7, 20, 3, MC.zipl)
    q(  3,-7,  7,14, MC.shut)
    q( -8, 1,  9, 5, MC.lab)
  elseif k == "TAPE" then
    q(-9,-6, 18,12, MC.tape)
    q(-9, 2, 18, 4, MC.tapel)
    local ca, sa = math.cos(a), math.sin(a)
    for _, o in ipairs({-4, 4}) do
      kom.circle(x + o*ca, y + o*sa - 2, 3, MC.tapel)
      kom.circle(x + o*ca, y + o*sa - 2, 1, MC.dark)
    end
  elseif k == "HDD" then
    kom.circle(x, y, 9, MC.dark)
    kom.circle(x, y, 8, MC.plat)
    kom.circle(x, y, 7, MC.silver)
    kom.line(x + math.cos(a)*7, y + math.sin(a)*7, x, y, MC.plat)
    kom.circle(x, y, 2, MC.dark)
    kom.line(x - 9, y + 8, x + 4, y + 3, MC.shut)
  else -- USB
    q(-8,-4, 12, 8, MC.usb)
    q( 4,-3,  6, 6, MC.usbm)
    q(-6,-2,  3, 2, MC.led)
  end
end

-- ---- a file icon (the targets) ----------------------------------------------
local function draw_file(px, py, w, h, t, hurtf, ang, hp, mhp)
  local body, lite, dark2 = t.c, t.cl, t.cd
  if hurtf then body = WHITE end
  if ang and math.abs(ang) > 0.04 then
    -- A tumbling target used to lose its face and read as a coloured brick, which
    -- is exactly the thing the player is trying to hit. The face rotates with it.
    local cx, cy = px + w / 2, py + h / 2
    rquad(cx, cy, -w/2, -h/2, w, h, ang, body)
    rquad(cx, cy, -w/2, -h/2, w, 2, ang, lite)
    rquad(cx, cy, -w/2+4, -h/2+7, 4, 4, ang, WHITE)
    rquad(cx, cy,  w/2-8, -h/2+7, 4, 4, ang, WHITE)
    rquad(cx, cy, -w/2+5, -h/2+8, 2, 2, ang, MC.dark)
    rquad(cx, cy,  w/2-7, -h/2+8, 2, 2, ang, MC.dark)
    rquad(cx, cy, -w/2+5,  h/2-8, w-10, 1, ang, dark2)
    return
  end
  kom.rect(px, py, w, h, body)
  kom.rect(px, py, w, 2, lite)
  kom.rect(px, py + h - 2, w, 2, dark2)
  kom.tri(px + w - 7, py, px + w, py, px + w, py + 7, lite)   -- folded corner
  kom.line(px + w - 7, py, px + w, py + 7, dark2)
  -- the face: two eyes with pupils, a brow that angles with how angry it is
  local ex, ey = px + 4, py + 7
  kom.rect(ex, ey, 4, 4, WHITE); kom.rect(px + w - 8, ey, 4, 4, WHITE)
  local look = (hp < mhp) and 1 or 0
  kom.rect(ex + 1 + look, ey + 1, 2, 2, MC.dark)
  kom.rect(px + w - 7 + look, ey + 1, 2, 2, MC.dark)
  kom.line(ex, ey - 2, ex + 3, ey - 1, dark2)
  kom.line(px + w - 8, ey - 1, px + w - 5, ey - 2, dark2)
  if hp < mhp then
    kom.line(px + 5, py + h - 7, px + w - 6, py + h - 7, dark2)      -- grimace
    kom.line(px + 5, py + h - 8, px + 7, py + h - 6, dark2)
  else
    kom.line(px + 6, py + h - 7, px + w - 6, py + h - 7, dark2)
  end
  local tw = kom.textw(t.ext, 1)
  kom.text(px + w/2 - tw/2, py + h - 6, t.ext, dark2, 1)
end

-- ---- world -------------------------------------------------------------------
local function draw_backdrop()
  kom.clear(TH.sky)
  -- motherboard skyline, parallax 0.45
  for i = 1, #props do
    local p = props[i]
    local x = math.floor(p.x - CX * 0.45)
    if x > -70 and x < W + 10 then
      if p.k == 1 then                                   -- chip with pin rows
        local yy = GY - p.h
        kom.rect(x, yy, p.w, p.h, TH.far)
        kom.rect(x, yy, p.w, 2, TH.far2)
        kom.rect(x + 3, yy - 2, p.w - 6, 2, TH.far2)
        kom.pset(x + 4, yy + 4, TH.rim)
      elseif p.k == 2 then                               -- capacitor
        kom.rect(x, GY - p.h - 8, p.r * 2, p.h + 8, TH.far)
        kom.rect(x, GY - p.h - 8, p.r * 2, 3, TH.far2)
        kom.rect(x + p.r - 1, GY - p.h - 8, 2, p.h + 6, TH.far2)
      else                                               -- RAM stick on edge
        kom.rect(x, GY - p.h - 14, p.w, p.h + 14, TH.far)
        for c = 0, p.n - 1 do
          kom.rect(x + 4 + c * 8, GY - p.h - 10, 6, 7, TH.far2)
        end
      end
    end
  end
  -- drifting data bits
  for i = 1, #dbits do
    local b = dbits[i]
    local x = math.floor(b.x - CX * 0.72)
    if x > -8 and x < W + 4 then
      kom.text(x, math.floor(b.y), (b.b == 1) and "1" or "0", TH.bit, 1)
    end
  end
end

local function draw_ground()
  local gy = wy(GY)
  kom.rect(0, gy, W, H - gy, TH.ground)
  kom.rect(0, gy, W, 1, TH.rim)
  local off = math.floor(CX) % 32
  for gx = -off, W, 32 do                                 -- copper traces + pads
    kom.rect(gx, gy + 5, 18, 1, TH.rim)
    kom.rect(gx + 8, gy + 5, 1, 8, TH.rim)
    kom.rect(gx + 22, gy + 9, 2, 2, TH.bit)
    kom.rect(gx + 3, gy + 16, 5, 5, TH.far)
  end
end

local function draw_bodies()
  for i = 1, #bodies do
    local b = bodies[i]
    if not b.dead and b.x - CX > -90 and b.x - CX < W + 8 then
      local px, py = wx(b.x), wy(b.y)
      do
        local flash = b.flash > 0
        if b.t then
          local bob = (not b.loose) and math.floor(math.sin(title_t * 2.2 + b.bob) * 1.5) or 0
          draw_file(px, py + bob, b.w, b.h, b.t, flash, b.loose and b.ang or 0, b.hp, b.mhp)
        else
          local m = b.m
          local col = flash and WHITE or m.c
          if b.loose and math.abs(b.ang) > 0.04 then
            rquad(px + b.w/2, py + b.h/2, -b.w/2, -b.h/2, b.w, b.h, b.ang, col)
            rquad(px + b.w/2, py + b.h/2, -b.w/2, -b.h/2, b.w, 2, b.ang, m.cl)
          else
            kom.rect(px, py, b.w, b.h, col)
            kom.rect(px, py, b.w, 2, m.cl)
            kom.rect(px, py + b.h - 2, b.w, 2, m.cd)
            if b.hp < b.mhp then                          -- cracks as damage
              local n = b.mhp - b.hp
              for c = 1, math.min(3, n) do
                local fx = px + 3 + (c * 7) % math.max(4, b.w - 5)
                kom.line(fx, py + 2, fx - 2, py + b.h - 3, m.cd)
              end
            end
            if b.w >= 40 and b.h >= 11 then
              local tw = kom.textw(m.ext, 1)
              kom.text(px + b.w/2 - tw/2, py + b.h/2 - 3, m.ext, m.cd, 1)
            end
          end
        end
      end
    end
  end
end

local function draw_shots()
  for i = 1, #shots do
    local s = shots[i]
    if not s.dead then
      local tr = s.trail
      for j = 1, #tr do
        local a = j / #tr
        kom.pset(wx(tr[j][1]), wy(tr[j][2]), TH.bit)
        if a > 0.6 then kom.pset(wx(tr[j][1]), wy(tr[j][2]) + 1, TH.dim) end
      end
      local px, py = wx(s.x), wy(s.y)
      if s.stuck then
        if s.blink then kom.circle(px, py, 11, MC.led) end
        draw_media(px, py, MED[6], 0)
      elseif s.shard then
        rquad(px, py, -5, -4, 10, 7, s.spin, MC.silver)
        rquad(px, py, -5, -4, 10, 2, s.spin, MC.cd1)
        rquad(px, py, -2, -1, 4, 2, s.spin, MC.hole)
      else
        draw_media(px, py, s.m, s.spin)
      end
    end
  end
end

local function draw_parts()
  for i = 1, (parts.n or 0) do
    local p = parts[i]
    local a = p.life / p.max
    local px, py = wx(p.x), wy(p.y)
    if p.k == "bit" then
      kom.text(px, py, p.s, p.c, 1)
    elseif p.k == "hex" then
      kom.text(px, py, p.s, p.c, 1)
    elseif p.k == "num" then
      kom.text(px - kom.textw(p.s, 1)/2, py, p.s, p.c, 1)
    elseif p.k == "kill" then
      local sc = (a > 0.7) and 2 or 1
      kom.text(px - kom.textw(p.s, sc)/2 + 1, py + 1, p.s, BLACK, sc)
      kom.text(px - kom.textw(p.s, sc)/2, py, p.s, p.c, sc)
    elseif p.k == "ring" then
      local r = (1 - a) * p.s
      for k = 0, 13 do
        local ang = k * 0.4488
        kom.pset(px + math.cos(ang) * r, py + math.sin(ang) * r, p.c)
      end
    else                                                   -- chip shard
      local sz = 1 + math.floor(a * 3)
      kom.rect(px - sz, py - sz, sz * 2, sz * 2, p.c)
    end
  end
end

-- ---- the sling ---------------------------------------------------------------
local function pocket()
  local pull = 7 + aim_p * 15
  return SX - math.cos(aim_a) * pull, SY + math.sin(aim_a) * pull
end

local function draw_sling(with_ammo)
  local bx, by = wx(SX), wy(SY)
  local gy = wy(GY)
  kom.rect(bx - 9, by + 4, 18, gy - by - 2, MC.dark)          -- drive rails
  kom.rect(bx - 9, by + 4, 18, 2, MC.shut)
  kom.rect(bx - 3, by + 8, 6, gy - by - 6, MC.tape)
  kom.rect(bx - 10, gy - 4, 20, 5, MC.tape)
  kom.rect(bx - 8, by - 12, 3, 18, MC.shut)                   -- prongs
  kom.rect(bx + 5, by - 12, 3, 18, MC.shut)
  kom.rect(bx - 8, by - 12, 3, 3, kom.col.accent)
  kom.rect(bx + 5, by - 12, 3, 3, kom.col.accent)
  if with_ammo then
    local ox, oy = pocket()
    local px, py = wx(ox), wy(oy)
    kom.line(bx - 7, by - 11, px, py, MC.tapel)               -- tape bands
    kom.line(bx - 7, by - 10, px, py + 1, MC.tape)
    kom.line(bx + 6, by - 11, px, py, MC.tapel)
    kom.line(bx + 6, by - 10, px, py + 1, MC.tape)
    draw_media(px, py, MED[ammo[ammo_i]], -aim_a * 0.5)
  end
end

local function draw_guide()
  for i = 1, (ghost.n or 0) do             -- the last shot, to correct against
    kom.pset(wx(ghost.x[i]), wy(ghost.y[i]), TH.dim)
  end
  if opts.guide == 0 then return end
  local vx, vy = launch_v()
  local n = (opts.guide == 1) and 7 or 17
  for i = 1, n do
    local t = i * 0.075
    local x = SX + math.cos(aim_a) * 11 + vx * t
    local y = SY - math.sin(aim_a) * 11 + vy * t + 0.5 * GRAV * t * t
    if y > GY then break end
    local px, py = wx(x), wy(y)
    if px > W + 8 then break end
    local col = (i % 2 == 0) and TH.bit or TH.dim
    kom.rect(px - 1, py - 1, 2, 2, col)
  end
  -- the aim readout lives ON the sling, not as a control legend
  local bx, by = wx(SX), wy(SY)
  local deg = math.floor(aim_a * 57.3 + 0.5)
  kom.text(bx - 12, by - 30, deg .. "DEG", TH.dim, 1)
  kom.rect(bx - 13, by - 22, 26, 4, TH.panel)
  kom.rect(bx - 12, by - 21, math.floor(24 * aim_p), 2, kom.col.accent)
end

-- ---- HUD ---------------------------------------------------------------------
local function mini_file(x, y, col, col2)
  kom.rect(x, y, 6, 8, col)
  kom.rect(x, y, 6, 1, col2)
  kom.pset(x + 5, y, col2)
end

-- The rating is PAPERCLIPS, not stars: a star says nothing about a machine that
-- eats files, and the office assistant everyone remembers was a bent wire.
-- Two sizes, both built from bars, both open at the bottom right like the real
-- thing. An unearned clip is a dim ghost, never the background colour -- that is
-- not "empty", that is invisible.
local function clip(cx, cy, col, small)
  if small then
    kom.rect(cx - 3, cy - 4, 1, 9, col)          -- outer left
    kom.rect(cx + 2, cy - 4, 1, 7, col)          -- outer right, stops short
    kom.rect(cx - 2, cy - 5, 4, 1, col)          -- top bend
    kom.rect(cx - 2, cy + 5, 4, 1, col)          -- bottom bend
    kom.rect(cx, cy - 2, 1, 6, col)              -- inner wire
    kom.rect(cx, cy + 4, 2, 1, col)
  else
    kom.rect(cx - 5, cy - 8, 2, 16, col)
    kom.rect(cx + 3, cy - 8, 2, 14, col)
    kom.rect(cx - 4, cy - 10, 8, 2, col)
    kom.rect(cx - 4, cy + 8, 8, 2, col)
    kom.rect(cx - 1, cy - 6, 2, 11, col)
    kom.rect(cx - 1, cy + 5, 5, 2, col)
  end
end

local function clip_slot(x, y, got, small)
  if got then
    clip(x, y, kom.col.accent, small)
    if not small then kom.rect(x - 5, y - 8, 2, 6, kom.col.hi) end   -- a glint
  else
    clip(x, y, TH.dim, small)
  end
end

local function draw_hud()
  kom.rect(0, 0, W, 15, TH.panel)
  kom.rect(0, 15, W, 1, kom.col.accent)
  local ls = string.format("L%02d", lvl)
  kom.text(6, 4, ls, kom.col.accent, 1)
  kom.text(6 + kom.textw(ls, 1) + 7, 4, LV.name, TH.ink, 1)
  local s = kbs(math.floor(shown))
  kom.text(W - 6 - kom.textw(s, 1), 4, s, TH.ink, 1)
  -- corrupt files still live, as pips
  local n = math.min(left, 6)
  local x0 = W / 2 - (n * 9) / 2
  for i = 1, n do mini_file(x0 + (i - 1) * 9, 4, MC.rust, MC.led) end

  -- The rack is what is STILL ON IT. The loaded medium is already in the sling,
  -- in the player's hand, and named in the badge on the right; drawing it here as
  -- well says there is one more shot than there is.
  local rem = #ammo - ammo_i
  local inplay = (state == "aim" or state == "fly" or state == "settle" or state == "intro")
  if inplay then
    if rem > 0 then
      -- the rack grows with what is on it: 8px of margin, 22px per slot, and a
      -- "+n" chip only when there are more than six left to draw
      local show = math.min(rem, 6)
      local extra = rem - show
      local chip = (extra > 0) and ("+" .. extra) or nil
      local pw = 16 + show * 22 + (chip and (kom.textw(chip, 1) + 10) or 0)
      kom.rect(6, H - 28, pw, 24, TH.panel)
      kom.frame(6, H - 28, pw, 24, TH.dim)
      for i = 1, show do
        draw_media(25 + (i - 1) * 22, H - 16, MED[ammo[ammo_i + i]], 0)
      end
      if chip then
        kom.text(14 + show * 22, H - 19, chip, TH.dim, 1)
      end
    end
    local bs, col = MED[ammo[ammo_i]].name, TH.dim
    local s1 = shots[1]
    if state=="settle" then
      bs=playing.skip and "SKIPPING..." or (playing.can_skip() and "X SKIP WAIT" or "SETTLING...")
      col=playing.can_skip() and TH.ink or TH.dim
    end
    if state == "fly" and s1 and not s1.dead and not s1.used and s1.m.ab then
      bs = s1.m.abn
      col = (math.floor(title_t * 8) % 2 == 0) and kom.col.accent or kom.col.hi
    end
    local bw = kom.textw(bs, 1) + 20
    kom.rect(W - 6 - bw, H - 28, bw, 24, TH.panel)
    kom.frame(W - 6 - bw, H - 28, bw, 24, TH.dim)
    kom.text(W - 6 - bw + 10, H - 20, bs, col, 1)
  end
end

-- ---- overlays (every box is sized FROM its text, ship rule 13) ---------------
-- The plate is sized FROM the glyph. The font is 7 rows tall, so an 11px box put
-- every selected label 2px low with the text nearly touching the frame: 15 tall
-- leaves 4 rows of air above and below, and 12px either side lets it breathe.
local PLATE_H = 15
local function menu_list(items, cur, y0, pitch)
  for i = 1, #items do
    local on = (i == cur)
    local s = items[i]
    local tw = kom.textw(s, 1)
    local x = math.floor(W / 2 - tw / 2)
    local y = y0 + (i - 1) * pitch
    if on then
      kom.rect(x - 12, y - 4, tw + 24, PLATE_H, TH.sky)
      kom.frame(x - 12, y - 4, tw + 24, PLATE_H, kom.col.accent)
      kom.rect(x - 12, y - 4, 2, PLATE_H, kom.col.accent)          -- end caps
      kom.rect(x + tw + 10, y - 4, 2, PLATE_H, kom.col.accent)
    end
    kom.text(x, y, s, on and kom.col.accent or TH.ink, 1)
  end
end

local function draw_pause()
  kom.rect(0, 60, W, 150, TH.panel)
  kom.rect(0, 60, W, 1, kom.col.accent)
  kom.rect(0, 209, W, 1, kom.col.accent)
  ctext(72, "PAUSED", hic(), 2)
  ctext(92, LV.name, TH.dim, 1)
  menu_list({ "RESUME", "RETRY SECTOR", "SELECT SECTOR", "MAIN MENU" }, psel, 116, 22)
end

local function draw_end()
  local win = (state == "win")
  local title = win and "SECTOR CLEARED" or "CLEANUP FAILED"
  local items
  if win then
    items = (lvl < #LEVELS) and { "NEXT SECTOR", "RETRY", "SELECT SECTOR" }
                             or { "RETRY", "SELECT SECTOR" }
  else
    items = { "RETRY SECTOR", "SELECT SECTOR" }
  end

  -- The score is a READOUT, not three centred sentences: labels left, values
  -- right, a rule above the total and the total itself at double height. It also
  -- disposes of "1 FILES LEFT" -- a count in a column has no grammar to get wrong.
  local rows = {
    { "FREED", kbs(score - bonus) },
    win and { "BONUS", kbs(bonus) } or { "FILES LEFT", tostring(left) },
  }
  local tot = kbs(score)

  local inner = kom.textw("TOTAL", 1) + 30 + kom.textw(tot, 2)
  for i = 1, #rows do
    local w2 = kom.textw(rows[i][1], 1) + 30 + kom.textw(rows[i][2], 1)
    if w2 > inner then inner = w2 end
  end
  local panelW = inner + 24
  local bw = math.max(kom.textw(title, 2), panelW)
  for i = 1, #items do
    local w2 = kom.textw(items[i], 1) + 28
    if w2 > bw then bw = w2 end
  end
  bw = bw + 28

  local panelH = 7 + 12 + 12 + 11 + 16 + 7
  local bh = 12 + 14 + 10 + (win and 26 or 0) + panelH + 14
             + (#items - 1) * 20 + PLATE_H + 12
  local bx, by = math.floor(W / 2 - bw / 2), math.floor(H / 2 - bh / 2)
  kom.rect(bx, by, bw, bh, TH.panel)
  kom.frame(bx, by, bw, bh, kom.col.accent)
  kom.frame(bx + 1, by + 1, bw - 2, bh - 2, TH.sky)

  local y = by + 12
  ctext(y, title, win and hic() or MC.led, 2)
  y = y + 24
  if win then
    for i = 1, 3 do
      clip_slot(W / 2 - 28 + (i - 1) * 28, y + 10, (i <= stars_got) and (end_t > 0.25 * i))
    end
    y = y + 26
  end

  local px = math.floor(W / 2 - panelW / 2)
  kom.rect(px, y, panelW, panelH, TH.sky)
  kom.frame(px, y, panelW, panelH, TH.dim)
  local ry = y + 7
  for i = 1, #rows do
    kom.text(px + 12, ry, rows[i][1], TH.dim, 1)
    kom.text(px + panelW - 12 - kom.textw(rows[i][2], 1), ry, rows[i][2], TH.ink, 1)
    ry = ry + 12
  end
  kom.rect(px + 10, ry + 4, panelW - 20, 1, TH.dim)
  ry = ry + 11
  kom.text(px + 12, ry + 4, "TOTAL", hic(), 1)
  kom.text(px + panelW - 12 - kom.textw(tot, 2), ry, tot, kom.col.accent, 2)

  menu_list(items, wsel, y + panelH + 18, 20)
end

-- ---- title -------------------------------------------------------------------
local function draw_title()
  kom.clear(TH.sky)
  draw_mbits()
  kom.rect(0, H - 26, W, 26, TH.ground)
  kom.rect(0, H - 26, W, 1, TH.rim)
  for gx = 0, W, 24 do
    kom.rect(gx, H - 21, 14, 1, TH.rim)
    kom.pset(gx + 18, H - 17, TH.bit)
  end

  -- the two halves of the joke, drawn either side of the wordmark
  draw_media(56, 96, MED[1], math.sin(title_t * 0.9) * 0.5)
  draw_media(56, 150, MED[2], title_t * 1.4)
  local fx = W - 76
  draw_file(fx, 84, 22, 26, TGT[4], false, 0, 1, 2)
  draw_file(fx + 6, 128, 20, 24, TGT[1], false, 0, 1, 1)

  local t1 = "BAD SECTOR"
  kom.text(W / 2 - kom.textw(t1, 3) / 2 + 2, 44, t1, BLACK, 3)
  kom.text(W / 2 - kom.textw(t1, 3) / 2, 42, t1, hic(), 3)
  ctext(70, "SLING THE MEDIA. DELETE THE FILES.", TH.dim, 1)
  menu_list({ "PLAY", "SELECT SECTOR", "HOW TO PLAY", "OPTIONS" }, sel, 104, 22)
  local tot = 0
  for i = 1, #LEVELS do tot = tot + (prog.st[i] or 0) end
  ctext(190, "CLIPS " .. tot .. " / " .. (#LEVELS * 3), TH.dim, 1)
  ctext(202, "SECTOR " .. prog.unl .. " OF " .. #LEVELS, TH.dim, 1)
end

-- ---- level select ------------------------------------------------------------
local function draw_select()
  kom.clear(TH.sky)
  draw_mbits()
  kom.rect(0, 0, W, 15, TH.panel)
  kom.rect(0, 15, W, 1, kom.col.accent)
  kom.text(6, 4, "SELECT SECTOR", kom.col.accent, 1)
  local tot = 0
  for i = 1, #LEVELS do tot = tot + (prog.st[i] or 0) end
  local ss = "CLIPS " .. tot .. " / " .. (#LEVELS * 3)
  kom.text(W - 6 - kom.textw(ss, 1), 4, ss, TH.ink, 1)

  -- Keep readable tiles: selection switches pages after sixteen entries. Input
  -- uses the same eight-column stride, including across the page boundary.
  local cols = (#LEVELS > 12) and 8 or 6
  local tw2  = (cols == 8) and 52 or 68
  local gap  = (cols == 8) and 6 or 8
  local th2  = 64
  local first = math.floor((hsel-1)/16)*16+1
  local rows = math.ceil(math.min(16,#LEVELS-first+1) / cols)
  local limit = H - 72                                   -- the footer starts here
  if 28 + (rows - 1) * (th2 + 12) + th2 > limit then
    th2 = math.floor((limit - 28 - (rows - 1) * 12) / rows)
    if th2 < 40 then th2 = 40 end
  end
  local x0 = W / 2 - (cols * tw2 + (cols - 1) * gap) / 2
  for i = first, math.min(first+15,#LEVELS) do
    local c, r = (i - first) % cols, math.floor((i - first) / cols)
    local x, y = x0 + c * (tw2 + gap), 28 + r * (th2 + 12)
    if y + th2 <= limit then
    local open = (i <= prog.unl)
    kom.rect(x, y, tw2, th2, open and TH.panel or TH.sky)
    kom.frame(x, y, tw2, th2, open and TH.dim or TH.panel)
    local ns = string.format("%02d", i)
    kom.text(x + tw2 / 2 - kom.textw(ns, 2) / 2, y + 11, ns,
             open and TH.ink or TH.dim, 2)
    if open then
      for s2 = 1, 3 do
        clip_slot(x + tw2 / 2 - 14 + (s2 - 1) * 14, y + 44, (prog.st[i] or 0) >= s2, true)
      end
      kom.rect(x + 6, y + th2 - 8, tw2 - 12, 2, THEMES[LEVELS[i].era] and
               C(THEMES[LEVELS[i].era].rr, THEMES[LEVELS[i].era].rg, THEMES[LEVELS[i].era].rb))
    else
      kom.rect(x + tw2 / 2 - 7, y + 38, 14, 11, TH.dim)      -- padlock
      kom.rect(x + tw2 / 2 - 5, y + 31, 10, 7, TH.dim)
      kom.rect(x + tw2 / 2 - 3, y + 33, 6, 5, TH.sky)
      kom.rect(x + tw2 / 2 - 1, y + 42, 2, 4, TH.sky)
    end
    if i == hsel then                                       -- rule 15: two rings
      kom.frame(x - 2, y - 2, tw2 + 4, th2 + 4, kom.col.accent)
      kom.frame(x - 1, y - 1, tw2 + 2, th2 + 2, TH.sky)
      kom.frame(x, y, tw2, th2, kom.col.accent)
    end
    end
  end
  local L = LEVELS[hsel]
  ctext(H - 66, L.name, hic(), 2)
  local era = THEMES[L.era].name
  ctext(H - 48, (hsel <= prog.unl) and (era .. "   " .. #L.ammo .. " MEDIA")
        or "LOCKED", TH.ink, 1)
  if hsel <= prog.unl then
    ctext(H - 34, (prog.st[hsel] or 0) .. " OF 3 CLIPS", TH.dim, 1)
  end
  ctext(H-20, (hsel<=12 and "SYSTEM REPAIR" or (hsel<=16 and "DEEP SCAN" or (hsel<=20 and "SILVER RECOVERY" or "COLD STORAGE"))).."  /  "..math.floor((hsel-1)/16+1).." OF "..math.ceil(#LEVELS/16), TH.dim, 1)
end

-- ---- how to play -------------------------------------------------------------
local ABDESC = {
  "STEADY. NO TRICKS.",
  "SPLITS INTO THREE SHARDS.",
  "SLAMS STRAIGHT DOWN. HEAVY.",
  "SPOOLS UP: FLAT AND FAST.",
  "DEMAGNETISES: BLAST RADIUS.",
  "PLUGS IN, THEN DETONATES.",
}
local function draw_help()
  kom.clear(TH.sky)
  draw_mbits()
  kom.rect(0, 0, W, 15, TH.panel)
  kom.rect(0, 15, W, 1, kom.col.accent)
  kom.text(6, 4, (psel == 1) and "STORAGE MEDIA" or "FILE TYPES", kom.col.accent, 1)
  kom.text(W - 6 - kom.textw("PAGE " .. psel .. "/2", 1), 4, "PAGE " .. psel .. "/2", TH.ink, 1)

  if psel == 1 then
    ctext(22, "PULL BACK, LET GO, THEN HIT X IN THE AIR", TH.dim, 1)
    local n = #MED
    local pitch = math.min(34, math.floor((H - 56) / n))    -- rule 26
    for i = 1, n do
      local y = 40 + (i - 1) * pitch
      kom.rect(20, y - 10, W - 40, pitch - 2, TH.panel)
      draw_media(38, y + 1, MED[i], 0)
      kom.text(58, y - 6, MED[i].name, hic(), 1)
      kom.text(58, y + 3, ABDESC[i], TH.dim, 1)
      if MED[i].abn ~= "" then
        kom.text(W - 26 - kom.textw(MED[i].abn, 1), y - 2, MED[i].abn, kom.col.accent, 1)
      end
    end
  else
    ctext(20, "BLOCKS ARE JUNK. THE FACES ARE THE TARGETS.", TH.dim, 1)
    kom.text(14, 34, "BLOCKS", hic(), 1)
    kom.text(250, 34, "CORRUPT FILES", hic(), 1)
    local p1 = math.min(40, math.floor((H - 60) / #MAT))     -- rule 26
    for i = 1, #MAT do
      local y = 46 + (i - 1) * p1
      kom.rect(10, y, 218, p1 - 6, TH.panel)
      local cy = y + (p1 - 6) / 2
      kom.rect(20, cy - 9, 46, 18, MAT[i].c)
      kom.rect(20, cy - 9, 46, 2, MAT[i].cl)
      kom.rect(20, cy + 7, 46, 2, MAT[i].cd)
      kom.text(43 - kom.textw(MAT[i].ext, 1) / 2, cy - 3, MAT[i].ext, MAT[i].cd, 1)
      kom.text(80, cy - 3, MAT[i].hp .. " HP", TH.ink, 1)
      kom.text(136, cy - 3, kbs(MAT[i].kb), TH.dim, 1)
    end
    local p2 = math.min(42, math.floor((H - 60) / #TGT))
    for i = 1, #TGT do
      local y = 46 + (i - 1) * p2
      kom.rect(244, y, 226, p2 - 4, TH.panel)
      draw_file(252, y + 2, 20, 24, TGT[i], false, 0, 1, 1)
      kom.text(280, y + 5, TGT[i].name, TGT[i].cl, 1)
      kom.text(280, y + 15, TGT[i].hp .. " HP", TH.ink, 1)
      kom.text(324, y + 15, kbs(TGT[i].kb), TH.dim, 1)
    end
  end
  for i = 1, 2 do
    kom.rect(W / 2 - 8 + (i - 1) * 12, H - 10, 6, 3, (i == psel) and kom.col.accent or TH.panel)
  end
end

-- ---- options -----------------------------------------------------------------
-- A destructive action asks first, the highlight starts on NO, and both answers
-- are selectable plates -- never a "[X] YES [O] NO" legend.
local function draw_confirm(msg)
  local mw = kom.textw(msg, 1)
  local bw = math.max(mw, 120) + 44
  local bh = 72
  local bx, by = math.floor(W / 2 - bw / 2), math.floor(H / 2 - bh / 2)
  -- a full-width curtain, because with no alpha a modal that lets the list it is
  -- covering poke out either side does not read as modal
  kom.rect(0, by - 10, W, bh + 20, TH.sky)
  kom.rect(0, by - 10, W, 1, TH.dim)
  kom.rect(0, by + bh + 9, W, 1, TH.dim)
  kom.rect(bx, by, bw, bh, TH.panel)
  kom.frame(bx, by, bw, bh, kom.col.accent)
  kom.frame(bx + 1, by + 1, bw - 2, bh - 2, TH.sky)
  kom.text(W / 2 - mw / 2, by + 16, msg, TH.ink, 1)
  local answer = { "YES", "NO" }
  for i = 1, 2 do
    local s2 = answer[i]
    local tw = kom.textw(s2, 1)
    local x = math.floor(W / 2 + (i == 1 and -40 or 40) - tw / 2)
    local y = by + 46
    if i == cfm_sel then
      kom.rect(x - 12, y - 4, tw + 24, PLATE_H, TH.sky)
      kom.frame(x - 12, y - 4, tw + 24, PLATE_H, kom.col.accent)
      kom.rect(x - 12, y - 4, 2, PLATE_H, kom.col.accent)
      kom.rect(x + tw + 10, y - 4, 2, PLATE_H, kom.col.accent)
    end
    kom.text(x, y, s2, (i == cfm_sel) and kom.col.accent or TH.dim, 1)
  end
end

local GUIDEN = { [0] = "OFF", [1] = "SHORT", [2] = "FULL" }
-- Settings are a LIST, not centred sentences padded out with spaces: one plate
-- per row, label left, value right, so values line up in a column and the
-- highlight is the same width whatever the value happens to say.
local OPT_W = 224
local function opt_row(i, y, label, value)
  local x = math.floor(W / 2 - OPT_W / 2)
  local on = (osel == i)
  kom.rect(x, y - 4, OPT_W, PLATE_H, on and TH.sky or TH.panel)
  kom.frame(x, y - 4, OPT_W, PLATE_H, on and kom.col.accent or TH.dim)
  if on then
    kom.rect(x, y - 4, 2, PLATE_H, kom.col.accent)
    kom.rect(x + OPT_W - 2, y - 4, 2, PLATE_H, kom.col.accent)
  end
  kom.text(x + 12, y, label, on and kom.col.accent or TH.ink, 1)
  if value then
    kom.text(x + OPT_W - 12 - kom.textw(value, 1), y, value,
             on and kom.col.accent or TH.dim, 1)
  end
end

local function draw_opts()
  kom.clear(TH.sky)
  draw_mbits()
  ctext(40, "OPTIONS", hic(), 3)
  opt_row(1, 104, "SOUND", opts.sound and "ON" or "OFF")
  opt_row(2, 126, "AIM GUIDE", GUIDEN[opts.guide])
  opt_row(3, 148, "PHYSICS", kom.boxstep and (opts.native and "NATIVE" or "LUA") or "LUA ONLY")
  opt_row(4, 170, "RESET PROGRESS", nil)
  opt_row(5, 192, "BACK", nil)
  if cfm then draw_confirm("ERASE ALL PROGRESS AND CLIPS?") end
end

-- ---- draw --------------------------------------------------------------------
function draw()
  if kom.perfnote then kom.perfnote(opts.native and kom.boxstep and "NATIVE" or "LUA") end
  CX, CY = camx, 0
  if shake_m > 0 then
    CX = CX + (math.random() - 0.5) * shake_m
    CY = (math.random() - 0.5) * shake_m
  end

  if state == "title" then draw_title(); return end
  if state == "select" then draw_select(); return end
  if state == "help" then draw_help(); return end
  if state == "opts" then draw_opts(); return end

  draw_backdrop()
  draw_ground()
  draw_bodies()
  draw_sling(state == "aim" or state == "intro")
  if state == "aim" then draw_guide() end
  draw_shots()
  draw_parts()
  draw_hud()

  if banner_t > 0 then
    -- The plate is FIXED. It used to slide six pixels down as it went, which reads
    -- as the HUD coming loose. The motion belongs INSIDE it: rules that wipe out
    -- from the centre, a name that types itself in, a scan line crossing it, and a
    -- flicker-out at the end. Nothing moves the plate.
    local el = BANNER_T - banner_t
    local title = banner
    local era = THEMES[LV.era].name
    local nstr = tostring(left)
    local cstr = (left == 1) and " CORRUPT FILE" or " CORRUPT FILES"
    local tw = kom.textw(title, 2)
    local ew = kom.textw(era, 1)
    local sw = ew + 14 + kom.textw(nstr, 1) + kom.textw(cstr, 1)
    local pw = math.max(tw, sw) + 48
    local ph = 38
    local px, py = math.floor(W / 2 - pw / 2), 24
    if banner_t > 0.4 or math.floor(banner_t * 22) % 2 == 0 then
      kom.rect(px, py, pw, ph, TH.panel)
      kom.frame(px, py, pw, ph, TH.dim)
      local wipe = math.floor(math.min(1, el / 0.18) * (pw / 2))    -- rules open out
      kom.rect(W / 2 - wipe, py, wipe * 2, 2, kom.col.accent)
      kom.rect(W / 2 - wipe, py + ph - 2, wipe * 2, 2, kom.col.accent)
      for _, c in ipairs({ { px, py, 1, 0 }, { px + pw - 9, py, -1, 0 },
                           { px, py + ph - 9, 1, 1 }, { px + pw - 9, py + ph - 9, -1, 1 } }) do
        kom.rect(c[1], c[2] + c[4] * 7, 9, 2, kom.col.accent)       -- lock-on corners
        kom.rect(c[1] + ((c[3] < 0) and 7 or 0), c[2], 2, 9, kom.col.accent)
      end
      -- The live element rides the RULES, not the type. A scan line across the
      -- plate filled the gaps between letters with dots, which reads as the text
      -- being corrupted rather than as a machine thinking.
      local run = math.floor((el * 110) % (pw + 40)) - 20
      local x1 = px + math.max(0, run)
      local x2 = math.min(px + pw, px + run + 26)
      if x2 > x1 then
        kom.rect(x1, py + ph - 2, x2 - x1, 2, TH.ink)
        kom.rect(px + pw - (x2 - px), py, x2 - x1, 2, TH.ink)
      end
      local tx = math.floor(W / 2 - tw / 2)
      local n = math.max(0, math.floor(#title * math.min(1, (el - 0.14) / 0.30)))
      kom.text(tx, py + 7, string.sub(title, 1, n), TH.ink, 2)
      if n < #title then
        kom.rect(tx + n * 12, py + 7, 9, 14, kom.col.accent)        -- the caret
      else
        local sx2 = math.floor(W / 2 - sw / 2)
        kom.text(sx2, py + 25, era, TH.dim, 1)
        kom.rect(sx2 + ew + 5, py + 27, 3, 3, kom.col.accent)
        kom.text(sx2 + ew + 14, py + 25, nstr, kom.col.accent, 1)
        kom.text(sx2 + ew + 14 + kom.textw(nstr, 1), py + 25, cstr, TH.ink, 1)
      end
    end
  end

  if state == "pause" then draw_pause() end
  if state == "win" or state == "lose" then draw_end() end
end

-- ---- load --------------------------------------------------------------------
function load()
  W, H = kom.W, kom.H
  GY = H - 30
  SX, SY = 66, GY - 46
  math.randomseed(math.floor(kom.time() * 1000) + 11)
  th = THEMES[1]; TH = pack_theme(th)
  bodies, shots, props, dbits = {}, {}, {}, {}
  parts = parts or {}; parts.n = 0
  load_state()
  lvl, LV, worldW = 1, LEVELS[1], W
  state = "title"
  sel, hsel, osel, psel, wsel = 1, 1, 1, 1, 1
  score, shown, left, bonus, stars_got = 0, 0, 0, 0, 0
  level_total, star2, star3 = 1, 1, 1
  ammo, ammo_i = { 1 }, 1
  ghost = ghost or { x = {}, y = {} }; ghost.n = 0
  camx, camtx, shake_t, shake_m = 0, 0, 0, 0
  aim_a, aim_p, tick_t = 0.72, 0.70, 0
  banner, banner_t, end_t, intro_t = "", 0, 0, 0
  settle_t, turn_t, moving = 0, 0, false
  mbits = {}
  for i = 1, 34 do mbits[i] = mkbit() end
end
