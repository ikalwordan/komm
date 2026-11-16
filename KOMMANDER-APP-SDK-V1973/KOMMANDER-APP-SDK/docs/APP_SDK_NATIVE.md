# KOMMANDER native app SDK — KAP V1

KAP V1 was exercised on PSP by Orbit and the native arcade apps. V1129 adds
shared opaque 3D depth; operator confirms the layering fixes on PSP.
Lua remains supported, including optional modules (APP_SDK 1.20).

> **Before you build:** BUILDING A SOLID GAME in APP_ENGINE_GUIDE.md (FPU traps, save caps, testing).

## Build a multi-file C app

Use WSL and the installed PSP toolchain:

```sh
bash tools/kap/build.sh work/native-orbit/main.kap \
  examples/native-orbit/main.c examples/native-orbit/scene.c
```

Copy `main.kap` and the example's `app.json` into one drawer folder when deploying
a matching shell. Assets live alongside it. Discovery keeps existing priority:
`main.lua`, then `main.tic`, then `main.kap`, then `main.gb` (built-in GB engine).
From V1133, set `"entry":"main.kap"` to select a native port explicitly even
when an old Lua entry point remains on the card. Native bundles appear under NATIVE C
in the engine filter. Save identity remains the bundle folder name.

`kap.h` is the exact C ABI. Implement `kap_main(host, app)`, verify the ABI and
host size, initialize state, fill `update`, `draw`, optionally `destroy`, and
return 1. Return 0 to refuse initialization. The host zeroes the callback table.
The shell owns the frame, quit prompt, audio, saves, images, mesh cleanup and
arena lifetime. Callbacks must return promptly; avoid long work in initialization.

The host table exposes dimensions, palette, batched rectangles/text, input,
analog, time, tones, save/load, images, sounds, native camera/boxes/meshes,
single-precision math, menu state and performance labels. Register mesh geometry
once; draw objects by transform. Existing APP_PERF telemetry covers KAP update,
draw, frames and GE work as it does Lua. Heap figures are not KAP allocator peaks.

`host->alloc(bytes)` returns zeroed 16-byte-aligned storage from the package's
bounded bump arena, or NULL. It has no individual free: allocate pools once and
reuse them. The entire arena goes away on unload. The builder currently reserves
256 KiB of app heap; use `pack.py --heap BYTES` to change it. Image+BSS+heap must
fit 4 MiB on the low-memory profile or 8 MiB otherwise, and still fit actual free
heap. The loader temporarily holds the file plus arena; alignment can cost up
to 64 KiB more. Image/sound/mesh allocations use their existing host limits.

## Compilation and relocations

Apps are freestanding C (`-G0 -mno-abicalls -fno-pic -fno-builtin`), linked at zero
with relocations preserved. No libc, PSP NIDs, global constructors or OS calls
are linked into an app. Unresolved imports fail the link. Call the host's math,
asset and I/O functions; use ordinary loops for memory/string operations.

The packer accepts image-relative R_MIPS_32, R_MIPS_26, HI16 and LO16 and rejects
unsupported types. KAP1 stores a 40-byte little-endian header, image, and sorted
12-byte relocation records; CRC32 covers the payload. BSS is zeroed. Runtime
arena alignment is **64 KiB**, preserving signed-low carry and compiler-reused
HI16 instructions without ambiguous pairing. Direct jumps must remain within
one 256 MiB region. The loader checks sizes, version, CRC, sorted unique patch
locations and callback address bounds, then flushes D-cache and invalidates
I-cache before execution. This is a custom packed image, not a Sony PRX.

Native apps are trusted machine code. These checks detect malformed packages;
they are not a sandbox. There is no Lua watchdog, memory isolation, forced unwind
or guarantee that a native crash/hang can return to the shell. Use host-owned
resources only; initialization failure releases the arena but does not call an
unvalidated destroy pointer. Do not retain arena pointers in asynchronous work.

## Verification and simulator boundaries

`bash tools/kap/run.sh` builds the real PSP example, drives the exact portable
loader against corrupt files and relocation bases, and compiles the same C
sources against the shared 3D core for 50 host lifecycle cycles. Its empty-frame
negative control must fail. This is a host logic test, not execution of MIPS
instructions and not a PSP leak measurement.

The web simulator runs modular Lua and explicit Lua fallbacks. It cannot execute
MIPS `.kap` files. A browser C/Wasm host adapter is future work; the native C
example currently has a command-line host twin. The shared C core transforms/clips and submits to the GE batch with opaque
depth since V1129. A textured-world atlas, VFPU and Media Engine optimization
are not new features of this engine.

Operator confirmed Modular Orbit and Native Orbit work on PSP (2026-09-20).
For a matched comparison use `tools/orbit_bench/README.md`: separate Lua and C
apps run CPU, 81-box and mixed stages using the existing host perf recorder.
Matched Orbit hardware CPU-work measurements Lua/C:5.4/.9ms CPU stage,
4.7/2.8 DRAW,9.3/3.1 MIXED; both59.9fps.50-cycle hardware measurements remain pending.

`examples/gravity-salvage` is a first playable C game, split into input/lifecycle,
physics, rendering and save modules. It uses the existing native 2D batch and a
bounded fixed-step simulation; see its README and `tools/gravity_salvage/run.sh`.
Its host tests include actual six-piece towing, game outcomes and 50 launches.
Gameplay balance and performance still require PSP validation.

`examples/frost-climber` adds a single-player arcade platformer with original
pixel sprites, breakable tile floors, enemies, moving platforms and saved high
scores. Its source separates lifecycle, physics, world rules, rendering and
saves. `tools/frost_climber/run.sh` verifies complete climbing routes through
three mountains on the host; this does not replace PSP play/performance tests.

`examples/arcade` contains five independent first-playable games: Stack Tower
and Jet Ski Rush use native 3D geometry; Draw Car, Bridge Works and Trials Ride
use 2D drawing/editing and bounded simulation. Each keeps game rules and
rendering in separate modules, with shared lifecycle/input/save support and a
shared wheel solver for the two vehicle games. No API or ABI changes were
needed. `tools/arcade_suite/run.sh` builds all five MIPS packages, completes
host gameplay routes, checks saves/pause/repeated launches and runs sanitizers
and the actual KAP loader. Pass an app slug to test only that app during small
iterations; see `examples/arcade/README.md`. Hardware play samples exist, including V1129 Stack/Jet at59.9fps; full-route
and repeated-lifecycle hardware validation remain incomplete. The browser
simulator still does not execute native apps.

Before native app rollout: repeat 50 load/exit cycles,
check suspend/quit and heap recovery, then compare median/p95/worst frames for a
real port against its Lua version with identical quality and workload.

## SHARED DEPTH — V1129

Camera/box/mesh output now uses per-vertex camera depth in the PSP GE buffer.
This is a host renderer improvement, with no KAP ABI change or required game
rebuild. Keep opaque objects geometrically correct; sort hints cannot force a
far face above a near one. Give coplanar decals a physical offset. Flush the
world before 2D HUD calls. The depth buffer resets once per app frame, not per
mesh or flush. 16-bit precision and transparent rendering still need care.
The host arcade preview now consumes real depth triangles instead of silently
displaying the old painter result. See APP_SDK.md and tools/komgl/run_depth.sh.

Game Boy is a separate built-in AppEngine, not executable code inside a .gb ROM
and not an expanded KAP host table. Framebuffer and PCM services are not yet
exposed as KAP ABI methods. See tools/gameboy/README.md for cartridge packaging.

See APP_ENGINE_GUIDE.md for the authoring workflow and
docs/plans/NATIVE-GAME-CONVERSION-PLAN.md for staged ports. SDK1.20 discdepth
is a Lua convenience over the C renderer, not a KAP ABI change. V1130 Pool
performance is awaiting hardware confirmation.
# V1133 additions: explicit entry and local ad hoc

Bundles can set `"entry":"main.kap"` in `app.json`. Accepted exact basenames
are `main.lua`, `main.tic`, `main.kap`, and `main.gb`. An explicit entry wins
over old payloads left in the same folder. A missing explicit payload hides
that incomplete bundle. Omit the field to retain the legacy fallback order.

The ABI-1 KapHost table appends `adhocOpen`, `adhocClose`, `adhocPoll`,
`adhocSend`, `adhocRecv`, `adhocMac`, and `adhocError`. Check `host->size`
before reading optional tail members; old compiled KAP apps remain compatible.
Rocket Labs requires the complete V1133 table, including for offline play.

Ad hoc is CFW-only and exclusively owns the existing KomNet transport.
Close other shell network sessions first. Open returns zero on success;
poll returns 0/down, 1/joining, 2/ready, or a negative error. Send/receive
datagrams are bounded to 1024 bytes. See `net/komnet.h` for return semantics.
Call close on every exit and transport error; the host also closes on unload.
OFW exposes an explicit unavailable error. The app owns peer discovery,
packet validation, protocol versioning, authority, retransmission and timeout.
These APIs do not provide Internet matchmaking or retail-game tunnelling.

Rocket Labs source: `native/rocket/`; build: `bash tools/rocket_native/build.sh`.
Host/loader/course/protocol checks: `bash tools/rocket_native/run.sh sanitize`.
Its preserved Lua implementation is `native/rocket/reference.lua`, for
comparison only. The released bundle executes C and does not start a Lua VM.


## V1327 private documents

KapHost appends `document(op, args)` after audioRoute. Check host size before
reading it. `KapDocumentArgs` in kap_document.h contains a flat filename, buffer
and length/capacity. KDOC_WRITE stages <=1MiB and retains the old .bak; READ
and BACKUP return an entire bounded file or -1. Paths are scoped to
SHELL/APPDATA/<app-id>-DOCUMENTS. No delete/network/arbitrary path access.
Existing KAP ABI offsets and read-only assetIo are unchanged. PIXEL STUDIO
uses this for eight project slots and native-size PNG/BMP/spritesheet export.
See native/pixelstudio/README.md for bounds and acceptance status.

## V1454 tail: clock, Unicode text, keyboard

KapHost appends four entries after memInfo (kap.h documents each). Check
`size >= offsetof(KapHost, field) + sizeof(void *)` before calling; a V1453 or
older shell ends at memInfo.

- `localTime(KapDate *out)`: the PSP's local clock (sceRtcGetCurrentClockLocalTime),
  1 = filled. It is the clock the user set: it can be hours off or jump back, so
  an app that schedules by date keeps its own monotonic guard (KARDS: KClock in
  native/kards/sched.c).
- `textUni(x, y, utf8, col, scale, maxW)` / `textUniWidth(utf8, scale)`: the
  shell's Unicode path (drawTextUniClip / textWUni). Latin accents draw up to
  2*scale px above y; CJK uses the Misaki 8x8 cells (9*scale px); clipped per
  glyph to maxW. The 5x7 `text()` stays ASCII only.
- `textInput(op, KapTextArgs *)`: the shell's on-screen keyboard. KTXT_BEGIN
  shows it with buf as the start text (at most 59 characters); while it is up
  the shell skips update() (draw still runs, the keyboard over it) and HOME still
  pauses. KTXT_POLL: 0 typing, 1 accepted (buf filled, trailing spaces trimmed),
  -1 cancelled / nothing pending; an emptied field reads as cancelled. The
  keyboard is closed at every stop, error and launch.

Host twin: tools/kards/app_probe.c implements all four for the KARDS gate.

## V1459 tail: services, PNG export, document delete and list

KapHost appends two entries after textInput, in this order (kap.h documents each). Check
`size >= offsetof(KapHost, field) + sizeof(void *)` before calling; a V1458 or older shell ends at textInput.

- `service(name, version)`: a named service's table, or NULL when this shell lacks it (use your fallback). Every
  table starts `{ uint32_t version, size; ... }`: check `size` covers the calls you use. `service` is FIRST after
  textInput on purpose: KOMOCHI 1.0 was built against that slot (its own `KapHostNext`).
  - `"inbox"` (`KapInboxSvc`, kap.h): small append-only boxes one app writes and another reads. A box is 1..16 of
    A-Z 0-9, stored as SHELL/APPDATA/INBOX-<BOX>.BIN, at most 32 KiB (an append past that is refused). `read` gives
    the oldest bytes up to cap (0 = empty), `ack(box, n)` drops the first n bytes you used, `append` adds one record
    of 1..1024 bytes. The record layout belongs to the apps sharing the box. Box "STUDY": one `KapStudyRec` per
    finished KARDS review session (native/kards/study.c studyPost), read by KOMOCHI for STUDY XP.
  - `"gps"`, `"mic"`, `"stats"`: answer NULL in V1459. Their tables are drafted in native/komochi/komochi.h; each
    needs its own hardware round before it ships (the GPS receiver takes the USB bus, the mic's capture blocks for a
    whole 93 ms block).
- `exportPng(name, png, bytes)`: a PNG the app has already encoded, into PICTURE/<APP ID>/<NAME>.PNG (the app id in
  capitals, letters and digits only: DrawPad writes PICTURE/DRAWPAD/), where the PHOTO tab and a PC see it. name is
  1..32 of A-Z a-z 0-9 _ - without an extension; bytes <= 2 MiB and must start with the PNG signature. Written as a
  .tmp then renamed; a file of the same name is replaced. Returns the bytes written or -1.
- `document()` gains two ops (kap_document.h). `KDOC_DELETE` (name only; data and bytes unused): removes the
  document and its .bak, 0 = something removed, -1 = nothing there. `KDOC_LIST` (name unused; data = a char buffer,
  bytes = its size): every document name followed by '\n', then a NUL; .bak and .tmp are never listed; a name that
  does not fit is left out whole, never cut; returns how many names fit. Older shells refuse both with -1, so test
  for the V1459 tail (the KapHost reaching exportPng) before relying on them.

Host twins: tools/kspaint/app_probe.c (exportPng into PICTURE and KDOC_DELETE, plus the older-shell fallbacks),
tools/komochi/app_probe.c (service), tools/kards (studyPost compiles against the tail). The shell's own inbox,
export and delete code (apps.c) has no host harness: it is checked on hardware.

## V1460 APP TIMERS: deadlines the shell shows while your app is closed

No KapHost change: an app writes its upcoming moments into the document `TIMERS.KTM` with `document(KDOC_WRITE)`
every time it saves, using the helpers in `kaptimers.h` (`ktmBegin`, `ktmAdd`, `ktmSeal`). The shell (apptimers.c)
reads SHELL/APPDATA/<app>-DOCUMENTS/TIMERS.KTM at boot, when an app closes and every five minutes, and then:
- HOME > NOTIFICATIONS lists, after the store's rows: EVENT and WARN timers whose deadline has passed (newest
  first, "12 MIN AGO"), COUNT timers that have started ("KARDS  12 CARDS DUE"; of several COUNTs with one text only
  the latest started one shows), and with KTM_AHEAD the ones still coming ("IN 2 H 10 M"). X on a row opens the APPS
  drawer with that app under the cursor.
- KTM_TOAST: one toast when a deadline passes while the shell is in front (never while an app runs: it waits; never
  a burst at boot or after the clock is set back: what passed unannounced stays a row).
- KTM_BADGE: a dot on the app's drawer icon while the timer holds.
Deadlines are local minutes (days since 2000-01-01 x 1440 + hour x 60 + minute, from `localTime`), up to 8 timers,
24-character upper-case text. Write the file again whenever a deadline changes; a row goes away when your app,
opened, writes a file without it. Users of it: KOMOCHI (egg hatches, hungry, sick, mess, a letter) and KARDS (cards
due now and at the next study day). Gate: tools/apptimers/run.sh (12 checks, 4 seeded faults).
