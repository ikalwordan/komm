-- @name Chess
-- @display fullscreen
--
-- CHESS -- full ruleset + a real alpha-beta engine, on a 333MHz MIPS running Lua.
--
-- Two things shape every decision in this file:
--   1. THE MOVE GENERATOR IS PROVED BY PERFT, not by looking at it. 10x12 mailbox,
--      pseudo-legal generation, legality by make-and-test. simulator/_chessperft.js
--      counts leaves against the published numbers for the six standard positions.
--   2. THE SEARCH CANNOT RECURSE ACROSS FRAMES. There are no coroutines in the
--      sandbox and a frame over 250ms is killed, so alpha-beta is written as an
--      EXPLICIT STACK MACHINE (see sstep): one call = one node visit or one return,
--      and update() runs as many as the frame budget allows and stops mid-tree.
--      Nothing is thrown away between frames; the machine simply resumes.
--
-- Locals are rationed (Lua allows 200 live per function and the chunk IS a
-- function), so every constant set that is only read at startup is built inside a
-- do...end block -- block locals give their registers back at the `end`.
local cfm, cfm_sel = false, 2      -- CLEAR SAVE confirm; NO is the default
local savedata = 0                 -- >0 when a game is stored; CLEAR SAVE wipes it

local W, H = 480, 272
local CELL, BX, BY, BSZ = 30, 4, 16, 240
local PX0, PW = 250, 226

-- ============================================================================
--  BOARD  (10x12 mailbox: 0..119, playable 21..98, border holds -1)
--  piece codes  1..6 = white P N B R Q K,  7..12 = black
-- ============================================================================
local bd    = {}
local PT    = {0,1,2,3,4,5,6,1,2,3,4,5,6}   -- PT[p+1] -- indexed p, see below
local PC    = {}
local PVAL  = {100,320,330,500,900,20000}
local CRM   = {}          -- castling-right mask per square
local SQC   = {}          -- square colour (0/1) for the bishop draw rule
-- names, in ONE table: five cold lookup sets for one local slot
local NM = {
  sq = {}, fi = {}, ra = {},
  pl = {"", "N", "B", "R", "Q", "K"},
  fp = {P=1,N=2,B=3,R=4,Q=5,K=6,p=7,n=8,b=9,r=10,q=11,k=12},
}

local PL    = {[0] = {}, [1] = {}}   -- piece lists per colour
local PLN   = {[0] = 0, [1] = 0}
local PIDX  = {}          -- square -> index in its colour's list
local KSQ   = {[0] = 95, [1] = 25}

local stm, cr, ep, hmc = 0, 15, 0, 0
local zk1, zk2 = 0, 0

local ND  = {-21,-19,-12,-8,8,12,19,21}
local KD  = {-11,-10,-9,-1,1,9,10,11}
local BDD = {-11,-9,9,11}
local RDD = {-10,-1,1,10}

local ZK1, ZK2 = {}, {}
local ZX = {{}, {}, {}, {}}      -- 1,2 = castling-rights keys; 3,4 = ep-file keys
local ZST1, ZST2 = 0, 0

-- undo stack: move, castling rights, ep square, halfmove clock, captured piece,
-- and both zobrist halves, as seven parallel arrays under ONE local slot
local UD = {{}, {}, {}, {}, {}, {}, {}}
local uply = 0
local HK1, HK2 = {}, {}
local hply = 0

local MVS, MSS = {}, {}   -- per-ply move / score arrays, allocated once each

-- ---- piece code tables ------------------------------------------------------
do
  PT = {}
  for p = 1, 6  do PT[p] = p;     PC[p] = 0 end
  for p = 7, 12 do PT[p] = p - 6; PC[p] = 1 end
  PT[0] = 0; PC[0] = -1
  for s = 0, 119 do bd[s] = -1; CRM[s] = 15 end
  CRM[95] = 12; CRM[98] = 14; CRM[91] = 13     -- e1 / h1 / a1
  CRM[25] = 3;  CRM[28] = 11; CRM[21] = 7      -- e8 / h8 / a8
  for r = 0, 7 do
    for f = 0, 7 do
      local s = 21 + r * 10 + f
      bd[s]    = 0
      SQC[s]   = (r + f) % 2
      NM.fi[s] = string.char(97 + f)
      NM.ra[s] = string.char(56 - r)
      NM.sq[s] = NM.fi[s] .. NM.ra[s]
    end
  end
end

-- ---- zobrist: a FIXED seed, so a saved game replays to the same keys ---------
do
  local x = 20260820
  local function zr()
    x = (x ~ (x << 13)) & 0x7FFFFFFF
    x = x ~ (x >> 7)
    x = (x ~ (x << 17)) & 0x7FFFFFFF
    if x == 0 then x = 0x2545F49 end
    return x
  end
  for i = 0, 12 * 120 + 119 do ZK1[i] = zr(); ZK2[i] = zr() end
  for i = 0, 15 do ZX[1][i] = zr(); ZX[2][i] = zr() end
  for i = 0, 9  do ZX[3][i] = zr(); ZX[4][i] = zr() end
  ZST1 = zr(); ZST2 = zr()
end

-- ============================================================================
--  EVALUATION TABLES
--  VMG/VEG fold material value, piece-square bonus AND the side's sign into one
--  flat lookup, so the whole material+placement term is one add per piece.
-- ============================================================================
local VMG, VEG = {}, {}
local PHW = {0,1,1,2,4,0}
local PASSB = {0,4,10,20,38,65,110,110}
local PF = {{}, {}, {}, {}, {}, {}}   -- WPF BPF WMN BMN WMX BMX, per file

do
  local MMG = {100,320,330,500,900,0}
  local MEG = {120,320,330,520,940,0}
  local T = {
   { 0,  0,  0,  0,  0,  0,  0,  0,      -- 1 pawn mg
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
     5,  5, 10, 25, 25, 10,  5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5, -5,-10,  0,  0,-10, -5,  5,
     5, 10, 10,-20,-20, 10, 10,  5,
     0,  0,  0,  0,  0,  0,  0,  0},
   {-50,-40,-30,-30,-30,-30,-40,-50,     -- 2 knight
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50},
   {-20,-10,-10,-10,-10,-10,-10,-20,     -- 3 bishop
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20},
   {  0,  0,  0,  0,  0,  0,  0,  0,     -- 4 rook
      5, 10, 10, 10, 10, 10, 10,  5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
      0,  0,  0,  5,  5,  0,  0,  0},
   {-20,-10,-10, -5, -5,-10,-10,-20,     -- 5 queen
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20},
   {-30,-40,-40,-50,-50,-40,-40,-30,     -- 6 king mg
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20},
   {  0,  0,  0,  0,  0,  0,  0,  0,     -- 7 pawn eg
    100,100,100,100,100,100,100,100,
     55, 55, 55, 55, 55, 55, 55, 55,
     30, 30, 30, 30, 30, 30, 30, 30,
     18, 18, 18, 18, 18, 18, 18, 18,
      8,  8,  8,  8,  8,  8,  8,  8,
      6,  6,  6,  6,  6,  6,  6,  6,
      0,  0,  0,  0,  0,  0,  0,  0},
   {-50,-40,-30,-20,-20,-30,-40,-50,     -- 8 king eg
    -30,-20,-10,  0,  0,-10,-20,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-30,  0,  0,  0,  0,-30,-30,
    -50,-30,-30,-30,-30,-30,-30,-50},
  }
  local MGT = {T[1],T[2],T[3],T[4],T[5],T[6]}
  local EGT = {T[7],T[2],T[3],T[4],T[5],T[8]}
  for i = 0, 12 * 120 + 119 do VMG[i] = 0; VEG[i] = 0 end
  for r = 0, 7 do
    for f = 0, 7 do
      local s = 21 + r * 10 + f
      local w64, b64 = r * 8 + f + 1, (7 - r) * 8 + f + 1
      for t = 1, 6 do
        VMG[t * 120 + s]       =  MMG[t] + MGT[t][w64]
        VEG[t * 120 + s]       =  MEG[t] + EGT[t][w64]
        VMG[(t + 6) * 120 + s] = -(MMG[t] + MGT[t][b64])
        VEG[(t + 6) * 120 + s] = -(MEG[t] + EGT[t][b64])
      end
    end
  end
end

-- ============================================================================
--  PIECE PLACEMENT  (board + piece list + zobrist stay in lockstep)
-- ============================================================================
local function addp(s, p)
  bd[s] = p
  local c = PC[p]
  local n = PLN[c] + 1
  PL[c][n] = s; PIDX[s] = n; PLN[c] = n
  if p == 6 or p == 12 then KSQ[c] = s end
  local k = p * 120 + s
  zk1 = zk1 ~ ZK1[k]; zk2 = zk2 ~ ZK2[k]
end

local function rmp(s)
  local p = bd[s]
  local c = PC[p]
  local i = PIDX[s]
  local n = PLN[c]
  local L = PL[c]
  local last = L[n]
  L[i] = last; PIDX[last] = i; PLN[c] = n - 1
  bd[s] = 0
  local k = p * 120 + s
  zk1 = zk1 ~ ZK1[k]; zk2 = zk2 ~ ZK2[k]
end

local function mvp(f, t)
  local p = bd[f]
  local c = PC[p]
  bd[t] = p; bd[f] = 0
  local i = PIDX[f]
  PL[c][i] = t; PIDX[t] = i
  zk1 = zk1 ~ ZK1[p * 120 + f] ~ ZK1[p * 120 + t]
  zk2 = zk2 ~ ZK2[p * 120 + f] ~ ZK2[p * 120 + t]
end

-- ============================================================================
--  ATTACK TEST -- rays FROM the square, not a scan of every enemy piece
-- ============================================================================
local function attacked(s, byc)
  local v
  if byc == 0 then
    if bd[s + 11] == 1 or bd[s + 9] == 1 then return true end
    for i = 1, 8 do if bd[s + ND[i]] == 2 then return true end end
    for i = 1, 8 do if bd[s + KD[i]] == 6 then return true end end
    for i = 1, 4 do
      local d = RDD[i]; local t = s + d; v = bd[t]
      while v == 0 do t = t + d; v = bd[t] end
      if v == 4 or v == 5 then return true end
    end
    for i = 1, 4 do
      local d = BDD[i]; local t = s + d; v = bd[t]
      while v == 0 do t = t + d; v = bd[t] end
      if v == 3 or v == 5 then return true end
    end
  else
    if bd[s - 11] == 7 or bd[s - 9] == 7 then return true end
    for i = 1, 8 do if bd[s + ND[i]] == 8 then return true end end
    for i = 1, 8 do if bd[s + KD[i]] == 12 then return true end end
    for i = 1, 4 do
      local d = RDD[i]; local t = s + d; v = bd[t]
      while v == 0 do t = t + d; v = bd[t] end
      if v == 10 or v == 11 then return true end
    end
    for i = 1, 4 do
      local d = BDD[i]; local t = s + d; v = bd[t]
      while v == 0 do t = t + d; v = bd[t] end
      if v == 9 or v == 11 then return true end
    end
  end
  return false
end

local function inCheck(c) return attacked(KSQ[c], 1 - c) end

-- ============================================================================
--  MOVE GENERATION
--  move = from + to*128 + promo*16384 + flag*131072
--  flag: 0 normal, 1 en-passant capture, 2 castle, 3 double pawn push
-- ============================================================================
local function genmoves(ply, caps)
  local L = MVS[ply]
  if not L then L = {}; MVS[ply] = L; MSS[ply] = {} end
  local n = 0
  local us = stm
  local them = 1 - us
  local Lu, cnt = PL[us], PLN[us]
  for idx = 1, cnt do
    local s = Lu[idx]
    local pc = bd[s]
    local ty = PT[pc]
    if ty == 1 then
      if us == 0 then
        local t = s - 10
        if bd[t] == 0 then
          if t <= 28 then
            for pr = 5, 2, -1 do n = n + 1; L[n] = s + t * 128 + pr * 16384 end
          elseif not caps then
            n = n + 1; L[n] = s + t * 128
            if s >= 81 and s <= 88 and bd[s - 20] == 0 then
              n = n + 1; L[n] = s + (s - 20) * 128 + 393216
            end
          end
        end
        for k = -11, -9, 2 do
          local c2 = s + k
          local v = bd[c2]
          if v > 0 and v > 6 then
            if c2 <= 28 then
              for pr = 5, 2, -1 do n = n + 1; L[n] = s + c2 * 128 + pr * 16384 end
            else
              n = n + 1; L[n] = s + c2 * 128
            end
          elseif v == 0 and c2 == ep and ep ~= 0 then
            n = n + 1; L[n] = s + c2 * 128 + 131072
          end
        end
      else
        local t = s + 10
        if bd[t] == 0 then
          if t >= 91 then
            for pr = 5, 2, -1 do n = n + 1; L[n] = s + t * 128 + pr * 16384 end
          elseif not caps then
            n = n + 1; L[n] = s + t * 128
            if s >= 31 and s <= 38 and bd[s + 20] == 0 then
              n = n + 1; L[n] = s + (s + 20) * 128 + 393216
            end
          end
        end
        for k = 9, 11, 2 do
          local c2 = s + k
          local v = bd[c2]
          if v > 0 and v < 7 then
            if c2 >= 91 then
              for pr = 5, 2, -1 do n = n + 1; L[n] = s + c2 * 128 + pr * 16384 end
            else
              n = n + 1; L[n] = s + c2 * 128
            end
          elseif v == 0 and c2 == ep and ep ~= 0 then
            n = n + 1; L[n] = s + c2 * 128 + 131072
          end
        end
      end
    elseif ty == 2 or ty == 6 then
      local D = (ty == 2) and ND or KD
      for k = 1, 8 do
        local t = s + D[k]
        local v = bd[t]
        if v == 0 then
          if not caps then n = n + 1; L[n] = s + t * 128 end
        elseif v > 0 and PC[v] == them then
          n = n + 1; L[n] = s + t * 128
        end
      end
      if ty == 6 and not caps then
        if us == 0 then
          if (cr & 1) ~= 0 and bd[96] == 0 and bd[97] == 0
             and not attacked(95, 1) and not attacked(96, 1) and not attacked(97, 1) then
            n = n + 1; L[n] = 95 + 97 * 128 + 262144
          end
          if (cr & 2) ~= 0 and bd[94] == 0 and bd[93] == 0 and bd[92] == 0
             and not attacked(95, 1) and not attacked(94, 1) and not attacked(93, 1) then
            n = n + 1; L[n] = 95 + 93 * 128 + 262144
          end
        else
          if (cr & 4) ~= 0 and bd[26] == 0 and bd[27] == 0
             and not attacked(25, 0) and not attacked(26, 0) and not attacked(27, 0) then
            n = n + 1; L[n] = 25 + 27 * 128 + 262144
          end
          if (cr & 8) ~= 0 and bd[24] == 0 and bd[23] == 0 and bd[22] == 0
             and not attacked(25, 0) and not attacked(24, 0) and not attacked(23, 0) then
            n = n + 1; L[n] = 25 + 23 * 128 + 262144
          end
        end
      end
    else
      local D = (ty == 3) and BDD or ((ty == 4) and RDD or KD)
      local nd = (ty == 5) and 8 or 4
      for k = 1, nd do
        local d = D[k]
        local t = s + d
        local v = bd[t]
        while v == 0 do
          if not caps then n = n + 1; L[n] = s + t * 128 end
          t = t + d; v = bd[t]
        end
        if v > 0 and PC[v] == them then n = n + 1; L[n] = s + t * 128 end
      end
    end
  end
  return n
end

-- ============================================================================
--  MAKE / UNMAKE
-- ============================================================================
local function domove(m)
  local f  = m % 128
  local t  = (m // 128) % 128
  local pr = (m // 16384) % 8
  local fl = m // 131072
  local us = stm
  uply = uply + 1
  UD[1][uply] = m;   UD[2][uply] = cr;  UD[3][uply] = ep
  UD[4][uply] = hmc; UD[6][uply] = zk1; UD[7][uply] = zk2
  local pc = bd[f]
  local ty = PT[pc]
  local cap = 0
  hmc = hmc + 1
  if ep ~= 0 then zk1 = zk1 ~ ZX[3][ep % 10]; zk2 = zk2 ~ ZX[4][ep % 10] end
  local nep = 0
  if fl == 1 then
    local cs = (us == 0) and (t + 10) or (t - 10)
    cap = bd[cs]; rmp(cs); hmc = 0
  elseif bd[t] ~= 0 then
    cap = bd[t]; rmp(t); hmc = 0
  end
  UD[5][uply] = cap
  mvp(f, t)
  if ty == 1 then
    hmc = 0
    if fl == 3 then nep = (us == 0) and (f - 10) or (f + 10) end
    if pr > 0 then
      rmp(t)
      addp(t, (us == 0) and pr or (pr + 6))
    end
  elseif ty == 6 then
    KSQ[us] = t
    if fl == 2 then
      if     t == 97 then mvp(98, 96)
      elseif t == 93 then mvp(91, 94)
      elseif t == 27 then mvp(28, 26)
      else                mvp(21, 24) end
    end
  end
  zk1 = zk1 ~ ZX[1][cr]; zk2 = zk2 ~ ZX[2][cr]
  cr = cr & CRM[f] & CRM[t]
  zk1 = zk1 ~ ZX[1][cr]; zk2 = zk2 ~ ZX[2][cr]
  ep = nep
  if ep ~= 0 then zk1 = zk1 ~ ZX[3][ep % 10]; zk2 = zk2 ~ ZX[4][ep % 10] end
  stm = 1 - us
  zk1 = zk1 ~ ZST1; zk2 = zk2 ~ ZST2
  hply = hply + 1
  HK1[hply] = zk1; HK2[hply] = zk2
end

local function undomove()
  local m  = UD[1][uply]
  local f  = m % 128
  local t  = (m // 128) % 128
  local pr = (m // 16384) % 8
  local fl = m // 131072
  stm = 1 - stm
  local us = stm
  if pr > 0 then
    rmp(t)
    addp(t, (us == 0) and 1 or 7)
  end
  mvp(t, f)
  if bd[f] == 6 or bd[f] == 12 then
    KSQ[us] = f
    if fl == 2 then
      if     t == 97 then mvp(96, 98)
      elseif t == 93 then mvp(94, 91)
      elseif t == 27 then mvp(26, 28)
      else                mvp(24, 21) end
    end
  end
  local cap = UD[5][uply]
  if cap ~= 0 then
    if fl == 1 then addp((us == 0) and (t + 10) or (t - 10), cap)
    else            addp(t, cap) end
  end
  cr = UD[2][uply]; ep = UD[3][uply]; hmc = UD[4][uply]
  zk1 = UD[6][uply]; zk2 = UD[7][uply]
  hply = hply - 1
  uply = uply - 1
end

-- ---- draw conditions --------------------------------------------------------
local function isrep()
  local lim = hply - hmc
  if lim < 0 then lim = 0 end
  for i = hply - 4, lim, -2 do
    if HK1[i] == zk1 and HK2[i] == zk2 then return true end
  end
  return false
end

local function repcount()
  local c = 1
  local lim = hply - hmc
  if lim < 0 then lim = 0 end
  for i = hply - 2, lim, -2 do
    if HK1[i] == zk1 and HK2[i] == zk2 then c = c + 1 end
  end
  return c
end

-- K v K, K+B v K, K+N v K, K+B v K+B on the same colour. Nothing else: K+N+N v K
-- is not a FIDE dead position and this must not claim it is.
local function insuff()
  local m0, m1, b0, b1 = 0, 0, -1, -1
  for c = 0, 1 do
    local L = PL[c]
    for i = 1, PLN[c] do
      local s = L[i]
      local ty = PT[bd[s]]
      if ty == 1 or ty == 4 or ty == 5 then return false end
      if ty == 2 or ty == 3 then
        if c == 0 then m0 = m0 + 1; if ty == 3 then b0 = SQC[s] end
        else            m1 = m1 + 1; if ty == 3 then b1 = SQC[s] end end
      end
    end
  end
  if m0 + m1 <= 1 then return true end
  if m0 == 1 and m1 == 1 and b0 >= 0 and b1 >= 0 and b0 == b1 then return true end
  return false
end

-- ============================================================================
--  EVALUATION
-- ============================================================================
local function evaluate()
  local mg, eg, ph = 0, 0, 0
  local nb0, nb1 = 0, 0
  local WPF, BPF, WMN, BMN, WMX, BMX = PF[1], PF[2], PF[3], PF[4], PF[5], PF[6]
  for i = 0, 9 do
    WPF[i] = 0; BPF[i] = 0
    WMN[i] = 9; BMN[i] = 9; WMX[i] = -1; BMX[i] = -1
  end
  for c = 0, 1 do
    local L = PL[c]
    for i = 1, PLN[c] do
      local s = L[i]
      local p = bd[s]
      local k = p * 120 + s
      mg = mg + VMG[k]; eg = eg + VEG[k]
      local ty = PT[p]
      ph = ph + PHW[ty]
      if ty == 1 then
        local fi = s % 10
        local rk = (s - 21) // 10
        if c == 0 then
          WPF[fi] = WPF[fi] + 1
          if rk < WMN[fi] then WMN[fi] = rk end
          if rk > WMX[fi] then WMX[fi] = rk end
        else
          BPF[fi] = BPF[fi] + 1
          if rk < BMN[fi] then BMN[fi] = rk end
          if rk > BMX[fi] then BMX[fi] = rk end
        end
      elseif ty == 3 then
        if c == 0 then nb0 = nb0 + 1 else nb1 = nb1 + 1 end
      end
    end
  end
  -- pawn structure, judged per file on that file's most advanced pawn
  for f = 1, 8 do
    if WPF[f] > 0 then
      local d = (WPF[f] - 1) * 12
      mg = mg - d; eg = eg - d - 4
      if WPF[f - 1] == 0 and WPF[f + 1] == 0 then mg = mg - 14; eg = eg - 18 end
      local rk = WMN[f]
      if BMN[f - 1] >= rk and BMN[f] >= rk and BMN[f + 1] >= rk then
        local b = PASSB[8 - rk]
        mg = mg + b // 2; eg = eg + b
      end
    end
    if BPF[f] > 0 then
      local d = (BPF[f] - 1) * 12
      mg = mg + d; eg = eg + d + 4
      if BPF[f - 1] == 0 and BPF[f + 1] == 0 then mg = mg + 14; eg = eg + 18 end
      local rk = BMX[f]
      if WMX[f - 1] <= rk and WMX[f] <= rk and WMX[f + 1] <= rk then
        local b = PASSB[rk + 1]
        mg = mg - b // 2; eg = eg - b
      end
    end
  end
  if nb0 >= 2 then mg = mg + 28; eg = eg + 44 end
  if nb1 >= 2 then mg = mg - 28; eg = eg - 44 end
  -- king shelter: pawns on the king's file and its neighbours (midgame only)
  local kf = KSQ[0] % 10
  local sh = 0
  for d = -1, 1 do
    local f = kf + d
    if f >= 1 and f <= 8 and WPF[f] > 0 then sh = sh + 1 end
  end
  mg = mg + (sh - 3) * 12
  kf = KSQ[1] % 10
  sh = 0
  for d = -1, 1 do
    local f = kf + d
    if f >= 1 and f <= 8 and BPF[f] > 0 then sh = sh + 1 end
  end
  mg = mg - (sh - 3) * 12
  if ph > 24 then ph = 24 end
  local sc = (mg * ph + eg * (24 - ph)) // 24
  if stm == 1 then sc = -sc end
  return sc
end

-- ============================================================================
--  SEARCH -- alpha-beta as an EXPLICIT STACK MACHINE so it can pause mid-tree
-- ============================================================================
local MAXPLY, QMAX, MATE, INF = 26, 6, 30000, 32000
local UIPLY = 28
local SA, SB, SD, SI, SNn = {}, {}, {}, {}, {}
local SBST, SBM, SCM, SLG, SIC, SQF = {}, {}, {}, {}, {}, {}
local KIL1, KIL2, HISQ = {}, {}, {}
local sp, retf, retv, srun, snodes, rootval, rootpv = 0, false, 0, false, 0, 0, 0
local bestm, bestsc, iterd, tnodes, thinking = 0, 0, 1, 0, false
local RT, rootn = {{}, {}}, 0   -- root move scores / moves

local function order(ply, n)
  local L, S = MVS[ply], MSS[ply]
  local k1, k2 = KIL1[ply], KIL2[ply]
  local pv = (ply == 0) and rootpv or 0
  for i = 1, n do
    local m = L[i]
    local t = (m // 128) % 128
    local v = bd[t]
    local s
    if v ~= 0 then
      s = 1000000 + PVAL[PT[v]] * 16 - PVAL[PT[bd[m % 128]]] // 16
    elseif (m // 16384) % 8 > 0 then
      s = 950000 + (m // 16384) % 8
    elseif (m // 131072) == 1 then
      s = 1001000
    elseif m == k1 then s = 800000
    elseif m == k2 then s = 790000
    else
      s = HISQ[bd[m % 128] * 120 + t]
    end
    if m == pv then s = 9000000 end
    S[i] = s
  end
end

local function sret(v)
  if sp == 0 then srun = false; rootval = v
  else sp = sp - 1; retv = v; retf = true end
end

local function sstep()
  local p = sp
  if retf then
    retf = false
    undomove()
    local sc = -retv
    if p == 0 then rootn = rootn + 1; RT[1][rootn] = sc; RT[2][rootn] = SCM[0] end
    if sc > SBST[p] then
      SBST[p] = sc
      SBM[p] = SCM[p]
      if sc > SA[p] then
        SA[p] = sc
        if sc >= SB[p] then
          local m = SCM[p]
          local t = (m // 128) % 128
          if bd[t] == 0 and (m // 131072) ~= 1 then
            if KIL1[p] ~= m then KIL2[p] = KIL1[p]; KIL1[p] = m end
            local hk = bd[m % 128] * 120 + t
            local d = SD[p]
            HISQ[hk] = HISQ[hk] + d * d
          end
          sret(SBST[p])
          return
        end
      end
    end
  else
    snodes = snodes + 1
    if p > 0 and (hmc >= 100 or isrep() or insuff()) then sret(0); return end
    local d = SD[p]
    local ic = inCheck(stm)
    SIC[p] = ic
    if p >= MAXPLY - 1 then sret(evaluate()); return end
    if d > 0 and ic then d = d + 1; SD[p] = d end
    if d <= 0 then
      if d <= -QMAX and not ic then sret(evaluate()); return end
      if ic then
        SQF[p] = false
        SBST[p] = -INF
        SNn[p] = genmoves(p, false)
      else
        local st = evaluate()
        if st >= SB[p] then sret(st); return end
        SQF[p] = true
        SBST[p] = st
        if st > SA[p] then SA[p] = st end
        SNn[p] = genmoves(p, true)
      end
    else
      SQF[p] = false
      SBST[p] = -INF
      SNn[p] = genmoves(p, false)
    end
    order(p, SNn[p])
    SI[p] = 1
    SLG[p] = 0
    SBM[p] = 0
  end
  -- pick the next move; an illegal one costs nothing but a make/unmake
  local L, S = MVS[p], MSS[p]
  local n = SNn[p]
  while true do
    local i = SI[p]
    if i > n then
      if SLG[p] == 0 and not SQF[p] then
        sret(SIC[p] and -(MATE - p) or 0)
      else
        sret(SBST[p])
      end
      return
    end
    local bi = i
    for k = i + 1, n do if S[k] > S[bi] then bi = k end end
    if bi ~= i then
      L[i], L[bi] = L[bi], L[i]
      S[i], S[bi] = S[bi], S[i]
    end
    SI[p] = i + 1
    local m = L[i]
    domove(m)
    if attacked(KSQ[1 - stm], stm) then
      undomove()
    else
      SLG[p] = SLG[p] + 1
      SCM[p] = m
      local q = p + 1
      SA[q] = -SB[p]; SB[q] = -SA[p]; SD[q] = SD[p] - 1
      sp = q
      return
    end
  end
end

local function startiter()
  sp = 0; retf = false; srun = true; snodes = 0; rootn = 0
  SA[0] = -INF; SB[0] = INF; SD[0] = iterd
  for i = 0, MAXPLY do KIL1[i] = 0; KIL2[i] = 0 end
end

-- ============================================================================
--  POSITION SETUP
-- ============================================================================
local function rehash()
  local k1, k2 = 0, 0
  for c = 0, 1 do
    local L = PL[c]
    for i = 1, PLN[c] do
      local s = L[i]
      local k = bd[s] * 120 + s
      k1 = k1 ~ ZK1[k]; k2 = k2 ~ ZK2[k]
    end
  end
  k1 = k1 ~ ZX[1][cr]; k2 = k2 ~ ZX[2][cr]
  if ep ~= 0 then k1 = k1 ~ ZX[3][ep % 10]; k2 = k2 ~ ZX[4][ep % 10] end
  if stm == 1 then k1 = k1 ~ ZST1; k2 = k2 ~ ZST2 end
  zk1, zk2 = k1, k2
end

local function setfen(fen)
  for r = 0, 7 do for f = 0, 7 do bd[21 + r * 10 + f] = 0 end end
  PLN[0] = 0; PLN[1] = 0
  zk1, zk2 = 0, 0
  local bp, sd, cs, es, hf = fen:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(%d*)")
  if not bp then return false end
  local sq = 21
  for i = 1, #bp do
    local ch = bp:sub(i, i)
    if ch == "/" then
      sq = sq + 2
    elseif ch >= "1" and ch <= "8" then
      sq = sq + (ch:byte() - 48)
    else
      local p = NM.fp[ch]
      if p then addp(sq, p) end
      sq = sq + 1
    end
  end
  stm = (sd == "b") and 1 or 0
  cr = 0
  if cs:find("K", 1, true) then cr = cr + 1 end
  if cs:find("Q", 1, true) then cr = cr + 2 end
  if cs:find("k", 1, true) then cr = cr + 4 end
  if cs:find("q", 1, true) then cr = cr + 8 end
  ep = 0
  if es ~= "-" and #es >= 2 then
    local f = es:byte(1) - 96
    local r = 56 - es:byte(2)
    if f >= 1 and f <= 8 and r >= 0 and r <= 7 then ep = 21 + r * 10 + (f - 1) end
  end
  hmc = tonumber(hf) or 0
  uply = 0; hply = 0
  rehash()
  HK1[0] = zk1; HK2[0] = zk2
  for i = 0, 12 * 120 + 119 do HISQ[i] = 0 end
  return true
end

-- ============================================================================
--  LEGAL MOVES FOR THE UI  (kept on its own ply so a paused search is safe)
-- ============================================================================
local LEGAL, NLEG = {}, 0

local function refreshLegal()
  local n = genmoves(UIPLY, false)
  local L = MVS[UIPLY]
  local o = 0
  for i = 1, n do
    local m = L[i]
    domove(m)
    if not attacked(KSQ[1 - stm], stm) then o = o + 1; LEGAL[o] = m end
    undomove()
  end
  NLEG = o
  return o
end

-- ============================================================================
--  ALGEBRAIC NOTATION  (call BEFORE the move is made; LEGAL must be current)
-- ============================================================================
local function sanOf(m)
  local f  = m % 128
  local t  = (m // 128) % 128
  local pr = (m // 16384) % 8
  local fl = m // 131072
  if fl == 2 then return (t > f) and "O-O" or "O-O-O" end
  local p  = bd[f]
  local ty = PT[p]
  local cap = (bd[t] ~= 0) or (fl == 1)
  local s
  if ty == 1 then
    s = cap and (NM.fi[f] .. "x" .. NM.sq[t]) or NM.sq[t]
    if pr > 0 then s = s .. "=" .. NM.pl[pr] end
    return s
  end
  local amb, sf, sr = false, false, false
  for i = 1, NLEG do
    local m2 = LEGAL[i]
    if m2 ~= m then
      local f2 = m2 % 128
      if bd[f2] == p and ((m2 // 128) % 128) == t then
        amb = true
        if f2 % 10 == f % 10 then sf = true end
        if (f2 - 21) // 10 == (f - 21) // 10 then sr = true end
      end
    end
  end
  local d = ""
  if amb then
    if not sf then d = NM.fi[f]
    elseif not sr then d = NM.ra[f]
    else d = NM.sq[f] end
  end
  return NM.pl[ty] .. d .. (cap and "x" or "") .. NM.sq[t]
end

-- ============================================================================
--  GAME STATE
-- ============================================================================
-- DB is the DISPLAY board. The engine pauses mid-tree between frames, so `bd`,
-- `stm` and `KSQ` belong to whatever node the search stopped on -- drawing from
-- them paints the search, not the game. Everything on screen reads DB / G.stm /
-- G.chk, which only change when a move is actually PLAYED.
local DB = {}
local G = {
  mv = {}, san = {}, mn = 0, mtot = 0,
  stm = 0, chk = 0,
  eng = 1,            -- -1 hotseat, 0 engine is white, 1 engine is black
  lvl = 2,            -- 1..4
  clk = 1,            -- 1 off, 2 = 5min, 3 = 10min, 4 = 3min+2s
  tw = 0, tb = 0, inc = 0,
  res = nil, resw = 0,
  last = 0,
}
local UI = {
  st = "menu", sel = 1, nsel = 1, osel = 1, psel = 1,
  cur = 95, sel_sq = 0, flip = false, scroll = 0,
  sound = true, coords = true, dots = true, freec = false,
  fx = 0, fy = 0, arep = 0, tick = 0, msg = "", lastt = 0,
  promo = 0, pfrom = 0, pto = 0, spin = 0,
}
local C = {}
-- Piece glyphs: 13x13 pixel art, drawn at scale 2 (26px) inside a 30px square so
-- a highlighted square still shows a 2px band around the piece. '1' outline,
-- '2' body, '3' spare. One kom.sprite call per piece -- the host expands the lit
-- pixels in C, so 32 pieces cost 32 VM calls, not 32 x 100 kom.rect calls.
local ART = {
  {".............",     -- PAWN
   ".....111.....",
   "....12221....",
   "....12221....",
   ".....121.....",
   "....11211....",
   "...1122211...",
   "...1222221...",
   "..112222211..",
   "..122222221..",
   "..122222221..",
   "..122222221..",
   "..111111111.."},
  {".......1.....",     -- KNIGHT: ear top-right, muzzle out to the left at rows
   "......121....",     -- 7-8, then the jaw CUTS BACK at row 9. That notch is
   ".....11221...",     -- what makes it read as a horse and not a blob.
   "...1122221...",
   "..122122221..",
   ".12222222221.",
   "122222222221.",
   "112222222221.",
   "..1122222221.",
   "....12222221.",
   "..122222221..",
   "..122222221..",
   "..111111111.."},
  {"......1......",     -- BISHOP
   ".....121.....",
   "....12221....",
   "....12121....",
   "...1221221...",
   "...1222221...",
   "....12221....",
   "....11211....",
   "...1222221...",
   "..122222221..",
   "..122222221..",
   "..122222221..",
   "..111111111.."},
  {".............",     -- ROOK
   "..11.111.11..",
   "..11.111.11..",
   "..111111111..",
   "..122222221..",
   "...1222221...",
   "...1222221...",
   "...1222221...",
   "...1222221...",
   "..122222221..",
   "..111111111..",
   "..122222221..",
   "..111111111.."},
  {"..1...1...1..",     -- QUEEN
   "..11.111.11..",
   "..122222221..",
   "..122222221..",
   "...1222221...",
   "....12221....",
   "....11211....",
   "...1222221...",
   "..122222221..",
   "..122222221..",
   "..111111111..",
   "..122222221..",
   "..111111111.."},
  {"......1......",     -- KING
   "....11111....",
   "......1......",
   "....12221....",
   "..122222221..",
   "..121222121..",
   "..122222221..",
   "...1222221...",
   "...1122211...",
   "..122222221..",
   "..111111111..",
   "..122222221..",
   "..111111111.."},
}
local PALW, PALB = {}, {}
local PCNT = {}
local INITC = {8,2,2,2,1,1}

-- The search leaves its moves ON THE UNDO STACK between frames -- that is how it
-- resumes without coroutines. So anything that touches the game position (undo,
-- redo, new game, walking away from the board) MUST unwind them first, or it
-- pops a SEARCH move off the stack and takes the piece lists apart. This cost a
-- crash 1410 frames into the drive route: L pressed while the engine was thinking.
local function abortThink()
  while uply > G.mn do undomove() end
  thinking = false
  srun = false
end

-- ============================================================================
--  SOUND
-- ============================================================================
local function snd(f, ms, w, v, f2) if UI.sound then kom.tone(f, ms, w, v, f2) end end
local function blip(i) if UI.sound then kom.sfx(i) end end

-- ============================================================================
--  SAVE / LOAD
-- ============================================================================
local function serialize()
  local t = {}
  for i = 1, G.mn do
    local m = G.mv[i]
    t[i] = string.format("%02d%02d%d", m % 128, (m // 128) % 128, (m // 16384) % 8)
  end
  return string.format("v1;e=%d;l=%d;c=%d;w=%d;b=%d;f=%d;s=%d;o=%d;m=%s",
    G.eng, G.lvl, G.clk, math.floor(G.tw), math.floor(G.tb),
    UI.flip and 1 or 0, UI.sound and 1 or 0, UI.dots and 1 or 0, table.concat(t))
end

local function findmove(f, t, pr)
  for i = 1, NLEG do
    local m = LEGAL[i]
    if m % 128 == f and (m // 128) % 128 == t and (m // 16384) % 8 == pr then return m end
  end
  return 0
end

local function newgame(fen)
  abortThink()
  setfen(fen or "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
  G.mn = 0; G.mtot = 0; G.res = nil; G.last = 0
  UI.sel_sq = 0; UI.scroll = 0; UI.msg = ""
  UI.cur = UI.flip and 25 or 95
  refreshLegal()
end

-- ============================================================================
--  GAME FLOW
-- ============================================================================
local function trayCounts()
  for i = 1, 12 do PCNT[i] = 0 end
  for c = 0, 1 do
    local L = PL[c]
    for i = 1, PLN[c] do
      local p = bd[L[i]]
      PCNT[p] = PCNT[p] + 1
    end
  end
end

-- one copy per PLAYED move, never per frame
local function syncDisp()
  for r = 0, 7 do
    for f = 0, 7 do
      local sq = 21 + r * 10 + f
      DB[sq] = bd[sq]
    end
  end
  G.stm = stm
  G.chk = inCheck(stm) and KSQ[stm] or 0
  trayCounts()
end

local function checkEnd()
  if NLEG == 0 then
    if inCheck(stm) then
      G.res = (stm == 0) and "CHECKMATE - BLACK WINS" or "CHECKMATE - WHITE WINS"
      G.resw = (stm == 0) and 1 or 0
    else
      G.res = "STALEMATE - DRAW"; G.resw = 2
    end
  elseif hmc >= 100 then
    G.res = "DRAW - FIFTY MOVE RULE"; G.resw = 2
  elseif repcount() >= 3 then
    G.res = "DRAW - THREEFOLD REPETITION"; G.resw = 2
  elseif insuff() then
    G.res = "DRAW - INSUFFICIENT MATERIAL"; G.resw = 2
  end
  if G.res then
    UI.st = "over"
    snd(440, 200, 1, 70, 300)
  end
end

local function applyMove(m)
  local s = sanOf(m)
  local cap = (bd[(m // 128) % 128] ~= 0) or (m // 131072) == 1
  local cas = (m // 131072) == 2
  domove(m)
  G.mn = G.mn + 1
  G.mv[G.mn] = m
  G.mtot = G.mn
  G.last = m
  refreshLegal()
  local ic = inCheck(stm)
  if NLEG == 0 and ic then s = s .. "#"
  elseif ic then s = s .. "+" end
  G.san[G.mn] = s
  UI.sel_sq = 0
  syncDisp()
  if G.clk > 1 then
    if stm == 1 then G.tw = G.tw + G.inc else G.tb = G.tb + G.inc end
  end
  if cas then snd(320, 70, 2, 60); snd(240, 90, 2, 55)
  elseif ic then snd(880, 90, 1, 70)
  elseif cap then snd(300, 60, 3, 50); snd(500, 70, 2, 55)
  else snd(620, 45, 2, 45) end
  checkEnd()
end

-- LEVEL / CLOCK config, one slot for eight tables.
--  d   max iterative-deepening depth       n    nodes searched per FRAME
--  cap total node ceiling for one move     slk  how far below best a root move
--                                               may still be chosen (variety)
local LV = {
  d   = {2, 3, 4, 5},
  n   = {90, 170, 240, 300},
  cap = {2500, 14000, 45000, 120000},
  slk = {70, 25, 0, 0},
  nm  = {"EASY", "CLUB", "STRONG", "EXPERT"},
  cnm = {"OFF", "5 MIN", "10 MIN", "3 MIN +2"},
  csec = {0, 300, 600, 180},
  cinc = {0, 0, 0, 2},
}

local function startThink()
  thinking = true
  bestm = 0; bestsc = 0; iterd = 1; tnodes = 0; rootpv = 0
  UI.spin = 0
  for i = 0, 12 * 120 + 119 do HISQ[i] = 0 end
  startiter()
end

local function pickRoot()
  local slack = LV.slk[G.lvl]
  if slack <= 0 or rootn <= 1 then return SBM[0] end
  local best = -INF
  for i = 1, rootn do if RT[1][i] > best then best = RT[1][i] end end
  local cand, nc = {}, 0
  for i = 1, rootn do
    if RT[1][i] >= best - slack then nc = nc + 1; cand[nc] = RT[2][i] end
  end
  if nc <= 1 then return SBM[0] end
  return cand[math.random(nc)]
end

local function thinkStep()
  local t0 = kom.time()
  local it, n0 = 0, snodes
  local budget = LV.n[G.lvl]
  while srun do
    sstep()
    it = it + 1
    if it >= 16 then
      it = 0
      if snodes - n0 >= budget then return end
      -- the real guard on hardware. kom.time() is frozen inside a simulator
      -- frame, so the node budget above is what stops the loop there.
      if kom.time() - t0 > 0.075 then return end
    end
  end
  -- one iteration finished
  bestm = SBM[0]; bestsc = rootval; rootpv = bestm
  if G.lvl <= 2 then bestm = pickRoot() end
  tnodes = tnodes + snodes
  if iterd < LV.d[G.lvl] and tnodes < LV.cap[G.lvl]
     and bestsc < MATE - 200 and bestsc > -(MATE - 200) then
    iterd = iterd + 1
    startiter()
  else
    thinking = false
    if bestm ~= 0 then applyMove(bestm) end
  end
end

-- ============================================================================
--  INPUT HELPERS
-- ============================================================================
local function visOf(s)
  local f = s % 10 - 1
  local r = (s - 21) // 10
  if UI.flip then f = 7 - f; r = 7 - r end
  return f, r
end

local function sqAt(f, r)
  if UI.flip then f = 7 - f; r = 7 - r end
  return 21 + r * 10 + f
end

local function sqx(s) local f = visOf(s); return BX + f * CELL end
local function sqy(s) local _, r = visOf(s); return BY + r * CELL end

local function moveCur(df, dr)
  local f, r = visOf(UI.cur)
  f = f + df; r = r + dr
  if f < 0 then f = 0 elseif f > 7 then f = 7 end
  if r < 0 then r = 0 elseif r > 7 then r = 7 end
  UI.cur = sqAt(f, r)
  UI.fx = BX + f * CELL + CELL // 2
  UI.fy = BY + r * CELL + CELL // 2
  blip(0)
end

local function humanTurn()
  return G.eng < 0 or G.stm ~= G.eng
end

local function trySelect()
  local s = UI.cur
  if UI.sel_sq ~= 0 then
    -- second press: play if legal, otherwise re-select
    local pr = 0
    local isprom = false
    for i = 1, NLEG do
      local m = LEGAL[i]
      if m % 128 == UI.sel_sq and (m // 128) % 128 == s then
        if (m // 16384) % 8 > 0 then isprom = true else pr = m end
      end
    end
    if isprom then
      UI.st = "promo"; UI.promo = 1; UI.pfrom = UI.sel_sq; UI.pto = s
      blip(3); return
    end
    if pr ~= 0 then applyMove(pr); return end
  end
  local p = bd[s]
  if p ~= 0 and PC[p] == G.stm then
    UI.sel_sq = s; blip(1)
  else
    UI.sel_sq = 0; blip(2)
  end
end

local function undoPly(n)
  abortThink()
  for _ = 1, n do
    if G.mn <= 0 then break end
    undomove()
    G.mn = G.mn - 1
  end
  G.last = (G.mn > 0) and G.mv[G.mn] or 0
  G.res = nil
  if UI.st == "over" then UI.st = "play" end
  UI.sel_sq = 0
  refreshLegal(); syncDisp()
end

local function redoPly(n)
  abortThink()
  for _ = 1, n do
    if G.mn >= G.mtot then break end
    domove(G.mv[G.mn + 1])
    G.mn = G.mn + 1
  end
  G.last = (G.mn > 0) and G.mv[G.mn] or 0
  UI.sel_sq = 0
  refreshLegal(); syncDisp()
  checkEnd()
end

-- ============================================================================
--  LOAD
-- ============================================================================
local function loadsave()
  local s = kom.load()
  if not s or #s < 4 then savedata = 0; return false end
  UI.sound = (s:match("s=(%d)") ~= "0")
  UI.dots  = (s:match("o=(%d)") ~= "0")
  UI.flip  = (s:match("f=(%d)") == "1")
  G.eng = tonumber(s:match("e=(%-?%d+)")) or 1
  G.lvl = tonumber(s:match("l=(%d)")) or 2
  G.clk = tonumber(s:match("c=(%d)")) or 1
  local mv = s:match("m=([0-9]*)") or ""
  newgame()
  G.inc = LV.cinc[G.clk]
  G.tw = tonumber(s:match("w=(%d+)")) or LV.csec[G.clk]
  G.tb = tonumber(s:match("b=(%d+)")) or LV.csec[G.clk]
  local i = 1
  while i + 4 <= #mv do
    local f = tonumber(mv:sub(i, i + 1))
    local t = tonumber(mv:sub(i + 2, i + 3))
    local pr = tonumber(mv:sub(i + 4, i + 4))
    local m = findmove(f, t, pr)
    if m == 0 then break end
    applyMove(m)
    i = i + 5
  end
  G.res = nil
  syncDisp()
  UI.st = "play"
  savedata = (G.mn > 0) and 1 or 0
  return true
end

local function storesave()
  savedata = 1
  kom.save(serialize())
end

function load()
  W, H = kom.W, kom.H
  C.bg     = kom.rgb(18, 18, 22)
  C.panel  = kom.rgb(28, 28, 34)
  C.panel2 = kom.rgb(38, 38, 46)
  C.rule   = kom.rgb(62, 62, 74)
  C.txt    = kom.rgb(228, 228, 234)
  C.dim    = kom.rgb(132, 132, 146)
  C.acc    = kom.rgb(228, 88, 40)
  C.lite   = kom.rgb(240, 217, 181)
  C.dark   = kom.rgb(168, 124, 88)
  C.lmL    = kom.rgb(214, 208, 116)
  C.lmD    = kom.rgb(176, 158, 78)
  C.selL   = kom.rgb(150, 200, 120)
  C.selring = kom.rgb(96, 226, 108)
  C.selD   = kom.rgb(110, 158, 82)
  C.chk    = kom.rgb(212, 78, 62)
  C.dotL   = kom.rgb(160, 148, 116)
  C.dotD   = kom.rgb(112, 84, 56)
  C.white  = kom.rgb(246, 244, 238)
  C.black  = kom.rgb(52, 50, 58)
  C.gold   = kom.rgb(240, 196, 72)
  C.green  = kom.rgb(110, 200, 120)
  -- One flat tone for all three sprite slots, and it is DARKER than the panel,
  -- not dimmer than the piece: a mid grey silhouette came out the same value as
  -- a live BLACK man (his fill is 58,56,66) and the two were indistinguishable.
  -- A captured slot is a hole punched through the panel instead, which reads the
  -- same way for both colours.
  C.gh = { kom.rgb(16, 16, 20), kom.rgb(16, 16, 20), kom.rgb(16, 16, 20) }
  PALW[1] = kom.rgb(26, 24, 22); PALW[2] = kom.rgb(246, 244, 238); PALW[3] = kom.rgb(190, 184, 172)
  PALB[1] = kom.rgb(12, 12, 14); PALB[2] = kom.rgb(58, 56, 66);    PALB[3] = kom.rgb(126, 124, 136)
  for i = 1, 6 do ART[i] = table.concat(ART[i], "\n") end
  for i = 0, MAXPLY do
    SA[i] = 0; SB[i] = 0; SD[i] = 0; SI[i] = 0; SNn[i] = 0
    SBST[i] = 0; SBM[i] = 0; SCM[i] = 0; SLG[i] = 0; SIC[i] = false; SQF[i] = false
    KIL1[i] = 0; KIL2[i] = 0
  end
  for i = 0, 12 * 120 + 119 do HISQ[i] = 0 end
  math.randomseed(math.floor(kom.time() * 10007) + 7)
  newgame()
  syncDisp()
  local s = kom.load()
  savedata = (s and #s > 4) and 1 or 0
  if s then
    UI.sound = (s:match("s=(%d)") ~= "0")
    UI.dots  = (s:match("o=(%d)") ~= "0")
  end
  UI.st = "menu"
  UI.lastt = kom.time()
end

-- ============================================================================
--  UPDATE
-- ============================================================================
local MEN = {
  main = {"NEW GAME", "RESUME GAME", "LEVEL", "CLOCK", "OPTIONS", "CLEAR SAVE"},
  new  = {"HOTSEAT  2 PLAYER", "PLAY AS WHITE", "PLAY AS BLACK"},
  opt  = {"SOUND", "COORDINATES", "MOVE DOTS", "ANALOG CURSOR", "BACK"},
  pau  = {"RESUME", "UNDO MOVE", "REDO MOVE", "FLIP BOARD", "SAVE GAME", "MAIN MENU"},
}

local function startPlay(eng)
  G.eng = eng
  G.inc = LV.cinc[G.clk]
  G.tw = LV.csec[G.clk]; G.tb = LV.csec[G.clk]
  UI.flip = (eng == 0)
  newgame()
  syncDisp()
  UI.st = "play"
  blip(4)
end

local function menuUpdate()
  local n = #MEN.main
  if kom.btnp("UP")   then UI.sel = UI.sel > 1 and UI.sel - 1 or 1; blip(0) end
  if kom.btnp("DOWN") then UI.sel = UI.sel < n and UI.sel + 1 or n; blip(0) end
  if UI.sel == 3 and (kom.btnp("LEFT") or kom.btnp("RIGHT")) then
    G.lvl = G.lvl + (kom.btnp("LEFT") and -1 or 1)
    if G.lvl < 1 then G.lvl = 4 elseif G.lvl > 4 then G.lvl = 1 end
    blip(1)
  end
  if UI.sel == 4 and (kom.btnp("LEFT") or kom.btnp("RIGHT")) then
    G.clk = G.clk + (kom.btnp("LEFT") and -1 or 1)
    if G.clk < 1 then G.clk = 4 elseif G.clk > 4 then G.clk = 1 end
    blip(1)
  end
  if kom.btnp("X") then
    if UI.sel == 1 then UI.st = "new"; UI.nsel = 1; blip(3)
    elseif UI.sel == 2 then
      if savedata > 0 and loadsave() then blip(4) else blip(5) end
    elseif UI.sel == 5 then UI.st = "opt"; UI.osel = 1; blip(3)
    elseif UI.sel == 6 then cfm, cfm_sel = true, 2; blip(3)
    end
  end
end

local function newUpdate()
  if kom.btnp("UP")   then UI.nsel = UI.nsel > 1 and UI.nsel - 1 or 1; blip(0) end
  if kom.btnp("DOWN") then UI.nsel = UI.nsel < 3 and UI.nsel + 1 or 3; blip(0) end
  if kom.btnp("O") then UI.st = "menu"; blip(2) end
  if kom.btnp("X") then
    startPlay(UI.nsel == 1 and -1 or (UI.nsel == 2 and 1 or 0))
  end
end

local function optUpdate()
  local n = #MEN.opt
  if kom.btnp("UP")   then UI.osel = UI.osel > 1 and UI.osel - 1 or 1; blip(0) end
  if kom.btnp("DOWN") then UI.osel = UI.osel < n and UI.osel + 1 or n; blip(0) end
  if kom.btnp("O") then UI.st = "menu"; blip(2); return end
  if kom.btnp("X") or kom.btnp("LEFT") or kom.btnp("RIGHT") then
    if UI.osel == 1 then UI.sound = not UI.sound
    elseif UI.osel == 2 then UI.coords = not UI.coords
    elseif UI.osel == 3 then UI.dots = not UI.dots
    elseif UI.osel == 4 then UI.freec = not UI.freec
    else UI.st = "menu" end
    blip(1)
  end
end

local function pauseUpdate()
  local n = #MEN.pau
  if kom.btnp("UP")   then UI.psel = UI.psel > 1 and UI.psel - 1 or 1; blip(0) end
  if kom.btnp("DOWN") then UI.psel = UI.psel < n and UI.psel + 1 or n; blip(0) end
  if kom.btnp("O") or kom.btnp("START") then UI.st = "play"; blip(2); return end
  if kom.btnp("X") then
    local s = UI.psel
    if s == 1 then UI.st = "play"; blip(2)
    elseif s == 2 then undoPly(G.eng >= 0 and 2 or 1); UI.st = "play"; blip(1)
    elseif s == 3 then redoPly(G.eng >= 0 and 2 or 1); UI.st = "play"; blip(1)
    elseif s == 4 then UI.flip = not UI.flip; UI.st = "play"; blip(1)
    elseif s == 5 then storesave(); UI.msg = "GAME SAVED"; UI.st = "play"; blip(4)
    else abortThink(); UI.st = "menu"; UI.sel = 1; blip(2) end
  end
end

local function promoUpdate()
  if kom.btnp("LEFT")  then UI.promo = UI.promo > 1 and UI.promo - 1 or 4; blip(0) end
  if kom.btnp("RIGHT") then UI.promo = UI.promo < 4 and UI.promo + 1 or 1; blip(0) end
  if kom.btnp("O") then UI.st = "play"; UI.sel_sq = 0; blip(2); return end
  if kom.btnp("X") then
    local pr = ({5, 4, 3, 2})[UI.promo]
    local m = findmove(UI.pfrom, UI.pto, pr)
    UI.st = "play"
    if m ~= 0 then applyMove(m) end
  end
end

local function playInput(dt)
  if kom.btnp("START") then abortThink(); UI.st = "pause"; UI.psel = 1; blip(3); return end
  if kom.btnp("SQUARE") then UI.flip = not UI.flip; blip(1) end
  if kom.btnp("L") then undoPly(G.eng >= 0 and 2 or 1); return end
  if kom.btnp("R") then redoPly(G.eng >= 0 and 2 or 1); return end
  if thinking then return end
  if not humanTurn() then return end
  if kom.btnp("UP")    then moveCur(0, -1) end
  if kom.btnp("DOWN")  then moveCur(0, 1) end
  if kom.btnp("LEFT")  then moveCur(-1, 0) end
  if kom.btnp("RIGHT") then moveCur(1, 0) end
  local ax, ay = kom.analog()
  if UI.freec then
    if ax > 24 or ax < -24 then UI.fx = UI.fx + ax * 1.6 * dt end
    if ay > 24 or ay < -24 then UI.fy = UI.fy + ay * 1.6 * dt end
    if UI.fx < BX then UI.fx = BX elseif UI.fx > BX + BSZ - 1 then UI.fx = BX + BSZ - 1 end
    if UI.fy < BY then UI.fy = BY elseif UI.fy > BY + BSZ - 1 then UI.fy = BY + BSZ - 1 end
    local nf = (UI.fx - BX) // CELL
    local nr = (UI.fy - BY) // CELL
    local ns = sqAt(nf, nr)
    if ns ~= UI.cur then UI.cur = ns; blip(0) end
  else
    UI.arep = UI.arep - dt
    if UI.arep <= 0 and (ax > 60 or ax < -60 or ay > 60 or ay < -60) then
      UI.arep = 0.16
      local aax = ax < 0 and -ax or ax
      local aay = ay < 0 and -ay or ay
      if aax > aay then moveCur(ax > 0 and 1 or -1, 0)
      else moveCur(0, ay > 0 and 1 or -1) end
    end
  end
  if kom.btnp("X") then trySelect() end
  if kom.btnp("O") then UI.sel_sq = 0; blip(2) end
end

local function clockTick()
  if G.clk <= 1 or G.res or UI.st ~= "play" then return end
  local now = kom.time()
  local d = now - UI.lastt
  UI.lastt = now
  if d <= 0 or d > 1 then return end
  if G.stm == 0 then
    G.tw = G.tw - d
    if G.tw <= 0 then G.tw = 0; G.res = "TIME - BLACK WINS"; G.resw = 1; UI.st = "over" end
  else
    G.tb = G.tb - d
    if G.tb <= 0 then G.tb = 0; G.res = "TIME - WHITE WINS"; G.resw = 0; UI.st = "over" end
  end
end

function update(dt)
  kom.menu(UI.st ~= "play")
  UI.tick = UI.tick + dt
  UI.lastt = kom.time()
  if UI.st == "menu" then menuUpdate(); return end
  if UI.st == "new"  then newUpdate();  return end
  if UI.st == "opt"  then optUpdate();  return end
  if UI.st == "pause" then pauseUpdate(); return end
  if UI.st == "promo" then promoUpdate(); return end
  if UI.st == "over" then
    if kom.btnp("X") or kom.btnp("O") or kom.btnp("START") then
      abortThink(); UI.st = "menu"; UI.sel = 1; blip(2)
    end
    if kom.btnp("L") then undoPly(1) end
    return
  end
  clockTick()
  playInput(dt)
  if UI.st ~= "play" then return end
  if G.res then return end
  -- once a search is under way it MUST be stepped every frame regardless of the
  -- live `stm`: that variable belongs to the paused node, not to the game.
  if not thinking and G.eng >= 0 and G.stm == G.eng and NLEG > 0 then startThink() end
  if thinking then
    UI.spin = UI.spin + dt * 6
    thinkStep()
  end
end

-- ============================================================================
--  DRAW
-- ============================================================================
local function ctext(x, y, s, col, sc)
  kom.text(x - kom.textw(s, sc) // 2, y, s, col, sc)
end

local function piece(p, x, y, s)
  kom.sprite(x, y, s, ART[PT[p]], (p < 7) and PALW or PALB)
end

local function drawBoard()
  kom.rect(BX, BY, BSZ, BSZ, C.lite)
  for r = 0, 7 do
    for f = 0, 7 do
      if (r + f) % 2 == 1 then
        kom.rect(BX + f * CELL, BY + r * CELL, CELL, CELL, C.dark)
      end
    end
  end
  -- last move
  if G.last ~= 0 then
    local a, b = G.last % 128, (G.last // 128) % 128
    for _, s in ipairs({a, b}) do
      local f, r = visOf(s)
      kom.rect(BX + f * CELL, BY + r * CELL, CELL, CELL,
               ((r + f) % 2 == 1) and C.lmD or C.lmL)
    end
  end
  -- selected square
  if UI.sel_sq ~= 0 then
    local f, r = visOf(UI.sel_sq)
    kom.rect(BX + f * CELL, BY + r * CELL, CELL, CELL,
             ((r + f) % 2 == 1) and C.selD or C.selL)
  end
  -- king in check
  if G.chk ~= 0 then
    local f, r = visOf(G.chk)
    kom.rect(BX + f * CELL, BY + r * CELL, CELL, CELL, C.chk)
  end
  -- coordinates, painted into the square corners the way a real board's edge
  -- does it: rank up the a-file, file along rank 1, in the opposite square colour
  if UI.coords then
    for i = 0, 7 do
      kom.text(BX + 2, BY + i * CELL + 2, NM.ra[sqAt(0, i)],
               (i % 2 == 0) and C.dark or C.lite, 1)
      kom.text(BX + i * CELL + CELL - 6, BY + 7 * CELL + CELL - 9, NM.fi[sqAt(i, 7)],
               ((7 + i) % 2 == 1) and C.lite or C.dark, 1)
    end
  end
  -- legal-move markers for the selected piece
  if UI.dots and UI.sel_sq ~= 0 then
    for i = 1, NLEG do
      local m = LEGAL[i]
      if m % 128 == UI.sel_sq then
        local t = (m // 128) % 128
        local f, r = visOf(t)
        local x, y = BX + f * CELL, BY + r * CELL
        local col = ((r + f) % 2 == 1) and C.dotD or C.dotL
        if DB[t] ~= 0 or (m // 131072) == 1 then
          kom.frame(x + 1, y + 1, CELL - 2, CELL - 2, col)
          kom.frame(x + 2, y + 2, CELL - 4, CELL - 4, col)
        else
          kom.circle(x + CELL // 2, y + CELL // 2, 4, col)
        end
      end
    end
  end
  -- pieces, straight off the display board (64 reads, no piece list -- the
  -- engine's piece lists belong to the node it paused on)
  for r = 0, 7 do
    for f = 0, 7 do
      local pc = DB[21 + r * 10 + f]
      if pc ~= 0 then
        local vf, vr = f, r
        if UI.flip then vf = 7 - f; vr = 7 - r end
        piece(pc, BX + vf * CELL + 2, BY + vr * CELL + 2, 2)
      end
    end
  end
  -- rings go ON TOP of the pieces. A 26px piece in a 30px square leaves a 2px
  -- band of the square colour, and 2px of tint under a piece is not a state
  -- anybody can read -- so the two states that MUST be unambiguous get an
  -- outline instead of relying on the fill underneath.
  if G.chk ~= 0 then
    local f, r = visOf(G.chk)
    kom.frame(BX + f * CELL, BY + r * CELL, CELL, CELL, C.chk)
    kom.frame(BX + f * CELL + 1, BY + r * CELL + 1, CELL - 2, CELL - 2, C.chk)
  end
  if UI.sel_sq ~= 0 then
    local f, r = visOf(UI.sel_sq)
    kom.frame(BX + f * CELL, BY + r * CELL, CELL, CELL, C.selring)
    kom.frame(BX + f * CELL + 1, BY + r * CELL + 1, CELL - 2, CELL - 2, C.selring)
  end
  -- cursor: two rings so it reads on a light square AND a dark one
  if UI.st == "play" and humanTurn() and not thinking then
    local f, r = visOf(UI.cur)
    local x, y = BX + f * CELL, BY + r * CELL
    kom.frame(x, y, CELL, CELL, C.acc)
    kom.frame(x + 1, y + 1, CELL - 2, CELL - 2, kom.rgb(20, 18, 16))
  end
  kom.frame(BX - 1, BY - 1, BSZ + 2, BSZ + 2, C.rule)
end

local function clockStr(t)
  if t < 0 then t = 0 end
  local m = math.floor(t / 60)
  local s = math.floor(t - m * 60)
  return string.format("%d:%02d", m, s)
end

-- The army, whole. The old tray drew only what had been CAPTURED, so for the
-- opening minutes of every game it drew a "-" and nothing else -- the weakest
-- thing on a panel that was already the emptiest half of the screen. A roster is
-- true from move zero, says everything the tray said, and says what is still on
-- the board as well. A man who has been taken is left as a flat silhouette in
-- his own slot, which reads as "gone" on both colours; a captured white piece
-- could not be dimmed and a captured black one shaded, they had to be the same.
local function drawForce(col, x, y, sc, per, rows, pit)
  local n, gw, cap = 0, 13 * sc, per * rows
  for t = 6, 1, -1 do
    local p = (col == 0) and t or (t + 6)
    local live = PCNT[p] or 0
    local slots = INITC[t]
    if live > slots then slots = live end          -- promotion: extra queens
    for k = 1, slots do
      if n < cap then
        local gx = x + (n % per) * pit
        local gy = y + (n // per) * (gw + 3)
        if k <= live then piece(p, gx, gy, sc)
        else kom.sprite(gx, gy, sc, ART[PT[p]], C.gh) end
        n = n + 1
      end
    end
  end
end

local function matScore()
  local s = 0
  for t = 1, 5 do
    s = s + (PCNT[t + 6] - INITC[t]) * PVAL[t] - (PCNT[t] - INITC[t]) * PVAL[t]
  end
  return -s
end

local function drawPanel()
  kom.rect(PX0, BY, PW, BSZ, C.panel)
  kom.frame(PX0, BY, PW, BSZ, C.rule)
  local y = BY + 4
  -- turn + clocks
  for i = 0, 1 do
    local ry = y + i * 15
    local on = (G.stm == i) and not G.res
    if on then kom.rect(PX0 + 3, ry - 2, PW - 6, 14, C.panel2) end
    kom.rect(PX0 + 7, ry + 1, 8, 8, (i == 0) and C.white or C.black)
    kom.frame(PX0 + 7, ry + 1, 8, 8, C.rule)
    kom.text(PX0 + 21, ry + 2, (i == 0) and "WHITE" or "BLACK",
             on and C.txt or C.dim, 1)
    if G.clk > 1 then
      local cs = clockStr((i == 0) and G.tw or G.tb)
      kom.text(PX0 + PW - 8 - kom.textw(cs, 1), ry + 2, cs,
               on and C.gold or C.dim, 1)
    elseif on then
      kom.text(PX0 + PW - 8 - kom.textw("TO MOVE", 1), ry + 2, "TO MOVE", C.acc, 1)
    end
  end
  y = y + 32
  kom.rect(PX0 + 4, y, PW - 8, 1, C.rule)
  y = y + 4
  -- The list takes exactly the rows it needs and MATERIAL keeps the rest, so
  -- neither half is ever a hole. At move zero both armies are drawn whole and
  -- large under the clocks; by move forty they are a two-row strip and the list
  -- owns the panel. Both are windowed on the rows that fit (rule 26).
  local bot = BY + BSZ - 4
  local pn = (G.mn + 1) // 2
  local lrows = (pn + 1) // 2
  local lmax = (bot - y - 19 - 50) // 9
  if lmax < 1 then lmax = 1 end
  if lrows > lmax then lrows = lmax end
  local fh = bot - y - 19 - lrows * 9

  local ms = matScore()
  local mstr, mcol = "EVEN", C.dim
  if ms > 0 then mstr, mcol = "WHITE +" .. (ms // 100), C.green
  elseif ms < 0 then mstr, mcol = "BLACK +" .. ((-ms) // 100), C.green end
  kom.text(PX0 + 8, y, "MATERIAL", C.dim, 1)
  kom.text(PX0 + PW - 8 - kom.textw(mstr, 1), y, mstr, mcol, 1)
  do
    local area = fh - 12
    local per, sc = 16, 1
    if area >= 76 then per = 8 end
    if per == 8 and area >= 124 then sc = 2 end
    local gw = 13 * sc
    local rws = 16 // per
    -- the eight roster columns keep the SAME x positions at either scale, so the
    -- block folds down in place instead of collapsing into a narrow left column
    local pit = (PW - 16) // per
    local blk = rws * (gw + 3)
    local gap = (area - blk * 2) // 3
    if gap < 2 then gap = 2 end
    local fx = PX0 + (PW - (per - 1) * pit - gw) // 2
    local fy = y + 12 + gap
    local bw = (per - 1) * pit + gw
    -- a lighter bed under each army: a live BLACK man is only 58,56,66 and on
    -- the bare panel he barely separated from it
    kom.rect(fx - 4, fy - 2, bw + 8, blk, C.panel2)
    kom.rect(fx - 4, fy + blk + gap - 2, bw + 8, blk, C.panel2)
    drawForce(0, fx, fy, sc, per, rws, pit)
    drawForce(1, fx, fy + blk + gap, sc, per, rws, pit)
  end

  local ly = y + fh
  kom.rect(PX0 + 4, ly, PW - 8, 1, C.rule)
  kom.text(PX0 + 8, ly + 4, "MOVES", C.dim, 1)
  local mv = "MOVE " .. tostring(G.mn // 2 + 1)
  kom.text(PX0 + PW - 8 - kom.textw(mv, 1), ly + 4, mv, C.dim, 1)
  ly = ly + 15
  local cap = lrows * 2
  local first = 1
  if pn > cap then first = pn - cap + 1 end
  for i = 0, cap - 1 do
    local p2 = first + i
    if p2 > pn then break end
    local cx = PX0 + 6 + (i // lrows) * ((PW - 12) // 2)
    local cy = ly + (i % lrows) * 9
    kom.text(cx, cy, tostring(p2) .. ".", C.dim, 1)
    kom.text(cx + 20, cy, G.san[p2 * 2 - 1] or "", C.txt, 1)
    kom.text(cx + 62, cy, G.san[p2 * 2] or "", C.txt, 1)
  end
end

local function drawBars()
  kom.rect(0, 0, W, 15, C.panel)
  kom.rect(0, 15, W, 1, C.rule)
  -- a king glyph as the title mark, so the bar is not bare text
  piece(6, 2, 1, 1)
  kom.text(18, 4, "CHESS", C.txt, 1)
  local m
  if G.res then m = G.res
  elseif thinking then
    local dots = ("..."):sub(1, 1 + (math.floor(UI.spin) % 3))
    m = "THINKING" .. dots .. "  D" .. tostring(iterd)
  elseif G.chk ~= 0 then m = "CHECK"
  else m = (G.stm == 0 and "WHITE" or "BLACK") .. " TO MOVE" end
  ctext(W // 2 + 20, 4, m, thinking and C.gold or (G.res and C.acc or C.txt), 1)
  kom.rect(0, H - 15, W, 15, C.panel)
  kom.rect(0, H - 16, W, 1, C.rule)
  local l = LV.nm[G.lvl] .. "  " ..
            (G.eng < 0 and "HOTSEAT" or (G.eng == 1 and "YOU WHITE" or "YOU BLACK"))
  kom.text(6, H - 11, l, C.dim, 1)
  local r = NM.sq[UI.cur] or ""
  if UI.msg ~= "" then r = UI.msg end
  kom.text(W - 6 - kom.textw(r, 1), H - 11, r, C.dim, 1)
end

local function popup(lines, edge)
  local bw = 0
  for i = 1, #lines do
    local w = kom.textw(lines[i][1], lines[i][2])
    if w > bw then bw = w end
  end
  bw = bw + 40
  local bh = 20
  for i = 1, #lines do bh = bh + 8 * lines[i][2] + 6 end
  local bx, by = W // 2 - bw // 2, H // 2 - bh // 2
  kom.rect(bx, by, bw, bh, kom.rgb(10, 10, 12))
  kom.frame(bx, by, bw, bh, edge)
  kom.frame(bx + 1, by + 1, bw - 2, bh - 2, C.rule)
  local ty = by + 10
  for i = 1, #lines do
    ctext(W // 2, ty, lines[i][1], lines[i][3], lines[i][2])
    ty = ty + 8 * lines[i][2] + 6
  end
end

-- a live board beside the menu: the position you would RESUME into, or the
-- opening array. It is what fills the right half of the title screen, and it is
-- the same DB the game draws from, so it is never a lie about what is stored.
local function drawMini(x, y, cell)
  kom.rect(x, y, cell * 8, cell * 8, C.lite)
  for r = 0, 7 do
    for f = 0, 7 do
      if (r + f) % 2 == 1 then kom.rect(x + f * cell, y + r * cell, cell, cell, C.dark) end
      local pc = DB[21 + r * 10 + f]
      if pc ~= 0 then piece(pc, x + f * cell + (cell - 13) // 2,
                                y + r * cell + (cell - 13) // 2, 1) end
    end
  end
  kom.frame(x - 1, y - 1, cell * 8 + 2, cell * 8 + 2, C.rule)
end

local function menuFrame()
  kom.clear(C.bg)
  kom.rect(0, 0, W, 46, C.panel)
  kom.rect(0, 46, W, 1, C.acc)
  piece(6, 8, 8, 2)
  piece(5, 36, 8, 2)
  kom.text(70, 8, "CHESS", C.txt, 3)
  kom.text(70, 32, "FULL RULES  ALPHA-BETA ENGINE", C.dim, 1)
  drawMini(310, 60, 18)
  local st = (savedata > 0) and ("SAVED GAME  " .. tostring((G.mn + 1) // 2) .. " MOVES")
             or "NO SAVED GAME"
  kom.text(310 + 72 - kom.textw(st, 1) // 2, 212, st, C.dim, 1)
  kom.rect(0, H - 15, W, 15, C.panel)
  kom.rect(0, H - 16, W, 1, C.rule)
  kom.text(6, H - 11, LV.nm[G.lvl] .. "   " .. LV.cnm[G.clk], C.dim, 1)
  local v = "V1.0"
  kom.text(W - 6 - kom.textw(v, 1), H - 11, v, C.rule, 1)
end

local function drawMenuRow(x, y, w, s, val, sel, dimmed)
  if sel then
    kom.rect(x, y, w, 15, C.panel2)
    kom.rect(x, y, 2, 15, C.acc)
    kom.rect(x + w - 2, y, 2, 15, C.acc)
  end
  kom.text(x + 10, y + 4, s, dimmed and C.rule or (sel and C.txt or C.dim), 1)
  if val then
    kom.text(x + w - 10 - kom.textw(val, 1), y + 4, val, sel and C.gold or C.dim, 1)
  end
end

function draw()
  if UI.st == "menu" or UI.st == "new" or UI.st == "opt" then
    menuFrame()
    local x, w = 14, 270
    -- pitch derived from the row count, never a constant (ship rule 26)
    local list, sel, head, vals
    if UI.st == "menu" then
      list, sel = MEN.main, UI.sel
      vals = {nil, nil, LV.nm[G.lvl], LV.cnm[G.clk], nil, nil}
    elseif UI.st == "new" then
      list, sel, head = MEN.new, UI.nsel, "NEW GAME"
    else
      list, sel, head = MEN.opt, UI.osel, "OPTIONS"
      vals = {UI.sound and "ON" or "OFF", UI.coords and "ON" or "OFF",
              UI.dots and "ON" or "OFF", UI.freec and "FREE" or "STEP", nil}
    end
    local top = 58
    if head then kom.text(x + 2, top, head, C.dim, 1); top = top + 14 end
    local avail = H - 22 - top
    local pitch = avail // #list
    if pitch > 24 then pitch = 24 elseif pitch < 16 then pitch = 16 end
    for i = 1, #list do
      local y = top + (i - 1) * pitch
      if y + 15 > H - 18 then break end
      drawMenuRow(x, y, w, list[i], vals and vals[i], sel == i,
                  (UI.st == "menu" and i == 2 and savedata == 0))
    end
    return
  end

  kom.clear(C.bg)
  drawBoard()
  drawPanel()
  drawBars()

  if UI.st == "promo" then
    local bw, bh = 4 * 34 + 32, 74
    local bx, by = W // 2 - bw // 2, H // 2 - bh // 2
    kom.rect(bx, by, bw, bh, kom.rgb(10, 10, 12))
    kom.frame(bx, by, bw, bh, C.gold)
    kom.frame(bx + 1, by + 1, bw - 2, bh - 2, C.rule)
    ctext(W // 2, by + 8, "PROMOTE TO", C.txt, 1)
    local ps = {5, 4, 3, 2}
    for i = 1, 4 do
      local px = bx + 16 + (i - 1) * 34
      if i == UI.promo then
        kom.rect(px - 2, by + 22, 32, 34, C.panel2)
        kom.frame(px - 2, by + 22, 32, 34, C.acc)
      end
      piece(ps[i] + (G.stm == 1 and 6 or 0), px, by + 24, 2)
    end
  elseif UI.st == "pause" then
    local bw = 190
    local bh = 26 + #MEN.pau * 18
    local bx, by = W // 2 - bw // 2, H // 2 - bh // 2
    kom.rect(bx, by, bw, bh, kom.rgb(10, 10, 12))
    kom.frame(bx, by, bw, bh, C.acc)
    kom.frame(bx + 1, by + 1, bw - 2, bh - 2, C.rule)
    ctext(W // 2, by + 7, "PAUSED", C.gold, 1)
    for i = 1, #MEN.pau do
      drawMenuRow(bx + 8, by + 20 + (i - 1) * 18, bw - 16, MEN.pau[i], nil, UI.psel == i,
                  (i == 2 and G.mn == 0) or (i == 3 and G.mn >= G.mtot))
    end
  elseif UI.st == "over" and G.res then
    popup({
      {G.res, 1, G.resw == 2 and C.gold or C.txt},
      {"MOVES " .. tostring((G.mn + 1) // 2), 1, C.dim},
    }, G.resw == 2 and C.gold or C.acc)
  end
end

-- ============================================================================
--  CLEAR SAVE CONFIRM  (house rule: selectable YES/NO, NO highlighted first)
-- ============================================================================
local function cfm_draw(msg)
  local mw = kom.textw(msg, 1)
  local bw = (mw > 132 and mw or 132) + 44
  local bh = 72
  local bx = W // 2 - bw // 2
  local by = H // 2 - bh // 2
  kom.rect(0, by - 10, W, bh + 20, C.bg)
  kom.rect(0, by - 10, W, 1, C.rule)
  kom.rect(0, by + bh + 9, W, 1, C.rule)
  kom.rect(bx, by, bw, bh, kom.rgb(0, 0, 0))
  kom.frame(bx, by, bw, bh, C.acc)
  kom.frame(bx + 1, by + 1, bw - 2, bh - 2, C.rule)
  kom.text(W // 2 - mw // 2, by + 16, msg, C.txt, 1)
  local ans = {"YES", "NO"}
  for i = 1, 2 do
    local s = ans[i]
    local tw = kom.textw(s, 1)
    local x = W // 2 + (i == 1 and -42 or 42) - tw // 2
    local y = by + 46
    if i == cfm_sel then
      kom.rect(x - 12, y - 4, tw + 24, 15, C.panel2)
      kom.frame(x - 12, y - 4, tw + 24, 15, C.acc)
      kom.rect(x - 12, y - 4, 2, 15, C.acc)
      kom.rect(x + tw + 10, y - 4, 2, 15, C.acc)
    end
    kom.text(x, y, s, (i == cfm_sel) and C.acc or C.dim, 1)
  end
end

local __cfm_update, __cfm_draw = update, draw
function update(dt)
  if cfm then
    kom.menu(true)
    if kom.btnp("LEFT") or kom.btnp("RIGHT") then cfm_sel = 3 - cfm_sel; kom.sfx(0) end
    if kom.btnp("O") then cfm = false; kom.sfx(2); return end
    if kom.btnp("X") then
      if cfm_sel == 1 then savedata = 0; kom.save("") end
      cfm = false; kom.sfx(2)
    end
    return
  end
  __cfm_update(dt)
end
function draw()
  __cfm_draw()
  if cfm then cfm_draw("CLEAR SAVED GAME?") end
end
