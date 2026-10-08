# Sequential ffdec export of all decoded resource SWFs: scripts + images + sprites(png) + sounds + binaryData
P=/c/Users/Administrator/Projects/vibe/godot-zmxy2
J="$(cygpath -w $P/tools/ffdec/ffdec-cli.jar)"
for f in $P/swf/res/dec/*.swf $P/swf/official/zmxy2_game.swf; do
  n=$(basename $f .swf); o="$(cygpath -w $P/decomp/res/$n)"
  echo "== $n $(date +%T)"
  timeout 1200 java -Xmx6g -jar "$J" -format script:as,image:png,sound:mp3_wav,shape:png -export script,image,sound,binaryData "$o" "$(cygpath -w $f)" 2>&1 | grep -vE '^Exported|^Exporting' | tail -3
done
echo ALLDONE $(date +%T)
