#!/bin/bash
# Web export into web/ (preset "Web", custom loading shell game/web_shell/shell.html) plus the caching service worker.
# The pack is split into content-defined chunks (tools/web_chunks.js); sw.js rebuilds it from the browser cache and
# downloads only the chunks a new build changed.
GODOT="${GODOT:-/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 2
mkdir -p web
# build id shown on the title: commit hash, plus "m" when the tree has uncommitted changes
id=$(git rev-parse --short=7 HEAD)$(git diff --quiet HEAD -- game || echo m)
echo "$id" > game/build_id.txt
(cd game && "$GODOT" --headless --path . --export-release Web ../web/index.html > ../tools/dl/web_export.log 2>&1) || { tail -20 tools/dl/web_export.log; exit 1; }
cp game/web_shell/loading_bg.png game/web_shell/loading_bar_empty.png game/web_shell/loading_bar_full.png web/
# the pack is published as chunks (web/chunks + web/pck.json) so an update downloads only what changed
node tools/web_chunks.js web || exit 1
build=$(cat web/pck.json web/index.wasm | sha1sum | cut -c1-12)
sed "s/__BUILD__/$build/" game/web_shell/sw.js > web/sw.js
echo "web build $build"
