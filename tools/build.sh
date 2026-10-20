#!/bin/bash
# Release export of the Windows exe: build/zmxy2_<branch>_v<version>.exe  (version = file_version of the export preset, trailing .0 dropped)
GODOT="${GODOT:-/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 2
ver=$(grep -m1 '^application/file_version=' game/export_presets.cfg | sed -E 's/.*="([0-9.]+)"/\1/; s/\.0$//')
branch=$(git rev-parse --abbrev-ref HEAD)
out="build/zmxy2_${branch}_v${ver}.exe"
mkdir -p build
# build id shown on the title: commit hash, plus "m" when the tree has uncommitted changes
id=$(git rev-parse --short=7 HEAD)$(git diff --quiet HEAD -- game || echo m)
echo "$id" > game/build_id.txt
# fonts: only the characters the game can show go into the export (tools/subset_fonts.py); the full ones come back after
PY="${PY:-/c/Users/Administrator/miniconda3/python.exe}"
"$PY" tools/subset_fonts.py subset || exit 1
trap '"$PY" tools/subset_fonts.py restore' EXIT
cd game && "$GODOT" --headless --path . --export-release Windows "../$out" > ../build/export.log 2>&1
cd .. && ls -la "$out"
