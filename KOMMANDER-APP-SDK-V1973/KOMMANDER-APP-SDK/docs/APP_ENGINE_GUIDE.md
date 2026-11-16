# KOMMANDER app engine guide

Authoring guide, 2026-09-20. KAP V1; SDK1.20. V1131 includes Lua discdepth,
Game Boy pacing and native menu updates. V1129 shared depth is operator-tested;
Pool/GB speed improvements await hardware measurement. Exact contracts:
kap.h, APP_SDK_NATIVE.md and APP_SDK.md.

## Choose an app format

| Format | Use | What runs natively |
|---|---|---|
| Modular Lua, main.lua | Fast prototyping, tools and smaller games | Host drawing, meshes, physics helpers where exposed |
| Native C, main.kap | Larger simulations/games needing predictable costs | App logic plus the shared host services |
| TIC-80, main.tic | Existing carts within TIC compatibility/resource limits | TIC engine; cart language still interpreted |
| Game Boy, main.gb | Original DMG cartridge emulation | Built-in emulator; not arbitrary C app code |

One folder per app under APPDRAWER. Discovery priority is main.lua, main.tic,
main.kap, main.gb. Keep experimental ports in separate folders; a leftover Lua
entry wins. app.json fields include name, kind, genre, author, desc and icon.
Save identity for ordinary apps follows the bundle folder; Game Boy uses ROM hash.

## Native project structure and first build

Start from examples/native-orbit or examples/arcade. A typical project:

```
examples/my-game/
  app.c          # lifecycle and mode transitions
  game.h         # state and module interfaces
  simulation.c   # rules/physics; no drawing calls
  input.c        # PSP input -> game intent
  render.c       # camera, scene submission, HUD
  save.c         # explicit versioned record
  data/          # tuning, maps, authored content
  app.json
  README.md      # file map, controls, tests, limits
tools/my-game/   # host tests, captures, build/package helpers
```

```
wsl bash tools/kap/build.sh work/my-game/main.kap examples/my-game/app.c examples/my-game/simulation.c examples/my-game/input.c examples/my-game/render.c examples/my-game/save.c
```

App sources include kap.h, not PSP headers. kap_main verifies host ABI/size and
sets update/draw/destroy callbacks; return0 to refuse initialization. Use the
example lifecycle instead of importing a desktop game loop. The shell owns
frame timing, HOME confirmation, audio worker, GPU state and resource cleanup.

KAP is freestanding MIPS C. No implicit libc/libm/OS dependencies: use host->sin,
cos,sqrt and service pointers; bounded loops for local memory/string work. Check
the actual header before inventing an API. Native packages are trusted code;
there is no Lua watchdog or memory isolation around a stalled C callback.

## Timing, memory and module boundaries

Update samples input and advances simulation. Draw reads state and submits a
frame. A bounded fixed-step accumulator is appropriate for physics; clamp long
stalls and limit catch-up deliberately. Pause must freeze simulation, not just
draw a menu over it. Cache button masks, geometry, colors and lookups at init.

Allocate persistent pools once. host->alloc is a zeroed16-byte-aligned bump arena
with no individual free; default package heap256KiB. Entire arena goes on unload.
Package+BSS+heap limits are4MiB low-memory profile/8MiB otherwise, constrained
further by available memory. Host image/mesh allocations have their own limits.
Check every handle/allocation. Avoid per-frame tables, heap growth and data copies.
Do not hide app-specific state in a shared engine service; keep module ownership
and reset/destruction clear. No threads or persistent pointers into unloaded apps.

## Memory tiers (shell V1452)

A native (KAP) app runs on one of two tiers. **Design for LOW first; HIGH only adds.**

| tier | when | arena (package + BSS + heap) |
|---|---|---|
| LOW | PSP-1000 (32 MB), the LUA / FX low-memory setting on, or the extra did not fit | 8 MiB (4 MiB with the setting) |
| HIGH | a 64 MB PSP (2000 / 3000 / Go), the setting off, and the larger arena allocated | up to 16 MiB |

- Declare memory once in the app source: `KAP_MEMORY(heapBytes, extraBytes);` (kap.h).
  `heap` is what LOW needs (package + BSS + heap <= 8 MiB); `extra` is what HIGH adds
  (all of it <= 16 MiB). `tools/kap/pack.py` reads it from the `.kapmem` section and writes
  `extra` into header word 9; without it pack.py uses `--heap` (256 KiB) and no extra.
- The shell grants the whole extra or none of it, tries HIGH first and falls back to LOW.
  Ask once at start: `if (h->size >= offsetof(KapHost, memInfo) + sizeof h->memInfo && h->memInfo)
  high = h->memInfo(&freeBytes) == 1;` (older shells lack it: treat as LOW).
- Put the HIGH-only things (texture art, bigger stream pools, more particles, longer draw
  distance) in `alloc()` buffers sized from `freeBytes`, never in static arrays: static BSS
  counts against LOW.
- Every HIGH feature needs its LOW fallback (flat colours, fewer pieces, shorter distance), and
  the app's host check must run both tiers (give the fake host a `memInfo` that returns 1).
- A package with a non-zero header word 9 is refused by shells older than V1452: deploy the
  shell first and power-cycle before the app.
- GRIT (native/grit) is the reference: `KAP_MEMORY(256 KiB, 6 MiB)`, MEM_TIER_HIGH and
  HEAP_FREE_KB_AT_START in its GRIT.sav report, `tierTest` in tools/grit/host.c.

## Drawing correctly and cheaply

Use cached meshes for detailed objects; boxes for simple geometry. Instance a
mesh by transform rather than projecting every corner in Lua. Lighting/fog are
flat-shaded services, not a modern shader pipeline. Current KAP has 2D image
drawing; a textured 3D mesh API is not yet exposed.

World geometry uses one camera/near plane per scene and shared opaque depth.
CPU near/screen clipping is retained because large nearby triangles can exceed
the GE transform guard band. Depth persists across flushes and resets each frame.
Flush the world before drawing 2D HUD. Plain triangle/line/circle calls are 2D
and cannot resolve occlusion. Sort hints cannot force far objects in front.

Give coplanar decals a physical offset and avoid duplicate surfaces. Choose a
sensible near plane;16-bit depth precision is finite. Transparent effects need a
deliberate order/depth-write policy; the present opaque path is not a universal
transparency solution. Keep counts below4096 queued faces and80000 batched vertices;
these are ceilings, not performance targets. Inspect dropped counters.

Lua custom-projector bridge:

```
kom.tridepth(x0,y0,z0, x1,y1,z1, x2,y2,z2, color, near)
kom.discdepth(x,y,radius,z,color,near) -- SDK1.20 / V1130
```

x/y are already projected screen coordinates; z is positive camera distance.
All primitives sharing depth must use the same near value. Clip triangles before
calling tridepth. discdepth builds a cached32-segment fan in C with constant
billboard depth; it is not a sphere and does not produce reflections. Prefer
this to20–32 Lua calls per circle. API crossing and Lua arithmetic matter even
when the final triangles share one GE batch. Keep Lua require modules for friendly
authoring; move hot loops into reusable C services only when measured.

## Saves, audio and assets

Use host save/load with a small explicit record: magic/version, lengths, ranges
and integrity checks. Validate before mutating game state; retain defaults on
corruption and surface write failure. Never reinterpret an old Lua save as a C
struct. Use a migration reader or a separate trial bundle without overwriting it.
Check native SDK save limits before designing a large world save.

Use host tones/WAV/image services. Keep effects pooled and rate-limited. Do not
claim the Game Boy internal PCM/framebuffer interface is available in KAP: adding
that contract is future engine work. Legal asset provenance belongs in app docs.

## Test and iterate

1. Build only the changed app; meaningful deterministic rules/physics fixtures.
2. Run host lifecycle/input/save tests, sanitizers and negative controls.
3. Run the actual KAP loader relocation/corruption checks.
4. Review host captures, then test PSP camera extremes, HUD/HOME and pause.
5. Capture APP_PERF for identical workloads before/after. Target60fps with
   approximately17ms p95 frame periods and enough CPU headroom for effects.
6. Check repeated load/exit and memory trends; a single heap reading isn't proof.

Use tools/komgl/run_depth.sh and Depth Lab for renderer changes; arcade suite
for existing native examples. The browser simulator previews Lua and discdepth/
tridepth, not MIPS KAP or GB cartridges, and not PSP speed. A C/Wasm simulator
adapter is planned only if it proves useful during the larger ports.

Small source files reduce context churn. Maintain a file map, benchmark fixture,
short changelog and named visual baseline; edit the responsible module. Data and
rendering should be changeable without rewriting collision/rules. Don't replace
a working app with an incomplete native demo merely to label it native.

## BUILDING A SOLID GAME

Every rule below was paid for by a shipped app on this console. Details and
numbers live in APP_SDK.md (Lua) and APP_SDK_NATIVE.md (KAP).

**Time and speed**
- `dt` is a constant (1/60, or 1/30 under `kom.fps(30)`), never a measurement.
  Move things with it, but time frames with `kom.time()` deltas (1 ms
  resolution), reset the peak each window and count LATE frames. A perf readout
  built from `dt` always says 60 FPS. (APP_SDK: TIME)
- Budget the WORST frame, not the average: Lua <= 15k VM steps avg / 20k worst,
  <= 400 kom calls, <= 3 KB garbage avg / 8 KB worst, worst frame <= ~3x the
  average. Profile the heaviest level with `simulator/_vmprof.js`,
  `_drawprof.js` and `_luaharness.lua`. A frame over 250 ms is killed.
  (APP_SDK: PERF BUDGETS, rules 33-35)

**Lua traps**
- A Lua function (the main chunk included) holds at most 200 locals. Past that
  the app fails to COMPILE and never starts. Group related values into tables
  early. (docs/BOOST-ARENA.md)
- A colour is write-only: never unpack a `kom.rgb` value with bit operators.
  Keep the r,g,b you built it from. (APP_SDK: COLOURS)

**Floating point**
- The PSP FPU traps Invalid, Divide-by-zero and Overflow. PPSSPP and x86 host
  probes quietly return NaN, so a 0/0 passes every test and then crashed the
  console (POCKET POOL V1195). The KAP loader now masks the traps around app
  calls (app_kap.c `fpuQuiet`), but the NaN is still a bug: run native probes
  with traps armed (`feenableexcept`) and draw once before the first update.
  Lua `kom.*` args are saturated (NaN becomes 0), which hides the bug too.

**Saves**
- The only persistence is the app's own blob: Lua `kom.save()` (<= 8 KB),
  KAP `save` / `saveAtomic` (atomic, <= 64 KiB since V1247; `loadBackup` still
  reads <= 8 KB). There is no other file access.
- The blob lives at `SHELL/APPDATA/<key>.sav`, and the key is the bundle FOLDER
  name (apps.c `appStableKey`). Renaming the folder loses the save unless an
  alias maps the new name to the old key.
- Formats are append-only: add fields at the end, never reorder or reuse them.
  Migrate by what the data contains (a version tag, a field that is present),
  not by guessing, and never overwrite a save you could not parse.
- RESET / CLEAR SAVE always asks first and the prompt has NO default: the
  player must move to YES on purpose.

**Look**
- No on-screen control legends or button hints. A live readout that changes
  with state is fine. (APP_SDK rule 28)
- UI text in CAPITALS, flat colour fills, no gradients.
- Folder names in CAPITALS (`appdrawer/MY GAME/`). See the save-key rule above
  before renaming anything that has shipped.
- `icon.png` is 48x48, drawn for the square tile, not a shrunken screenshot.
  `preview-01.png` (and -02...) are full 480x272 frames.

**Testing**
- Drive the game headless (`simulator/headless.js` plus a `_xxxdrive.js`
  route) and make every probe able to FAIL: assert a value that would be
  wrong if the feature broke, and check that the tested path actually ran.
- LOOK at the screenshots. A green probe over a black or clipped screen is
  still a broken game.
- Prove every level is finishable: a scripted route reaches the win state with
  normal damage on, and no goal, key or brick is sealed off. (APP_SDK rule on
  reachable wins; tools/frost_climber/run.sh does this for climbing routes)
- Then run it on a PSP. The simulator does not measure PSP speed.

## Game Boy real cartridges

V1129 can test real DMG ROMs now. Existing ROMs do not automatically appear in
Apps from the Retro ROM directory. Package a COPY as APPDRAWER/<name>/main.gb:

```
python tools/gameboy/package.py "H:/PSP/KOMMANDER1/ROMS/GB/Tetris.gb" "GB Tetris" --output "H:/PSP/KOMMANDER/APPDRAWER"
```

Reprobe the card path first and verify copied bytes. The original is untouched;
the package tool refuses existing destinations. Start with Tetris for simple
video/input/audio, Super Mario Land for scrolling, and Link's Awakening for
battery save/reopen. All three passed a first operator playtest; V1129 had performance dips.
DMG only: no CGB-only/SGB/link/save states/offline RTC. Existing Retro .sav files
are not automatically imported. TRIANGLE pause; D-pad/X select picture, frame output, sound, save,
controls or confirmed restart; O backs out of help/restart;
HOME normal exit. See tools/gameboy/README.md for the complete contract.

## Small-screen menus and help

Keep the game visible behind a compact menu. Use a large title, one highlighted
primary action, short selectable rows and a consistent footer. Hide actions that
do nothing (for example course selection in a one-course game). Separate help
from the start screen; show two short action cards per page with explicit back
and page controls. Confirm restart, keep resume immediate and freeze simulation
while menus are open. Keep all labels inside480x272, including long values.

The seven native game menus were refreshed in V1131. The five arcade games share
examples/arcade/common/arcade.c; Frost/Gravity have separate themed layouts and
SQUARE quick guides. Host captures use the real shell glyphs; inspect them before
shipping, then verify readability on PSP. KAP ABI and save formats are unchanged.
