# KOMMANDER APPS: developer guide

Updated 2026-11-15 for shell V1973. Lua SDK 1.23, native KAP ABI 1.

This guide is the starting point for anyone who wants to make their own app for the
**APPS** tab of the KOMMANDER shell. It covers what kinds of app you can make, where the
files go, how the drawer finds and shows your app, and how to build, test and share it.

The full API references are separate files:

| File | What it is |
|---|---|
| `APP_SDK.md` | The Lua API (`kom.*`). Written so you can paste it into an AI and ask for an app. The shell copies it to `PSP/KOMMANDER/Desktop-Tools/APP_SDK.md` when you deploy the built-in apps. |
| `APP_SDK_NATIVE.md` | The native C (KAP) API and build details. |
| `APP_ENGINE_GUIDE.md` | Engine notes for bigger games: timing, memory tiers, drawing cost, testing. |
| `kap.h` | The native header. It is the contract: if a call is not in it, it does not exist. |

All of these, plus the build tools, examples and the Lua simulator, are in the
**KOMMANDER APP SDK** zip (`KOMMANDER-APP-SDK-V<shell>.zip`).

---

## 1. Pick an app type

Every app is one folder with one entry file. The entry file decides which engine runs it.

| Type | Entry file | Best for | What you need |
|---|---|---|---|
| **Lua** | `main.lua` | Most apps: tools, 2D games, small 3D games, prototypes | A text editor. Nothing to compile. |
| **Native C (KAP)** | `main.kap` | Big games and simulations that need full CPU speed | The PSP toolchain (pspdev), `kap.h`, and the KAP build tools |
| **TIC-80 cart** | `main.tic` | Existing TIC-80 carts | A `.tic` cart within TIC-80 limits |
| **Game Boy ROM** | `main.gb` | Original DMG Game Boy games you own | The ROM file |

### Can an app be Lua and C at once?

Not in one app: a folder runs on exactly one engine. But a Lua app already gets native speed
for the heavy parts, because many `kom.*` calls are C services inside the shell:

- `kom.mesh` / `kom.drawmesh`: 3D models transformed, lit and culled in C
- `kom.cam`, `kom.box`, `kom.slab`, `kom.face`: the native 3D scene
- `kom.powder`: a native falling-sand / pixel physics sandbox
- `kom.sprite`, batched `kom.rect` / `kom.tri`: GE-batched drawing
- `kom.track`: streamed music

So the usual path is: **start in Lua, measure, and move to native C only if Lua is the
limit.** `examples/orbit-bench-lua` and `examples/orbit-bench-native` are the same scene in both,
to compare on your own PSP.

### Making a Lua app with an AI

Yes, this works and is the intended route:

1. Open `APP_SDK.md` (on your card in `PSP/KOMMANDER/Desktop-Tools/`).
2. Paste the whole file into your AI chat.
3. Add one line, for example *"make a Lua app: a Snake game with a high score"*.
4. The AI returns `main.lua` and `app.json`. Put them in a folder (section 2).

Tell the AI it is a **Lua app for KOMMANDER** and keep the SDK text in the chat: the SDK lists
the only calls that exist, and an AI without it will invent ones that do not.

Native C apps can also be written with an AI (give it `APP_SDK_NATIVE.md`, `kap.h` and
`examples/hello-kap/main.c` from the SDK kit), but they must be compiled on a PC first (section 6).

---

## 2. Where the files go

```
PSP/KOMMANDER/APPDRAWER/
  MY_GAME/              one folder per app (folder name = the app's save id)
    main.lua            entry file (or main.kap / main.tic / main.gb)
    app.json            name, icon, labels
    icon.png            drawer icon, 48 x 48
    preview-01.png      optional screenshots for the details panel and dash
    preview-02.png
    jump.wav            any assets your app loads
    game/camera.lua     optional Lua modules (require("game.camera"))
```

- Memory Stick: `ms0:/PSP/KOMMANDER/APPDRAWER/`. PSP Go internal storage: `ef0:/PSP/KOMMANDER/APPDRAWER/`.
  Both are scanned.
- After copying, open **APPS** and use **TRIANGLE > REFRESH**. The drawer is scanned once per boot.
- **Category folders:** a folder with no entry file is a group, and every app folder inside it is
  listed. One level only.
- Folders starting with `_` are not apps (`_PREVIEWS`, `_FEATURED`, `_ARCHIVE` are used by the shell).
- **Do not rename your app's folder after release.** The folder name is the save key: a renamed
  folder starts with an empty save.

---

## 3. app.json

```json
{
  "name": "MY GAME",
  "icon": "icon.png",
  "kind": "2D",
  "genre": "ARCADE",
  "desc": "Dodge the blocks, beat your best time.",
  "author": "YOUR NAME",
  "version": "1.0"
}
```

| Field | Max length | Meaning |
|---|---|---|
| `name` | 63 | Name in the drawer. Falls back to the `-- @name` header, then the folder name. |
| `icon` | 39 | Icon file in the folder. **Required for the icon to show**, even if `icon.png` exists. |
| `kind` | 7 | `2D`, `3D`, `DEMO`... Shown as the app's dimension. `TOOL` puts it in the TOOLS row, `EMU` in emulators; anything else counts as a game. |
| `genre` | 15 | Filter value: `ARCADE`, `PUZZLE`, `RACING`, `ACTION`, `PLATFORM`, `STRATEGY`. |
| `desc` | 95 | One line for the details panel. |
| `author` | 23 | Your name or handle. |
| `version` | 11 | Shown in the details panel VERSION row. |
| `entry` | | Optional. Forces one entry file (`main.lua`, `main.kap`, `main.tic`, `main.gb`) when the folder holds more than one, for example while moving an app from Lua to C. If the named file is missing, the app is not listed. |
| `display` | | Legacy. Apps always run fullscreen (480 x 272). |

Longer values are cut. The whole file must be under 8 KB.

Without `entry`, the shell picks the first that exists: `main.lua`, `main.tic`, `main.kap`, `main.gb`.
A forgotten `main.lua` next to a new `main.kap` wins, so delete it or set `entry`.

**Icons and previews:** `icon.png` 48 x 48 (decoded to at most 64 px). Previews are
`preview-01.png`, `preview-02.png`... at 480 x 272; the shell makes its own thumbnails.

---

## 4. A first Lua app

```lua
-- @name BOUNCE
-- @display fullscreen

local x, y, vx, vy, best

function load()
  x, y, vx, vy = kom.W / 2, kom.H / 2, 120, 90
  best = tonumber(kom.load() or "0") or 0
end

function update(dt)
  x, y = x + vx * dt, y + vy * dt
  if x < 0 or x > kom.W - 8 then vx = -vx end
  if y < 0 or y > kom.H - 8 then vy = -vy end
  if kom.btnp("X") then best = best + 1; kom.save(tostring(best)) end
end

function draw()
  kom.clear(kom.rgb(0, 0, 0))
  kom.rect(x, y, 8, 8, kom.rgb(255, 42, 42))
  kom.text(8, 8, "BEST " .. best, kom.rgb(255, 255, 255))
end
```

The model: `load()` once, then `update(dt)` and `draw()` every frame, optional `unload()` on exit.
Read `APP_SDK.md` for every call, then its **RULES** and **SHIP-QUALITY RULES** sections before you
share anything.

### Lua limits that catch everyone

- **Libraries:** `math`, `string`, `table` and base only. No `io`, `os`, `print`, `load`, coroutines.
  Use `kom.time()` for time.
- **Watchdog:** a frame that runs longer than 250 ms stops the app. Never loop forever.
- **Memory:** about 4 MB on a PSP-1000, about 8 MB on a 2000 / 3000 / Go. Do not build big tables every frame.
- **`dt` is a fixed 1/60**, not a measurement. To time a frame, use `kom.time()` differences.
- **Colours are write-only:** never use bitwise operators on a `kom.rgb` value. It crashes on hardware.
- **Saves:** one string per app, up to 8 KB, stored in `PSP/KOMMANDER/SHELL/APPDATA/<FOLDER>.sav`.
  Save at checkpoints or in `unload()`, not every frame.
- **Lua 5.4 has a 200-local limit per function.** Large single-file games hit it: split into
  modules with `require` (SDK 1.18).
- **Buttons:** `X O SQUARE TRIANGLE L R UP DOWN LEFT RIGHT START SELECT`. HOME belongs to the shell
  (quit prompt and overlay). Use START for your pause menu.
- **Text:** `kom.text` is 5 x 7 ASCII. Use a bitmap font (`kom.loadfont`) for anything else.

---

## 5. Test on the PC first (Lua)

The browser simulator runs Lua apps on Windows, macOS or Linux with a live editor:

1. Open `simulator/index.html` from the SDK kit (double-click, no server).
2. Click once to enable audio.
3. **Open bundle folder** (or drag your app folder in). Edit on the right, it re-runs as you type.
4. Keys: arrows = D-pad, Z = X, X = O, A = SQUARE, S = TRIANGLE, Q / W = L / R, Enter = START, right Shift = SELECT.
   A gamepad works too.

The simulator is for layout, logic and input. **It is not the PSP's speed or its floating point:**
always run on a real PSP before calling a game finished. Things that pass in a browser and fail on
hardware: frame rate, divide-by-zero / NaN maths (crashes the PSP, quiet on a PC), memory use.

---

## 6. Native C apps (KAP)

A KAP app is freestanding MIPS C loaded by the shell. The shell owns the frame, input, audio,
saves, HOME and cleanup; your code fills in callbacks.

```c
#include "kap.h"

KAP_MEMORY(64 * 1024, 0);   /* heap on every PSP, extra on 64 MB models */

static const KapHost *H;
static float t;

static void update(float dt) { t += dt; }
static void draw(void) {
    H->clear(H->color(0, 0, 0));
    H->rect(200 + (int)(40 * H->sin(t)), 120, 16, 16, H->color(255, 42, 42));
    H->text(8, 8, "HELLO KAP", H->color(255, 255, 255), 1);
}

int kap_main(const KapHost *host, KapApp *app) {
    if (host->abi != KAP_ABI || host->size < sizeof *host) return 0;  /* shell too old: refuse */
    H = host;
    app->update = update;
    app->draw = draw;
    return 1;
}
```

**Get the kit:** the **KOMMANDER APP SDK** zip holds the headers (`include/`), the build tools
(`tools/`), these docs, the examples and the Lua simulator.

**Install the toolchain** (Linux, or WSL on Windows): install pspdev
(https://github.com/pspdev/pspdev) and python3, then `export PSPDEV=$HOME/pspdev`.

**Build** from the kit folder:

```sh
bash tools/build.sh out/HELLO_KAP/main.kap examples/hello-kap/main.c
bash tools/build.sh out/MY_GAME/main.kap src/app.c src/game.c src/render.c
```

`build.sh` compiles with the exact flags the shell expects, then `pack.py` turns the result into a
`.kap` and refuses it if it breaks the memory budget. Copy `main.kap` + `app.json` + `icon.png` +
assets into `APPDRAWER/MY_GAME/` and REFRESH.

(Inside the shell's own source tree the same tools are `tools/kap/build.sh`, with `kap.h` at the root.)

### Native rules

- **No libc, no PSP headers.** Only what `KapHost` gives you (`host->sin`, `cos`, `sqrt`, `alloc`,
  drawing, input, audio, files). Check `kap.h` before using anything.
- **No sandbox.** A native app is trusted code: a crash or endless loop takes the console with it.
  There is no watchdog.
- **Memory:** declare it once with `KAP_MEMORY(heapBytes, extraBytes);`. Design for the LOW tier
  (8 MiB total, PSP-1000) and treat the HIGH tier (up to 16 MiB, 2000 / 3000 / Go) as extras.
  See *Memory tiers* in `APP_ENGINE_GUIDE.md`.
- **Saves:** `save()` / `saveAtomic()` only, up to 64 KiB, kept in `SHELL/APPDATA/<FOLDER>.sav`.
  Apps cannot write other files, except through the documents service (`kap_document.h`).
- **Floating point traps on the PSP.** `0.0f / 0.0f` is a crash, not a NaN. Guard every divide and
  every `sqrt` of a value that can go negative.
- **New host calls are appended at the end of `KapHost`.** Before calling one, check
  `host->size` covers it, so your app still runs (without that feature) on an older shell.

Start from a working example rather than an empty file:

| Example (in the kit) | Shows |
|---|---|
| `examples/hello-kap` | Smallest native app: input, drawing, save on exit |
| `examples/native-orbit` | Multi-file native app with the shared 3D engine |
| `examples/modular-orbit` | Lua app split into `require` modules |

The shell's source tree has more (`examples/arcade`, `examples/frost-climber`, `examples/depth-lab`).

---

## 7. Before you share an app

- Runs on a real PSP at a steady frame rate on its busiest screen (show FPS while testing).
- Pause menu on START, and the game stops while paused.
- No button-hint text on screen (house rule).
- Nothing drawn outside its box, text fits with the longest values.
- Survives HOME > QUIT at any moment and loads its save next launch.
- Works on a PSP-1000 (32 MB), or says clearly that it needs more memory.
- `app.json` filled in, `icon.png` 48 x 48, at least one `preview-01.png`.

To share: zip the app folder. Users unzip it into `PSP/KOMMANDER/APPDRAWER/` and press REFRESH.

---

## 8. Quick answers

| Question | Answer |
|---|---|
| My app does not show up | REFRESH the drawer. Check the entry file name is exactly `main.lua` / `main.kap`. If `app.json` has `entry`, that file must exist. |
| The icon is a letter tile | `app.json` must name it: `"icon": "icon.png"`. |
| My save vanished | The folder was renamed, or the save went over its limit (8 KB Lua, 64 KiB native). |
| "FRAME TIMEOUT" | A Lua frame took over 250 ms. Spread the work over several frames. |
| Fine in the simulator, crashes on PSP | Division by zero / NaN, a bitwise operation on a colour, or out of memory. |
| Can I read files or use the network? | Lua: only your own bundle's assets and your save. Native: assets, save and documents. No network API. |
