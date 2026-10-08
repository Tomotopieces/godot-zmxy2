# Export static texts of every SWF as SVG (zoom 1; FFDec clips zoomed text SVGs). Godot rasterizes them at 2x.
P=/c/Users/Administrator/Projects/vibe/godot-zmxy2; cd $P
J="$(cygpath -w tools/ffdec/ffdec-cli.jar)"
for f in swf/res/dec/*.swf swf/official/zmxy2_game.swf; do n=$(basename $f .swf); o=decomp/texts/$n
  [ -f $o/.done ] && continue; mkdir -p $o; echo "== $n $(date +%T)"
  timeout 900 java -Xmx4g -jar "$J" -format text:svg -export text "$(cygpath -w $o)" "$(cygpath -w $f)" 2>&1 | grep -E 'rror|Exception' | head -3
  touch $o/.done
done; echo TEXTSDONE $(date +%T)
