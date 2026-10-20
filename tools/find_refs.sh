#!/usr/bin/env bash
# Who uses a resource? Like the editor's "View Owners": lists every scene / resource / script / data file that refers to
# the given res:// file by path or by its uid (from the .import / .uid file next to it).
#   bash tools/find_refs.sh game/assets/shared/ui/OtherMat_v10_236.png [more files...]
cd "$(dirname "$0")/../game" || exit 1
for f in "$@"; do
  p="${f#game/}"; p="${p#res://}"
  uid=$(grep -m1 -oP 'uid="?\Kuid://[a-z0-9]+' "$p.import" "$p.uid" 2>/dev/null | head -1 | sed 's/^[^:]*://')
  [ -f "$p.uid" ] && uid=$(head -1 "$p.uid")
  [ -z "$uid" ] && uid=$(head -1 "$p" 2>/dev/null | grep -oP 'uid="\Kuid://[a-z0-9]+')
  pat="res://$p"; [ -n "$uid" ] && pat="$pat|$uid"
  hits=$(grep -rlE "$pat" --include=*.tscn --include=*.tres --include=*.gd --include=*.json --include=*.gdshader --include=project.godot . 2>/dev/null | grep -vE '^\./\.godot/|\.import$' | sed 's#^\./##')
  echo "$p (${uid:-no uid}): ${hits:-UNUSED}"
done
