# 造梦西游2 重制版 — what an agent needs to know

## Controls (actions in scripts / act)

| | action | keyboard |
|---|---|---|
| move | `left` / `right` | A / D |
| run | tap a direction twice, or hold `run` while moving | |
| jump / double jump | `jump` (again in the air) | K |
| drop through a platform | hold `down`, press `jump` | S + K |
| attack (combo by pressing again) | `attack` | J |
| enter a door / portal | `up` | W |
| skills | `skill_u` `skill_i` `skill_o` `skill_l` | U I O L |
| 无双 (transform, rage bar full) | `rage` | Space |
| 法宝 skill (worn treasure) | `treasure` | H |

## Heroes and skills

Skills are learned with souls (灵魂) in 技能 (map button, or the in-stage menu). Each costs MP when used.

- 孙悟空 — 升龙斩 `up`+`attack` · 火炎突击 `attack` while running · 烈焰闪 `skill_u` · 烈焰风暴 `skill_i` · 火魔斩 `skill_o`
- 唐僧 — ranged. 冰龙波 hold `attack` · 玄冰阵 `skill_u` · 水幻影 `skill_i` (again: teleport to it) · 天降甘露 `skill_o` (heal) · 水魔爆 `skill_l`
- 猪八戒 — melee, three-hit combo. 碎石破 `skill_u` (ground) · 土流盾 `skill_i` (spin, blocks blows from the front) ·
  地滚战车 `skill_o` (charge, invincible while it rolls) · 战争怒吼 `up`+`attack` (pulls enemies in) · 土魔刺 `skill_l`
  (stance that reflects damage; `skill_l` again after a moment fires stabs). 八戒 is unlocked by beating 红孩儿 once.

## Screens (list_ui / press_ui)

- Title: 新的开始 (new game -> hero choice -> opening comic -> map), 继续游戏 (load a save), 游戏帮助, 退出游戏.
- Map: the stages (Stage1Level1 … Stage4Level1 on the main path, unlocked in order; NiuMoGu = 6-1 牛魔谷,
  LuoXuanDiYu = 10-1 螺旋地狱), BtnSkills, BtnForge (炼丹炉), BtnShop (商城), BtnSave, BtnActivity, BtnBack.
- The menu (pause in a stage; C / V / B or BtnSkills on the map) has tabs BtnBag 背包 / BtnSkill 技能 / BtnTreasure 法宝 /
  BtnSettings 设置 and BtnBack 返回 (or back_ui) to close it. 技能: an unlearned skill's icon learns it for souls; the
  passive page (PassiveButton) has 升级 buttons.
- 背包: three pages (装备 / 道具 / 时装). Press an item cell for its menu (装备 / 出售 / 使用 / 丢弃); press a worn slot
  to take it off. The tooltip of a cell is its name and quality.
- 炼丹炉: 强化 (equipment + stones) and 合成 (three materials -> one item; e.g. three marks of the same kind of boss -> a 法宝).
- Results: 下一关 / 重新挑战 / 返回地图. Saving happens automatically after a cleared stage when the game has a slot.

## Stages

Main path: 1-1 鬼城 · 1-2 无常巷 · 1-3 鬼门关 · 2-1 接引院 · 2-2 判官殿 · 2-3 阎罗殿 · 3-1 忘川河 · 3-2 奈何桥 · 3-3 望乡台 ·
4-1 转轮殿 (转轮王, three forms). Side: 6-1 牛魔谷 (红孩儿), 10-1 螺旋地狱 (a hall: hit the round dial to choose a door,
then hit both stones at the same time to open it; doors lead to 10-2 … 10-5, the statue to 10-6). Hidden: 1-2's 白骨门,
3-1's aurora with the 避水珠, 刑天门s in 2-2 / 2-3.

A stage is a row of rooms: the screen locks at each stop until its enemies are gone (`stage.locked`, `room`/`rooms`);
then GOGO, walk on. After the last room (or the boss) the exit door opens: stand in it and press `up`.

## Things the game does by itself

- Drops: equipment falls to the ground and goes into the bag when you walk over it (it vanishes after a while unless
  it is boss loot). Soul orbs fly to the hero.
- Five hits within a second give a short invincibility (anti-lock).
- Falling into a pit kills the hero.
