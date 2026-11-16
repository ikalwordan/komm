# KOMSTATION App SDK â€” paste this into any AI to generate an app

**SDK version 1.23 - 2026-10-26 (V1486: 16 sample handles, mono samples kept mono and up to 20 s).** Bump this whenever the `kom.*` surface or its behaviour changes,
and add a CHANGELOG row. Apps written against an older SDK keep working; the version tells you
which behaviours you can rely on.

## BACKLIGHT AND QUIT (SDK 1.21)

`kom.torch([level])` sets the LCD backlight for a light app (the built-in TORCH). `level` 1..99 is
clamped to 10..99 (the shell's own range; 99 is its cap) and lights the screen at that level;
no argument means 99; `0` puts the owner's own brightness back. It returns the level the shell now
holds (0 = off).

```lua
function load() if kom.torch then kom.torch(99) end end   -- feature-detect: older shells lack it
```

- **RAM only.** The saved brightness is never changed and nothing is written to the card.
- **The shell turns it off on every exit**: HOME > QUIT, `kom.quit()`, an error, leaving the tab,
  a failed launch and the shell's own exit. You do not need `unload()` for it. If the shell itself
  crashes, the next boot restores the saved level.
- While it is on the DISPLAY button does not step the brightness presets, and the screen does not
  dim, blank or sleep on its own. After a sleep the shell lights it again.
- **No effect on stock firmware or in PPSSPP** (no kernel bridge): the screen shows what you draw
  at the current brightness. Do not flash it: setting the backlight every few frames races the
  firmware; draw black and white frames instead.

`kom.quit()` closes your app back to the APPS drawer, exactly as HOME > QUIT does. It is a request:
the shell acts on it after `update()` returns, and `unload()` still runs. Native KAP apps have had
the same call (`KapHost.quit`) since V1344.

## NATIVE PROJECTED DISCS (SDK 1.20)

`kom.discdepth(x,y,radius,z,color[,near=0.35])` draws an opaque32-segment
billboard circle in native C, using a cached unit circle and the same shared
depth as tridepth. No Lua fan-generation/trigonometry loop is needed. x/y/radius
are projected pixels, z is camera distance and near must match other geometry.
Invalid/nonfinite inputs or z<near are rejected. This is a disc, not a sphere.
Simulator provides a software counterpart; KAP ABI is unchanged (Lua service).
Pool uses it to remove V1129's per-circle20 Lua calls. PSP speed pending.
For full authoring workflow see APP_ENGINE_GUIDE.md.

## SHARED 3D DEPTH (SDK 1.19)

PSP native boxes, faces, slabs and meshes now retain per-vertex reciprocal camera
depth through CPU clipping and use the GE depth buffer. Lua native-3D calls and
KAP V1 camera/box/mesh calls share this path; existing native app packages need no
rebuild. Depth clears once per app frame, remains across `flush3d`, and does not
affect normal 2D HUD drawing. Draw world geometry first, flush, then draw the HUD.

For a custom Lua projector, use
`kom.tridepth(x0,y0,z0,x1,y1,z1,x2,y2,z2,color[,near=0.35])`.
Coordinates are projected app-local x/y; z is positive camera-space distance,
not world height or sort order. Clip polygons against `near` first. All world
geometry sharing a frame must use the same near value. Plain `kom.tri` remains
a 2D operation and cannot resolve 3D visibility. Prefer native meshes over
manually projecting every vertex in Lua. Pocket Pool, Kube and Kom Modeler use this compatibility path.

Opaque geometry is supported. Transparent surfaces still require a deliberate
rendering strategy; coplanar surfaces can tie in the 16-bit buffer. This removes
face-centre sorting failures, not every possible modeling or transparency defect.
Allocation/vertex-limit failures are counted rather than reverting to painter order.

Browser `kom.tridepth` has a software depth preview; it is not a PSP speed model.
The simulator does not emulate native KAP/GB or automatically convert other apps'
Lua fallback `kom.tri` calls into depth-aware geometry. Gates:
`tools/komgl/run_depth.sh`, `node tools/komgl/depth_sim_probe.js`, and the native
arcade suite. Repeat PSP screenshots for camera extremes and test overlay/HOME UI.

## OPTIONAL MODULES AND NATIVE-FIRST AUTHORING (SDK 1.18)

For a matched Lua/native performance test on PSP, see
`tools/orbit_bench/README.md`. The benchmark pair uses the existing perf recorder
with identical CPU, 81-box and mixed workloads; browser timing is not PSP timing.

Small apps can still be one `main.lua`. For larger apps, put related code into
bundle-local modules. `require("game.camera")` loads `game/camera.lua` relative
to the entry file's directory, even when called from a nested module. Names use
ASCII letters/underscores, digits after the first character of each component,
and dots between components (95 characters maximum). No slashes, device names,
parent paths, package search paths, bytecode or dynamic C libraries.

```lua
-- main.lua: lifecycle/composition only
local game = require("game.scene")
function load() game.reset() end
function update(dt) game.update(dt) end
function draw() game.draw() end
```

Modules return a table, function or other value. The value is cached for this
app launch, including `false`; no return/nil becomes `true`. Cycles raise an
error; failed imports can be retried. A restart creates a fresh cache. Modules
share the app globals, memory budget and watchdog; they do not get extra RAM
or their own frame budget. Prefer explicit arguments and returned tables over
globals. Module top-level code runs once; put recurring work in functions.

Use `examples/modular-orbit` as the complete example. The simulator opens its
folder, edits modules in a source selector, saves complete revisions and exports
a ZIP containing `main.lua`, modules and assets. Modules cannot run on an older
shell which lacks this loader. Do not convert deployed apps until the matching
shell is installed with the entire bundle.

For ambitious apps, start with `main.lua`, `game/state.lua`, `game/rules.lua`,
`game/camera.lua`, `render/scene.lua`, `ui/menu.lua`, and `data/tuning.lua` only
where those responsibilities exist. Keep mutable state explicitly owned by one
module. Keep a short README mapping features to files and listing replay checks.
Do not split by arbitrary line counts or move everything into a shared global table.

Use shared native operations for bulk work: registered `kom.mesh` models and
`kom.drawmesh` for repeated geometry, `kom.boxstep`/`kom.boxsupport` for the
supported body solver, and `kom.powder` for the pixel sandbox. Cache models and
assets outside draw loops. Lua keeps rules, menus and orchestration. Preserve a
Lua fallback when browser support matters; feature-detect the actual operation.
Avoid one Lua/C call per particle/vertex when a bulk native service exists.
Profile before porting additional algorithms; marshaling can outweigh savings.

Full compiled apps use **KAP V1**, described in `APP_SDK_NATIVE.md`. It shares the
shell's host services and 3D core. It does not automatically translate Lua or
TIC-80 carts into C. Hardware timing remains a separate acceptance gate.

## PERFORMANCE LOG (SDK 1.14)

Every app session is measured on the console, with nothing to call. When the app exits, the
shell appends a block to `LOGS/APP_PERF.TXT`:
- frame period (avg, p50, p95, p99, max, fps)
- frames over 20ms and over 34ms
- CPU work, update() and draw() time
- batched draw calls and vertices
- dropped vertices
- the Lua VM's peak memory, and heap growth

Not counted: loading (the first 30 frames), the quit prompt, and frames spent on your own menu
(`kom.menu(true)`).

`kom.perfnote(a [, b])` names what is being measured, for example
`kom.perfnote("NATIVE", "MEDIUM")`. Changing the note closes the current block and starts a new
one, so an in-game toggle gives one comparable block per setting. Pass string constants, not
concatenations: it is meant to be called every frame, and a concatenation would make garbage
every frame.

## NATIVE 3D (SDK 1.13)

A flat-shaded 3D scene service in C. It does the work a Lua 3D game used to do per corner:
project, near-plane clip, light, fog, and queue with per-vertex depth. The triangles go out through the batched
draw path. VICE BAY is the reference user; its pause menu switches RENDERER between NATIVE and LUA.

**Feature-detect it.** An older shell and the web simulator do not have it yet:

    if kom.box then ... native path ... else ... your Lua path ... end

Coordinates are world units: x east, y up, z forward. With the camera facing +z, screen right
is -x. Colours for box, slab and face are **components** (0..255), because the service shades
them. `kom.quad3d` takes a finished `kom.rgb` colour.

| call | what it does |
|---|---|
| `kom.cam(ex,ey,ez, tx,ty,tz [, cx,cy, focal, near])` | Eye and look-at. Screen centre defaults to 240,136, focal to 280, near plane to 0.35. |
| `kom.light(lx,ly,lz [, ambient, diffuse, side])` | Direction the light travels. Shade = ambient + diffuse * max(0, n.-L). Side faces are multiplied by `side`. Defaults are 0.55, 0.45, 1.0. |
| `kom.haze(r,g,b)` | The colour that fog fades toward. |
| `kom.box(cx,cy,cz, hx,hy,hz, r,g,b [, yaw [, fog [, sortDepth]]])` | Box with its centre and half-sizes, rotated by `yaw` about its own centre. Only the up to 3 visible faces are queued. `fog` is 0..1. |
| `kom.slab(cx,cy,cz, halfW, halfH, r,g,b)` | Camera-facing billboard for far LODs. Skipped whole if it touches the near plane. |
| `kom.face(x1,y1,z1, ..., x4,y4,z4, r,g,b [, shade [, fog [, sortDepth]]])` | One quad. Wind the corners bottom-left, bottom-right, top-right, top-left. `shade` is the WHOLE colour multiplier: the face is not lit from its normal (a mesh is). |
| `kom.quad3d(x1,y1,z1, ..., x4,y4,z4, colour [, strict])` | Drawn **immediately**, never sorted. Use it for ground laid down before the scene. Near-cut unless `strict`, which skips any quad with a corner behind the camera. |
| `kom.flush3d()` | Draws everything queued, far to near. Call it once, after the last box. |
| `kom.stats3d()` | Returns boxes, slabs, triangles this frame, then dropped. Dropped is per app and should stay 0. |
| `kom.mesh(verts, faces)` | **1.17.** Registers a model ONCE and returns its id (or nil + reason when the 64 slots or memory run out). `verts` is flat x,y,z. `faces` is flat, TEN numbers a face: i1,i2,i3,i4 (1-based corners, wound as for `kom.face`; repeat one for a triangle), r,g,b, shade, flags (1 SHELL, 2 GROUND), bias. A red below 0 is PAINT: green is its brightness and the draw call's tint is the colour. |
| `kom.drawmesh(id, px,py,pz, rx,ry,rz, ux,uy,uz, fx,fy,fz [, tr,tg,tb [, fog [, sortDepth [, mode]]]])` | **1.17.** Draws a mesh at a position with its right/up/forward axes in world space, in ONE call: C transforms, backface- and frustum-culls, LIGHTS each face from its normal (ambient + diffuse, times its shade) and queues it. Origin plus identity axes skip the transform (a world mesh). `mode` 0 sorted (default); 1 ROOM: every face drawn now in face order, SHELL faces skip the backface test; 2 RECESS: SHELL faces as ROOM, the rest sorted by far edge; 3 OUTSIDE: all sorted by far edge minus `bias`. GROUND faces sort by their far edge. |
| `kom.meshfree(id)` | **1.17.** Frees a mesh. Every mesh is freed when the app stops. |

- The queue resets at the start of every `draw()`. Anything not flushed is gone next frame.
- **Draw models as meshes.** Moving every corner through the camera basis in Lua and handing faces
  over one `kom.face` at a time was most of ROCKET LABS' frame on the console (draw 16.5ms of
  16.7). As meshes the same scene is ~1/3 of the VM steps, and the picture matches the Lua
  renderer (tools/komgl/run_parity_rl.sh: worst sampled frame 0.41% match, 1.10% free roam).
  Build big meshes across several `update()` calls: `load()` runs under the 250ms watchdog too.
- `sortDepth` is only a submission-order hint in SDK 1.19. Opaque visibility uses camera depth
  per pixel; it cannot force a farther surface through a nearer one. Give decals a real small
  geometric offset, avoid overlapping/coplanar opaque faces, and choose a sensible near plane.
- Draw order is kept. 2D calls made before `flush3d` land under the scene, and calls after it
  land on top (HUD, tracers).
- Limits: 4096 queued faces a frame, and 80000 batched vertices a frame. Anything past them is
  counted in `dropped`, never drawn half-way.

## NATIVE PIXEL SANDBOX (SDK 1.12)

Powder Lab demonstrates `kom.powder(op, ...)`. Call `kom.powder("init")` once
and handle false on allocation failure. The fixed pool and two textures belong
to the VM and are freed on unload. Intended for fullscreen apps: a 480x248
canvas is drawn at (0,16).

- `step`: once per display update, a real 5 ms deadline checked every 128 visits;
  unfinished work resumes fairly next frame.
- `draw, glow, view`: once per update; views 0 natural, 1 temperature, 2 motion.
- `brush, x, y, radius, element, tool`: at most 32 calls/update, radius 0..16;
  tool 0 pour, 1 erase, 2 heat, 3 cool, 4 push. Elements 1..24 follow PowderLab.
- `options, gravity, wind, sealed`: gravity/wind clamp to -1..1; open by default.
- `clear`; `stats` returns count/escaped/reactions/visits; `sample, x, y` returns
  element and Celsius.
- `save` returns success; `restore` returns success and, on success, gravity,
  wind and sealed. These are explicit menu actions. Complete validated PL3
  scenes occupy at most 140016 bytes; the ordinary Lua string save limit remains
  8192 bytes. PL1 import is supported. The large writer preserves a `.bak`.

`viewport, x, y, width, height, scale` selects a screen rectangle and 1/2/4px
cells. Dimensions must be divisible by scale and fit 480x272 (height <=248).
Simulation coordinates and brush radii are in cells; bounds follow the viewport.
Example: `kom.powder("viewport",8,32,416,208,4)` creates a 104x52 world.
Scale changes resample the scene: coarse cells merge, solid walls retain their
footprint on enlargement, up to the pool limit. PL3 saves include world dimensions;
restore returns a fifth result, scale, and matches a saved 1/2/4px viewport when
possible. PL1/PL2 imports adapt to the current viewport. Existing 4-result callers
continue working. Empty draw uploads nothing; paused frames reuse the texture;
all canvas draws use <=64px strips. Only the active power-of-two texture area is
cleared/uploaded (16KB for the example, 64KB at 2px, 256KB at 1px). The canvas now uses
opaque RGB565 textures, halving buffer memory and upload traffic. Cell resolution
and the Lua interface are unchanged; PowderLab defaults to 2px.

Example: `kom.powder("brush",240,60,4,2,0)` pours water. This is a toy local
reaction model, not scientific thermodynamics. Dense scenes may need multiple
display frames per physics sweep. Do not claim hardware 60fps from host tests.

## CHANGELOG

| Version | Date | Change |
|---|---|---|
| **1.23** | 2026-10-26 | `kom.sound`: 16 handles (was 8); a mono WAV is stored mono (half the RAM) and may run to 20 s, stereo keeps the 4 s cap (SOUND). Older shells refuse the extra handles and long mono files with 0. Host probe tools/appsnd/run.py (extracts wavTo441 from apps.c; --selftest mutant must fail). HAXOR's 18 s dial-up is the first user. V1486, not yet run on hardware. |
| **1.22** | 2026-10-18 | Native (KAP) apps only, `kom.*` unchanged: the V1454 KapHost tail `localTime`, `textUni` / `textUniWidth`, `textInput` (APP_SDK_NATIVE.md "V1454 tail"). Built-in KARDS flashcards app. V1454, not yet run on hardware. |
| **1.21** | 2026-10-18 | `kom.torch([level])` (LCD backlight, RAM only, the shell restores the owner's level on every exit) and `kom.quit()` (BACKLIGHT AND QUIT). Built-in TORCH app. V1453, not yet run on hardware. |
| **1.20** | 2026-09-20 | Native projected discdepth, simulator counterpart, Pool cached helpers. V1130 hardware performance pending. |
| **1.19** | 2026-09-20 | Shared PSP opaque depth for native 3D, Lua `tridepth`, simulator depth preview; hardware validation pending. |
| **1.18** | 2026-09-20 | Optional bundle-local `require`, text-only Lua loading, simulator module editing/persistence/ZIP export; native-first module architecture and KAP V1 companion SDK. Candidate: PSP execution not yet verified. |
| **1.17** | 2026-09-18 | **Meshes**: `kom.mesh` / `kom.drawmesh` / `kom.meshfree` (NATIVE 3D). A model is registered once and drawn by one call that transforms, culls, lights and queues it in C; room modes keep build order for a convex room painted unsorted. ROCKET LABS: 32k VM steps a frame to 11.5k. `kom.face` documentation corrected: its shade is the whole multiplier. |
| **1.16** | 2026-09-14 | `kom.powder("budget", true)` is now driven by missed vblanks: 1.5ms back after a late frame, 0.1ms more per on-time frame, 5 to 11ms. On hardware, the 1.15 headroom estimate ran 1px scenes at 43-58fps against FIXED's 59.8, because the GE's render time was not in it. |
| **1.15** | 2026-09-14 | **`kom.powder("budget", adaptive)`**: the powder step deadline follows frame headroom (5 to 11ms, 30ms target at 30fps) instead of a flat 5ms; `false` restores the fixed deadline. `stats` gains a 5th value, the current budget in microseconds. **`kom.boxstep` / `kom.boxsupport`**: BAD SECTOR's box solver in native C, bit-identical to its Lua step (tools/boxphys/run_parity.sh). These are that game's solver, not a general physics API. |
| **1.14** | 2026-09-14 | **Performance log**: every session writes `LOGS/APP_PERF.TXT` on exit, and `kom.perfnote(a [, b])` tags segments (PERFORMANCE LOG). Tower Defense gains the native renderer (OPTIONS > RENDERER). |
| **1.13** | 2026-09-14 | **Native 3D service**: `kom.cam/light/haze/box/slab/face/quad3d/flush3d/stats3d` (NATIVE 3D). **Batched drawing**: consecutive `kom.rect/pset/frame/clear` go to the GE as one sprite draw call and `kom.tri/line/circle` as one triangle draw call. Text, images, bitmap fonts, mono and the powder canvas flush first, so draw order is unchanged. No signature changes. VICE BAY's picture was compared Lua vs native: worst sampled frame 0.112% of pixels (tools/komgl/run_parity.sh). Console frame times are not measured yet. |
| **1.12** | 2026-09-12 | RGB565 native canvas halves texture memory/upload traffic; PowderLab defaults to 2px. |
| **1.11** | 2026-09-11 | Native viewport/scaling, bounded strip rendering, empty/paused texture reuse; PL3 dimensions and restore scale. |
| **1.10** | 2026-09-11 | Native pixel sandbox service `kom.powder`: bounded physics, batched texture rendering, open edges, validated full-scene saves. Ordinary `kom.save` rejects oversized data and reports short writes instead of silently truncating. |
| **1.9** | 2026-09-11 | Optional `unload()` callback for a final save on normal app exit. Keep it short; watchdog/error limits still apply. Never save per score event during active gameplay. |
| **1.8** | 2026-09-11 | Bounded binary sidecar reads, one native monochrome bitmap per draw, and app-owned streamed music with an audio-consumption clock. Includes voxel/sandbox and media guidance. |
| **1.7** | 2026-09-11 | Sprite rendering merges equal palette indices into clipped horizontal row runs. Same signature, palette and output; no per-frame sprite allocation. Adds tested game-loop lessons from the game refresh. |
| **1.6** | 2026-09-11 | Audio-aware performance: repeated deterministic tones reuse idle buffers; fullscreen Lua apps skip hidden spectrum analysis. Circles retain 22 triangles but batch them into one GE submission. Integer bindings avoid float conversion. Corrects the old claim that frequent tones are effectively free; adds collapse/audio budgets and Bad Apple guidance. API signatures and Lua numeric format are unchanged. |
| **1.5** | 2026-08-23 | **PERF BUDGETS, all three axes MEASURED.** A frame's cost is VM steps + kom-call/GE cost + garbage, and each axis has its own profiler and its own budget number now, calibrated against DOOK (ships smooth) and VICE BAY (ships laggy). Corrects _vmprof's old claim that draw calls are "effectively free" â€” every `kom.rect` is one GE draw call and a `kom.sprite` is one PER LIT PIXEL. Rules 33-35: stay under the step budget on the WORST frame, allocation discipline (garbage/frame is a budget), and bound the spike (worst frame â‰¤ 3x the average â€” BAD SECTOR's sector-12 collapse frames run 11x its average and that is the hitch the operator feels). See PERF BUDGETS. |
| **1.4** | 2026-08-21 | **Rule 28: no button-hint text anywhere** (standing operator rule, swept from the shell in v10.12 and repeatedly re-broken by new apps). **Rule 32: every panel must earn its space at every point in the game, judged at its emptiest reachable state.** **Rules 29-31: the DETERMINISM CONTRACT.** A game that wants to be playable over an adhoc link between two consoles has to produce the same state from the same moves on both. The rules are cheap to follow from the start and expensive to retrofit, so they are in the SDK now even though the multiplayer layer is not built yet. Includes the measured LCG modulus trap. See DETERMINISM. |
| 1.3 | 2026-08-19 | **`dt` is a hard-coded constant, not a measurement** â€” documented how to time a frame honestly with `kom.time()` deltas (peak must reset, count late frames). Six new ship rules (21â€“27) from the VICE BAY hardware round: perf-HUD honesty, culling parity across entity types, fog that reaches the background before the cull, fog on true distance, ground extent vs fog radius, list pitch derived from row count, and third-person camera collision. See TIME. |
| 1.2 | 2026-08-14 | Documented that **a colour is write-only** â€” you cannot take a `kom.rgb` value apart with bitwise operators on this console. Not a behaviour change, a behaviour that was always true and undocumented. See COLOURS. |
| 1.1 | 2026-08-01 | Numeric args to `kom.*` are now **saturated** (NaN to 0, inf and beyond Â±1000000 clamped, colours past 32 bits to `0xFFFFFFFF`). Previously an out-of-range value was undefined behaviour in the host and could hard-lock the console. See SANDBOX. |
| 1.0 | â€” | Initial documented surface: drawing, input, sprites, images, sound, fonts, save/load, `kom.menu`. |

---

Copy everything below the line into ChatGPT/Claude/etc., then add one sentence describing the app
you want (e.g. *"make a Snake game"* or *"a tip calculator"*). The AI returns an app you drop on
your Memory Stick, then open the **APPS** tab to run it.

> **New to making games here?** Read BUILDING A SOLID GAME in APP_ENGINE_GUIDE.md first.

## WHERE THE APP GOES (read this first)

```
ms0:/PSP/KOMMANDER/APPDRAWER/<YourApp>/main.lua
                                             icon.png
                                             app.json
```

- The drawer is `<KOMMANDER root>/APPDRAWER`, outside `SHELL`. If your KOMMANDER
  folder is at the device root, use `KOMMANDER/APPDRAWER`. Existing legacy
  `SHELL/APPDRAWER` installs are migrated when the destination is absent; mixed
  installs remain readable, with the canonical copy winning duplicate app keys.
- On the PSP's Memory Stick that is `PSP/KOMMANDER/APPDRAWER` â€” on a PSP Go, `ef0:` instead
  of `ms0:`. Both are scanned. (Old docs said `PSP/KOMSTATION/appdrawer` â€” that path is dead.)
- **Every app is a folder (a "bundle").** Even a one-file app: make the folder, name the script
  `main.lua`, drop an `icon.png` beside it. Loose `<name>.lua` files in the drawer root still run,
  but the folder layout is the house standard and is the only way to ship assets or an icon.
- After copying files onto the card, open **APPS** and press **TRIANGLE > REFRESH** â€” the drawer is
  scanned once per boot, so a new app will not show up until you refresh (or reboot).
- **SELECT** toggles the drawer between list and grid. **X** launches. **HOME** quits a running app.
- If the drawer is empty, the APPS tab shows a **DEPLOY BUILT-IN APPS** button: press **X** and the
  shell unpacks its own bundled game set into that folder (it never overwrites files you put there).
  The same action lives in `SETTINGS > SYSTEM > GAMES > DEPLOY BUILT-IN APPS`. That deploy also
  drops a copy of **this document** (`APP_SDK.md`) into the APPDRAWER folder.

---

## ROLE

You write small apps for **KOMSTATION**, a launcher for the Sony PSP. Apps are **Lua 5.4** scripts run
by a sandboxed interpreter. Output **one complete `main.lua`** (plus the tiny `app.json`, see BUNDLES at
the end) and nothing else unless asked. Never explain unless asked.

## THE SCREEN

- The canvas is **480Ã—272**, origin top-left, +x right, +y down. Pixels are integers.
- **Always use `kom.W` and `kom.H`** for size, never hard-code 480/272. Coordinates are relative to
  the region's top-left. Apps always run fullscreen, so today `kom.W` = 480 and `kom.H` = 272.

## PROGRAM MODEL

Define these **global functions** (all optional, but you almost always want `update` + `draw`):

```lua
function unload()    end   -- optional: final save before normal VM teardown (not guaranteed after an error)
function load()      end   -- called once when the app starts
function update(dt)  end   -- called every frame; dt is a FIXED 1/60 (see TIME â€” it is not measured)
function draw()      end   -- called every frame after update; do ALL drawing here
```

The host calls them every frame â€” **your code must return each frame**. Never write an infinite loop
(`while true do ... end` with no exit): a watchdog kills any frame that runs >250 ms. Keep per-frame
work small. State lives in Lua locals/upvalues between frames.

## SANDBOX (what you may use)

- Available Lua libraries: **base, `math`, `string`, `table`** only.
- **NOT available** (do not call): `io`, `os`, `dofile`, `load`, `print`, `collectgarbage`,
  file access, networking, coroutines-for-IO. There is no `os.time`/`os.clock` â€” use `kom.time()`.
- Memory budget â‰ˆ 4 MB (PSP-1000) to 8 MB. Don't allocate giant tables every frame.

### Numbers passed to `kom.*` are SATURATED (2026-08-01)

Every numeric argument to a `kom.*` call is clamped before it reaches the drawing layer:

| You pass | The host uses |
|---|---|
| `nan` | `0` |
| `inf` / `-inf` | `+/-1000000` |
| anything beyond `+/-1000000` | clamped to that |
| a colour beyond 32 bits | `0xFFFFFFFF` |

**Why this exists:** the host is C, and converting an out-of-range float to an `int` there is
*undefined behaviour* â€” it produced a garbage coordinate that went straight into the drawing
primitives and **locked the console hard enough to force a restart**. A calculator app overflowing
past ~1e39 was enough to take the whole shell down. That is now impossible from Lua.

**What this means for you:** you still cannot rely on a runaway number doing anything *useful* â€” it
will just clamp and draw somewhere silly. Guard your own maths. Formatting a result is the usual
place it bites:

```lua
local function fmt(v)
  if v ~= v or v == math.huge or v == -math.huge then return "ERROR" end
  return string.format("%.8g", v)
end
```

The clamp is far wider than the 480x272 screen on purpose, because apps legitimately compute
off-screen positions and let the drawing layer clip them.

## INPUT

Button names (strings): `"X" "O" "SQUARE" "TRIANGLE" "L" "R" "UP" "DOWN" "LEFT" "RIGHT"`.

```lua
kom.btn("X")    -- true while held
kom.btnp("X")   -- true only on the frame it was pressed (edge)
local ax, ay = kom.analog()   -- analog stick, each ~ -128..127, 0 = centre
```

`kom.btn`/`kom.btnp` also accept **`"START"`** and **`"SELECT"`** now. Convention: `START` = pause /
settings menu, `SELECT` = stats / powerups view. **HOME is still reserved** (a single HOME press shows the
OS "Quit app?" prompt) â€” never read HOME. The old hold-START-to-quit was removed, so START is yours to use.

### Handing gestures back to the shell â€” `kom.menu(on)`

A running app owns every button, which used to mean the player had to quit your game to skip a
music track. Tell the shell when you are on your own menu and it takes the gesture back:

```lua
function update(dt)
  kom.menu(state ~= "play")    -- true on menus/pause/title, false during play
```

While `true`, **HOLD SQUARE** opens the shell's media transport over your app (your app stops
updating until it is closed) and a quick **TAP** of Square is still delivered to you. While
`false`, nothing changes and every button is yours. Call it every frame â€” it tracks your state,
it is not a one-time switch. It resets to `false` automatically when your app starts or stops.
See ship-quality rule 19.

## DRAWING  (call only inside `draw()`)

```lua
kom.clear(col)                          -- fill the whole region with col
kom.rect(x, y, w, h, col)               -- filled rectangle
kom.frame(x, y, w, h, col)              -- 1px rectangle outline
kom.line(x1, y1, x2, y2, col)           -- line
kom.tri(x1,y1, x2,y2, x3,y3, col)       -- filled triangle
kom.circle(x, y, r, col)                -- filled circle (centre x,y)
kom.pset(x, y, col)                     -- single pixel
kom.text(x, y, str, col [, scale])      -- bitmap text, scale int >=1 (default 1)
local w = kom.textw(str [, scale])      -- pixel width of str at scale
```

### COLOURS â€” a colour is WRITE-ONLY

```lua
local c = kom.rgb(255, 120, 0)          -- make a colour from 0..255 R,G,B
```

**Never take a colour apart.** Pass it to `kom.*` and store it; that is all it is for.

```lua
local r = c & 255                       -- CRASHES ON THE CONSOLE
local g = (c >> 8) & 255                -- CRASHES ON THE CONSOLE
```
```
APP ERROR :144: number (local 'c') has no integer representation
```

Why: pspdev builds Lua with `LUA_32BITS`, so `lua_Integer` on the PSP is **32 bits**. A colour is
`0xAABBGGRR` and the alpha byte is always `0xFF`, so every colour is about **4.28 billion** â€” it does
not fit in a signed 32-bit integer, Lua cannot convert it, and every bitwise operator on one throws.

If you will need the components again, **keep the components**:

```lua
-- wrong: you can never get these numbers back
local WALL = { kom.rgb(228, 72, 62), kom.rgb(168, 44, 40) }

-- right: keep r,g,b and build whatever colours you need from them
local WALL = { 228, 72, 62,  168, 44, 40 }
local function shade(r, g, b, t)        -- e.g. fade toward the sky by t = 0..1
  return kom.rgb(r + (104 - r) * t, g + (190 - g) * t, b + (255 - b) * t)
end
```

Precompute shaded colours into a table at load rather than rebuilding them per frame â€” a lookup is
far cheaper than arithmetic plus a `kom.rgb` call in a per-column loop.

Note the byte order if you ever hard-code a literal: **red is the LOW byte** (`0xAABBGGRR`), so a
value written as if it were `0xRRGGBB` comes out with red and blue swapped.

Or use the **live theme palette** (matches the user's KOMSTATION colours):

```lua
kom.col.bg      kom.col.accent   kom.col.hi
kom.col.dark    kom.col.text     kom.col.grey
```

The host pre-clears the region to `kom.col.bg` each frame, so a minimal app already looks themed.

## SPRITES (procedural pixel-art, no asset file)

```lua
-- rows separated by \n. ' ', '.', '0' = transparent.
-- '1'..'9' -> palette[1..9],  'a'..'f' -> palette[10..15].
local pal = { kom.rgb(240,170,40), kom.rgb(200,60,60), kom.rgb(255,255,255) }
local art = "1111\n1221\n1221\n3..3"
kom.sprite(x, y, scale, art, pal)       -- scale int >=1; draws scaleÃ—scale per pixel
```
From rev1005, adjacent pixels with the same palette index on a row share one clipped rect. Transparent cells split runs. The host allocates no sprite scratch buffers. Prefer compact art with broad flat regions; checkerboards still cost one draw per visible cell.

## IMAGES (PNG/JPG)

Two ways to provide an image â€” a **sidecar file** (bundle apps) or **embedded base64** (single file).
Images are decoded once and capped to a 256-pixel box. Max 8 images per app.

```lua
local h = kom.image("logo.png")         -- load a file next to the script (bundle); 0 = failed
local h = kom.imageb64("<BASE64...>")   -- decode an embedded base64 PNG/JPG; 0 = failed
kom.imgdraw(h, x, y)                     -- draw at native size
kom.imgdraw(h, x, y, w, h2)              -- draw scaled to wÃ—h2
local iw, ih = kom.imgw(h), kom.imgh(h)  -- native size
```
To embed base64: tell the user *"give me the image as base64 and I'll paste it into `kom.imageb64`"*, or
put the file in a bundle and use `kom.image`. Do not invent base64 data.

## SOUND

Audio mixes **polyphonically** (up to 8 voices overlap) â€” great for music/drums. Volume follows the
user's UI-sound setting.

**Host behaviour (rev1002).** Audio shares the CPU with the game; integer synthesis
reduces its cost but does not make a burst of notes free:

- `kom.tone` synthesis is **all-integer** â€” no divide, no float, per sample. A cache miss
  still generates the WHOLE note on the main thread: 6,615 sample frames for a 150ms note.
  Exact repeats of frequency/duration/wave/volume/end-frequency reuse an idle tone buffer.
  Noise is regenerated to keep it varied. Zero-volume notes do no sample work.
  The cache uses the same six buffers and does not increase the sample-memory limit.
  Continuous parameter changes miss the cache; it is an optimization, not a timing guarantee.
- A tone whose buffer is still sounding is **never overwritten**. If all 6 tone slots are busy the
  new tone is **dropped**. Loaded samples share eight mixer voices and can still steal a
  voice when those are all occupied. Do not promise that every request is audible.
- Use one short impact accent per 55â€“90ms for a collapse or multi-hit burst. Reserve
  layered notes for launch, abilities and results. Copter starts its spool-up alone,
  then joins the repeating rotor beats; Bad Sector coalesces debris/deletion/impact
  sounds without reducing physics work or deleting visual debris.
- Fullscreen Lua games have no spectrum API and cover shell visualizers, so their hidden
  spectrum analysis is skipped. Music decoding, EQ, boost and audible playback continue.
  This does not make background playback cost-free; test it explicitly.

**Synth tones (no asset needed) â€” best for music, blips, retro SFX:**

```lua
-- kom.tone(freq, ms [, wave [, vol [, freq2]]])
--   freq  = Hz (20..8000)        ms   = length (10..700)
--   wave  = 0 square (default), 1 sine, 2 triangle, 3 noise, 4 saw
--   vol   = 0..100 (default 80)
--   freq2 = if >0, linear pitch sweep from freq -> freq2 (kicks, zaps, coins)
kom.tone(440, 200, 1, 80)            -- an A note (sine)
kom.tone(150, 130, 1, 100, 45)       -- punchy kick drum (pitch sweep down)
kom.tone(8000, 40, 3, 45)            -- hi-hat (short noise)
kom.tone(300, 150, 0, 70, 720)       -- jump zap (sweep up)
```
Each note has a built-in decay envelope. Play several `kom.tone` calls together for chords/layered drums.

**Sampled WAV** - PCM (8/16-bit, mono/stereo), resampled to 44.1 kHz. **SDK 1.23 (V1486): up to 16 per app; a MONO file stays mono in RAM and may run to 20 s, stereo is capped at 4 s.** A sample is held for the whole session at 44.1 kHz (mono 88 KB per second, stereo 176 KB per second), so ship mono and keep them short. Ship them at 44.1 kHz: the host resamples nearest-neighbour, which doubles every sample of a 22.05 kHz file and mirrors its top end into harsh images (key clicks suffer most). On a shell older than V1486 a mono file over 4 s and any handle past the 8th return 0, so feature-detect by checking the handle:

```lua
local s = kom.sound("hit.wav")          -- sidecar file (bundle)
local s = kom.soundb64("<BASE64 WAV>")  -- embedded base64 WAV
kom.play(s)                              -- one-shot (overlaps other voices)
```

**Built-in UI blips:** `kom.sfx(id)` â€” id 0=move, 1=select, 2=back, 3=open, 4=launch, 5=error, 6=volume.

## TEXT FONTS

`kom.font(...)` still exists but is a **NO-OP** â€” switching the shell's built-in face mid-frame
rebuilt a shared atlas while the GPU was drawing and crashed. Don't call it. `kom.text` uses the
shell face; for custom type use a bitmap atlas:

Custom bitmap font from an image atlas (a grid of equal cells, ASCII order from `first`):

```lua
-- font.png is colsÃ—rows cells of cwÃ—ch px; first glyph = the given char/code
local f = kom.loadfont("font.png", 12, 16, " ")        -- sidecar; ' ' = ASCII 32
local f = kom.loadfontb64("<BASE64 PNG>", 12, 16, 32)  -- embedded
kom.bmtext(f, x, y, "HELLO", scale [, col])             -- draw; optional col tints a white atlas
local w = kom.bmtextw(f, "HELLO", scale)               -- width
```
The atlas image must be â‰¤256 px. Make glyphs **white** and pass a `col` (from `kom.rgb`/`kom.col.*`) to
recolour them. For most apps, plain `kom.text` is enough.

## STREAMED MEDIA (SDK1.8)

```lua
local bits = kom.readasset("frames.bin", frame * 1536, 1536)
-- Packed row-major, MSB first.128x96 source ->360x270 display, centred4:3.
if bits then kom.mono(60, 1, 360, 270, bits, 128, 96) end
local ok = kom.track("track.mp3")
local seconds = kom.tracktime()
kom.trackpause(true)     -- false resumes
kom.trackstop()
```

`readasset(name, offset, count)` accepts a flat filename inside the current app
bundle, integer offsets0..32MiB and counts1..65536. No parent components, path
separators or drive names. Assets larger than32MiB are refused. Returns exactly
`count` binary bytes or `nil` on missing file/short read. It caches one file
handle; changing names replaces that handle. Keep frames in one file and read
only the frame needed. Asset handles close when the app exits.

`mono(x,y,w,h,bits,sw,sh)` returns a boolean. Source dimensions are1..128 on
each axis and byte length must equal `ceil(sw*sh/8)` (no row padding). Zero is
opaque black, one opaque white. It uses two persistent128x128 RGBA textures
(128KiB total), expands changed bits once, and submits one textured quad.
Only one successful `mono` call is allowed per `draw()`; further calls return
false. Unchanged frames reuse the texture. It is not a general image atlas.

`track` requests streamed playback through the shell music engine, replacing
the current music selection. The filename must be a flat bundle sidecar and
fit the engine path limit. It returns whether selection succeeded, not whether
the decoder has finished opening. Use supported music formats (BadApple uses
44.1kHz stereo MP3); never turn an entire song into a Lua table or PCM sound.
`tracktime()` returns fractional seconds consumed by the audio output, or -1
while opening/after another track is selected. Same-path restarts wait for the
new decoder generation. A saved music resume position, if enabled, can move
that clock; follow it. `trackpause`/`trackstop` affect only the app-selected path.
App exit stops its owned track, while a different user-selected track is kept.

For video, compute `floor(tracktime()*fps)` and seek directly to that frame.
Skip missed frames; never catch up with a decoding loop. Pause the audio clock
with the picture. Silent playback uses `kom.time()` with paused duration removed.
Provide an opening timeout and report short reads. BadApple is the full worked
example:128x96/15fps,1536-byte reads, original4:3 display. Credits and exact media
hashes are in its bundle; `tools/convert_badapple.py` reproduces conversion from
a local source MP4. Source repository software licences do not relicense music
or animation. Host clock/raster tests do not establish PSP A/V synchronization.

### Editable worlds on PSP

Use one grid for visible cells and collision. Rebuild meshes only after edits;
reuse projection/sort scratch arrays. Clip at the camera near plane before
perspective division and at screen edges before submitting triangles. Reject
fully offscreen faces and skip clipping for fully onscreen ones. Bound view
radius and visible entities. Stage large mesh construction across update calls.
For side-view terrain, merge horizontal material runs and decorate within that
same traversal; a second per-cell drawing scan can cost more than the game logic.
Keep saves below8KiB, validate their format and counts, and report failed writes.

## SAVE / LOAD (one private blob per app)

```lua
kom.save("highscore=1234")              -- store a string (â‰¤ 8 KB); returns true on success
local data = kom.load()                 -- returns the stored string, or nil if none yet
kom.snap("MYAPP")                       -- export the LAST DRAWN frame as a BMP to
                                        -- PICTURE/MYAPP/ (shows up in the IMAGES tab).
                                        -- Pattern: draw 2-3 CLEAN frames (no HUD/cursor)
                                        -- via a countdown flag, then call it once.
                                        -- Returns true on success; real hardware only.
```
Saves are per-app and persist between launches. Serialize numbers/tables to a string yourself.

## TIME

```lua
local t = kom.time()                    -- seconds (float), monotonic, REAL clock (~1 ms resolution)
```

### `dt` IS A CONSTANT. IT IS NOT A MEASUREMENT. (2026-08-19)

The `dt` handed to `update(dt)` is **hard-coded** â€” the host runs `dt = 1.0f/60.0f` every frame
and never times anything (`main.c`, "V3 pacing: fixed dt"). That is *fine* for motion: a fixed
timestep is why physics is reproducible and why the simulator matches the console.

**But it means `dt` can never tell you the frame took too long.** An app that builds a perf HUD
out of `dt` reads its own timestep back and prints a flat `16.7 MS / 60 FPS` on a frame that
really took 40 ms. VICE BAY shipped exactly that and it cost a whole hardware round â€” the
operator could see the game stuttering while the counter insisted on 60.

**Measure with `kom.time()` deltas instead:**

```lua
local now  = kom.time()
local real = now - last_t                     -- SECONDS actually elapsed
last_t = now
if real <= 0 or real > 1 then real = dt end   -- first frame / clock hiccup
local fms = real * 1000
```

Two rules that come with it, both learned the hard way:

- **A peak must RESET each window.** `ms_max = ms_max*0.5 + ms_avg*0.5` decays toward the mean,
  so a real spike is averaged away within a window or two and "PK" sits at the average forever â€”
  a peak that cannot report a peak.
- **Count LATE FRAMES, don't just average.** A 30-frame mean buries stutter: one 33 ms frame
  among 29 good ones moves the average half a millisecond and the FPS readout not at all. Count
  frames over ~20 ms and show that number. `L0` vs `L30` is the difference between "smooth" and
  "every single frame missed", and an average cannot tell you which you have.

`kom.time()` resolution is **1 ms** (the host does an integer `/1000` before the float), so it is
coarse for profiling but decisive for 16 ms vs 33 ms â€” which is the question that matters.

## PERF BUDGETS (measured 2026-08-23)

These are workload targets, not a promise of 60fps. Rev1002's host probes verify
contracts and relative work; they cannot measure PSP frame time, decoder contention,
GPU rasterization or card stalls. Run the worst level with app SFX alone, music alone,
and both together. Use `kom.time()` intervals as described under TIME, not fixed `dt`.
Record late-frame count and peak over a fresh sampling window, plus audio underruns
if available. Compare the same track, EQ/boost settings, stage and input route.

For Bad Sector, `tools/run_appperf.sh` compares a deterministic launch/ability/collapse
route in stages 1 and 12â€“16, including the ordered draw stream and gameplay state.
`tools/appengine_probe.py` extracts the actual native source for PCM/cache, geometry
and numeric-boundary checks; `--selftest` must reject its deliberately broken circle.
The source baseline is pinned in the runner so a later commit cannot quietly turn
the comparison into new-code-versus-itself. The default host Lua is 64-bit/double;
`tools/build_lua32_probe.sh` builds an isolated host interpreter with PSP-sized
32-bit integers/floats. Set `LUA_BIN=backups/appperf-r1002/lua32` when running the
comparison. Pointer sizes, allocator overhead and all hardware timing still differ.

### Planning a Bad Apple-style app

Treat it as streamed media, not a frame full of `kom.pset` or `kom.sprite` calls.
A 480x272 bitmap has 130,560 pixels; issuing Lua calls per pixel exceeds the drawing
budget before audio is added. The current app image API has eight handles and no
streaming texture-update/release API, so loading a whole animation as individual
images is not a viable implementation either.

The efficient next engine addition would be a bounded decoder in native code: a
preconverted monochrome/delta stream, two reusable texture buffers, batched texture
upload/draw, and a playback clock tied to audio. Decode ahead within a fixed memory
budget, drop late VIDEO frames rather than blocking input/audio, and measure card
read latency on the PSP. A short benchmark clip should establish resolution and
frame-rate limits before converting a full song. This is a proposed design;
rev1002 does not add video streaming to `kom.*` or ship a Bad Apple app.

Removed/shelved apps remain separate work. Use the earlier workload findings in
`docs/PERF-FINDINGS-2026-08-23.md` to choose a real stress route, then remeasure on
the new engine before restoring or packaging an app.

The console gives a frame 16.7 ms. A frame's cost has **three axes**, each with its own
profiler in `simulator/` and its own budget. All numbers below were measured on the shipping
games with the same input routes the play-tests use â€” DOOK is the calibrated "ships smooth"
reference, VICE BAY the calibrated "ships laggy" one (2.3x DOOK, and it lags on hardware).

| Axis | Tool | Budget (per frame) | Reference points |
|---|---|---|---|
| **Lua VM steps** | `_vmprof.js` | **â‰¤ 15,000 avg, â‰¤ 20,000 worst** | DOOK 13.5k = smooth; VICE BAY 31k avg / 37k max = lags |
| **kom calls â†’ GE draws** | `_drawprof.js` | **â‰¤ 400 kom calls, â‰¤ 600 GE draws** | BAD SECTOR 232, VICE BAY 318 max â€” both fine |
| **Garbage (allocation)** | `_luaharness.lua` (real Lua 5.4) | **â‰¤ 3 KB avg, â‰¤ 8 KB worst** | DOOK 0.6 KB; BAD SECTOR sector 12: 3.8 KB avg, 13 KB p99 = hitches |

```
node _vmprof.js   <main.lua> <drive.js> [frames]     # VM steps, worst frames
node _drawprof.js <main.lua> <drive.js> [frames]     # kom calls by type + GE expansion
node _tracedump.js <drive.js> <frames> > route.tsv   # export the route, then:
wsl ~/lua54 _luaharness.lua <main.lua> route.tsv     # wall ms + garbage KB on REAL Lua 5.4
```

`_luaharness.lua` takes two optional extra args â€” a chunk run at frame 30 and a chunk appended
inside the app's scope â€” which is how you profile a late level without playing to it:
`~/lua54 _luaharness.lua main.lua route.tsv "start_level(12)" "_G.start_level = start_level"`.

**Why each axis is real:**

- **VM steps** are the interpreter's own cost. DOOK's whole frame is ~13.5k and ships at 60fps;
  the budget leaves headroom because the shell (music decode, media transport) shares the CPU.
- **Host calls, GE submissions and vertices are separate costs.** A rect uses one
  `sceGuGetMemory` plus one `sceGuDrawArray`, with per-call CPU setup. From rev1002,
  a `kom.circle` batches its **22 triangles / 66 vertices into one submission** and
  reuses a unit-circle table. A `kom.line` still makes 2 submissions, a `kom.frame` 4, and
  `kom.sprite` emits **one rect per visible same-index row run** from rev1005. Broad flat
  regions are cheaper; alternating colours still generate many draws. Use the updated
  `_drawprof.js` (its historical `spritepx` field now counts these runs). `kom.text` is cheap: one batched call per string.
- **Garbage is deferred cost.** Every table/closure/string built in `update()`/`draw()` is work
  the incremental GC does *during play*; steady churn steals frame time and spiky churn is a
  visible hitch. The classic sources: `{x=..,y=..}` literals per entity per frame, `..`
  concatenation for HUD text every frame (format once, cache until the value changes), closures
  created inside loops, and `table.remove` shuffles (swap-with-last instead). Pools fix this â€”
  BAD SECTOR's particle pool is the model (`parts[i]` reused, live count in `parts.n`).

**The spike is the lag.** A game with a fine average and a 10x worst frame feels worse than a
game that is uniformly slower â€” BAD SECTOR averages *half* of DOOK yet hitches on sector-12
collapses because its worst frames run 11x its own average. Whatever the event (a collapse, a
wave spawn, a level rebuild mid-play), amortize it: cap how many bodies wake per frame, spread
spawning over frames, precompute at level *load* (a one-off load frame may spike; a play frame
may not).

## METADATA HEADER

Put these comment lines at the very top of `main.lua` so the drawer shows a name even without
an `app.json`:

```lua
-- @name My Cool App
-- @display fullscreen
```

Apps run **fullscreen** â€” the whole 480Ã—272 canvas, no OS chrome. There is one render
mode; `kom.W` is 480 and `kom.H` is 272. (Older docs mentioned `inset`/`window` modes and a
SQUARE mode-cycle; those were removed â€” `inset`/`window` in a header or `app.json` is ignored, and
`SQUARE` is now free for your gameplay.)

## RULES (follow exactly)

1. Output a valid Lua 5.4 file, or a complete bundle using SDK 1.18 `require` for larger apps. No `io`/`os`, no infinite loops. Include every module and a short file map for bundles.
2. Use `kom.W`/`kom.H`, not 480/272. Do drawing only in `draw()`, logic in `update(dt)`.
3. Use `dt` for motion (`x = x + speed * dt`) so speed is frame-rate independent.
4. Don't read HOME (it quits). START and SELECT ARE available â€” use START for the
   in-app pause/menu.
5. Only call `kom.*` functions listed here. Don't invent APIs or asset data.
5b. **Never apply a bitwise operator to a colour** (`c & 255`, `c >> 8`). A `kom.rgb`
    value has no integer representation on this console and it will crash on the
    first frame. Keep the r,g,b components if you need them. See COLOURS.
6. Begin with the `-- @name` / `-- @display` header, and ship the app as a folder
   (`<AppName>/main.lua` + `app.json` + `icon.png`) â€” that is where the shell looks.

## SHIP-QUALITY RULES (a game fails review if it breaks these)

7. **No background music.** Never auto-play a looping melody (a note-array table advanced
   by a timer). It is the single most-rejected pattern. Sound must be **event-driven only**:
   `kom.tone`/`kom.sfx` on a hit, score, jump, lock, bounce, or menu move. A playable
   instrument/sequencer that only sounds when the user acts is fine.
8. **Centre every overlay.** Titles, HUD readouts, game-over/win boxes: centre with
   `kom.W/2 - kom.textw(str, scale)/2`, never a hand-tuned magic offset. Fill the canvas â€”
   no large dead bands, nothing drawn past the 480/272 edges (watch loops like `for i=0,16`
   that spill one step off the bottom).
9. **Directional sprites must point the right way in ALL directions.** If a tank barrel,
   ship nose, turret, or arrow indicates facing, verify it points correctly for up, down,
   left, AND right. The classic bug: a rect/tri that always grows in +x/+y so "up"/"left"
   render backward. Draw the marker extending *from centre toward the facing dir* per axis.
10. **A game must be winnable AND losable.** Wire a real end state: increment the wave/level
    counter so bosses/goals actually trigger, set `state="win"` somewhere reachable, and make
    sure levels/mazes aren't sealed so a goal/dot/brick is unreachable. Don't ship a "win"
    screen that no code path sets.
11. **Stay inside the frame budget.** A frame that runs >250 ms is killed. Per-pixel effects
    (plasma, metaballs, life) must render on a coarse cell grid (8â€“12 px cells), not per pixel.
12. **Reserve space for chrome.** If you draw a top bar or a bottom help line, lay the
    playfield out *between* them (compute origins from `kom.H`), so the footer never covers
    the bottom of the game area.
13. **Popup boxes are sized FROM their text.** `bw = max(kom.textw(line, scale) for every
    line) + 32`, and the first/last line sits â‰¥8px inside the box. Never a hand-tuned
    `kom.rect(cx-60, ..., 120, ...)` around text you didn't measure â€” overflowing or
    edge-hugging win/lose boxes are an instant-fail review item.
14. **Respect the PSP speakers.** They roll off below ~200 Hz â€” a 90 Hz "boom" is SILENCE.
    Keep tone fundamentals in 200â€“2000 Hz. Keep tones â‰¤300 ms and â‰¤3 per event; FREQUENT
    events (coins, ticks) get ONE short tone. Deaths/losses are soft descending SINE sweeps
    (`kom.tone(400,220,1,42,140)` style), never loud square/noise buzzes.
15. **The cursor must read on EVERY cell state.** A selection shown only as a background
    tint disappears on same-coloured cells (revealed minesweeper grey, etc). Draw a
    two-ring outline (accent + dark inner) that contrasts on both light and dark cells.
16. **Guard against degenerate states.** Physics can settle into a stale loop: a breakout
    ball bouncing wall-to-wall near-horizontally forever, a spawner that stops, a boss that
    never triggers. Clamp the state each frame (e.g. vertical velocity always â‰¥25% of ball
    speed) so the game cannot stall.
17. **The player sprite must POP.** Dark outline + bright fill + a light detail (belly,
    visor, glint), sized generously â€” it must read instantly on the busiest background the
    game ever shows. And keep backgrounds bright/flat behind gameplay: dark gradient
    vignettes around the edges read as a rendering bug, not a mood.
18. **True rotation, not shearing.** To tilt a sprite (flappy-style), rotate its quads via
    two `kom.tri` per rect around the sprite centre. Offsetting horizontal slices reads as
    STRETCHING, not rotation.
19. **Call `kom.menu()` every frame, from the top of `update(dt)`.** Pass `true` while you are
    showing your OWN menu â€” title screen, START menu, pause, game-over â€” and `false` during
    play. It is what lets the player reach the shell's media transport (HOLD SQUARE) to change
    a track without quitting your app. One line, and it must be a live expression, not a
    one-off call, because it has to follow your state every frame:
    ```lua
    function update(dt)
      kom.menu(state ~= "play")
      ...
    ```
    While it is `true`, a HOLD of Square is taken by the shell; a quick TAP is still delivered
    to you, so a Square action on a menu keeps working. **Never pass `true` during gameplay** â€”
    if you use Square while playing (a held paddle control, for instance), the hold would be
    stolen from you.
20. **Bound sound bursts at their source.** Play important event cues promptly,
    reuse short deterministic effects, and coalesce repetitive debris/collision
    sounds with independent cooldowns. Tone synthesis still costs CPU and the
    mixer has finite voices; profile with background audio active (see SOUND).
21. **Never derive a perf readout from `dt`** â€” it is a constant, so the readout is a constant.
    Time with `kom.time()` deltas, reset the peak each window, and show a LATE-FRAME COUNT.
    See TIME. A HUD that cannot report a bad frame is worse than no HUD: it actively argues
    against what the player can see.
22. **EVERY entity type gets the same culling.** If buildings test `d2 < fog2` and a frustum,
    so do the pedestrians. VICE BAY drew its two walkers as full six-box figures behind the
    camera and a hundred units away â€” ~9k VM steps a frame, on the one detail rung where the
    lag was reported. When you add a new entity type, copy the gate from an existing one; the
    one that gets forgotten is always the one added last.
23. **Distance fog must reach the BACKGROUND COLOUR before the cull radius.** Capping the fog
    blend at 0.9 leaves an object 10% of its own colour at the exact distance it is deleted, so
    it POPS. The discontinuity is at the cull distance by construction and no amount of extra
    draw distance hides it â€” only a fog curve that finishes does. Make the last band identical
    to whatever is painted behind it and the cull becomes invisible.
24. **Fog on TRUE distance, never one axis.** `fog(dz)` is free and looks right until the
    camera turns: everything off to the side sits at z-distance ~0 and renders at full
    saturation, so the world appears to change colour and width with your heading. Use
    `dx*dx + dz*dz`. And fog every element the same way â€” a ground fogged on z beside
    buildings fogged on true distance disagree with each other in every frame.
25. **The ground must outlast the fog in EVERY axis.** VICE BAY's ground ran x âˆ’64..64 while
    the player could walk to x=58: the world edge was six units away and no fog radius can hide
    an edge you are standing on. Ground extent â‰¥ camera reach + fog radius, on both axes.
    Widening alone is not enough â€” a single flat quad cannot carry a gradient, so subdivide the
    outer bands too, and fog each band by its NEAREST point (its centre hazes out the near edge
    you are standing on).
26. **A LIST'S ROW PITCH IS DERIVED FROM ITS COUNT, never a constant.** A fixed pitch against a
    height-clamped panel agrees only for the count it was written against; add one row and it
    is drawn through the bottom border and off the screen. Compute
    `pitch = clamp(available / n, min, max)` and, as a backstop, WINDOW the draw loop on the
    rows that actually fit â€” a clamp that can be exceeded is not a clamp. This bug shipped
    twice in the shell's own settings menu, once per nesting level.
27. **A third-person camera needs its own collision.** Colliding the player is not enough: the
    camera sits behind them, so backing into a wall puts the CAMERA inside the geometry and the
    screen fills with the inside of a building. Pull the camera in toward the player when the
    span between them is blocked.


28. **NO BUTTON-HINT TEXT. ANYWHERE.** No `[X] SELECT  [O] BACK` strip, no `PRESS X TO
    CONFIRM`, no control legend along the bottom of the play screen. This is a standing
    operator rule and it was swept out of the entire shell app-wide in v10.12; a game that
    ships one fails review. Instead:
    - let **selection highlighting** and intuitive controls carry the affordance;
    - confirms use **highlighted selectable YES / NO words**, never `[X]=yes [O]=no` letters,
      and **NO is the default** on anything destructive (reset, clear save, quit);
    - bottom and status bars carry **STATUS** text (`MOVE 12`, `SHOTS 24`, `PHASE REINFORCE`),
      never control mappings;
    - if a mapping genuinely needs documenting, put it behind a **CONTROLS entry in a START
      menu**, not on the play screen.

    A **live readout that changes with state is not a legend** and is fine â€” showing which
    face is selected and what turning it will do, or which ship is being placed and its
    orientation, is state, not a hint.


## DETERMINISM (only matters if the game might ever be played console-to-console)

Two PSPs on an adhoc link play the same game by **sending each other moves, not board state**, and
both applying them to the same starting position. That only works if the two consoles agree on
every consequence of every move. These three rules cost nothing in single player and are what make
a game eligible for a match later, so follow them in any turn-based game.

29. **All shared state changes go through ONE `applyMove(m)`.** `m` is a small table of plain
    integers, e.g. `{ t = MV_DROP, col = 3 }`. The human input path and the AI path BOTH build a
    move and call it; nothing else touches the board, the turn, or the score. Provide
    `encodeMove(m)` and `decodeMove(s)` returning and taking a short byte string (under 8 bytes,
    built with `string.char`). Mark the four functions with a `-- ADHOC SEAM` comment.

30. **Never use `math.random` for anything a rule depends on.** Use an app-local generator seeded
    by a single `seedGame(n)`, so both consoles can be handed the same seed. `math.random` is fine
    for purely cosmetic effects that no rule reads.

31. **Use a portable generator, and integers for shared state.** This is measured, not theory.
    The PSP builds Lua with `LUA_32BITS` so integers are 32-bit and wrap on overflow; the
    desktop simulator holds integers as doubles, which are exact only to 2^53. A generator
    that ignores either limit produces a different stream in each, and then the harness that
    was supposed to prove the game correct is testing something the console will never run.

    **Three separate traps, all of them real:**

    | Written this way | What happens |
    |---|---|
    | `s = (s * 16807) % 2147483647` (Park-Miller, the obvious form) | **Diverges on the first step.** 2^32 is not a multiple of 2^31-1, so the console's wrap does not commute with the modulo. |
    | `s = (s * 1103515245 + 12345) % 2147483648` | The product is about 2^61. The **console wraps it correctly but the simulator silently drops it to a FLOAT**, and the two stop agreeing. Floats also leak into the game: army counts render as `2.0`. |
    | any literal above 2147483647, such as `2147483648` | **Does not fit a 32-bit `lua_Integer`, so it lexes as a FLOAT**, and every value it touches becomes a float from then on. |

    **Use this. It is the same classic LCG, computed in 16-bit halves so every intermediate
    stays under 2^31 and stays an integer on both, with no oversized literal anywhere.**
    Verified against an exact big-integer reference over 200,000 steps, zero mismatches, and
    the largest intermediate is 1,758,528,717.

    ```lua
    -- ADHOC SEAM.  rs = (rs * 1103515245 + 12345) % 2^31,  1103515245 = 16838*65536 + 20077
    local rs = 1
    local function seedGame(n)
      if n < 0 then n = -n end
      rs = (n // 65536) % 32768 * 65536 + n % 65536
      if rs == 0 then rs = 1 end
    end
    local function rnd(n)                       -- 0 .. n-1
      local lo, hi = rs % 65536, rs // 65536
      local t1 = 20077 * lo + 12345
      local t2 = (16838 * lo + 20077 * hi + t1 // 65536) % 32768
      rs = t2 * 65536 + t1 % 65536
      return (rs // 65536) % n
    end
    ```

    **The same rule binds your state hash.** A textbook 32-bit FNV-1a
    (`h = (h ~ v) * 16777619`) fails twice over: the product leaves the exact-integer range,
    Lua turns it into a float, and the next `~` throws *"number has no integer
    representation"*. Multiply-add with a power-of-two modulus whose literal fits has neither
    problem:

    ```lua
    local function stateHash()
      local h = 18652613                         -- the FNV offset basis, already reduced mod 2^30
      local function mix(v) h = (h * 65599 + (v % 1073741824)) % 1073741824 end
      ...
      return h
    end
    ```

    Note the seed constant is written **pre-reduced**. `2166136261 % 1073741824` would be correct
    arithmetic and wrong code: the literal does not fit a 32-bit `lua_Integer`, so it lexes as a
    float -- and under `LUA_32BITS` a `lua_Number` is a **32-bit float with a 24-bit mantissa**,
    which cannot even represent 2166136261 (it becomes 2166136320). **Check every literal in your
    seam against 2147483647**, and keep shared state in integers: 24 bits of mantissa is not much
    room to be wrong in.

    Finally, avoid depending on `pairs()` iteration order for anything that changes state --
    it is not guaranteed to match between two VMs. Use `ipairs` or a numeric `for`.

## LAYOUT

32. **EVERY PANEL MUST EARN ITS SPACE AT EVERY POINT IN THE GAME, NOT JUST THE BUSIEST MOMENT.**
    A side panel that fills up nicely by move 30 and is two thirds empty at move 1 is a broken
    layout, because move 1 is the first thing anybody sees. Judge a screen at its EMPTIEST
    reachable state and fix that one.

    The fix is one of two things, never a third:
    - **Give it something true that always exists.** A move history has nothing at move 1, but the
      score, the material on the board, the scramble you were just dealt, the threats in the
      current position and the session record all exist from the first frame.
    - **Make it smaller and rebalance.** A narrower panel with a board centred in the space it
      actually owns beats a wide one with a hole in it.

    **Do not pad with decoration, and above all do not fill it with a control legend** -- that
    breaks rule 28 and is the exact thing rule 28 removed.

    Two mechanics that make this easy: derive the board origin from the space left over
    (`BX = (PANEL_X - 8 - CELL*COLS) // 2`) instead of hard-coding a margin, so the board
    re-centres itself whenever the panel resizes; and let two stacked lists share one region, the
    first taking exactly the rows it needs and the second keeping the remainder (rule 26).
---

## PERF RULES (measured â€” see PERF BUDGETS for the numbers and the tools)

33. **Stay under the step budget on the WORST frame, not the average.** â‰¤15k VM steps average,
    â‰¤20k worst frame, â‰¤400 kom calls. Profile with the real route (`_vmprof.js` + your drive
    module), and profile the HEAVIEST level â€” export the level-select local through the
    harness epilogue rather than assuming level 1 generalizes. It does not: BAD SECTOR
    sector 1 is half of DOOK, sector 12 is 3.5x sector 1 with 11x spikes.
34. **Allocation is a budget: â‰¤3 KB of garbage per play frame, â‰¤8 KB worst.** No table
    literals, string concats, or closures created per entity per frame. Pool what recurs
    (particles, contacts, bullets: swap-with-last + a live count, never `table.remove` from
    the middle), cache formatted HUD strings until the value changes, and hoist constant
    tables out of `update()`/`draw()`.
35. **Bound the spike: the worst play frame stays within ~3x the average.** Events that touch
    many entities at once (collapse, wave spawn, board rebuild) get amortized â€” a per-frame cap
    on wakes/spawns/checks, work spread across frames (round-robin like BAD SECTOR's
    support_step), or moved to level load. If a feature cannot be amortized, it is too big for
    this console.

## TEMPLATE

```lua
-- @name Bouncer
-- @display fullscreen
local x, y, vx, vy, r

function load()
  x, y = kom.W / 2, kom.H / 2
  vx, vy, r = 90, 70, 10
end

function update(dt)
  x = x + vx * dt
  y = y + vy * dt
  if x < r or x > kom.W - r then vx = -vx; kom.sfx(1) end
  if y < r or y > kom.H - r then vy = -vy; kom.sfx(1) end
end

function draw()
  kom.clear(kom.col.bg)
  kom.frame(2, 2, kom.W - 4, kom.H - 4, kom.col.accent)
  kom.circle(math.floor(x), math.floor(y), r, kom.col.hi)
  kom.text(8, 8, "BOUNCER", kom.col.text, 1)
  kom.text(8, kom.H - 16, "HOME QUITS", kom.col.grey, 1)
end
```

## EXAMPLE â€” persisting state + input

```lua
-- @name Tally
-- @display fullscreen
local n = 0

function load()
  n = tonumber(kom.load() or "") or 0     -- restore last value
end

function update(dt)
  if kom.btnp("UP")   then n = n + 1; kom.save(tostring(n)); kom.sfx(0) end
  if kom.btnp("DOWN") then n = n - 1; kom.save(tostring(n)); kom.sfx(2) end
end

function draw()
  kom.clear(kom.col.bg)
  local s = tostring(n)
  kom.text(kom.W/2 - kom.textw(s,3)/2, kom.H/2 - 12, s, kom.col.hi, 3)
  kom.text(kom.W/2 - kom.textw("UP / DOWN",1)/2, kom.H - 22, "UP / DOWN", kom.col.grey, 1)
end
```

---

## BUNDLES â€” the standard app layout

Every app is a **folder** under `PSP/KOMMANDER/APPDRAWER/`:

```
APPDRAWER/
  MyApp/
    main.lua          (required â€” same program model as above)
    app.json          (metadata: name, display, icon)
    icon.png          (drawer icon â€” make it a 48Ã—48 PNG)
    <any .png/.wav>   (loaded with kom.image("x.png") / kom.sound("x.wav"))
```

`app.json`:

```json
{
  "name": "My App",
  "display": "fullscreen",
  "icon": "icon.png"
}
```

Inside `main.lua`, load sidecar assets by bare filename (no paths, same folder only):

```lua
local logo = kom.image("icon.png")
local jump = kom.sound("jump.wav")
```

`name`/`display` in `app.json` override the `-- @name`/`-- @display` header. `"icon"` must be present
for the icon to load â€” a folder holding an `icon.png` that `app.json` never names shows the fallback
tile. The icon appears next to the app in the APPS drawer (list and grid views); apps with no icon get
a generated letter tile. Icons are decoded to at most 64 px, so 48Ã—48 is the sweet spot.

A folder is only registered as an app if it contains `main.lua`. Saves live outside the folder, in
`PSP/KOMMANDER/SHELL/APPDATA/<foldername>.sav`, so copying the folder never carries scores with it.

### Game refresh lessons (2026-09-11)

- Fit a rotating perspective camera against the outer geometry, including rails
  and skirts, at every interpolated angle. A near-plane clipper prevents invalid
  polygons but cannot make an excessively close camera readable. Pocket Pool
  now uses analytic box support bounds to keep the whole table in its viewport.
- Do not silently accelerate CPU turns by running several complete physics
  updates per displayed frame. Pocket Pool previously forced 3x; normal turns
  now use 1x, with deliberate held fast-forward limited to 2x. A 120-frame CPU
  break probe used 3,098,700 VM instructions versus 3,653,000 before (15.2% less,
  including changed simulation pace). This is not a PSP FPS measurement.
- Flight AI needs enough impulse per second to balance gravity. Joust's old
  slow-tier cadence added more downward velocity than its flap removed. Test
  descent recovery near hazards, not only enemies spawned safely on platforms.
- `tools/game_refresh_probe.lua` exercises Pool camera transitions/CPU rolling
  and Joust danger recovery/gait using the actual app source. Both old versions
  fail their named-defect checks; use the PSP-sized Lua build for verification.

## Game refresh lessons (rev1005)

- Share the building data between rendering and collision. Vice Bay keeps its flat arrays, visible-row culling, distance detail and cached shades; aligned cross streets add navigability without a whole-city scan. Car collision must use the renderer's rotation and a rotated footprint, not two arbitrary nose/tail circles.
- Craters searches one weapon/power candidate per frame. The 27-case Lua32 test preserves 24 old plans; three unreachable-target cases now bound the previously enormous random aim error. Peak planning work fell from 59,800 to 27,300 VM instructions on this fixture. Do not multiply an error sentinel into a gameplay parameter.
- Cache packed colours at load/spawn. Stikk Stikk's 600-frame combat route fell from 12,650 to 11,088 average VM instructions (about 12%), with an identical frame-420 raster. This is host instruction evidence, not PSP FPS. Tank Battle's four-corner movement check now allocates no tables.
- Snake uses two queued turns and a bounded free-cell scan. Save the best score even when the live score display has already advanced it; a growing tail remains occupied.
- Sky Hopper tests the segment from the previous feet height to the new height. A fragile platform must still provide enough bounce to reach the next platform; restrict generated horizontal gaps.
- Graze caches shot directions and draws straight shots with two rectangles. Its 0.12-second hit-to-bomb window is explicit state: repeated hits must not extend it.
- Gameplay assistance needs actual route verification. A low-block jump aid must not be assumed to preserve a whole level merely because it clears one isolated square. Copter instead uses a one-hit shield and timed recovery, replenished after eight obstacles.

The native sprite probe checks 80 raster fixtures, extreme coordinates and a deliberately broken negative control. Its call reduction describes those fixtures, not every game. All hardware frame-rate and audio-coexistence claims still require PSP observation.

Native row batching on the unchanged Dook 600-frame drive reduced estimated GE submissions from 585 to 434 average (about 26%); p99 fell from 641 to 489. These are instrumented host counts, not measured PSP frame rates. Stikk Stikk uses procedural figures, so its separate colour/closure changes, not sprite batching, account for its VM reduction.

## Restored racing games (rev1007)

- Pick a simulation model that fits the gameplay. Meat Wheels now runs a single arcade bike state during riding and eight bounded ballistic points for 1.5 seconds after a crash. Its archived 15-particle, 31-link, eight-substep solver made ordinary riding expensive and fragile. Reducing substeps alone failed settling tests; the replacement deliberately changes handling and courses.
- A checkpoint needs activation, safe placement and the actual menu retry path tested. Keep elapsed time across retries, reset transient jump/contact state and verify completion routes with normal damage enabled. Old Meat Wheels unlocks migrate, but its old-course time records do not.
- Align road, scenery and vehicle visibility to one projection horizon. Kart Zero caches road edges, uses squared fog thresholds and draws compact kart silhouettes. Event-only sound avoids filling the audio queue with repeated engine tones. Its matched 900-frame route uses 54% fewer VM instructions and 56% fewer estimated GE submissions than the archived version; these are host proxies, not PSP FPS.
- Use source-based tests with deliberately broken variants. The two restored apps have dedicated Lua32 route/logic probes. Compare both identical-input workloads and representative new gameplay when a rewrite changes the mechanics; label those comparisons separately.

## Drawer management (rev1008)

Triangle opens app options: Hide App, Delete App, Show Hidden Apps and Recycle Bin, alongside Refresh. Show Hidden Apps reveals hidden entries; select one and choose Unhide App. Visibility is stored separately from bundles and survives app updates and refreshes. The empty hidden view also offers Show Hidden Apps.

Delete App uses the shared recycle/permanent-delete prompt. A bundle removes its folder; a loose script removes only that file. App saves in APPDATA remain intact. Recycled apps can be restored through the Files recycle bin exposed in the same menu. On two-device systems deletion targets the selected physical copy; another copy can appear after refresh. Deliberately reinstalling a built-in app can restore a deleted bundle.

### App frame cap (r1057)

`kom.fps(30)` caps the app to every second display refresh; `kom.fps(60)` restores the default. Other values raise an error. `update(dt)` receives the matching 1/30 or 1/60 step. The cap resets on app exit, so it does not change shell or other app pacing. This is a cap, not a guarantee that expensive frames meet their deadline. Use time-based movement.


## Native KAP persistence tail (V1137)

KapHost ABI 1 appends saveAtomic(data, length) and loadBackup(buffer, capacity).
Existing service offsets and Lua saves are unchanged. Native apps using this tail
must check host.size before reading its pointers; Ghost Kernel requires the V1137
host. saveAtomic is limited to 65536 bytes (8192 before V1247) and uses the existing staged scene-save
writer: temporary file, previous .bak, rename with rollback on failure. loadBackup
reads only the current app identity plus .bak, with a capacity of 1..8192 bytes.
Apps must validate both primary and backup data themselves (version, size, checksum
and ranges). A returned error must remain visible and must not mark state clean.
This is recovery against interrupted/failed writes, not a hardware power-loss
guarantee. Neither service grants arbitrary filesystem access.
