-- @name Modular Orbit
-- A small composition root. All modules are optional for ordinary Lua apps.
local scene = require("game.scene")
function load() scene.reset() end
function update(dt) scene.update(dt) end
function draw() scene.draw() end
