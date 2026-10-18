#!/bin/bash
# Web export into web/ (preset "Web", custom loading shell game/web_shell/shell.html) plus the caching service worker:
# sw.js gets a build id from index.pck + index.wasm, so players download the game once per build.
GODOT="${GODOT:-/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 2
mkdir -p web
# build id shown on the title: commit hash, plus "m" when the tree has uncommitted changes
id=$(git rev-parse --short=7 HEAD)$(git diff --quiet HEAD -- game || echo m)
echo "$id" > game/build_id.txt
(cd game && "$GODOT" --headless --path . --export-release Web ../web/index.html > ../tools/dl/web_export.log 2>&1) || { tail -20 tools/dl/web_export.log; exit 1; }
cp game/web_shell/loading_bg.png game/web_shell/loading_bar_empty.png game/web_shell/loading_bar_full.png web/
build=$(cat web/index.pck web/index.wasm | sha1sum | cut -c1-12)
sed "s/__BUILD__/$build/" game/web_shell/sw.js > web/sw.js
echo "web build $build"; ls -la web/index.pck web/index.wasm
