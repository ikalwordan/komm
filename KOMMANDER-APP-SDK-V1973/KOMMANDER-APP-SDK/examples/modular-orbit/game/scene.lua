local settings = require("game.settings")
local M, angle = {}, 0
function M.reset() angle = 0 end
function M.update(dt) angle = angle + dt * settings.speed end
function M.draw()
  kom.clear(kom.col.bg)
  if kom.box then
    kom.cam(math.sin(angle)*16,10,math.cos(angle)*16,0,0,0)
    for z=-4,4 do for x=-4,4 do
      local h=1+math.sin(angle*2+x*.4+z*.5)*.7
      kom.box(x*2,0,z*2,.6,h,.6,70+x*15,150+z*12,220)
    end end
    kom.flush3d()
  else
    -- The simulator's 2D fallback illustrates the same animation/state.
    for z=-4,4 do for x=-4,4 do
      local h=1+math.sin(angle*2+x*.4+z*.5)*.7
      kom.rect(230+x*23,135+z*11-h*12,12,h*12,kom.rgb(70+x*15,150+z*12,220))
    end end
  end
  kom.text(12,12,"MODULAR LUA / SHARED NATIVE 3D",kom.col.text)
end
return M
