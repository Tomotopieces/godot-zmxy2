P=/c/Users/Administrator/Projects/vibe/godot-zmxy2; cd $P
for x in decomp/xml/*.xml; do n=$(basename $x .xml); echo "== $n"; timeout 600 node --max-old-space-size=8192 tools/scripts/swfxml2json.js $x decomp/timeline/$n.json 2>&1 | tail -1; done; echo JSONDONE
