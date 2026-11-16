-- @name Arkanoid
-- @display fullscreen
local cfm, cfm_sel = false, 2   -- reset confirm; NO is the default

-- ============================================================
--  SCREEN / PLAY FIELD
--  v5 (visual pass): the field is now WIDE. A 480x272 screen wants a
--  landscape brick wall, not a ported-portrait column with a dead sidebar
--  eating 120px. Everything the sidebar used to hold moved into the top bar
--  and a chip strip along the floor.
-- ============================================================
local W, H = 480, 272            -- filled from kom.W/kom.H in load()
local PF_X, PF_Y = 8, 22
local PF_W, PF_H = 464, 246

local B_COLS   = 16
local B_ROWS   = 8
local B_W      = 29              -- 16 * 29 = 464 = PF_W exactly
local B_H      = 13
local B_PAD_X  = PF_X
local B_PAD_Y  = PF_Y + 18

local PAD_W_NORMAL = 60
local PAD_H        = 7
local PAD_Y_OFF    = 18
-- v6 (operator: "paddle is too slow compared to the distance the ball travels").
-- The field is 464 wide. At 250 px/s the paddle needed 1.86s to cross it, and a
-- ball dropping straight down from the top of the wall arrives in about 1.4s --
-- so there were reachable balls the paddle physically could not get to, however
-- early you started moving. 420 px/s crosses the full field in 1.1s, which is
-- inside the fastest fall, so every ball on the screen is now winnable.
local PAD_SPEED    = 420

local BALL_R        = 4
local BALL_BASE_SPD = 170
local TRAIL         = 5

local PU_W, PU_H = 22, 9

-- ============================================================
--  COLOURS  (components kept; a kom.rgb value is WRITE-ONLY)
-- ============================================================
local TIER_RGB = {
  {232, 64, 60},   -- 1 red
  {242,140, 44},   -- 2 orange
  {238,214, 64},   -- 3 yellow
  { 74,200, 96},   -- 4 green
  { 64,178,232},   -- 5 cyan
  {158,104,236},   -- 6 violet
  {206,178, 96},   -- 7 gold (G bricks)
}
local BR_FACE, BR_LITE, BR_DARK = {}, {}, {}
local TRAIL_A, TRAIL_B = {}, {}          -- ball-trail ramps: normal / thru
local ROW_COLS = {}                      -- face colour per tier (particles, chips)
local C_WHITE, C_BLACK
local C_FIELD, C_GRID, C_BEZ, C_BEZ_L, C_BEZ_D
local C_DOT, C_RAIL, C_FLOOR1, C_FLOOR2, C_FLOOR3, C_HALO, C_FLASH
local C_BAR, C_BAR_L, C_STEEL, C_STEEL_L
local C_SHADOW

-- ============================================================
--  LEVEL LAYOUTS  (16 wide, 8 rows -- rebuilt for the wide field)
-- ============================================================
local LEVELS = {
  {
    "................",
    "1111111111111111",
    "2222222222222222",
    "3333333333333333",
    "4444444444444444",
    "5555555555555555",
    "66666666GG666666",
    "................",
  },
  {
    "1.1.1.1.1.1.1.1.",
    ".2.2.2.2.2.2.2.2",
    "3.3.3.3.3.3.3.3.",
    ".4.4.4.4.4.4.4.4",
    "5.5.5.5.5.5.5.5.",
    ".G.G.G.G.G.G.G.G",
    "6.6.6.6.6.6.6.6.",
    "................",
  },
  {
    ".......11.......",
    "......1221......",
    ".....122221.....",
    "....12333321....",
    "...1234443211...",
    "..123455543211..",
    ".12345666543211.",
    "..GGGG....GGGG..",
  },
  {
    "1.2.3.4.5.6.1.2.",
    ".2.3.4.5.6.1.2.3",
    "3.4.5.6.1.2.3.4.",
    ".4.5.6.1.2.3.4.5",
    "5.6.1.2.3.4.5.6.",
    ".6.1.2.3.4.5.6.1",
    "1.2.3.4.5.6.1.2.",
    ".2.3.4.5.6.1.2.3",
  },
  {
    "......1111......",
    ".....111111.....",
    "....22222222....",
    "...3333333333...",
    "..444444444444..",
    ".55555555555555.",
    "6666666666666666",
    "GG............GG",
  },
  {
    "G1G1G1G1G1G1G1G1",
    "2222222222222222",
    "3.3.3.3.3.3.3.3.",
    ".1.1.1.1.1.1.1.1",
    "2222222222222222",
    "3.3.3.3.3.3.3.3.",
    "1111111111111111",
    "22222222GG222222",
  },
}
local LEVEL_NAMES = {"BANDS","CHECKER","PYRAMID","DIAGONAL","WEDGE","FORTRESS"}

-- ============================================================
--  POWER-UP TYPES
-- ============================================================
local PU_TYPES  = {"E","S","M","L","T","C"}
local PU_LABELS = {E="EXP",S="SLW",M="MLT",L="+1L",T="THR",C="CGH"}
local PU_COLS_I = {E=4, S=5, M=2, L=3, T=6, C=1}

-- ============================================================
--  STATE VARS
-- ============================================================
local state, menu_sel
local paddle_x, paddle_w
local balls, bricks, powerups
-- wall-strike flashes: which wall, where on it, and how long it has left. The
-- rails are lit for ~5 frames where the ball actually hit, so a bounce off an
-- empty wall reads as a contact instead of the ball silently changing its mind.
local wall_fx_l, wall_fx_r, wall_fx_t = 0, 0, 0
local wall_fx_ly, wall_fx_ry, wall_fx_tx = 0, 0, 0
local score, lives, level_num, hi_score
local brick_count
local active_pus
local catch_held, catch_ball_dx
local level_clear_timer, intro_timer
local screen_flash, flash_col
local combo, combo_timer
local particles
local shake

-- ============================================================
--  GAME KIT (sound gate + tolerant save; no BGM by design)
-- ============================================================
local opt_sel
local opts = { sound = true }
local ktone, ksfx = kom.tone, kom.sfx
local function snd(f,ms,w,v,f2) if opts.sound then ktone(f,ms,w,v,f2) end end
local function blip(id)          if opts.sound then ksfx(id) end end
local function save_state()
  kom.save("snd="..(opts.sound and "1" or "0")..";hi="..(hi_score or 0))
end
local function load_state()
  local s = kom.load() or ""
  if s:find("=") then
    opts.sound = (s:match("snd=(%d)") ~= "0")
    hi_score   = tonumber(s:match("hi=(%d+)")) or 0
  else
    hi_score  = tonumber(s) or 0   -- tolerant of the old bare-number save
    opts.sound = true
  end
end

-- ============================================================
--  HELPERS
-- ============================================================
local krect, kframe, ktext, ktextw = kom.rect, kom.frame, kom.text, kom.textw
local kcircle, ktri, kline = kom.circle, kom.tri, kom.line

local function clamp(v,lo,hi2) return math.max(lo,math.min(hi2,v)) end

local function pad_y() return PF_Y + PF_H - PAD_Y_OFF - PAD_H end

local function spawn_particles(x,y,col,n)
  if #particles > 110 then return end       -- a burst must never become the frame
  n = n or 6
  for _=1,n do
    local a = math.random()*math.pi*2
    local spd = math.random(30,110)
    particles[#particles+1] = {
      x=x, y=y,
      vx=math.cos(a)*spd, vy=math.sin(a)*spd,
      life=0.35+math.random()*0.3, max_life=0.65, col=col
    }
  end
end

-- SLW is a MULTIPLIER ON A BASE SPEED, never an edit to the velocity (v6,
-- operator: "slow effects are permanent and dont expire causing the game to slow
-- down"). It used to scale vx,vy by 0.65 on pickup and NOTHING put them back --
-- only the paddle-expand powerup restored itself when its timer ran out. So every
-- SLW you collected multiplied the ball speed by 0.65 FOREVER, they stacked
-- (0.65^2, 0.65^3...), and a ball spawned while SLW was up was born slow and
-- stayed slow. Each ball now carries the speed it is SUPPOSED to have and the
-- slow is applied fresh every frame, so it cannot leak past its timer.
local function slow_mul() return (active_pus.S > 0) and 0.65 or 1 end

local function new_ball(x,y,ang)
  ang = ang or (-math.pi/2 + (math.random()-0.5)*0.5)
  local base = BALL_BASE_SPD * (1 + (level_num-1)*0.05)
  local spd = base * slow_mul()
  local b = {x=x,y=y, vx=math.cos(ang)*spd, vy=math.sin(ang)*spd, active=true,
             base=base, tx={}, ty={}, ti=1}
  for i=1,TRAIL do b.tx[i]=x; b.ty[i]=y end
  return b
end

local function parse_level(idx)
  local layout = LEVELS[((idx-1) % #LEVELS)+1]
  bricks = {}
  brick_count = 0
  for r=1,B_ROWS do
    bricks[r] = {}
    local row_str = layout[r] or ""
    for c=1,B_COLS do
      local ch = row_str:sub(c,c)
      if ch == '.' or ch == '' then
        bricks[r][c] = nil
      elseif ch == 'G' then
        -- gold is TOUGH, not immortal: 3 hits, so no level is ever sealed
        bricks[r][c] = {hp=3, max_hp=3, tier=7}
        brick_count = brick_count + 1
      else
        local tier = clamp(tonumber(ch) or 1, 1, 6)
        local hp = (tier == 6) and 2 or 1
        bricks[r][c] = {hp=hp, max_hp=hp, tier=tier}
        brick_count = brick_count + 1
      end
    end
  end
end

local function start_level(lvl)
  level_num = lvl
  parse_level(lvl)
  paddle_w = PAD_W_NORMAL
  paddle_x = PF_X + PF_W/2 - paddle_w/2
  powerups = {}
  wall_fx_l, wall_fx_r, wall_fx_t = 0, 0, 0
  active_pus = {E=0,S=0,T=0,C=0}   -- must exist before new_ball (reads active_pus.S)
  local bx = PF_X + PF_W/2
  local by = pad_y() - BALL_R - 2
  balls = { new_ball(bx,by) }
  balls[1].vy = -math.abs(balls[1].vy)
  catch_held = false
  catch_ball_dx = paddle_w/2
  combo = 0
  combo_timer = 0
  level_clear_timer = 0
  intro_timer = 1.4
  screen_flash = 0
  shake = 0
  flash_col = nil
  state = "intro"
end

local function start_game()
  math.randomseed(math.floor(kom.time()*10000))
  score = 0
  lives = 3
  particles = {}
  start_level(1)
end

-- ============================================================
--  BALL vs RECT  (returns "top"/"bot"/"left"/"right" or nil)
-- ============================================================
local function ball_vs_rect(bx,by,rx,ry,rw,rh)
  local ex,ey = rx-BALL_R, ry-BALL_R
  local ew,eh = rw+BALL_R*2, rh+BALL_R*2
  if bx < ex or bx > ex+ew or by < ey or by > ey+eh then return nil end
  local dl = bx-ex
  local dr = ex+ew-bx
  local dt2 = by-ey
  local db = ey+eh-by
  local m = math.min(dl,dr,dt2,db)
  if m==dt2 then return "top"
  elseif m==db then return "bot"
  elseif m==dl then return "left"
  else return "right" end
end

-- ============================================================
--  LOAD
-- ============================================================
local function mix(c, t, r2, g2, b2)
  return kom.rgb(c[1] + (r2-c[1])*t, c[2] + (g2-c[2])*t, c[3] + (b2-c[3])*t)
end

function load()
  W, H = kom.W, kom.H
  for i = 1, 7 do
    local c = TIER_RGB[i]
    BR_FACE[i] = kom.rgb(c[1], c[2], c[3])
    BR_LITE[i] = mix(c, 0.55, 255, 255, 255)
    BR_DARK[i] = kom.rgb(c[1]*0.42, c[2]*0.42, c[3]*0.42)
    ROW_COLS[i] = BR_FACE[i]
  end
  for i = 1, TRAIL do
    local t = i / (TRAIL + 1)                     -- 1 = oldest / dimmest
    TRAIL_A[i] = kom.rgb(255*t*0.9 + 20, 205*t*0.9 + 14, 60*t*0.9 + 24)
    TRAIL_B[i] = kom.rgb(158*t*0.9 + 20, 104*t*0.9 + 14, 236*t*0.9 + 24)
  end
  C_WHITE  = kom.rgb(255,255,255)
  C_BLACK  = kom.rgb(0,0,0)
  C_FIELD  = kom.rgb(13,13,22)
  C_GRID   = kom.rgb(26,26,42)
  C_BEZ    = kom.rgb(66,68,88)
  C_BEZ_L  = kom.rgb(126,130,158)
  C_BEZ_D  = kom.rgb(30,30,44)
  C_BAR    = kom.rgb(26,26,38)
  C_BAR_L  = kom.rgb(80,82,104)
  C_STEEL  = kom.rgb(150,156,178)
  C_STEEL_L= kom.rgb(226,230,244)
  C_SHADOW = kom.rgb(6,6,10)
  -- v6 visual pass. The empty half of the field was a black void with two sets of
  -- full-length grid lines drawn across it, which read as graph paper rather than
  -- as depth. A dot lattice, a lit floor under the paddle and a neon rail down
  -- each side give the space somewhere to be without competing with the bricks.
  C_DOT    = kom.rgb(34,34,54)
  C_RAIL   = kom.rgb(58,120,190)
  C_FLOOR1 = kom.rgb(18,20,34)
  C_FLOOR2 = kom.rgb(24,27,44)
  C_FLOOR3 = kom.rgb(30,34,56)
  C_HALO   = kom.rgb(120,80,30)
  C_FLASH  = kom.rgb(255,255,255)
  load_state()
  particles = {}
  menu_sel = 1
  opt_sel = 1
  shake = 0
  state = "menu"
end

local function update_particles(dt)
  local i=1
  while i <= #particles do
    local p = particles[i]
    p.x = p.x + p.vx*dt
    p.y = p.y + p.vy*dt
    p.vy = p.vy + 150*dt
    p.life = p.life - dt
    if p.life <= 0 then table.remove(particles,i) else i=i+1 end
  end
end

-- ============================================================
--  UPDATE
-- ============================================================
function update(dt)
  kom.menu(state ~= "play" and state ~= "intro")

  if state == "menu" then
    if kom.btnp("UP")   then menu_sel=math.max(1,menu_sel-1); blip(0) end
    if kom.btnp("DOWN") then menu_sel=math.min(3,menu_sel+1); blip(0) end
    if kom.btnp("X") or kom.btnp("O") then
      if menu_sel==1 then start_game()
      elseif menu_sel==2 then state="options"; blip(1)
      else cfm, cfm_sel = true, 2; blip(3) end
    end
    return
  end

  if state == "options" then
    if kom.btnp("LEFT") or kom.btnp("RIGHT") or kom.btnp("X") then opts.sound=not opts.sound; save_state(); blip(1) end
    if kom.btnp("O") then state="menu"; blip(2) end
    return
  end

  if state == "gameover" or state == "win" then
    if score > hi_score then hi_score=score; save_state() end
    update_particles(dt)
    if shake > 0 then shake = shake - dt end
    if kom.btnp("X") or kom.btnp("O") then
      state="menu"
    end
    return
  end

  if state == "pause" then
    if kom.btnp("TRIANGLE") then state="play"; blip(3) end
    return
  end

  if state == "intro" then
    intro_timer = intro_timer - dt
    if kom.btnp("X") or kom.btnp("O") then intro_timer = 0 end
    if intro_timer <= 0 then state = "play" end
    return
  end

  if state == "levelclear" then
    update_particles(dt)
    level_clear_timer = level_clear_timer + dt
    if level_clear_timer > 2.2 then
      if level_num >= #LEVELS * 2 then state="win"
      else start_level(level_num+1) end
    end
    return
  end

  -- PLAY
  if kom.btnp("TRIANGLE") then state="pause"; blip(2); return end

  update_particles(dt)
  if screen_flash > 0 then screen_flash = screen_flash - dt*4 end
  if shake > 0 then shake = shake - dt end
  if combo_timer > 0 then
    combo_timer = combo_timer - dt
    if combo_timer <= 0 then combo=0 end
  end

  if wall_fx_l > 0 then wall_fx_l = wall_fx_l - dt end
  if wall_fx_r > 0 then wall_fx_r = wall_fx_r - dt end
  if wall_fx_t > 0 then wall_fx_t = wall_fx_t - dt end
  -- bricks is bricks[row][col], not a flat list -- ipairs over it walks the ROWS
  for r = 1, B_ROWS do
    local brow = bricks[r]
    if brow then
      for c = 1, B_COLS do
        local br = brow[c]
        if br and br.flash and br.flash > 0 then br.flash = br.flash - dt end
      end
    end
  end

  for k,_ in pairs(active_pus) do
    if active_pus[k] > 0 then
      active_pus[k] = active_pus[k] - dt
      if active_pus[k] <= 0 then
        active_pus[k] = 0
        if k=="E" then paddle_w = PAD_W_NORMAL end
      end
    end
  end

  -- paddle
  local ax,_ = kom.analog()
  local move = 0
  if kom.btn("LEFT")  then move=-1 end
  if kom.btn("RIGHT") then move=1  end
  if math.abs(ax) > 20 then move=ax/128 end
  paddle_x = clamp(paddle_x + move*PAD_SPEED*dt, PF_X, PF_X+PF_W-paddle_w)

  -- catch hold
  if catch_held then
    if kom.btnp("X") or kom.btnp("O") then
      catch_held=false
      local b=balls[1]
      b.vy=-math.abs(b.vy)
      blip(1)
    end
    local b=balls[1]
    b.x=paddle_x+catch_ball_dx
    b.y=pad_y()-BALL_R-1
    return
  end

  -- count active balls
  local act=0
  for _,b in ipairs(balls) do if b.active then act=act+1 end end

  local bi=1
  while bi <= #balls do
    local b=balls[bi]
    if not b.active then bi=bi+1; goto cont end

    -- hold the ball at the speed it is SUPPOSED to have. Direction is whatever
    -- the bounces made it; magnitude is always base * the live slow multiplier,
    -- so SLW ending restores full speed by itself and cannot stack.
    do
      local want = (b.base or BALL_BASE_SPD) * slow_mul()
      local sp = math.sqrt(b.vx*b.vx + b.vy*b.vy)
      if sp > 0.001 and math.abs(sp - want) > 0.5 then
        local k = want / sp
        b.vx = b.vx * k; b.vy = b.vy * k
      end
    end

    b.x=b.x+b.vx*dt
    b.y=b.y+b.vy*dt

    local ti = b.ti % TRAIL + 1
    b.ti = ti; b.tx[ti] = b.x; b.ty[ti] = b.y

    -- walls
    if b.x-BALL_R < PF_X then
      b.x=PF_X+BALL_R; b.vx=math.abs(b.vx); snd(440,30,2,60)
      wall_fx_l, wall_fx_ly = 0.09, b.y
    end
    if b.x+BALL_R > PF_X+PF_W then
      b.x=PF_X+PF_W-BALL_R; b.vx=-math.abs(b.vx); snd(440,30,2,60)
      wall_fx_r, wall_fx_ry = 0.09, b.y
    end
    if b.y-BALL_R < PF_Y then
      b.y=PF_Y+BALL_R; b.vy=math.abs(b.vy); snd(440,30,2,60)
      wall_fx_t, wall_fx_tx = 0.09, b.x
    end

    -- anti-stale: the vertical component always carries >=25% of the speed (and
    -- the horizontal >=10%), so the ball can never ping-pong sideways forever
    do
      local spd2 = math.sqrt(b.vx*b.vx + b.vy*b.vy)
      if spd2 > 1 then
        if math.abs(b.vy) < spd2*0.25 then
          local sy2 = (b.vy < 0) and -1 or 1
          if b.vy == 0 then sy2 = -1 end
          b.vy = sy2 * spd2*0.25
          local sx2 = (b.vx < 0) and -1 or 1
          b.vx = sx2 * math.sqrt(math.max(0, spd2*spd2 - b.vy*b.vy))
        elseif math.abs(b.vx) < spd2*0.10 then
          local sx2 = (b.vx < 0) and -1 or 1
          if b.vx == 0 then sx2 = 1 end
          b.vx = sx2 * spd2*0.10
          local sy2 = (b.vy < 0) and -1 or 1
          b.vy = sy2 * math.sqrt(math.max(0, spd2*spd2 - b.vx*b.vx))
        end
      end
    end

    -- lost
    if b.y-BALL_R > PF_Y+PF_H+10 then
      b.active=false; act=act-1
      if act <= 0 then
        lives=lives-1
        shake = 0.35
        snd(320,240,1,42,140); snd(160,360,1,32,80)   -- soft descending loss
        if lives <= 0 then
          state="gameover"
        else
          balls={}
          local nb=new_ball(paddle_x+paddle_w/2, pad_y()-BALL_R-2)
          nb.vy=-math.abs(nb.vy)
          balls[1]=nb
          if active_pus.C > 0 then catch_held=true; catch_ball_dx=paddle_w/2 end
        end
      end
      bi=bi+1; goto cont
    end

    -- paddle
    local ps = ball_vs_rect(b.x,b.y, paddle_x,pad_y(), paddle_w,PAD_H)
    if ps then
      local rel = clamp((b.x-(paddle_x+paddle_w/2))/(paddle_w/2),-0.9,0.9)
      local spd = math.sqrt(b.vx*b.vx+b.vy*b.vy)
      local ang = rel*(math.pi/3)
      b.vx=spd*math.sin(ang)
      b.vy=-math.abs(spd*math.cos(ang))
      b.y=pad_y()-BALL_R-1
      blip(0)
      if active_pus.C > 0 and #balls==1 then
        catch_held=true; catch_ball_dx=b.x-paddle_x
      end
      combo=0; combo_timer=0
    end

    -- bricks: only the cells the ball's swollen box can touch, not all 128
    do
      local c0 = math.floor((b.x - BALL_R - B_PAD_X) / B_W) + 1
      local c1 = math.floor((b.x + BALL_R - B_PAD_X) / B_W) + 1
      local r0 = math.floor((b.y - BALL_R - B_PAD_Y) / B_H) + 1
      local r1 = math.floor((b.y + BALL_R - B_PAD_Y) / B_H) + 1
      if c0 < 1 then c0 = 1 end
      if c1 > B_COLS then c1 = B_COLS end
      if r0 < 1 then r0 = 1 end
      if r1 > B_ROWS then r1 = B_ROWS end
      for r=r0,r1 do
        local brow = bricks[r]
        for c=c0,c1 do
          local br=brow[c]
          if br then
            local bx2=B_PAD_X+(c-1)*B_W
            local by2=B_PAD_Y+(r-1)*B_H
            local hs=ball_vs_rect(b.x,b.y, bx2,by2, B_W-1,B_H-1)
            if hs then
              if not (active_pus.T > 0) then
                if hs=="top" or hs=="bot" then b.vy=-b.vy else b.vx=-b.vx end
              end
              br.hp=br.hp-1
              br.flash = 0.07              -- a survived hit has to LAND visually
              spawn_particles(bx2+B_W/2, by2+B_H/2, BR_LITE[br.tier], 4)
              if br.hp <= 0 then
                brow[c]=nil
                brick_count = brick_count - 1
                combo=combo+1; combo_timer=2.0
                local pts=(10*(9-r))*(1+combo//3)*level_num
                score=score+pts
                spawn_particles(bx2+B_W/2, by2+B_H/2, BR_FACE[br.tier], 8)
                snd(300+r*60, 60, 0, 70)
                if math.random() < 0.20 then
                  local kind=PU_TYPES[math.random(#PU_TYPES)]
                  powerups[#powerups+1]={x=bx2+B_W/2-PU_W/2, y=by2+B_H, vy=58, kind=kind, active=true}
                end
                screen_flash=0.14; flash_col=BR_FACE[br.tier]
              else
                snd(200,40,0,50)
              end
              goto next_b
            end
          end
        end
      end
    end
    ::next_b::

    bi=bi+1
    ::cont::
  end

  -- power-ups falling
  local pi=1
  while pi <= #powerups do
    local p=powerups[pi]
    if not p.active then pi=pi+1; goto puc end
    p.y=p.y+p.vy*dt
    if p.y+PU_H >= pad_y() and p.y <= pad_y()+PAD_H and
       p.x+PU_W >= paddle_x and p.x <= paddle_x+paddle_w then
      p.active=false
      local k=p.kind
      spawn_particles(p.x+PU_W/2, p.y+PU_H/2, ROW_COLS[PU_COLS_I[k] or 1], 8)
      if k=="E" then
        active_pus.E=15; paddle_w=PAD_W_NORMAL*1.7
        snd(523,100,1,80)
      elseif k=="S" then
        active_pus.S=10          -- the per-frame normalise does the rest
        snd(300,150,1,80)
      elseif k=="M" then
        local nb={}
        for _,b in ipairs(balls) do
          if b.active then
            local a=math.random()*math.pi*2
            local sp=math.sqrt(b.vx*b.vx+b.vy*b.vy)
            local bb=new_ball(b.x,b.y,a)
            bb.vx=math.cos(a)*sp; bb.vy=-math.abs(math.sin(a)*sp)
            nb[#nb+1]=bb
          end
        end
        for _,b in ipairs(nb) do balls[#balls+1]=b end
        snd(660,200,0,90); snd(880,150,0,90)
      elseif k=="L" then
        lives=lives+1
        snd(784,100,1,90); snd(1047,150,1,90)
      elseif k=="T" then
        active_pus.T=8
        snd(1000,80,0,70); snd(1200,80,0,70)
      elseif k=="C" then
        active_pus.C=12; snd(440,120,2,70)
      end
    end
    if p.y > PF_Y+PF_H+20 then p.active=false end
    pi=pi+1
    ::puc::
  end

  -- level clear check (counter, not a 128-cell sweep every frame)
  if brick_count <= 0 then
    state="levelclear"; level_clear_timer=0
    snd(523,100,1,90); snd(659,100,1,90)
    snd(784,100,1,90); snd(1047,300,1,100)
    for r=1,B_ROWS,2 do for c=1,B_COLS,2 do
      spawn_particles(B_PAD_X+(c-0.5)*B_W, B_PAD_Y+(r-0.5)*B_H, BR_FACE[math.random(6)], 2)
    end end
  end
end

-- ============================================================
--  DRAW HELPERS
-- ============================================================
local function draw_brick(x,y,br)
  local t = br.tier
  local w,h = B_W-1, B_H-1
  krect(x, y, w, h, BR_FACE[t])
  krect(x, y, w, 2, BR_LITE[t])
  krect(x, y, 2, h, BR_LITE[t])
  krect(x, y+h-2, w, 2, BR_DARK[t])
  krect(x+w-2, y, 2, h, BR_DARK[t])
  if br.flash and br.flash > 0 then
    -- a hit that does not destroy needs to LAND. Cracks alone are a static
    -- difference you only notice by comparing two frames.
    krect(x, y, w, h, C_FLASH)
  end
  if br.hp < br.max_hp then
    -- damage reads as CRACKS, not as a different colour: the tier colour is the
    -- row's identity and must survive being hit
    local d = BR_DARK[t]
    kline(x+5, y+2, x+9, y+h-3, d)
    if br.max_hp - br.hp > 1 then
      kline(x+w-6, y+2, x+w-11, y+h-3, d)
      kline(x+3, y+h//2, x+w-4, y+h//2, d)
    end
  end
end

local function draw_field()
  -- bezel: a raised metal surround, lit from the top-left
  krect(PF_X-4, PF_Y-4, PF_W+8, PF_H+8, C_BEZ)
  krect(PF_X-4, PF_Y-4, PF_W+8, 1, C_BEZ_L)
  krect(PF_X-4, PF_Y-4, 1, PF_H+8, C_BEZ_L)
  krect(PF_X-4, PF_Y+PF_H+3, PF_W+8, 1, C_BEZ_D)
  krect(PF_X+PF_W+3, PF_Y-4, 1, PF_H+8, C_BEZ_D)
  krect(PF_X, PF_Y, PF_W, PF_H, C_FIELD)
  -- the floor lifts toward the paddle, so the empty half of the field has a
  -- direction instead of being a flat void (three bands, cheapest gradient there is)
  local fb = PF_Y + PF_H
  krect(PF_X, fb-54, PF_W, 18, C_FLOOR1)
  krect(PF_X, fb-36, PF_W, 18, C_FLOOR2)
  krect(PF_X, fb-18, PF_W, 18, C_FLOOR3)
  -- dot lattice rather than ruled lines: it reads as a back panel, not graph paper
  for gy = PF_Y+16, PF_Y+PF_H-8, 22 do
    for gx = PF_X+15, PF_X+PF_W-8, 29 do krect(gx, gy, 2, 2, C_DOT) end
  end
  -- neon rails down the walls, brighter for a moment where the ball just struck
  krect(PF_X, PF_Y, 1, PF_H, C_RAIL)
  krect(PF_X+PF_W-1, PF_Y, 1, PF_H, C_RAIL)
  krect(PF_X, PF_Y, PF_W, 1, C_RAIL)
  if wall_fx_l > 0 then krect(PF_X, wall_fx_ly-14, 2, 28, C_FLASH) end
  if wall_fx_r > 0 then krect(PF_X+PF_W-2, wall_fx_ry-14, 2, 28, C_FLASH) end
  if wall_fx_t > 0 then krect(wall_fx_tx-14, PF_Y, 28, 2, C_FLASH) end
end

local function draw_paddle()
  local x,y,w,h = math.floor(paddle_x), pad_y(), math.floor(paddle_w), PAD_H
  local pcol, plite = C_STEEL, C_STEEL_L
  if active_pus.E > 0 then pcol, plite = BR_FACE[4], BR_LITE[4] end
  if active_pus.T > 0 then pcol, plite = BR_FACE[6], BR_LITE[6] end
  if active_pus.C > 0 then pcol, plite = BR_FACE[2], BR_LITE[2] end
  -- a glow pooled on the floor under the paddle, then the chassis
  krect(x-3, y+h+1, w+6, 1, C_FLOOR3)
  krect(x, y+h, w, 2, C_SHADOW)
  krect(x, y, w, h, pcol)
  krect(x, y, w, 2, plite)
  krect(x+3, y+3, w-6, 1, C_WHITE)          -- the lit core strip down the middle
  krect(x, y+h-1, w, 1, C_BLACK)
  -- end caps read as the paddle's grip; CATCH grows them into claws
  local cap = (active_pus.C > 0) and 6 or 4
  krect(x, y-1, cap, h+1, plite)
  krect(x+w-cap, y-1, cap, h+1, plite)
  if active_pus.C > 0 then
    krect(x, y-3, 2, 3, plite)
    krect(x+w-2, y-3, 2, 3, plite)
  end
  if active_pus.T > 0 then
    krect(x+w//2-1, y-3, 3, 3, BR_LITE[6])
  end
end

local function draw_balls()
  local ramp = (active_pus.T > 0) and TRAIL_B or TRAIL_A
  local col  = (active_pus.T > 0) and BR_LITE[6] or kom.col.hi
  for _,b in ipairs(balls) do
    if b.active then
      -- trail: oldest first, so the newest sample paints on top
      local ti = b.ti
      for i=1,TRAIL do
        local k = (ti + i - 1) % TRAIL + 1
        local s = 1 + i//2
        krect(math.floor(b.tx[k])-s//2, math.floor(b.ty[k])-s//2, s, s, ramp[i])
      end
      -- halo, coloured body, WHITE core: a 4px dot in the tier palette vanished
      -- against a brick of the same hue the instant it touched one
      local bx, by = math.floor(b.x), math.floor(b.y)
      kcircle(bx, by, BALL_R+2, ramp[1])
      kcircle(bx, by, BALL_R, col)
      kcircle(bx, by, BALL_R-2, C_WHITE)
      krect(bx-2, by-3, 2, 2, C_WHITE)
    end
  end
end

local function draw_powerups_f()
  for _,p in ipairs(powerups) do
    if p.active then
      local ci=PU_COLS_I[p.kind] or 1
      local px,py=math.floor(p.x),math.floor(p.y)
      krect(px,py,PU_W,PU_H,BR_FACE[ci])
      krect(px,py,PU_W,2,BR_LITE[ci])
      krect(px,py+PU_H-2,PU_W,2,BR_DARK[ci])
      ktext(px+2,py+1,PU_LABELS[p.kind] or "?",C_BLACK,1)
    end
  end
end

local function draw_particles_f()
  for _,p in ipairs(particles) do
    local a=p.life/p.max_life
    local sz=math.max(1,math.floor(a*3))
    krect(math.floor(p.x)-sz//2,math.floor(p.y)-sz//2,sz,sz,p.col)
  end
end

local function draw_life_icon(x,y)
  -- a mini paddle: it has to read as A LIFE at 16x6, so it gets the same three
  -- tones as the real one rather than being a grey dash
  krect(x, y, 16, 6, C_STEEL)
  krect(x, y, 16, 2, C_STEEL_L)
  krect(x, y+5, 16, 1, C_SHADOW)
  krect(x, y, 3, 6, C_STEEL_L)
  krect(x+13, y, 3, 6, C_STEEL_L)
end

local function draw_hud()
  krect(0,0,W,PF_Y-4,C_BAR)
  krect(0,PF_Y-5,W,1,C_BAR_L)
  ktext(6,2,string.format("%06d",score),kom.col.hi,2)

  local lc = math.min(lives, 6)
  local lw = lc*20 - 4
  for i=1,lc do draw_life_icon(W//2 - lw//2 + (i-1)*20, 6) end
  if lives > 6 then ktext(W//2 + lw//2 + 4, 5, "+"..(lives-6), kom.col.grey, 1) end

  local ls = "LVL "..tostring(level_num)
  local hs = "HI "..string.format("%06d",hi_score)
  local lx = W-6-ktextw(ls,1)
  -- white on a neutral chip: an accent-on-accent readout is unreadable the moment
  -- the user's theme accent is a dark red
  krect(lx-4, 1, ktextw(ls,1)+8, 10, kom.rgb(58,58,80))
  ktext(lx, 2, ls, C_WHITE, 1)
  ktext(W-6-ktextw(hs,1), 10, hs, kom.col.grey, 1)
end

-- active-powerup chips + combo, along the floor of the field (out of play)
local function draw_chips()
  local cy = PF_Y + PF_H - 13
  local list = {}
  if active_pus.E > 0 then list[#list+1] = {"EXP", 4, active_pus.E} end
  if active_pus.S > 0 then list[#list+1] = {"SLW", 5, active_pus.S} end
  if active_pus.T > 0 then list[#list+1] = {"THR", 6, active_pus.T} end
  if active_pus.C > 0 then list[#list+1] = {"CGH", 2, active_pus.C} end
  local n = #list
  if n > 0 then
    local cw = 40
    local x0 = W//2 - (n*cw + (n-1)*4)//2
    for i,e in ipairs(list) do
      local x = x0 + (i-1)*(cw+4)
      krect(x, cy, cw, 12, BR_DARK[e[2]])
      krect(x, cy, cw, 1, BR_FACE[e[2]])
      ktext(x+3, cy+3, e[1], BR_LITE[e[2]], 1)
      ktext(x+25, cy+3, tostring(math.ceil(e[3])), C_WHITE, 1)
    end
  end
  if combo >= 3 then
    ktext(PF_X+5, cy+3, "COMBO X"..tostring(combo), kom.col.hi, 1)
  end
end

-- a popup box sized FROM its text (ship rule 13)
local function popup(lines, top_col)
  local bw = 0
  local bh = 16
  for _,l in ipairs(lines) do
    local w2 = ktextw(l[1], l[2])
    if w2 > bw then bw = w2 end
    bh = bh + l[2]*8 + 4
  end
  bw = bw + 40
  local bx = W//2 - bw//2
  local by = H//2 - bh//2
  krect(bx+3, by+3, bw, bh, C_SHADOW)
  krect(bx, by, bw, bh, kom.rgb(18,18,28))
  kframe(bx, by, bw, bh, top_col)
  kframe(bx+1, by+1, bw-2, bh-2, C_BEZ_D)
  local y = by + 10
  for _,l in ipairs(lines) do
    ktext(W//2 - ktextw(l[1], l[2])//2, y, l[1], l[3], l[2])
    y = y + l[2]*8 + 4
  end
end

-- ============================================================
--  DRAW
-- ============================================================
function draw()
  kom.clear(kom.col.bg)

  if state == "menu" then
    local cx=W//2
    -- brick-wall banner: the game's own art, at title size
    for i=0,5 do
      krect(cx-150+i*50, 16, 48, 12, BR_FACE[i+1])
      krect(cx-150+i*50, 16, 48, 2, BR_LITE[i+1])
      krect(cx-150+i*50, 26, 48, 2, BR_DARK[i+1])
    end
    local ty=40
    local title="ARKANOID"
    ktext(cx-ktextw(title,3)//2,ty,title,kom.col.hi,3)
    ktext(cx-ktextw("FOR KOMSTATION",1)//2,ty+28,"FOR KOMSTATION",kom.col.grey,1)
    local items={"START GAME","OPTIONS","RESET HI-SCORE"}
    for i,item in ipairs(items) do
      local iy=ty+52+(i-1)*20
      local sel = (menu_sel==i)
      local tw = ktextw(item,1)
      if sel then
        krect(cx-tw//2-14, iy-4, tw+28, 15, kom.rgb(40,40,58))
        krect(cx-tw//2-14, iy-4, 2, 15, kom.col.accent)
        krect(cx+tw//2+12, iy-4, 2, 15, kom.col.accent)
      end
      ktext(cx-tw//2,iy,item,sel and kom.col.hi or kom.col.text,1)
    end
    local bs = "BEST "..string.format("%06d",hi_score)
    ktext(cx-ktextw(bs,1)//2, ty+52+#items*20+16, bs, kom.col.grey, 1)
    -- a demo ball resting on a demo paddle, bottom right, so the title screen
    -- shows what the game looks like
    krect(cx-30, H-22, 60, 6, C_STEEL)
    krect(cx-30, H-22, 60, 2, C_STEEL_L)
    kcircle(cx, H-28, 4, kom.col.hi)
    return
  end

  if state == "options" then
    local cx=W//2
    ktext(cx-ktextw("OPTIONS",3)//2,54,"OPTIONS",kom.col.hi,3)
    krect(cx-90, 86, 180, 2, kom.col.accent)
    local s="SOUND  "..(opts.sound and "ON" or "OFF")
    ktext(cx-ktextw(s,2)//2,120,s,kom.col.accent,2)
    ktext(cx-ktextw("LEFT / RIGHT TOGGLE    O BACK",1)//2,H-18,
      "LEFT / RIGHT TOGGLE    O BACK",kom.col.grey,1)
    return
  end

  draw_field()
  draw_hud()

  for r=1,B_ROWS do
    local brow = bricks[r]
    local y = B_PAD_Y+(r-1)*B_H
    for c=1,B_COLS do
      local br = brow[c]
      if br then draw_brick(B_PAD_X+(c-1)*B_W, y, br) end
    end
  end

  draw_powerups_f()
  draw_paddle()
  draw_balls()
  draw_particles_f()
  draw_chips()
  if screen_flash > 0 and flash_col then
    kframe(PF_X, PF_Y, PF_W, PF_H, flash_col)
    kframe(PF_X+1, PF_Y+1, PF_W-2, PF_H-2, flash_col)
  end
  if shake > 0 then
    kframe(PF_X, PF_Y, PF_W, PF_H, kom.col.accent)
  end

  if state == "intro" then
    local nm = LEVEL_NAMES[((level_num-1) % #LEVEL_NAMES)+1]
    popup({
      {"LEVEL "..tostring(level_num), 3, kom.col.hi},
      {nm, 1, kom.col.accent},
      {"READY", 1, kom.col.grey},
    }, kom.col.accent)
    return
  end

  if state == "levelclear" then
    local ns="LEVEL "..tostring(level_num+1).." NEXT"
    if level_num >= #LEVELS*2 then ns="ALL CLEAR" end
    popup({
      {"LEVEL CLEAR", 2, kom.col.hi},
      {ns, 1, kom.col.accent},
    }, kom.col.hi)
    return
  end

  if state == "pause" then
    popup({{"PAUSED", 2, kom.col.hi},
           {"LVL "..level_num.."   BRICKS "..brick_count, 1, kom.col.grey}}, kom.col.accent)
    return
  end

  if state == "gameover" then
    popup({
      {"GAME OVER", 2, BR_FACE[1]},
      {"SCORE "..string.format("%06d",score), 1, kom.col.text},
      {"BEST "..string.format("%06d",hi_score), 1, kom.col.grey},
    }, BR_FACE[1])
    return
  end

  if state == "win" then
    local lines = {
      {"YOU WIN", 2, kom.col.hi},
      {"SCORE "..string.format("%06d",score), 1, kom.col.text},
    }
    if score >= hi_score then lines[#lines+1] = {"NEW BEST", 1, kom.col.accent} end
    lines[#lines+1] = {"BEST "..string.format("%06d",hi_score), 1, kom.col.grey}
    popup(lines, kom.col.hi)
    return
  end
end

-- ---- RESET CONFIRM (house rule: selectable YES/NO, NO highlighted first) -----
-- Wiping a score used to happen on one X press with nothing in between. This
-- wraps update/draw rather than rewriting the menu: the prompt paints over
-- whatever is on screen and swallows input while it is up.
local function cfm_draw(msg)
  local W2, H2 = kom.W, kom.H
  local mw = kom.textw(msg, 1)
  local bw = (mw > 132 and mw or 132) + 44
  local bh = 72
  local bx = W2 // 2 - bw // 2
  local by = H2 // 2 - bh // 2
  kom.rect(0, by - 10, W2, bh + 20, kom.col.bg)      -- curtain: it is a MODAL
  kom.rect(0, by - 10, W2, 1, kom.col.dark)
  kom.rect(0, by + bh + 9, W2, 1, kom.col.dark)
  kom.rect(bx, by, bw, bh, kom.rgb(0, 0, 0))
  kom.frame(bx, by, bw, bh, kom.col.accent)
  kom.frame(bx + 1, by + 1, bw - 2, bh - 2, kom.col.dark)
  kom.text(W2 // 2 - mw // 2, by + 16, msg, kom.col.text, 1)
  local ans = { "YES", "NO" }
  for i = 1, 2 do
    local s = ans[i]
    local tw = kom.textw(s, 1)
    local x = W2 // 2 + (i == 1 and -42 or 42) - tw // 2
    local y = by + 46
    if i == cfm_sel then
      kom.rect(x - 12, y - 4, tw + 24, 15, kom.col.dark)
      kom.frame(x - 12, y - 4, tw + 24, 15, kom.col.accent)
      kom.rect(x - 12, y - 4, 2, 15, kom.col.accent)
      kom.rect(x + tw + 10, y - 4, 2, 15, kom.col.accent)
    end
    kom.text(x, y, s, (i == cfm_sel) and kom.col.accent or kom.col.grey, 1)
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
      if cfm_sel == 1 then hi_score=0; save_state() end
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
