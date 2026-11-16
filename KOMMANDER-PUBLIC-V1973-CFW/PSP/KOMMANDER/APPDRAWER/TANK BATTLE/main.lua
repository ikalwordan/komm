-- @name Tank Battle
-- @display fullscreen
local cfm, cfm_sel = false, 2   -- reset confirm; NO is the default
-- Top-down tank battle: D-pad / analog drives + aims, X fires. Smash brick walls, blast
-- enemy tanks, protect your base (the flag). 3 levels, each denser and meaner.
local TS = 16                 -- tile size
local cols, rows, ox, oy
local grid                    -- 0 empty, 1 brick(destructible), 2 steel
local player, enemies, bullets, base
local score, lives, kills, level, spawnT, t, clear_t
local particles, explosions
local state, menu_sel         -- menu | options | play | clear | over | win
local hi_score

-- ---- KOMSTATION game kit (shared convention: options + save + sound gate) ----
local PAINT = {}
local opts = { sound = true }
local ktone, ksfx = kom.tone, kom.sfx           -- aliases so a bulk rename never hits the wrappers
local function snd(f,ms,w,v,f2) if opts.sound then ktone(f,ms,w,v,f2) end end
local function blip(id)         if opts.sound then ksfx(id) end end
local function save_state() kom.save("hi="..tostring(hi_score or 0)..";snd="..(opts.sound and "1" or "0")) end
local function load_state()
  local s = kom.load() or ""
  hi_score = tonumber(s:match("hi=(%d+)")) or tonumber(s) or 0   -- tolerate old bare-number saves
  opts.sound = (s:match("snd=(%d)") ~= "0")
end

local DIRS = { [0]={0,-1}, [1]={1,0}, [2]={0,1}, [3]={-1,0} }   -- up,right,down,left

local function rndi(a, b) return a + math.random() * (b - a) end

-- ---- levels: pattern generators over the computed grid + per-level tuning ----
local LEVELS = {
  { name="OUTSKIRTS", kills=8,  espd=40, efire=1.0, emax=3,
    gen=function(r,c)
      if (r % 3 == 1) and (c % 4 ~= 0) and r > 1 and r < rows - 3 then return 1 end
      if r % 6 == 4 and c % 7 == 3 then return 2 end
      return 0
    end },
  { name="FORTRESS", kills=12, espd=48, efire=1.3, emax=4,
    gen=function(r,c)
      if r > 1 and r < rows - 3 and (c % 5 == 1 or c % 5 == 2) and r % 4 ~= 0 then return 1 end
      if r % 5 == 2 and c % 9 == 6 then return 2 end
      return 0
    end },
  { name="IRON MAZE", kills=16, espd=56, efire=1.6, emax=5,
    gen=function(r,c)
      if r > 1 and r < rows - 3 and ((r + c) % 3 == 0 or (r % 4 == 2 and c % 2 == 0)) then return 1 end
      if r % 4 == 1 and c % 6 == 3 then return 2 end
      return 0
    end },
}

local function tileAt(px, py)
  local c = math.floor((px - ox) / TS)
  local r = math.floor((py - oy) / TS)
  if c < 0 or r < 0 or c >= cols or r >= rows then return 2, c, r end   -- wall border
  return grid[r][c], c, r
end

local function blocked(px, py)
  -- Four scalar tests; the old literal allocated five tables per collision.
  return tileAt(px-6,py-6)~=0 or tileAt(px+6,py-6)~=0
      or tileAt(px-6,py+6)~=0 or tileAt(px+6,py+6)~=0
end

local function spawn_particles(x,y,col,n,spd)
  spd = spd or 70
  for _=1,n do
    if #particles>=96 then break end
    local a=math.random()*math.pi*2; local s=rndi(spd*0.4,spd)
    particles[#particles+1]={x=x,y=y,vx=math.cos(a)*s,vy=math.sin(a)*s,
      life=0.35+math.random()*0.25,max_life=0.6,col=col}
  end
end

local function spawn_explosion(x,y,col,big)
  explosions[#explosions+1]={x=x,y=y,t=big and 0.45 or 0.25,max=big and 0.45 or 0.25,col=col}
  spawn_particles(x,y,col,big and 14 or 7,big and 110 or 70)
end

local function start_level(n)
  level = n
  local L = LEVELS[n]
  grid = {}
  for r = 0, rows - 1 do
    grid[r] = {}
    for c = 0, cols - 1 do grid[r][c] = L.gen(r,c) end
  end
  base = { c = cols // 2, r = rows - 1, hp = 3 }
  -- clear a pocket around the base, brick shoulders beside it
  for r = rows - 2, rows - 1 do for c = base.c - 1, base.c + 1 do
    if grid[r] and grid[r][c] ~= nil then grid[r][c] = (r == rows-1 and c ~= base.c) and 1 or 0 end
  end end
  player = { x = ox + base.c * TS + TS/2, y = oy + (rows - 2) * TS + TS/2, dir = 0, cd = 0, inv = 2 }
  enemies, bullets = {}, {}
  particles, explosions = {}, {}
  kills, spawnT = 0, 0.5
  state = "play"
end

local function start_game()
  math.randomseed(math.floor(kom.time()*9999))
  score, lives, t = 0, 3, 0
  start_level(1)
end

function load()
  PAINT[1]=kom.rgb(255,240,150)
  PAINT[2]=kom.rgb(200,110,60)
  PAINT[3]=kom.rgb(220,220,230)
  PAINT[4]=kom.rgb(255,120,40)
  PAINT[5]=kom.rgb(255,170,40)
  PAINT[6]=kom.rgb(120,220,140)
  PAINT[7]=kom.rgb(195,200,210)
  PAINT[8]=kom.rgb(245,248,252)
  PAINT[9]=kom.rgb(150,155,165)
  PAINT[10]=kom.rgb(20,22,26)
  PAINT[11]=kom.rgb(90,200,120)
  PAINT[12]=kom.rgb(40,40,40)
  PAINT[13]=kom.rgb(30,30,30)
  PAINT[14]=kom.rgb(12,13,18)
  PAINT[15]=kom.rgb(110,55,30)
  PAINT[16]=kom.rgb(170,90,50)
  PAINT[17]=kom.rgb(150,150,160)
  PAINT[18]=kom.rgb(210,210,220)
  PAINT[19]=kom.rgb(90,90,100)
  PAINT[20]=kom.rgb(60,50,30)
  PAINT[21]=kom.rgb(200,200,210)
  PAINT[22]=kom.rgb(210,90,90)
  PAINT[23]=kom.rgb(255,255,255)
  PAINT[24]=kom.rgb(255,245,200)
  PAINT[25]=kom.rgb(0,0,0)
  PAINT[26]=kom.rgb(220,50,50)
  cols = (kom.W - 16) // TS
  rows = (kom.H - 40) // TS
  ox = (kom.W - cols * TS) // 2
  oy = 28
  load_state()
  particles, explosions = {}, {}
  menu_sel = 1; state = "menu"
end

local function fire(who, friendly)
  if who.cd > 0 then return end
  who.cd = friendly and 0.35 or 0.9
  local d = DIRS[who.dir]
  bullets[#bullets + 1] = { x = who.x + d[1]*10, y = who.y + d[2]*10, dx = d[1], dy = d[2], f = friendly }
  explosions[#explosions+1]={x=who.x+d[1]*11,y=who.y+d[2]*11,t=0.06,max=0.06,col=PAINT[1]}
  if friendly then snd(700, 50, 0, 45, 400) end
end

local function spawnEnemy()
  local spots = { ox + TS, ox + (cols//2)*TS, ox + (cols-2)*TS }
  enemies[#enemies + 1] = { x = spots[math.random(#spots)], y = oy + TS, dir = 2, cd = 0, tm = 0 }
end

local function end_run(won)
  if score > hi_score then hi_score = score; save_state() end
  state = won and "win" or "over"
end

local function tryMove(dir,dt)
    if not kom.btn("L") then player.dir = dir end
    local d = DIRS[dir]
    local nx, ny = player.x + d[1]*70*dt, player.y + d[2]*70*dt
    if not blocked(nx, ny) then player.x, player.y = nx, ny; return end
    -- Guide a slightly off-centre tank into a one-tile lane. Check the entire
    -- sideways correction and forward step so assistance cannot cross a wall.
    local center = d[1] == 0 and (ox + (math.floor((player.x-ox)/TS)+0.5)*TS)
                                  or (oy + (math.floor((player.y-oy)/TS)+0.5)*TS)
    local offset = center - (d[1] == 0 and player.x or player.y)
    if math.abs(offset) > 5 then return end
    local ax, ay = player.x, player.y
    for i=1,math.ceil(math.abs(offset)) do
      local shift = (offset < 0 and -1 or 1)*math.min(i,math.abs(offset))
      ax,ay = player.x + (d[1]==0 and shift or 0), player.y + (d[1]~=0 and shift or 0)
      if blocked(ax,ay) then return end
    end
    nx,ny=ax+d[1]*70*dt,ay+d[2]*70*dt
    if not blocked(nx,ny) then player.x,player.y=nx,ny end
  end

function update(dt)
  kom.menu(state ~= "play")   -- shell transport reachable from our own menu
  if dt > 0.05 then dt = 0.05 end

  if state == "menu" then
    if kom.btnp("UP")   then menu_sel = math.max(1, menu_sel-1); blip(0) end
    if kom.btnp("DOWN") then menu_sel = math.min(3, menu_sel+1); blip(0) end
    if kom.btnp("X") or kom.btnp("O") then
      if menu_sel == 1 then start_game()
      elseif menu_sel == 2 then state = "options"; blip(3)
      else cfm, cfm_sel = true, 2; blip(3) end
    end
    return
  end

  if state == "options" then
    if kom.btnp("LEFT") or kom.btnp("RIGHT") or kom.btnp("X") then
      opts.sound = not opts.sound; save_state(); blip(1)
    end
    if kom.btnp("O") then state = "menu"; blip(2) end
    return
  end

  if state == "over" or state == "win" then
    if kom.btnp("X") or kom.btnp("O") then state = "menu" end
    return
  end

  if state=="pause" then
    if kom.btnp("START") or kom.btnp("O") then state="play" end
    return
  end
  if state=="play" and kom.btnp("START") then state="pause";return end
  t = t + dt

  -- particles / explosions tick (also during the level-clear pause)
  local i = 1
  while i <= #particles do
    local p = particles[i]; p.x = p.x + p.vx*dt; p.y = p.y + p.vy*dt
    p.life = p.life - dt
    if p.life <= 0 then table.remove(particles, i) else i = i + 1 end
  end
  for j = #explosions, 1, -1 do
    explosions[j].t = explosions[j].t - dt
    if explosions[j].t <= 0 then table.remove(explosions, j) end
  end

  if state == "clear" then
    clear_t = clear_t - dt
    if clear_t <= 0 then start_level(level + 1) end
    return
  end

  local L = LEVELS[level]

  -- player drive
  if kom.btn("UP") then tryMove(0,dt) elseif kom.btn("RIGHT") then tryMove(1,dt)
  elseif kom.btn("DOWN") then tryMove(2,dt) elseif kom.btn("LEFT") then tryMove(3,dt)
  else
    local ax,ay=kom.analog()
    ax,ay=ax or 0,ay or 0
    if math.max(math.abs(ax),math.abs(ay)) > 40 then
      if math.abs(ax)>math.abs(ay) then tryMove(ax>0 and 1 or 3,dt)
      else tryMove(ay>0 and 2 or 0,dt) end
    end
  end
  player.cd = math.max(0, player.cd - dt)
  player.inv = math.max(0, (player.inv or 0) - dt)
  if kom.btn("X") or kom.btnp("X") then fire(player, true) end

  -- spawn enemies
  spawnT = spawnT - dt
  if spawnT <= 0 and #enemies < L.emax then spawnT = 2.4; spawnEnemy() end

  -- enemy AI: amble, occasionally retarget toward base, shoot
  for _, e in ipairs(enemies) do
    e.cd = math.max(0, e.cd - dt)
    e.tm = e.tm - dt
    if e.tm <= 0 then
      e.tm = rndi(0.6, 1.6)
      if math.random() < 0.6 then e.dir = (oy + base.r*TS > e.y) and 2 or (math.random(0,3)) else e.dir = math.random(0,3) end
    end
    local d = DIRS[e.dir]
    local nx, ny = e.x + d[1]*L.espd*dt, e.y + d[2]*L.espd*dt
    if blocked(nx, ny) then e.tm = 0 else e.x, e.y = nx, ny end
    if math.random() < dt * L.efire then fire(e, false) end
  end

  -- bullets
  for i2 = #bullets, 1, -1 do
    local b = bullets[i2]
    b.x = b.x + b.dx * 260 * dt
    b.y = b.y + b.dy * 260 * dt
    local v, c, r = tileAt(b.x, b.y)
    local dead = false
    if v == 1 then
      grid[r][c] = 0; dead = true
      spawn_explosion(ox+c*TS+TS/2, oy+r*TS+TS/2, PAINT[2])
      snd(200, 60, 3, 40)
    elseif v == 2 then
      dead = true
      spawn_particles(b.x, b.y, PAINT[3], 4, 50)
      snd(300, 40, 3, 30)
    end
    -- hit base
    if not b.f and c == base.c and r == base.r then
      spawn_explosion(ox+base.c*TS+TS/2, oy+base.r*TS+TS/2, PAINT[4], true)
      snd(180, 340, 1, 45, 70); snd(90, 600, 1, 36, 50)   -- soft rumble, not a buzz
      base.hp=base.hp-1
      if base.hp<=0 then end_run(false) end
      dead = true
    end
    if not dead and b.f then
      for j = #enemies, 1, -1 do
        local e = enemies[j]
        if math.abs(b.x - e.x) < 9 and math.abs(b.y - e.y) < 9 then
          table.remove(enemies, j); dead = true
          score = score + 10 * level; kills = kills + 1
          spawn_explosion(e.x, e.y, PAINT[5], true)
          snd(500, 120, 3, 55, 120)
          break
        end
      end
    elseif not dead then
      if player.inv <= 0 and math.abs(b.x - player.x) < 9 and math.abs(b.y - player.y) < 9 then
        dead = true; lives = lives - 1
        spawn_explosion(player.x, player.y, PAINT[6], true)
        snd(280, 220, 1, 40, 110); snd(140, 340, 1, 30, 70)   -- soft descending loss
        player.x = ox + base.c*TS + TS/2; player.y = oy + (rows-2)*TS + TS/2
        player.dir = 0; player.inv = 2
        if lives <= 0 then end_run(false) end
      end
    end
    if dead then table.remove(bullets, i2) end
  end

  -- level cleared?
  if state == "play" and kills >= L.kills then
    if level >= #LEVELS then
      snd(523,120,1,80); snd(784,140,1,85); snd(1047,220,1,90)
      end_run(true)
    else
      snd(523,100,1,80); snd(659,120,1,85); snd(784,180,1,90)
      state = "clear"; clear_t = 2
    end
  end
end

local function tank(x, y, dir, col, blink)
  if blink then return end
  kom.rect(x - 7, y - 7, 14, 14, col)
  local d = DIRS[dir]
  -- v2 (operator: turrets too dark): bright steel barrel + turret so the facing
  -- reads at a glance on the dark field
  local steel, glint = PAINT[7], PAINT[8]
  if d[1] ~= 0 then           -- horizontal
    kom.rect(d[1] > 0 and x or (x - 12), y - 2, 12, 4, steel)
    kom.rect(d[1] > 0 and x or (x - 12), y - 2, 12, 1, glint)
  else                        -- vertical
    kom.rect(x - 2, d[2] > 0 and y or (y - 12), 4, 12, steel)
    kom.rect(x - 2, d[2] > 0 and y or (y - 12), 1, 12, glint)
  end
  kom.rect(x - 4, y - 4, 8, 8, PAINT[9])
  kom.rect(x - 3, y - 3, 3, 3, glint)
end

function draw()
  kom.clear(PAINT[10])

  if state == "menu" then
    local cx = kom.W//2; local ty = 30
    -- tank emblem
    local pal = {PAINT[11], PAINT[12], PAINT[13]}
    local art = "..2..\n.111.\n12321\n.111.\n.1.1."
    kom.sprite(cx-20, ty, 5, art, pal)
    ty = ty + 52
    kom.text(cx-kom.textw("TANK BATTLE",2)//2, ty, "TANK BATTLE", kom.col.hi, 2)
    local items = {"START","OPTIONS","RESET HI-SCORE"}
    for i,item in ipairs(items) do
      local iy = ty + 30 + (i-1)*18
      local col = menu_sel==i and kom.col.accent or kom.col.text
      local pre = menu_sel==i and "> " or "  "
      kom.text(cx-kom.textw(pre..item,1)//2, iy, pre..item, col, 1)
    end
    kom.text(cx-kom.textw("BEST: "..tostring(hi_score),1)//2,
      ty+30+#items*18+10, "BEST: "..tostring(hi_score), kom.col.grey, 1)
    kom.text(cx-kom.textw("D-PAD drive  X fire",1)//2, kom.H-14, "D-PAD drive  X fire", kom.col.dark, 1)
    return
  end

  if state == "options" then
    local cx = kom.W//2; local ty = 60
    kom.text(cx-kom.textw("OPTIONS",3)//2, ty, "OPTIONS", kom.col.hi, 3)
    local s = "SOUND:  "..(opts.sound and "ON" or "OFF")
    kom.text(cx-kom.textw(s,2)//2, ty+56, s, kom.col.accent, 2)
    kom.text(cx-kom.textw("X/LEFT/RIGHT toggle    O back",1)//2, kom.H-14,
      "X/LEFT/RIGHT toggle    O back", kom.col.dark, 1)
    return
  end

  local L = LEVELS[level]

  -- HUD strip
  kom.rect(0,0,kom.W,25,PAINT[14])
  kom.rect(0,25,kom.W,1,kom.col.accent)
  kom.text(6,4,"LV"..level.." "..L.name,kom.col.accent,1)
  kom.text(6,14,"KILLS "..kills.."/"..L.kills,kom.col.grey,1)
  kom.text(kom.W//2-kom.textw("SCORE "..score,1)//2,4,"SCORE "..score,kom.col.text,1)
  kom.text(kom.W//2-kom.textw("HI "..hi_score,1)//2,14,"HI "..hi_score,kom.col.grey,1)
  kom.text(kom.W-70,4,"LIVES",kom.col.grey,1)
  for i=1,lives do kom.rect(kom.W-70+(i-1)*14,14,10,8,PAINT[11]) end

  -- tiles
  local mortar = PAINT[15]
  for r = 0, rows - 1 do for c = 0, cols - 1 do
    local v = grid[r][c]
    local x, y = ox + c*TS, oy + r*TS
    if v == 1 then
      -- brick: face + mortar seam + staggered head joint
      kom.rect(x, y, TS-1, TS-1, PAINT[16])
      kom.rect(x, y+7, TS-1, 1, mortar)
      kom.rect(x + ((r+c)%2==0 and 4 or 10), y, 1, 7, mortar)
    elseif v == 2 then
      -- steel: beveled plate
      kom.rect(x, y, TS-1, TS-1, PAINT[17])
      kom.rect(x, y, TS-1, 2, PAINT[18])
      kom.rect(x, y+TS-3, TS-1, 2, PAINT[19])
    end
  end end

  -- base: flag on a block
  local bx0, by0 = ox + base.c*TS, oy + base.r*TS
  kom.rect(bx0, by0, TS-1, TS-1, PAINT[20])
  kom.rect(bx0+7, by0+2, 2, 12, PAINT[21])
  kom.tri(bx0+9, by0+2, bx0+9, by0+8, bx0+15, by0+5, kom.col.accent)

  for i=1,3 do kom.rect(bx0+(i-1)*5,by0+TS-3,4,2,i<=base.hp and kom.col.hi or kom.col.dark) end

  -- tanks (player blinks while invincible)
  local blink = player.inv and player.inv > 0 and math.floor(t*10)%2 == 0
  tank(math.floor(player.x), math.floor(player.y), player.dir, PAINT[11], blink)
  for _, e in ipairs(enemies) do tank(math.floor(e.x), math.floor(e.y), e.dir, PAINT[22]) end

  -- bullets
  for _, b in ipairs(bullets) do
    kom.rect(math.floor(b.x)-2, math.floor(b.y)-2, 4, 4, kom.col.text)
    kom.rect(math.floor(b.x)-1, math.floor(b.y)-1, 2, 2, PAINT[23])
  end

  -- explosions (expanding ring + hot core)
  for _, ex in ipairs(explosions) do
    local a = ex.t / ex.max
    local r = math.floor((1-a) * (ex.max > 0.3 and 18 or 10)) + 2
    kom.circle(math.floor(ex.x), math.floor(ex.y), r, ex.col)
    if r > 4 then kom.circle(math.floor(ex.x), math.floor(ex.y), r-3, PAINT[24]) end
  end

  -- particles
  for _, p in ipairs(particles) do
    local a = p.life / p.max_life
    local sz = math.max(1, math.floor(a*3))
    kom.rect(math.floor(p.x)-sz//2, math.floor(p.y)-sz//2, sz, sz, p.col)
  end

  if state == "clear" then
    local m = "LEVEL "..level.." CLEAR!"
    kom.rect(kom.W/2-90, kom.H/2-16, 180, 32, PAINT[25])
    kom.frame(kom.W/2-90, kom.H/2-16, 180, 32, kom.col.accent)
    kom.text(kom.W/2 - kom.textw(m,2)/2, kom.H/2-8, m, kom.col.hi, 2)
  end
  if state == "over" or state == "win" then
    local m = state == "win" and "VICTORY!" or "BASE LOST"
    kom.rect(kom.W/2-90, kom.H/2-24, 180, 48, PAINT[25])
    kom.frame(kom.W/2-90, kom.H/2-24, 180, 48, kom.col.accent)
    kom.text(kom.W/2 - kom.textw(m,2)/2, kom.H/2-18, m,
      state == "win" and kom.col.hi or PAINT[26], 2)
    kom.text(kom.W/2 - kom.textw("X to menu",1)/2, kom.H/2+8, "X to menu", kom.col.grey, 1)
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
  kom.rect(bx, by, bw, bh, PAINT[25])
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
      if cfm_sel == 1 then hi_score = 0; save_state() end
      cfm = false; kom.sfx(2)
    end
    return
  end
  __cfm_update(dt)
end
function draw()
  __cfm_draw()
  if state=="pause" then kom.rect(174,113,132,42,kom.col.bg);kom.frame(174,113,132,42,kom.col.hi);kom.text(204,128,"PAUSED",kom.col.text,2) end
  if cfm then cfm_draw("RESET HI-SCORE?") end
end
