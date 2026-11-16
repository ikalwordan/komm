-- @name Tetris
-- @display fullscreen
local cfm, cfm_sel = false, 2   -- reset confirm; NO is the default

-- v4 VISUAL PASS
--  * the well is 130x260 -- it now runs the FULL height of the screen instead of
--    floating in the middle of it, and the two 156px bands either side became real
--    panels (HOLD + stats + controls left, a three-deep NEXT queue + status right)
--    rather than loose text with a 74px dead strip on the right edge
--  * tetromino colours are the classic seven and J/L are the right way round (J was
--    orange and L was blue, which is backwards); every tile is bevelled from a
--    PRECOMPUTED face/light/dark triple, so no colour arithmetic happens per cell
--  * juice: two-phase line clear (strobe, then the row collapses to the centre),
--    screen shake, a ghost in the piece's own colour, lock-delay brightening, a
--    level-up banner, and clear names (TETRIS / T-SPIN / B2B / COMBO) in the panel
--  * empty cells used to cost a kom.pset EACH -- 200 a frame on an empty board. The
--    well grid is 27 lines drawn once instead.

-- ============================================================
--  CONSTANTS
-- ============================================================
local COLS, ROWS = 10, 20
local CELL        = 13
local BW, BH      = COLS*CELL, ROWS*CELL
local BOARD_X, BOARD_Y = 0, 6           -- BOARD_X set in load() from kom.W
local PANW        = 156
local PL_X, PR_X  = 8, 0                -- PR_X set in load()
local FLASH_T     = 0.30

-- Tetrominoes: each piece = list of {r,c} offsets from pivot
local PIECES = {
  -- I
  { cells = {{0,-1},{0,0},{0,1},{0,2}} },
  -- O
  { cells = {{0,0},{0,1},{1,0},{1,1}} },
  -- T
  { cells = {{0,0},{0,-1},{0,1},{-1,0}} },
  -- S
  { cells = {{0,0},{-1,0},{-1,1},{0,-1}} },
  -- Z
  { cells = {{0,0},{-1,-1},{-1,0},{0,1}} },
  -- J
  { cells = {{0,0},{0,-1},{0,1},{-1,-1}} },
  -- L
  { cells = {{0,0},{0,-1},{0,1},{-1,1}} },
}

-- The classic seven, kept as COMPONENTS. A kom.rgb value is write-only on this
-- console, so anything that needs a lighter or darker version of a colour has to be
-- built from the numbers here and cached -- never taken back apart.
local PRGB = {
  {  0, 222, 222 },   -- I  cyan
  { 244, 202,  24 },  -- O  yellow
  { 172,  54, 214 },  -- T  purple
  {  46, 208,  76 },  -- S  green
  { 230,  52,  52 },  -- Z  red
  {  52, 104, 240 },  -- J  blue
  { 242, 140,  26 },  -- L  orange
}

-- ============================================================
--  GLOBALS
-- ============================================================
local state           -- "menu" | "play" | "pause" | "gameover"
local board           -- [row][col] = piece kind 1..7, or 0
local cur             -- current piece {cells,kind,pr,pc}
local next_piece, hold_piece
local hold_used       -- hold is limited to once per falling piece
local piece_queue     -- shuffled seven-bags waiting to be dealt
local score, lines, level
local combo, back_to_back
local drop_timer, drop_interval
local lock_timer, lock_delay
local das_timer, das_delay, das_repeat -- delayed auto-shift
local das_dir
local flash_timer, flash_rows
local menu_sel
local hi_score, new_best
local msg, msg_t                       -- clear name shown in the STATUS panel
local lvl_t                            -- level-up banner
local shake_t

-- ============================================================
--  COLOUR PALETTE  (built in load, after kom is ready)
-- ============================================================
local FACE, LIT, DRK, GHOSTC = {}, {}, {}, {}
local LOCKR = {}          -- per kind, 3 progressively brighter faces
local PBOX  = {}          -- per kind, spawn bounding box for previews
local WELL, GRID, PANEL, HEADBG, EDGE, INK, INK2, GOLD, WHITE, DIMV

-- ============================================================
--  HELPERS
-- ============================================================
local function new_board()
  local b = {}
  for r = 1, ROWS do
    b[r] = {}
    for c = 1, COLS do b[r][c] = 0 end
  end
  return b
end

local function rotated(cells, times)
  times = (times or 1) % 4
  local c = cells
  for _ = 1, times do
    local n = {}
    for _, rc in ipairs(c) do n[#n+1] = {rc[2], -rc[1]} end
    c = n
  end
  return c
end

local I_ROTATIONS = {
  {{0,-1},{0,0},{0,1},{0,2}},
  {{-1,1},{0,1},{1,1},{2,1}},
  {{1,-1},{1,0},{1,1},{1,2}},
  {{-1,0},{0,0},{1,0},{2,0}},
}

local function cells_at_rotation(kind, rotation)
  if kind == 1 then return I_ROTATIONS[rotation + 1] end
  if kind == 2 then return PIECES[kind].cells end
  return rotated(PIECES[kind].cells, rotation)
end

-- SRS kick offsets stored as {row, column}, converted from the standard {x, y} tables.
local JLSTZ_KICKS = {
  ["0>1"]={{0,0},{0,-1},{-1,-1},{2,0},{2,-1}},
  ["1>0"]={{0,0},{0,1},{1,1},{-2,0},{-2,1}},
  ["1>2"]={{0,0},{0,1},{1,1},{-2,0},{-2,1}},
  ["2>1"]={{0,0},{0,-1},{-1,-1},{2,0},{2,-1}},
  ["2>3"]={{0,0},{0,1},{-1,1},{2,0},{2,1}},
  ["3>2"]={{0,0},{0,-1},{1,-1},{-2,0},{-2,-1}},
  ["3>0"]={{0,0},{0,-1},{1,-1},{-2,0},{-2,-1}},
  ["0>3"]={{0,0},{0,1},{-1,1},{2,0},{2,1}},
}

local I_KICKS = {
  ["0>1"]={{0,0},{0,-2},{0,1},{1,-2},{-2,1}},
  ["1>0"]={{0,0},{0,2},{0,-1},{-1,2},{2,-1}},
  ["1>2"]={{0,0},{0,-1},{0,2},{-2,-1},{1,2}},
  ["2>1"]={{0,0},{0,1},{0,-2},{2,1},{-1,-2}},
  ["2>3"]={{0,0},{0,2},{0,-1},{-1,2},{2,-1}},
  ["3>2"]={{0,0},{0,-2},{0,1},{1,-2},{-2,1}},
  ["3>0"]={{0,0},{0,1},{0,-2},{2,1},{-1,-2}},
  ["0>3"]={{0,0},{0,-1},{0,2},{-2,-1},{1,2}},
}

local function piece_fits(cells, pr, pc)
  for _, rc in ipairs(cells) do
    local r, c = pr + rc[1], pc + rc[2]
    if r > ROWS or c < 1 or c > COLS then return false end
    if r >= 1 and board[r][c] ~= 0 then return false end
  end
  return true
end

local function try_rotate(direction)
  if cur.kind == 2 then return end -- O does not change orientation in SRS
  local from = cur.rotation
  local to = (from + direction) % 4
  local cells = cells_at_rotation(cur.kind, to)
  local kicks = (cur.kind == 1 and I_KICKS or JLSTZ_KICKS)[from..">"..to]
  for kick_index, kick in ipairs(kicks) do
    local pr, pc = cur.pr + kick[1], cur.pc + kick[2]
    if piece_fits(cells, pr, pc) then
      cur.cells = cells
      cur.rotation = to
      cur.pr, cur.pc = pr, pc
      cur.last_rotation = true
      cur.last_kick = kick_index
      lock_timer = nil
      kom.sfx(0)
      return
    end
  end
end

local function spawn_piece(p)
  local cells = {}
  for _, rc in ipairs(PIECES[p].cells) do cells[#cells+1] = {rc[1], rc[2]} end
  local spawn_row = (p == 1 or p == 2) and 1 or 2
  cur = { cells = cells, kind = p, rotation = 0, pr = spawn_row, pc = 5,
          last_rotation = false, last_kick = nil }
  if not piece_fits(cur.cells, cur.pr, cur.pc) then
    state = "gameover"
    -- latch the record BEFORE save_hi() raises it, or the panel says NEW BEST every
    -- time (save_hi runs once a frame for as long as the screen is up)
    new_best = score > hi_score
    kom.sfx(5)
  end
end

local function add_bag()
  local bag = {}
  for p = 1, #PIECES do bag[p] = p end
  for i = #bag, 2, -1 do
    local j = math.random(1, i)
    bag[i], bag[j] = bag[j], bag[i]
  end
  for _, p in ipairs(bag) do piece_queue[#piece_queue+1] = p end
end

-- keep at least three in hand: the NEXT panel shows a three-deep queue, and a bag
-- that only refills when it is EMPTY leaves that panel with holes in it
local function next_from_bag()
  if #piece_queue <= 3 then add_bag() end
  return table.remove(piece_queue, 1)
end

local function occupied(r, c)
  if r < 1 or r > ROWS or c < 1 or c > COLS then return true end
  return board[r][c] ~= 0
end

local function spin_type()
  if cur.kind ~= 3 or not cur.last_rotation then return nil end
  local r, c = cur.pr, cur.pc
  local corners = {
    occupied(r-1,c-1), occupied(r-1,c+1),
    occupied(r+1,c-1), occupied(r+1,c+1),
  }
  local count = 0
  for _, filled in ipairs(corners) do if filled then count = count + 1 end end
  if count < 3 then return nil end

  local front
  if cur.rotation == 0 then front = {corners[1], corners[2]}
  elseif cur.rotation == 1 then front = {corners[2], corners[4]}
  elseif cur.rotation == 2 then front = {corners[3], corners[4]}
  else front = {corners[1], corners[3]} end
  if (front[1] and front[2]) or cur.last_kick == 5 then return "full" end
  return "mini"
end

local CLEAR_NAME = { "SINGLE", "DOUBLE", "TRIPLE", "TETRIS" }

local function lock_piece()
  local spin = spin_type()
  for _, rc in ipairs(cur.cells) do
    local r, c = cur.pr + rc[1], cur.pc + rc[2]
    if r >= 1 and r <= ROWS then
      board[r][c] = cur.kind
    end
  end
  -- check full rows
  local full = {}
  for r = 1, ROWS do
    local ok = true
    for c = 1, COLS do if board[r][c] == 0 then ok = false; break end end
    if ok then full[#full+1] = r end
  end
  if #full > 0 then
    flash_rows = full
    flash_timer = FLASH_T
    local cleared = #full
    local base
    if spin == "full" then base = ({400,800,1200,1600})[cleared+1]
    elseif spin == "mini" then base = ({100,200,400})[cleared+1] or 400
    else base = ({100,300,500,800})[cleared] end
    -- a piece can only complete four rows, so every lookup above is in range for
    -- any state the game can reach -- but a nil here is an arithmetic crash two
    -- lines down, and a scoring table is not worth a hard lock (ship rule 16)
    if not base then base = 800 end

    local difficult = cleared == 4 or (spin ~= nil and cleared > 0)
    local was_back_to_back = back_to_back
    if difficult then
      if was_back_to_back then base = math.floor(base * 1.5) end
      back_to_back = true
    else
      back_to_back = false
    end

    combo = combo + 1
    score = score + (base + 50 * combo) * level

    local name = CLEAR_NAME[cleared] or "CLEAR"
    if spin == "full" then name = "T-SPIN "..name
    elseif spin == "mini" then name = "MINI T-SPIN "..name end
    if difficult and was_back_to_back then name = "B2B "..name end

    -- A clear is perfect when every row not being removed is empty.
    local perfect = true
    local clearing = {}
    for _, r in ipairs(full) do clearing[r] = true end
    for r = 1, ROWS do
      if not clearing[r] then
        for c = 1, COLS do
          if board[r][c] ~= 0 then perfect = false; break end
        end
      end
      if not perfect then break end
    end
    if perfect then
      local pc_bonus = ({800,1200,1800,2000})[cleared]
      if cleared == 4 and was_back_to_back then pc_bonus = 3200 end
      score = score + pc_bonus * level
      name = "PERFECT CLEAR"
    end
    msg, msg_t = name, 1.8
    shake_t = (cleared == 4) and 0.24 or 0.12

    lines = lines + #full
    local new_level = math.floor(lines / 10) + 1
    if new_level > level then
      level = new_level
      drop_interval = math.max(0.05, 0.5 - (level-1)*0.04)
      lvl_t = 1.2
      -- level-up fanfare
      kom.tone(523,80,0,90) kom.tone(659,80,0,90) kom.tone(784,120,0,90)
    end
    -- line-clear sfx
    if #full == 4 then
      kom.tone(880,200,1,100) kom.tone(1100,200,1,100)
    else
      kom.tone(440,100,0,80) kom.tone(660,120,0,80)
    end
  else
    if spin == "full" then score = score + 400 * level; msg, msg_t = "T-SPIN", 1.4
    elseif spin == "mini" then score = score + 100 * level; msg, msg_t = "MINI T-SPIN", 1.4 end
    combo = -1
    kom.tone(220,60,2,50)   -- soft thud
  end
  -- spawn next
  local np = next_piece
  next_piece = next_from_bag()
  spawn_piece(np)
  hold_used = false
  lock_timer = nil
  drop_timer = 0
end

local function remove_full_rows()
  if not flash_rows then return end
  for _, fr in ipairs(flash_rows) do
    table.remove(board, fr)
    local nr = {}
    for c = 1, COLS do nr[c] = 0 end
    table.insert(board, 1, nr)
  end
  flash_rows = nil
end

local function ghost_row()
  local pr = cur.pr
  while piece_fits(cur.cells, pr + 1, cur.pc) do pr = pr + 1 end
  return pr
end

local function save_hi()
  if score > hi_score then
    hi_score = score
    kom.save(tostring(hi_score))
  end
end

-- ============================================================
--  LOAD
-- ============================================================
function load()
  math.randomseed(math.floor(kom.time() * 1000))

  WELL   = kom.rgb(8, 9, 14)
  GRID   = kom.rgb(28, 30, 44)
  PANEL  = kom.rgb(18, 19, 28)
  HEADBG = kom.rgb(32, 34, 50)
  EDGE   = kom.rgb(56, 60, 86)
  INK    = kom.rgb(232, 236, 246)
  INK2   = kom.rgb(142, 150, 176)
  GOLD   = kom.rgb(255, 206, 84)
  WHITE  = kom.rgb(255, 255, 255)
  DIMV   = kom.rgb(6, 7, 11)

  -- every shade a tile can ever need, built ONCE from the components above
  for k = 1, 7 do
    local r, g, b = PRGB[k][1], PRGB[k][2], PRGB[k][3]
    FACE[k]   = kom.rgb(r, g, b)
    LIT[k]    = kom.rgb(r + (255-r)*0.50, g + (255-g)*0.50, b + (255-b)*0.50)
    DRK[k]    = kom.rgb(r*0.42, g*0.42, b*0.42)
    GHOSTC[k] = kom.rgb(r*0.55 + 8, g*0.55 + 9, b*0.55 + 14)
    LOCKR[k]  = {}
    -- lock-delay brightening. It stops well short of white on purpose: a piece
    -- that blanches to paper loses the one thing the player is tracking it by.
    for i = 1, 3 do
      local t = 0.12 + i*0.14
      LOCKR[k][i] = kom.rgb(r + (255-r)*t, g + (255-g)*t, b + (255-b)*t)
    end
    -- spawn bounding box, so a preview can be CENTRED instead of hand-offset
    local mnr, mxr, mnc, mxc = 9, -9, 9, -9
    for _, rc in ipairs(PIECES[k].cells) do
      if rc[1] < mnr then mnr = rc[1] end
      if rc[1] > mxr then mxr = rc[1] end
      if rc[2] < mnc then mnc = rc[2] end
      if rc[2] > mxc then mxc = rc[2] end
    end
    PBOX[k] = { mnr, mxr, mnc, mxc }
  end

  BOARD_X = (kom.W - BW) // 2
  PR_X    = kom.W - PL_X - PANW

  hi_score = tonumber(kom.load() or "") or 0
  menu_sel = 1
  msg, msg_t, lvl_t, shake_t = nil, 0, 0, 0
  new_best = false
  state = "menu"
end

-- ============================================================
--  START GAME
-- ============================================================
local function start_game()
  board = new_board()
  score = 0
  lines = 0
  level = 1
  combo = -1
  back_to_back = false
  drop_interval = 0.5
  drop_timer = 0
  lock_timer = nil
  lock_delay = 0.45
  das_timer = 0
  das_delay = 0.18
  das_repeat = 0.06
  das_dir = nil
  flash_rows = nil
  flash_timer = 0
  hold_piece = nil
  hold_used = false
  msg, msg_t, lvl_t, shake_t = nil, 0, 0, 0
  new_best = false
  piece_queue = {}
  spawn_piece(next_from_bag())
  next_piece = next_from_bag()
  state = "play"
end

-- ============================================================
--  UPDATE
-- ============================================================
function update(dt)
  kom.menu(state ~= "play")   -- shell transport reachable from our own menu

  if state == "menu" then
    if kom.btnp("UP")   then menu_sel = math.max(1, menu_sel-1); kom.sfx(0) end
    if kom.btnp("DOWN") then menu_sel = math.min(2, menu_sel+1); kom.sfx(0) end
    if kom.btnp("X") or kom.btnp("O") then
      if menu_sel == 1 then start_game()
      else
        cfm, cfm_sel = true, 2; kom.sfx(3)
      end
    end
    return
  end

  if state == "gameover" then
    save_hi()
    if kom.btnp("X") or kom.btnp("O") then state = "menu" end
    return
  end

  if state == "pause" then
    if kom.btnp("TRIANGLE") then state = "play"; kom.sfx(3) end
    return
  end

  -- PLAY --
  if kom.btnp("TRIANGLE") then state = "pause"; kom.sfx(2); return end

  -- presentation timers run even while the board is frozen mid-clear, otherwise
  -- the shake and the banner both stall on the one frame they matter most
  if msg_t   > 0 then msg_t   = msg_t - dt end
  if lvl_t   > 0 then lvl_t   = lvl_t - dt end
  if shake_t > 0 then shake_t = shake_t - dt end

  -- flash delay (don't accept input while rows flash)
  if flash_timer > 0 then
    flash_timer = flash_timer - dt
    if flash_timer <= 0 then remove_full_rows() end
    return
  end

  -- hold once per falling piece; held pieces respawn in their original orientation
  if kom.btnp("UP") and not hold_used then
    local outgoing = cur.kind
    if hold_piece then
      local incoming = hold_piece
      hold_piece = outgoing
      spawn_piece(incoming)
    else
      hold_piece = outgoing
      local incoming = next_piece
      next_piece = next_from_bag()
      spawn_piece(incoming)
    end
    hold_used = true
    lock_timer = nil
    drop_timer = 0
    das_dir = nil
    kom.sfx(0)
    return
  end

  -- rotate: shoulder and face-button pairs mirror each other
  if kom.btnp("L") or kom.btnp("SQUARE") then try_rotate(-1) end -- CCW
  if kom.btnp("R") or kom.btnp("O")      then try_rotate(1)  end -- CW

  -- hard drop
  if kom.btnp("X") then
    local gr = ghost_row()
    score = score + (gr - cur.pr) * 2
    if gr > cur.pr then cur.last_rotation = false end
    cur.pr = gr
    lock_piece()
    kom.tone(180, 80, 0, 70)
    return
  end

  -- DAS left/right
  local lr = nil
  if kom.btn("LEFT")  then lr = -1 end
  if kom.btn("RIGHT") then lr =  1 end
  if lr then
    if das_dir ~= lr then das_dir = lr; das_timer = das_delay
      if piece_fits(cur.cells, cur.pr, cur.pc + lr) then
        cur.pc = cur.pc + lr; kom.sfx(0)
        cur.last_rotation = false
        lock_timer = nil
      end
    else
      das_timer = das_timer - dt
      if das_timer <= 0 then
        das_timer = das_repeat
        if piece_fits(cur.cells, cur.pr, cur.pc + lr) then
          cur.pc = cur.pc + lr; kom.sfx(0)
          cur.last_rotation = false
          lock_timer = nil
        end
      end
    end
  else
    das_dir = nil
  end

  -- soft drop
  if kom.btn("DOWN") then drop_timer = drop_timer + dt * 12 end

  -- gravity
  drop_timer = drop_timer + dt
  if drop_timer >= drop_interval then
    drop_timer = 0
    if piece_fits(cur.cells, cur.pr + 1, cur.pc) then
      cur.pr = cur.pr + 1
      cur.last_rotation = false
      if kom.btn("DOWN") then score = score + 1 end
      lock_timer = nil
    else
      -- start lock delay
      if lock_timer == nil then lock_timer = lock_delay end
    end
  end

  -- lock delay
  if lock_timer ~= nil then
    lock_timer = lock_timer - dt
    if lock_timer <= 0 then lock_piece() end
  end
end

-- ============================================================
--  DRAW HELPERS
-- ============================================================

-- one bevelled tile. The bevel width follows the tile size so a 9px preview cell
-- does not end up more edge than face.
local function tile(px, py, sz, k, face)
  local b = (sz >= 11) and 2 or 1
  kom.rect(px, py, sz-1, sz-1, face or FACE[k])
  kom.rect(px, py, sz-1, b, LIT[k])
  kom.rect(px, py, b, sz-1, LIT[k])
  kom.rect(px, py + sz-1-b, sz-1, b, DRK[k])
end

local function panel(x, y, w, h, title)
  kom.rect(x, y, w, h, PANEL)
  kom.frame(x, y, w, h, EDGE)
  kom.rect(x+1, y+1, w-2, 11, HEADBG)
  kom.rect(x+1, y+12, w-2, 1, EDGE)
  kom.text(x+6, y+3, title, kom.col.accent, 1)
end

local function ctext(cx, y, s, col, sc)
  kom.text(cx - kom.textw(s, sc)//2, y, s, col, sc)
end

-- a piece drawn centred inside a box, from its precomputed bounding box
local function preview(bx, by, bw, bh, k, sz)
  if not k then return end
  local bb = PBOX[k]
  local w = (bb[4]-bb[3]+1) * sz
  local h = (bb[2]-bb[1]+1) * sz
  local ox = bx + (bw - w)//2 - bb[3]*sz
  local oy = by + (bh - h)//2 - bb[1]*sz
  for _, rc in ipairs(PIECES[k].cells) do
    tile(ox + rc[2]*sz, oy + rc[1]*sz, sz, k)
  end
end

local function slot(x, y, w, h, k, sz)
  kom.rect(x, y, w, h, DIMV)
  kom.frame(x, y, w, h, EDGE)
  preview(x, y, w, h, k, sz)
end

local function is_flashing(r)
  if not flash_rows then return false end
  for i = 1, #flash_rows do if flash_rows[i] == r then return true end end
  return false
end

local function draw_board(bx, by)
  kom.rect(bx, by, BW, BH, WELL)
  -- the well grid used to be one kom.pset per EMPTY cell -- 200 calls on an empty
  -- board. 27 lines draw the same lattice and never scale with how empty it is.
  for c = 1, COLS-1 do kom.line(bx + c*CELL, by, bx + c*CELL, by + BH - 1, GRID) end
  for r = 1, ROWS-1 do kom.line(bx, by + r*CELL, bx + BW - 1, by + r*CELL, GRID) end
  kom.frame(bx-1, by-1, BW+2, BH+2, EDGE)
  kom.frame(bx-3, by-3, BW+6, BH+6, kom.col.accent)
  kom.frame(bx-4, by-4, BW+8, BH+8, PANEL)

  for r = 1, ROWS do
    if not is_flashing(r) then
      local row = board[r]
      local py = by + (r-1)*CELL
      for c = 1, COLS do
        local k = row[c]
        if k ~= 0 then tile(bx + (c-1)*CELL, py, CELL, k) end
      end
    end
  end

  -- the clear, in two phases: the row STROBES, then it collapses to the centre.
  -- Recolouring the cells and deleting them a fifth of a second later (the old
  -- behaviour) never read as anything happening.
  if flash_rows then
    for i = 1, #flash_rows do
      local py = by + (flash_rows[i]-1)*CELL
      if flash_timer > FLASH_T*0.5 then
        local on = math.floor(flash_timer * 45) % 2 == 0
        kom.rect(bx, py, BW, CELL-1, on and WHITE or GOLD)
      else
        local w = math.floor(BW * (flash_timer / (FLASH_T*0.5)))
        kom.rect(bx, py, BW, CELL-1, WELL)
        kom.rect(bx + (BW-w)//2, py, w, CELL-1, WHITE)
      end
    end
  end
end

local function draw_ghost(bx, by)
  local gr = ghost_row()
  if gr == cur.pr then return end
  local col = GHOSTC[cur.kind]
  for _, rc in ipairs(cur.cells) do
    local r, c = gr + rc[1], cur.pc + rc[2]
    if r >= 1 and r <= ROWS then
      local px, py = bx + (c-1)*CELL, by + (r-1)*CELL
      kom.frame(px, py, CELL-1, CELL-1, col)
      kom.rect(px + CELL//2 - 1, py + CELL//2 - 1, 2, 2, col)
    end
  end
end

local function draw_piece(bx, by)
  -- the piece brightens as the lock delay runs out, so "it is about to set" is
  -- something you can SEE rather than something you learn by losing
  local face = nil
  if lock_timer then
    local t = 1 - (lock_timer / lock_delay)
    local i = 1 + math.floor(t * 2.99)
    if i < 1 then i = 1 elseif i > 3 then i = 3 end
    face = LOCKR[cur.kind][i]
  end
  for _, rc in ipairs(cur.cells) do
    local r, c = cur.pr + rc[1], cur.pc + rc[2]
    if r >= 1 and r <= ROWS then
      tile(bx + (c-1)*CELL, by + (r-1)*CELL, CELL, cur.kind, face)
    end
  end
end

-- ============================================================
--  PANELS
-- ============================================================
-- one label/value line. A panel that is only populated while something transient
-- is happening reads as broken chrome the rest of the time, so every row here has a
-- resting value ("-") rather than vanishing.
local function kv(x, y, w, k, v, col)
  kom.text(x + 7, y, k, INK2, 1)
  kom.text(x + w - 7 - kom.textw(v, 1), y, v, col, 1)
end

local function stat_row(x, y, w, label, value, col)
  kom.text(x + 7, y + 1, label, INK2, 1)
  local s = tostring(value)
  kom.text(x + w - 7 - kom.textw(s, 2), y + 9, s, col, 2)
end

local function draw_left()
  panel(PL_X, 6, PANW, 64, "HOLD")
  slot(PL_X + 40, 24, 76, 40, hold_piece, 9)
  -- the hold is once per piece; say so, rather than leaving a box that looks live
  if hold_used then kom.text(PL_X + PANW - 6 - kom.textw("USED",1), 9, "USED", INK2, 1) end

  panel(PL_X, 74, PANW, 118, "STATS")
  stat_row(PL_X, 90,  PANW, "SCORE", score, GOLD)
  stat_row(PL_X, 116, PANW, "LINES", lines, INK)
  stat_row(PL_X, 142, PANW, "LEVEL", level, kom.col.accent)
  stat_row(PL_X, 168, PANW, "BEST",  hi_score, INK2)

  panel(PL_X, 196, PANW, 70, "CONTROLS")
  local cx = PL_X + 7
  local rows = {
    "L / \21    ROTATE CCW",
    "R / O     ROTATE CW",
    "DOWN       SOFT DROP",
    "X          HARD DROP",
    "UP              HOLD",
    "\18              PAUSE",
  }
  for i, r in ipairs(rows) do kom.text(cx, 212 + (i-1)*9, r, INK2, 1) end
end

local function draw_right()
  panel(PR_X, 6, PANW, 132, "NEXT")
  slot(PR_X + 8, 23, PANW - 16, 54, next_piece, 12)
  slot(PR_X + 8, 82, 66, 46, piece_queue[1], 9)
  slot(PR_X + 82, 82, 66, 46, piece_queue[2], 9)

  panel(PR_X, 142, PANW, 124, "STATUS")
  kv(PR_X, 160, PANW, "LAST",  msg or "-",                        msg and INK or INK2)
  kv(PR_X, 174, PANW, "COMBO", combo > 0 and ("X"..combo) or "-", combo > 0 and GOLD or INK2)
  kv(PR_X, 188, PANW, "B2B",   back_to_back and "ON" or "-",
     back_to_back and kom.col.accent or INK2)
  kom.rect(PR_X + 7, 202, PANW - 14, 1, EDGE)

  -- lines-to-next-level, as a bar rather than arithmetic the player has to do
  kom.text(PR_X + 7, 210, "NEXT LEVEL", INK2, 1)
  local into = lines % 10
  local bx, bw2 = PR_X + 7, PANW - 14
  kom.rect(bx, 222, bw2, 10, DIMV)
  kom.frame(bx, 222, bw2, 10, EDGE)
  if into > 0 then kom.rect(bx + 1, 223, (bw2 - 2) * into // 10, 8, kom.col.accent) end
  kv(PR_X, 238, PANW, "ROWS",  into.." / 10", INK)
  kv(PR_X, 252, PANW, "GRAVITY", string.format("%.2fS", drop_interval), INK2)
end

-- ============================================================
--  MENU DRAW
-- ============================================================
local function draw_menu()
  local cx = kom.W // 2
  kom.text(cx - kom.textw("TETRIS",4)//2 + 2, 28, "TETRIS", EDGE, 4)
  kom.text(cx - kom.textw("TETRIS",4)//2, 26, "TETRIS", GOLD, 4)
  ctext(cx, 60, "KOMSTATION ARCADE", INK2, 1)

  -- the seven, in their own colours, on a rail: decoration that doubles as the key
  -- to which block is which
  local sz = 9
  local total = 0
  for k = 1, 7 do total = total + (PBOX[k][4] - PBOX[k][3] + 1) * sz end
  total = total + 6 * 12
  local x = cx - total // 2
  kom.rect(cx - total//2 - 8, 106, total + 16, 1, EDGE)
  for k = 1, 7 do
    local bb = PBOX[k]
    local w = (bb[4] - bb[3] + 1) * sz
    local h = (bb[2] - bb[1] + 1) * sz
    for _, rc in ipairs(PIECES[k].cells) do
      tile(x + (rc[2] - bb[3])*sz, 104 - h + (rc[1] - bb[1])*sz, sz, k)
    end
    x = x + w + 12
  end

  local items = {"START GAME", "RESET HI-SCORE"}
  for i, item in ipairs(items) do
    local iy = 130 + (i-1)*28
    local w = kom.textw(item, 2)
    if menu_sel == i then
      kom.rect(cx - w//2 - 12, iy - 5, w + 24, 22, HEADBG)
      kom.frame(cx - w//2 - 12, iy - 5, w + 24, 22, kom.col.accent)
      kom.rect(cx - w//2 - 12, iy - 5, 3, 22, kom.col.accent)
      ctext(cx, iy, item, kom.col.accent, 2)
    else
      ctext(cx, iy, item, INK, 2)
    end
  end

  local s = "BEST  "..tostring(hi_score)
  local bw2 = kom.textw(s, 2) + 40
  kom.rect(cx - bw2//2, 200, bw2, 26, PANEL)
  kom.frame(cx - bw2//2, 200, bw2, 26, EDGE)
  ctext(cx, 206, s, GOLD, 2)

  ctext(cx, kom.H - 22, "X SELECT", INK2, 1)
end

-- ============================================================
--  OVERLAY PANELS  (sized FROM their text -- ship rule 13)
-- ============================================================
local function box(lines2, scales)
  local bw2 = 0
  for i, l in ipairs(lines2) do
    local w = kom.textw(l, scales[i])
    if w > bw2 then bw2 = w end
  end
  bw2 = bw2 + 44
  local bh2 = 20
  for i = 1, #lines2 do bh2 = bh2 + (scales[i] == 2 and 22 or 13) end
  local bx = kom.W//2 - bw2//2
  local by = kom.H//2 - bh2//2
  kom.rect(bx, by, bw2, bh2, PANEL)
  kom.frame(bx, by, bw2, bh2, kom.col.accent)
  kom.frame(bx+2, by+2, bw2-4, bh2-4, EDGE)
  local y = by + 10
  for i, l in ipairs(lines2) do
    ctext(kom.W//2, y, l, i == 1 and GOLD or INK, scales[i])
    y = y + (scales[i] == 2 and 22 or 13)
  end
end

-- ============================================================
--  DRAW
-- ============================================================
function draw()
  kom.clear(kom.col.bg)

  if state == "menu" then
    draw_menu()
    return
  end

  local sx, sy = 0, 0
  if shake_t > 0 then
    local k = math.floor(shake_t * 70)
    sx = ((k % 3) - 1) * 2
    sy = ((k % 2) * 2) - 1
  end
  local bx, by = BOARD_X + sx, BOARD_Y + sy

  draw_board(bx, by)

  -- The callouts sit over the WELL, arcade style -- but UNDER the falling piece.
  -- Drawn on top they would hide the piece for the second and a half after a spin,
  -- which is a gameplay bug wearing a presentation costume.
  if msg_t > 0 and msg and state == "play" then
    local sc = (kom.textw(msg, 2) <= BW - 8) and 2 or 1
    local w = kom.textw(msg, sc)
    local h = (sc == 2) and 22 or 14
    kom.rect(BOARD_X + BW//2 - w//2 - 8, BOARD_Y + 24, w + 16, h, PANEL)
    kom.frame(BOARD_X + BW//2 - w//2 - 8, BOARD_Y + 24, w + 16, h, GOLD)
    ctext(BOARD_X + BW//2, BOARD_Y + 28, msg, GOLD, sc)
  end
  if lvl_t > 0 and state == "play" then
    local y = BOARD_Y + BH//2 - 14
    kom.rect(BOARD_X - 4, y, BW + 8, 28, PANEL)
    kom.frame(BOARD_X - 4, y, BW + 8, 28, kom.col.accent)
    ctext(BOARD_X + BW//2, y + 7, "LEVEL "..level, GOLD, 2)
  end

  if state == "play" and not flash_rows then
    draw_ghost(bx, by)
    draw_piece(bx, by)
  end
  draw_left()
  draw_right()

  if state == "gameover" then
    kom.rect(BOARD_X, BOARD_Y, BW, BH, DIMV)
    box({ "GAME OVER", "SCORE "..tostring(score), "LINES "..tostring(lines),
          new_best and "NEW BEST!" or ("BEST "..tostring(hi_score)) },
        { 2, 1, 1, 1 })
  elseif state == "pause" then
    box({ "PAUSED", "\18 RESUME" }, { 2, 1 })
  end
end

-- ---- RESET CONFIRM (house rule: selectable YES/NO, NO highlighted first) -----
-- Wiping a score used to happen on one X press with nothing in between. This
-- wraps update/draw rather than rewriting the menu: the prompt paints over
-- whatever is on screen and swallows input while it is up.
local function cfm_draw(msg2)
  local W2, H2 = kom.W, kom.H
  local mw = kom.textw(msg2, 1)
  local bw2 = (mw > 132 and mw or 132) + 44
  local bh2 = 72
  local bx = W2 // 2 - bw2 // 2
  local by = H2 // 2 - bh2 // 2
  kom.rect(0, by - 10, W2, bh2 + 20, kom.col.bg)      -- curtain: it is a MODAL
  kom.rect(0, by - 10, W2, 1, EDGE)
  kom.rect(0, by + bh2 + 9, W2, 1, EDGE)
  kom.rect(bx, by, bw2, bh2, PANEL)
  kom.frame(bx, by, bw2, bh2, kom.col.accent)
  kom.frame(bx + 2, by + 2, bw2 - 4, bh2 - 4, EDGE)
  kom.text(W2 // 2 - mw // 2, by + 16, msg2, INK, 1)
  local ans = { "YES", "NO" }
  for i = 1, 2 do
    local s = ans[i]
    local tw = kom.textw(s, 1)
    local x = W2 // 2 + (i == 1 and -42 or 42) - tw // 2
    local y = by + 46
    if i == cfm_sel then
      kom.rect(x - 12, y - 4, tw + 24, 15, HEADBG)
      kom.frame(x - 12, y - 4, tw + 24, 15, kom.col.accent)
      kom.rect(x - 12, y - 4, 2, 15, kom.col.accent)
      kom.rect(x + tw + 10, y - 4, 2, 15, kom.col.accent)
    end
    kom.text(x, y, s, (i == cfm_sel) and kom.col.accent or INK2, 1)
  end
end

local __cfm_update, __cfm_draw = update, draw
function update(dt)
  if cfm then
    kom.menu(true)                       -- this IS our own menu (ship rule 19)
    if kom.btnp("LEFT") or kom.btnp("RIGHT") then
      cfm_sel = 3 - cfm_sel; kom.sfx(0)
    end
    if kom.btnp("O") then cfm = false; kom.sfx(2); return end
    if kom.btnp("X") then
      if cfm_sel == 1 then hi_score = 0; kom.save("0") end
      cfm = false; kom.sfx(2)
    end
    return
  end
  __cfm_update(dt)
end
function draw()
  __cfm_draw()
  if cfm then cfm_draw("RESET HI-SCORE?") end
end
