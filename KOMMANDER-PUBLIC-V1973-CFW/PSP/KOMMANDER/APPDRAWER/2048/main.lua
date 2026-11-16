-- @name 2048
-- @display fullscreen
local cfm, cfm_sel = false, 2   -- reset confirm; NO is the default

local GS = 4  -- grid size
local CELL = 58
local GAP  = 6
local BOARD = GS*CELL + (GS-1)*GAP            -- 250
local GX = 12
local GY = (272 - BOARD) // 2                 -- 11 (board fills the vertical extent)
local SBX = GX + BOARD + 16                   -- sidebar x (dead landscape space -> HUD)

local ANIM_DUR = 0.09
local POP_DUR  = 0.13

local state, menu_sel
local grid            -- [r][c] = value (0=empty)
local score, best, hi_score
local won, win_shown
local particles
local anim_tiles, anim_t          -- sliding-tile list + timer
local pop_t, pop_kind             -- [r][c] pop timer + "new"/"merge"
local new_cell, merged_cells      -- pending pops, triggered when the slide settles

local TILE_COLS = {}  -- set in load

-- ---- game kit: sound gate + tolerant save ----
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

local function rnd(lo,hi) return math.floor(math.random()*(hi-lo+1))+lo end

local function cell_center(r,c)
  return GX+(c-1)*(CELL+GAP)+CELL/2, GY+(r-1)*(CELL+GAP)+CELL/2
end

local function spawn_particles(x,y,col,n)
  for _=1,n do
    local a=math.random()*math.pi*2; local spd=rnd(30,90)
    particles[#particles+1]={x=x,y=y,vx=math.cos(a)*spd,vy=math.sin(a)*spd,
      life=0.4+math.random()*0.3,max_life=0.7,col=col}
  end
end

local function add_tile()
  local empty={}
  for r=1,GS do for c=1,GS do
    if grid[r][c]==0 then empty[#empty+1]={r=r,c=c} end
  end end
  if #empty==0 then new_cell=nil; return end
  local pos=empty[rnd(1,#empty)]
  grid[pos.r][pos.c] = math.random()<0.9 and 2 or 4
  new_cell={r=pos.r,c=pos.c}
end

local function reset_pops()
  pop_t={}; pop_kind={}
  for r=1,GS do pop_t[r]={}; pop_kind[r]={}; for c=1,GS do pop_t[r][c]=0; pop_kind[r][c]=nil end end
end

local function new_grid()
  grid={}
  for r=1,GS do grid[r]={}; for c=1,GS do grid[r][c]=0 end end
  reset_pops()
  anim_tiles={}; anim_t=ANIM_DUR
  new_cell=nil; merged_cells=nil
  add_tile(); add_tile()
end

-- ordered cell lists per line, from the target edge outward (tiles slide toward index 1)
local function traverse(dr,dc)
  local lines={}
  if dc~=0 then
    for r=1,GS do
      local line={}
      if dc==-1 then for c=1,GS do line[#line+1]={r=r,c=c} end
      else            for c=GS,1,-1 do line[#line+1]={r=r,c=c} end end
      lines[#lines+1]=line
    end
  else
    for c=1,GS do
      local line={}
      if dr==-1 then for r=1,GS do line[#line+1]={r=r,c=c} end
      else            for r=GS,1,-1 do line[#line+1]={r=r,c=c} end end
      lines[#lines+1]=line
    end
  end
  return lines
end

local function move(dr,dc)
  local lines=traverse(dr,dc)
  local moves={}; local merged={}; local gain=0; local changed=false
  for _,line in ipairs(lines) do
    local vals={}
    for i=1,GS do vals[i]=grid[line[i].r][line[i].c] end
    local result={0,0,0,0}
    local target=1; local lastTarget=nil; local lastVal=nil
    for i=1,GS do
      if vals[i]~=0 then
        if lastVal==vals[i] and lastTarget then
          result[lastTarget]=vals[i]*2
          gain=gain+vals[i]*2
          moves[#moves+1]={from=line[i], to=line[lastTarget], val=vals[i], merged=true}
          merged[#merged+1]=line[lastTarget]
          lastVal=nil; lastTarget=nil
        else
          result[target]=vals[i]
          moves[#moves+1]={from=line[i], to=line[target], val=vals[i], merged=false}
          lastTarget=target; lastVal=vals[i]
          target=target+1
        end
      end
    end
    for i=1,GS do
      if grid[line[i].r][line[i].c]~=result[i] then changed=true end
      grid[line[i].r][line[i].c]=result[i]
    end
  end
  if not changed then return false end

  anim_tiles={}
  for _,m in ipairs(moves) do
    anim_tiles[#anim_tiles+1]={val=m.val, fr=m.from.r, fc=m.from.c, tr=m.to.r, tc=m.to.c}
  end
  anim_t=0
  merged_cells=merged
  score=score+gain
  if gain>0 then
    snd(440+gain//10,80,1,60)
    if gain>=64 then
      local col=TILE_COLS[gain] or kom.col.hi
      spawn_particles(GX+BOARD//2,GY+BOARD//2,col,8)
    end
  end
  add_tile()
  for r=1,GS do for c=1,GS do
    if grid[r][c]>=2048 and not won then
      won=true
      snd(523,150,1,90); snd(784,150,1,90); snd(1047,300,1,100)
    end
  end end
  return true
end

local function check_dead()
  for r=1,GS do for c=1,GS do if grid[r][c]==0 then return false end end end
  for r=1,GS do for c=1,GS do
    if (grid[r+1] and grid[r+1][c]==grid[r][c]) or
       (grid[r][c+1] and grid[r][c+1]==grid[r][c]) then return false end
  end end
  return true
end

local function start_game()
  math.randomseed(math.floor(kom.time()*9999))
  score=0; won=false; win_shown=false
  particles={}
  new_grid()
  state="play"
end

function load()
  load_state()
  best=hi_score
  TILE_COLS[2]=kom.rgb(238,228,218)
  TILE_COLS[4]=kom.rgb(237,224,200)
  TILE_COLS[8]=kom.rgb(242,177,121)
  TILE_COLS[16]=kom.rgb(245,149,99)
  TILE_COLS[32]=kom.rgb(246,124,95)
  TILE_COLS[64]=kom.rgb(246,94,59)
  TILE_COLS[128]=kom.rgb(237,207,114)
  TILE_COLS[256]=kom.rgb(237,204,97)
  TILE_COLS[512]=kom.rgb(237,200,80)
  TILE_COLS[1024]=kom.rgb(237,197,63)
  TILE_COLS[2048]=kom.rgb(237,194,46)
  particles={}; menu_sel=1; state="menu"
  reset_pops(); anim_tiles={}; anim_t=ANIM_DUR
end

function update(dt)
  kom.menu(state ~= "play")   -- shell transport reachable from our own menu
  if dt>0.05 then dt=0.05 end

  if state=="menu" then
    if kom.btnp("UP")   then menu_sel=math.max(1,menu_sel-1); blip(0) end
    if kom.btnp("DOWN") then menu_sel=math.min(3,menu_sel+1); blip(0) end
    if kom.btnp("X") or kom.btnp("O") then
      if menu_sel==1 then start_game()
      elseif menu_sel==2 then state="options"; blip(1)
      else cfm, cfm_sel = true, 2; blip(2) end
    end
    return
  end

  if state=="options" then
    if kom.btnp("LEFT") or kom.btnp("RIGHT") or kom.btnp("X") then opts.sound=not opts.sound; save_state(); blip(1) end
    if kom.btnp("O") then state="menu"; blip(2) end
    return
  end

  local i=1
  while i<=#particles do
    local p=particles[i]; p.x=p.x+p.vx*dt; p.y=p.y+p.vy*dt
    p.life=p.life-dt
    if p.life<=0 then table.remove(particles,i) else i=i+1 end
  end

  -- advance slide animation; when it settles, fire the new-tile pop + merge bumps
  if anim_t < ANIM_DUR then
    anim_t = anim_t + dt
    if anim_t >= ANIM_DUR then
      if new_cell then pop_t[new_cell.r][new_cell.c]=POP_DUR; pop_kind[new_cell.r][new_cell.c]="new" end
      for _,mc in ipairs(merged_cells or {}) do pop_t[mc.r][mc.c]=POP_DUR; pop_kind[mc.r][mc.c]="merge" end
      new_cell=nil; merged_cells=nil
    end
  end
  for r=1,GS do for c=1,GS do if pop_t[r][c]>0 then pop_t[r][c]=math.max(0,pop_t[r][c]-dt) end end end

  if state=="gameover" then
    if kom.btnp("X") or kom.btnp("O") then state="menu" end
    return
  end

  local sliding = anim_t < ANIM_DUR
  if not sliding then   -- lock input during the (very short) slide so moves stay legible
    if kom.btnp("LEFT")  then move(0,-1) end
    if kom.btnp("RIGHT") then move(0,1)  end
    if kom.btnp("UP")    then move(-1,0) end
    if kom.btnp("DOWN")  then move(1,0)  end
    local ax,ay=kom.analog()
    if math.abs(ax)>80 then move(0,ax>0 and 1 or -1)
    elseif math.abs(ay)>80 then move(ay>0 and 1 or -1,0) end
  end

  if score>best then best=score; hi_score=score; save_state() end

  if not sliding and check_dead() then state="gameover" end

  if won and not win_shown then
    if kom.btnp("X") or kom.btnp("O") then win_shown=true end
  end
end

local function draw_tile(cx,cy,val,scale)
  local sz=math.floor(CELL*scale)
  if sz<2 then return end
  local x=math.floor(cx-sz/2); local y=math.floor(cy-sz/2)
  local col=TILE_COLS[val] or kom.rgb(60,60,80)
  kom.rect(x,y,sz,sz,col)
  kom.rect(x,y,sz,2,kom.rgb(255,255,255))                 -- soft top highlight
  kom.rect(x,y+sz-2,sz,2,kom.rgb(0,0,0))                  -- bottom shade for depth
  local str=tostring(val)
  local s = (#str<=2) and 3 or 2
  local tw=kom.textw(str,s)
  local tcol = val<=4 and kom.rgb(119,110,101) or kom.rgb(249,246,242)
  kom.text(math.floor(cx-tw/2), math.floor(cy-s*7/2), str, tcol, s)
end

function draw()
  kom.clear(kom.col.bg)

  if state=="menu" then
    local cx=kom.W//2
    local bg=kom.rgb(13,19,30);local panel=kom.rgb(24,34,48)
    local accent=kom.rgb(100,216,202);local ink=kom.rgb(236,241,247)
    kom.clear(bg)
    kom.rect(0,0,kom.W,22,panel)
    kom.text(12,7,"KOMMANDER / ARCADE",accent,1)
    kom.text(28,52,"2048",ink,3)
    kom.text(28,80,"SLIDE. MERGE. ONE MORE MOVE.",kom.col.grey,1)
    local colors={kom.rgb(71,103,119),kom.rgb(50,132,142),kom.rgb(214,155,70),kom.rgb(224,188,83)}
    for i=1,4 do
      local x=296+((i-1)%2)*65;local y=105+math.floor((i-1)/2)*56
      kom.rect(x,y,58,49,colors[i])
      local label=tostring(math.floor(2^(i+3)));kom.text(x+29-kom.textw(label,2)/2,y+18,label,ink,2)
    end
    local items={"START","OPTIONS","RESET BEST"}
    for i,item in ipairs(items) do
      local y=116+(i-1)*33
      kom.rect(24,y,238,27,panel)
      if menu_sel==i then kom.frame(24,y,238,27,accent);kom.rect(24,y,3,27,accent) end
      kom.text(38,y+10,item,menu_sel==i and ink or kom.col.grey,1)
      if menu_sel==i then kom.text(243,y+10,">",accent,1) end
    end
    kom.text(28,236,"BEST  "..tostring(hi_score),accent,1)
    kom.text(310,236,"X SELECT",ink,1)
    return
  end

  if state=="options" then
    local cx=kom.W//2
    kom.text(cx-kom.textw("OPTIONS",3)//2,60,"OPTIONS",kom.col.hi,3)
    local s="SOUND:  "..(opts.sound and "ON" or "OFF")
    kom.text(cx-kom.textw(s,2)//2,130,s,kom.col.accent,2)
    return
  end

  -- board background
  kom.rect(GX-6,GY-6,BOARD+12,BOARD+12,kom.rgb(28,28,42))
  for r=1,GS do for c=1,GS do
    local x=GX+(c-1)*(CELL+GAP); local y=GY+(r-1)*(CELL+GAP)
    kom.rect(x,y,CELL,CELL,kom.rgb(44,44,62))
  end end

  -- tiles: sliding during the anim, settled (with pop scale) otherwise
  if anim_t < ANIM_DUR then
    local p=anim_t/ANIM_DUR; local e=p*p*(3-2*p)   -- smoothstep
    for _,at in ipairs(anim_tiles) do
      local fx,fy=cell_center(at.fr,at.fc); local tx,ty=cell_center(at.tr,at.tc)
      draw_tile(fx+(tx-fx)*e, fy+(ty-fy)*e, at.val, 1.0)
    end
  else
    for r=1,GS do for c=1,GS do
      local val=grid[r][c]
      if val>0 then
        local cx,cy=cell_center(r,c)
        local scale=1.0
        local pt=pop_t[r][c]
        if pt>0 then
          local q=1-pt/POP_DUR                      -- 0..1 through the pop
          if pop_kind[r][c]=="new" then scale=0.3+0.7*q
          else scale=1+0.18*math.sin(q*math.pi) end -- merge bump
        end
        draw_tile(cx,cy,val,scale)
      end
    end end
  end

  -- particles
  for _,pp in ipairs(particles) do
    local a=pp.life/pp.max_life; local sz=math.max(1,math.floor(a*4))
    kom.rect(math.floor(pp.x)-sz//2,math.floor(pp.y)-sz//2,sz,sz,pp.col)
  end

  -- sidebar HUD (fills the landscape dead space)
  kom.text(SBX,GY,"2048",kom.rgb(237,194,46),3)
  kom.rect(SBX,GY+40,196,44,kom.rgb(28,28,42))
  kom.text(SBX+8,GY+46,"SCORE",kom.col.grey,1)
  kom.text(SBX+8,GY+60,tostring(score),kom.col.text,2)
  kom.rect(SBX,GY+92,196,44,kom.rgb(28,28,42))
  kom.text(SBX+8,GY+98,"BEST",kom.col.grey,1)
  kom.text(SBX+8,GY+112,tostring(best),kom.rgb(237,194,46),2)
  kom.text(SBX,GY+152,"JOIN TILES,",kom.col.grey,1)
  kom.text(SBX,GY+164,"REACH 2048!",kom.col.grey,1)

  -- win banner
  if won and not win_shown then
    local cx=kom.W//2; local cy=kom.H//2
    kom.rect(cx-64,cy-26,128,52,kom.rgb(237,194,46))
    kom.frame(cx-64,cy-26,128,52,kom.col.dark)
    kom.text(cx-kom.textw("YOU GOT 2048!",1)//2,cy-18,"YOU GOT 2048!",kom.col.dark,1)
    kom.text(cx-kom.textw("X TO KEEP GOING",1)//2,cy-4,"X TO KEEP GOING",kom.col.dark,1)
    kom.text(cx-kom.textw("SCORE "..tostring(score),1)//2,cy+8,"SCORE "..tostring(score),kom.col.dark,1)
  end

  if state=="gameover" then
    local cx=kom.W//2; local cy=kom.H//2
    kom.rect(cx-52,cy-22,104,44,kom.col.dark)
    kom.frame(cx-52,cy-22,104,44,kom.col.accent)
    kom.text(cx-kom.textw("GAME OVER",2)//2,cy-16,"GAME OVER",kom.rgb(220,50,50),2)
    kom.text(cx-kom.textw("X to menu",1)//2,cy+8,"X to menu",kom.col.grey,1)
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
      if cfm_sel == 1 then hi_score=0; best=0; save_state() end
      cfm = false; kom.sfx(2)
    end
    return
  end
  __cfm_update(dt)
end
function draw()
  __cfm_draw()
  if cfm then cfm_draw("RESET BEST?") end
end
