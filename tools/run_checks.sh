#!/bin/bash
# Runs the headless logic checks (game/tools/*_check, *_test) and exits non-zero if any fails.
#   bash tools/run_checks.sh            all checks
#   bash tools/run_checks.sh forge      only those whose name contains "forge"
# A check fails on a line starting with FAIL, a script/parse error, or a timeout. The randomised treasure check gets one retry.
GODOT="${GODOT:-/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/../game" || exit 2
CHECKS=("role_check" "smoke_test" "bag_check" "forge_check" "treasure_check" "stage_test -- hub" "stage_test -- door12")
failed=0
run() {
  local scene="${1%% *}" rest="${1#"$scene"}" out
  out=$(timeout 240 "$GODOT" --headless --path . "res://tools/$scene.tscn" $rest 2>&1)
  local code=$?
  if [ $code -ne 0 ] && [ $code -ne 1 ] || echo "$out" | grep -qE "^FAIL|SCRIPT ERROR|Parse Error"; then
    echo "$out" | grep -E "^FAIL|SCRIPT ERROR|Parse Error" | head -5
    return 1
  fi
  return 0
}
for c in "${CHECKS[@]}"; do
  [ -n "$1" ] && [[ "$c" != *"$1"* ]] && continue
  if run "$c" || { [[ "$c" == treasure_check* ]] && run "$c"; }; then echo "PASS  $c"; else echo "FAIL  $c"; failed=1; fi
done
exit $failed
