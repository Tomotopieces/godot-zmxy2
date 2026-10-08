# Export every shape + image of every SWF as PNG at 2x (used by the Godot FlashClip runtime)
P=/c/Users/Administrator/Projects/vibe/godot-zmxy2; cd $P
J="$(cygpath -w tools/ffdec/ffdec-cli.jar)"
for f in swf/res/dec/*.swf swf/official/zmxy2_game.swf; do n=$(basename $f .swf); o=decomp/shapes/$n
  [ -f $o/.done ] && continue; mkdir -p $o; echo "== $n $(date +%T)"
  timeout 1800 java -Xmx6g -jar "$J" -zoom 2 -format shape:png,morphshape:png_start_end,image:png -export shape,morphshape,image "$(cygpath -w $o)" "$(cygpath -w $f)" 2>&1 | grep -E 'rror|Exception' | head -3
  touch $o/.done
done; echo SHAPESDONE $(date +%T)
