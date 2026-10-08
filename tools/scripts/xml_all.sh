P=/c/Users/Administrator/Projects/vibe/godot-zmxy2; cd $P
J="$(cygpath -w tools/ffdec/ffdec-cli.jar)"
for f in swf/res/dec/*.swf swf/official/zmxy2_game.swf; do n=$(basename $f .swf)
  [ -f decomp/timeline/$n.json ] && continue
  echo "== $n $(date +%T)"
  timeout 900 java -Xmx6g -jar "$J" -swf2xml "$(cygpath -w $f)" "$(cygpath -w decomp/xml/$n.xml)" >/dev/null 2>&1
  timeout 600 node --max-old-space-size=8192 tools/scripts/swfxml2json.js decomp/xml/$n.xml decomp/timeline/$n.json 2>&1 | tail -1
done; echo ALLDONE $(date +%T)
