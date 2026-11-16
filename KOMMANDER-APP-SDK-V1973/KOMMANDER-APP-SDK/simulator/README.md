# KOMMANDER LUA — App Simulator

Run the LUA `.lua` apps in a web browser, on any OS (Windows/Linux/macOS), to
iterate on gameplay/layout/input/audio before deploying to a PSP. It's built for
**developing** apps: a live-reload code editor sits next to the preview, so you edit
on the right and watch it run on the left.

## Use it
1. Open **`index.html`** in a browser (double-click — no server needed).
2. Click the page once so audio can start.
3. Pick a **Local App** (loads it into the editor and runs it), then just **edit the
   code** — it re-runs live as you type. Or load your own:
   - **Open .lua…** / drag a `.lua` onto the drop zone — single-file apps.
   - **Open bundle folder…** / drag a folder — bundle apps (`main.lua` + `app.json`
     + sidecar `icon.png`/`.wav` etc.); `kom.image("x.png")` resolves from the folder.
   - Loaded code drops into the editor so you can keep tweaking.
4. **RUN** / **RESTART** re-run the editor's code. **Live reload** can be toggled off.

### Layout
- **Top:** a KOMMANDER OS status bar (with live clock) + preview (left) + live editor (right).
- **Bottom-left:** Local Apps list, My Revisions, and your-app loaders (same width as the preview).
- **Bottom-right:** Display settings, Theme, key reference, and notes.

### Saving & revisions
- **SAVE** persists your edits (in this browser): for a Local App they're remembered and
  re-loaded next time (the row shows a ● and "edited"); use **ORIGINAL** to revert.
- **SAVE AS…** stores a named **revision** (listed under *My Revisions*).
- **DOWNLOAD** writes the editor's code out as a `.lua` — the way to get it onto the card.
- Switching apps with unsaved edits prompts: *Save changes / Save as revision / Discard / Cancel*.

### Editor
Bundle folders may contain nested Lua modules (`require("game.camera")` loads
`game/camera.lua`). Select a source file above the editor to edit it; RUN always
starts `main.lua`. SAVE and SAVE AS preserve all module edits. DOWNLOAD exports
a bundle ZIP with nested paths and assets; single-file apps still download as
`.lua`. Use **Open bundle folder** for nested files: browser drag/drop support
for directories varies. Extract the ZIP to its own app folder before deploying.
Requires a matching shell with SDK 1.18 module support. Example:
`../examples/modular-orbit`. Modules are cached per run; errors, cycles, invalid
names and bytecode are rejected. Module restarts discard previous caches.

A full CodeMirror editor: line numbers, Lua syntax highlighting, bracket matching, and
**autocomplete** (Ctrl-Space, or as you type) for the `kom.*` API and Lua keywords.

### Settings
The **⚙ SETTINGS** button (top bar) toggles: dark/light interface, 24/12-hour clock,
preview glow (none/soft/strong), and a preview outline. Choices persist in this browser.

### Focus mode
**⛶ FOCUS** opens a fullscreen split (preview | editor) with a draggable divider to resize,
plus a preview-size control: **FIT**, **PSP 1×** (480×272), or **4×**. Esc or **EXIT** returns.
The editor and live-reload keep working throughout.

### Display & Theme
- **Render mode is LOCKED TO FULL** and the switch is hidden. The shell has one
  render mode now — `inset`/`window` in a header or `app.json` are ignored on the
  device — so a preview in either was a preview of something that cannot happen.
  The regions and the radios are still in the code (`MODES` in kom.js, the hidden
  field in index.html) if that ever changes back.
- **CRT effect** toggle — scanlines + vignette + a rolling flicker band, mirroring the
  PSP EBOOT's `themeOverlay()` (theme.c).
- **Theme** — pick a preset (Red/Amber/Green/Cyan/Violet/Mono) or a custom accent; the
  whole palette derives from it exactly like the PSP theme menu (`deriveFromBase`), and
  the page UI re-tints to match. The running app re-runs so its `kom.col` updates.

## Controls
| Key | PSP |
|-----|-----|
| Arrows | D-pad |
| Z / X | ✕ / ◯ |
| A / S | ▢ / △ |
| Q / W | L / R |
| Enter | START |
| Right Shift | SELECT |
| Esc   | HOME (quit) |

A standard **gamepad** also works (left stick → `kom.analog`).

## Native engines

The C SDK (`../APP_SDK_NATIVE.md`) builds multi-file `.kap` apps for the new
native backend. This browser cannot execute PSP machine code. Its C example has
a command-line host twin; a browser C/Wasm adapter is future work. Lua apps can
use the shared native services on PSP and keep explicit Lua browser fallbacks.

The catalogue is regenerated from the current curated release apps. PowderLab's
`kom.powder` engine runs in native PSP C and is not emulated by this Lua browser
host. Its current source is available to edit/download and clearly labelled
PSP NATIVE ENGINE; test the simulation on PSP. This tool does not measure PSP FPS.

## What it is / isn't
Faithful: the 5×7 bitmap font and the palette are ported from the C source
(`font.c`, `theme.c`), colours use the same packing, render regions match `apps.c`,
the CRT overlay matches `themeOverlay()`, and `kom.tone` mirrors the PSP synth.

It tests **app logic, layout, input and audio** — **not** PSP RAM/CPU limits or
exact frame timing. Things it will NOT catch (check on real hardware): out-of-memory
on a PSP-1000, framerate drops, and exact audio timbre. The Lua engine is Fengari
(Lua 5.3, 32-bit integers) — near-identical to our 5.4 apps for everything the `kom`
API does. An infinite loop inside `update()` will freeze the browser tab (there's no
watchdog like the PSP host) — just close the tab.

## Files
- `index.html` — the page/UI (preview + editor + settings).
- `kom.js` — the `kom` host API + run loop + input + audio + theme/CRT (mirrors
  `app_lua.c`/`apps.c`/`theme.c`).
- `font.js` — the 5×7 font ported from `font.c`.
- In the source repository, `../appdrawer/` provides current shipped apps and
  `appdrawer/` provides extra demos; public release exclusions apply to both.
- `apps.js` — those apps embedded as data, so the picker works offline from `file://`
  (browsers can't fetch sibling files there). Regenerate after editing `appdrawer/`:
  **`node simulator/gen_apps.js`** from the source repository root.
  Release archives contain the generated catalogue; the source generator and
  demo folders remain in the repository. The APP PACKAGE contains current
  shipped app sources.
- `vendor/fengari-web.js` — the Lua engine (MIT).
- `vendor/codemirror/` — the code editor (CodeMirror 5, MIT): core + Lua mode + hint/bracket addons.

## Authoring
Pair this with `../APP_SDK.md` (the paste-into-an-AI app guide): generate an app,
run/iterate here, then drop the `.lua` into `PSP/KOMMANDER/APPDRAWER/` (or `KOMMANDER/APPDRAWER/` for a root-layout install) on the PSP.

## Desktop audio companion

The [Mood Scanner](../mood-scanner/index.html) runs the same way: open its HTML
file directly or serve its folder on a static host. It analyses local audio and
exports PSP-compatible mood.dat, with merge/resume and protected manual choices.
Release packages include both HTML tools under PSP/KOMMANDER/TOOLS.
The complete bundle also provides independent HTML tools and APP_SDK.md.
