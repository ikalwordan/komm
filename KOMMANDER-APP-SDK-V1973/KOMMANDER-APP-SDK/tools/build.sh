#!/bin/bash
# KOMMANDER APP SDK: build a native KAP app.
#   bash tools/build.sh OUTPUT.kap APP.c [MORE.c ...]
# Needs the PSP toolchain (pspdev, https://github.com/pspdev/pspdev) and python3.
# psp-gcc is taken from PATH, or from $PSPDEV/bin when PSPDEV is set.
set -euo pipefail
if [ $# -lt 2 ]; then echo "usage: bash tools/build.sh OUTPUT.kap APP.c [MORE.c ...]" >&2; exit 2; fi
if [ -n "${PSPDEV:-}" ]; then export PATH="$PSPDEV/bin:$PATH"; fi
if ! command -v psp-gcc >/dev/null 2>&1; then
    echo "psp-gcc not found: install pspdev and set PSPDEV (export PSPDEV=\$HOME/pspdev)" >&2; exit 1
fi
kit="$(cd "$(dirname "$0")/.." && pwd)"
output="$1"; shift
mkdir -p "$(dirname "$output")"
psp-gcc -O2 -G0 -mno-abicalls -fno-pic -ffreestanding -fno-builtin \
  -fno-common -fno-stack-protector -Wall -Wextra -Werror -std=c99 \
  -nostdlib -I"$kit/include" -Wl,--emit-relocs,-T,"$kit/tools/kap.ld" \
  "$@" -o "$output.elf"
python3 "$kit/tools/pack.py" "$output.elf" "$output"
rm -f "$output.elf"
echo "built $output"
