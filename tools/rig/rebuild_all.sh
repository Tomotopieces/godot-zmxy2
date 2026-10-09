#!/bin/bash
# Rebuilds every rig scene (.tscn + anims.res) from its rig.json, after the textures or their paths changed.
cd "$(dirname "$0")/../.."
GD="${GODOT:-/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe}"
args=()
for f in game/assets/rigs/*/rig.json; do args+=("res://${f#game/}"); done
cd game
timeout 900 "$GD" --headless --path . --import > ../tools/dl/import.log 2>&1
timeout 1800 "$GD" --headless --path . -s res://tools/build_rig.gd -- "${args[@]}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'ERROR|SCRIPT' | grep -vE 'leaked|still in use'
echo "rebuilt ${#args[@]} rigs"
