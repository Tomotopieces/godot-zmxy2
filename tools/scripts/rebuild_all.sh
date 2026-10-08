P=/c/Users/Administrator/Projects/vibe/godot-zmxy2; cd $P
bash tools/scripts/json_all.sh
bash tools/scripts/texts_all.sh
NOSOUND=1 timeout 2400 node --max-old-space-size=8192 tools/scripts/build_assets.js 1_v6 2 3 4 5 5_v7 6 7 8 9 10 11 Pig9 Role_v6 OtherMat_v10 Common_v7 zmxy2_game backpack_v5
echo REBUILDDONE $(date +%T)
