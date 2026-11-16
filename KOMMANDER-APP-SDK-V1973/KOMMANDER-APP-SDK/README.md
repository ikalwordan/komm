# KOMMANDER APP SDK

Everything needed to make apps for the **APPS** tab of the KOMMANDER shell, in Lua or native C.

Read `docs/APPS_DEVELOPER_GUIDE.md` first.

## What is in this kit

| Folder | Contents |
|---|---|
| `docs/` | `APPS_DEVELOPER_GUIDE.md` (start here), `APP_SDK.md` (Lua API, paste into an AI), `APP_SDK_NATIVE.md` (native API), `APP_ENGINE_GUIDE.md` (engine notes for big games) |
| `include/` | `kap.h` and the headers it includes. The native API contract. |
| `tools/` | `build.sh` (compile + pack), `kap.ld` (linker script), `pack.py` (ELF to KAP, checks the memory budget) |
| `examples/` | `hello-kap` (smallest native app), `native-orbit` (native, multi-file, 3D), `modular-orbit` (Lua with modules) |
| `simulator/` | Browser simulator for Lua apps. Open `index.html`. |

## Lua app in 4 steps

1. Paste `docs/APP_SDK.md` into an AI and ask for a Lua app (or write `main.lua` yourself).
2. Try it in `simulator/index.html` (OPEN BUNDLE FOLDER).
3. Copy the folder to `PSP/KOMMANDER/APPDRAWER/` on the memory stick.
4. On the PSP: APPS, TRIANGLE, REFRESH.

## Native app in 4 steps

1. Install pspdev (https://github.com/pspdev/pspdev) on Linux or WSL, and python3.
2. `export PSPDEV=$HOME/pspdev`
3. From this folder: `bash tools/build.sh out/HELLO_KAP/main.kap examples/hello-kap/main.c`
4. Copy `out/HELLO_KAP/main.kap` and `examples/hello-kap/app.json` into
   `PSP/KOMMANDER/APPDRAWER/HELLO_KAP/`, then REFRESH the drawer.

Needs a KOMMANDER shell of the version in `VERSION.txt` or later; older shells may refuse newer
packages.

## Licence

The headers, tools, docs and simulator code are under `LICENSE.md`. Third-party parts of the
simulator are listed in `THIRD-PARTY.txt`.
