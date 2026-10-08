# Extract + build rigs. Usage: bash tools/rig/batch.sh specs.txt
#   spec lines: <lib> <AS class|#id[@frame]> <name> [<lib>:<host class>:<child> whose placement filters apply]
cd /c/Users/Administrator/Projects/vibe/godot-zmxy2
GD="/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"
args=()
while read -r lib cls name filters_from; do
  [ -z "$lib" ] || [ "${lib:0:1}" = "#" ] && continue
  timeout 120 node tools/rig/extract_rig.js "$lib" "$cls" "$name" "game/assets/rigs/$name/rig.json" $filters_from > "tools/dl/rig_$name.log" 2>&1 || echo "EXTRACT FAIL $name"
  grep -q UNKNOWN "tools/dl/rig_$name.log" && echo "unknown scripts in $name (see tools/dl/rig_$name.log)"
  args+=("res://assets/rigs/$name/rig.json")
done < "$1"
cd game
timeout 900 "$GD" --headless --path "$(cygpath -w $PWD)" --import > ../tools/dl/import.log 2>&1
timeout 1800 "$GD" --headless --path "$(cygpath -w $PWD)" -s res://tools/build_rig.gd -- "${args[@]}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^built|ERROR|SCRIPT' | grep -vE 'leaked|still in use'
