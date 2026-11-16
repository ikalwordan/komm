# WATER//TOY V9J

An original pocket water-ring game for KOMMANDER App Drawer, inspired by the
operator's PSP-shaped water-toy reference. Native C / KAP V1. All tank rails,
floor, pegs, ring tori, coral and burst bubbles are real depth-tested 3D geometry.
Bright cyan, hot pink, acid yellow and violet; shell bitmap terminal lettering.
The shallow tank uses a bounded 2D fluid-inspired play plane, with 3D ring tilt.
This is an arcade water toy, not a volumetric fluid solver.

## Controls

- **Any D-pad direction or L**: left pump.
- **Any face button (X, O, SQUARE, TRIANGLE) or R**: right pump. Both pumps work independently and simultaneously.
- Tap and release for a soft jet. Hold up to **1.1 seconds** for full pressure;
  release to discharge. The tank nearly fills the screen with an even narrow inset,
  with no HUD bars, meters or on-screen pump buttons. Longer holds cap safely.
- **Analog**: tilt the tank. Center gives a straight front view; a small deadzone
  rejects stick drift. Left/right tilt also steers loose rings; vertical tilt
  changes viewing pitch and the gravity component. Tilt returns smoothly to neutral.
- **START**: pause/resume. **X**: play, resume or next level.
- Level select: Up/Down (Left/Right also work), X to launch. All eight available.
- **TRIANGLE**: guide from title/pause; O returns.
- Pause: Square requests restart, O selects levels, Left/Right toggles sound.
  Restart defaults to Keep Playing and needs X confirmation.
- **HOME**: shell-owned exit. Held charges are canceled across pause and long
  elapsed-frame interruptions; release controls before charging again.

## Levels

1. Shallow Reef: 6 rings, two equal-height pegs.
2. Deep Blue: 6 rings, staggered peg heights and a gentle current.
3. Coral Gates: 8 rings, three coral shelves.
4. Drift Dock: 8 rings, slowly moving pegs and a current.
5. Tidal Garden: 10 rings, three pegs, side shelves and the strongest current.
6. Spin Cycle: 8 rings, three short pegs.
7. High Tide: 9 rings, two tall pegs and a current.
8. Solder Sea: 10 rings, three moving pegs.

Rings must descend with the peg tip inside their visible opening. Rim hits bounce.
There is no magnetic steering or teleport to a slot: rings slide down the shaft,
rest on the base or other rings, and count only after settling. Rings can lift
back off a peg. Threaded rings receive full pump force and remain mobile.
Whole-ring contacts prevent entry through pole sides or beneath the base.
Ring pairs use their actual rim geometry for loose, threaded and mixed contacts.
Balanced contact impulses and bounded corrections replace the sideways proximity
push. Rings and poles are solved together; resting stacks can retain a slight tilt.
Any peg can hold a stack; there are no hidden per-peg quotas. There is no timer loss or limited-pump penalty.
The completion screen records elapsed time and pump strokes. Completed levels,
last level and sound preference use an 8-byte versioned/checksummed save; atomic
save is used when exposed by the host. Save failure remains visible.

## Installation

Copy the **Water Toy** folder into your existing KOMMANDER **APPDRAWER** folder:
`PSP/KOMMANDER/APPDRAWER/WATER TOY` (or `KOMMANDER/APPDRAWER/WATER TOY` for a
root-layout installation). Required: main.kap, app.json, icon.png. Open Apps.
No shell rebuild or replacement is needed for the current native-app host.

## Source and verification

- main.c: host lifecycle, input, menus, persistence.
- physics.c: eight authored levels, pressure, fixed-step flow/contact/capture.
- render.c: cached torus/cylinder meshes, 3D aquarium, terminal HUD and menus.
- tools/watertoy/probe.c: actual app callbacks with the shared KOMGL C core.
- tools/watertoy/check_package.py: actual KAP loader and relocation checks.

Build: `bash tools/kap/build.sh OUTPUT/main.kap native/watertoy/{main,physics,render}.c`.
Host: tools/watertoy/run.sh (WSL PSPDEV; GCC with ASan/UBSan).
The run helper defaults to work/watertoy; use WT_OUT to override it.

V6 validation: warning-free PSP compilation; sanitizer checks; independent,
combined and hold-vs-tap input; pause blocking; real capture/miss cases; corrupt
save rejection/write failure; five physical completion fixtures; pole-wall clearance and full-force threaded pump tests; 50 host
load/exit cycles; bounded 3D geometry and no dropped faces; missing-geometry
negative control; actual KAP relocation/load checks at three bases and corrupt /
truncated payload rejection. Preview PNGs use real shell bitmap glyphs and shared
depth output; they are host captures, not PSP screenshots.

**V6 native build and host checks pass; PSP gameplay not yet tested.** Hardware pressure feel, sustained frame
rate, HOME/suspend and repeated native-app memory recovery still need validation.
The optional --routes lookahead bot stalled in level 2 in V5 and has not been
re-certified for V6. All five physical completion fixtures pass; human difficulty
and hardware frame rate still need playtesting.
All art is original procedural geometry; no reference-image assets were copied.

## V7

Bright toy look: flat colour-band backdrop per level (no gradients), swaying
plants and fish, coloured ring set, white-flash plus spark burst when a ring
settles, splash when a ring threads a peg, water plume on strong jets, and a
clear card with 1-3 stars (pumps used) and falling confetti. Pump meters are two
rects each. Ring-pair contacts gained exact-equivalent row/midpoint pruning
(same results, host bench ~35% less physics time on level 5). Controls and
physics tuning are unchanged. Not yet run on PSP hardware.

## V9H — immersive framing

Removed the top level/ring HUD. All eight maps and all three themes share the
taller, vertically centered tank with approximately 10 px neutral-view padding.
The title layout, controls, pump strengths and physics are unchanged.

## V9I — clean catches and even frame

Ring entry and settling no longer spawn particles; the brief ring highlight
and settling tone remain. Level-complete celebration is separate. All eight
maps share equal-width rails with flush corner joins and a closed bottom edge.

## V9J — silent settling

Removed the per-ring settling tone and white flash. Ring movement, pressure,
collisions and level progress are unchanged. The level-complete celebration
and pump sounds remain separate from settling feedback.
