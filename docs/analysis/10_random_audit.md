# 10 随机性审计（重制版 Rng.* vs 原版 AS3）

范围：game/src 下全部 `Rng.*` 调用（brains / monster / hero / treasure / stages / items / core / data）对照 decomp/ 原版。
已知并已修复的（Math.round(random*(n-1)) 首尾半概率：装备掉落表、法宝元素/被动/成长、装备属性、英雄攻击浮动）与药/灵气/装备/石头掉落不再重复。
严重度：高=明显改变玩家体验；中=可察觉的分布/行为差；低=统计上很小。

## A. 不一致（按严重度）

### 中
1. **M79 -> 79/80 随机未实现**
   重制：game/src/level/level.gd:277/315 直接 `monster_data(sp.enemy)`，11-1 永远是 M79（HP 3000）。
   原版：my/MainGame.as:141 `createMonster`: `if(id==79) id += Math.round(Math.random())`，50% 劈天斧(79) / 50% 风神盾(80, HP 30000)。
   修：spawner/level 创建怪物前 `if id == 79: id += Rng.randi() % 2`（04/05/06 文档已记载，代码漏了）。
2. **泰山王 74/76 攻击概率写死 50%**
   重制：actors/brains/taishan.gd:42,49 `Rng.randf() < 0.5`。
   原版：Monster74/76.as:22 `isattback = 70`，Monster73/75 为 50（`randomNum(isattback)`，Monster7x.as:105/121）。monster_74/76.tres 里 attack_chance=70 已烘焙但没被用。
   修：`Rng.randi() % 100 < m.data.attack_chance`（与 base_ai 一致）。
3. **罗刹妖伞毒伤：公式 + 掷骰时机都不对**
   重制：actors/treasures/treasure_lsys.gd:26 每根针（一次 8 根）各掷一次 `int((50 + 15*L) * element_mul)`。
   原版：base/BaseHero.as:282-286 `50 + L*15*mul`（mul 只乘每级项，木 1.5+r*0.5，其他 1+(r-0.5)*0.2），且只在 `updateMagicWeapon()`（换装备/强化/创建英雄）时掷一次，之后所有针共用同一个 int 值。
   修：在法宝创建/装备变更时算一次 `50 + int(L*15*mul)`，缓存复用。
4. **血海魔童(xhmt)目标选取是随机，原版是确定的**
   重制：treasures/treasure_xhmt.gd:32 `all[Rng.randi() % all.size()]`。
   原版：magicWeapon/MagicPearl.as:62-72 取 monsterArray 里**第一个**非无敌且非 57/60/70 的怪（无随机；技能描述写"随机怪物"但代码不是）。
   修：`all[0]`（保持 monsters() 的生成顺序）。若想保留描述就当作有意偏离并在文档注明。
5. **五毒兽(wds)选目标：先过滤再等概率 vs 原版先抽再作废**
   重制：treasures/treasure_wds.gd:34(H 技能)、:60(自动吐弹) 都用 `candidates()`（已排除 skip 与不可命中）。
   原版：WuDu.as:61 H 技能 `doHit1` 在**全部** monsterArray 里抽，无 skip；:212 自动弹抽到 Monster70 则这次作废（不重抽）。
   差异：H 技能可抽到 70/78 等道具怪（原版如此，重制不会）；自动弹对其他怪的分布相同，只是不浪费次数。影响小，按需保留。

### 低
6. **英雄受击浮动：分布不同**
   重制：actors/hero.gd:479 `mitigated(...) + Rng.randi_range(-5, 5)`（11 个值等概率，方差 10）。
   原版：BaseHero.as:439/540 `int noise = (Math.random()-0.5)*10`（`_loc2_:int`，向零取整 -> -4..4，0 占 20%，方差 6），且加在**减防之前**（`_loc4_ = getRealPower + noise` 再 toBlood / `*= 1-magicdef`）。
   修：`noise = int((Rng.randf()-0.5)*10)`，加到 `h.damage` 后再做 mitigated（Hit.mitigated 需接受已加噪声的伤害）。
7. **M69 分身 / M72 起跳的重置计数多一个值（闭区间）**
   重制：brain_69.gd:30 `randi_range(10,20)`，brain_72.gd:18 `randi_range(5,10)`。
   原版：Monster69.as:80 `int = 10 + random*10` -> 10..19；Monster72.as:98 `5 + random*5` -> 5..9。
   修：上界减 1（`randi_range(r[0], r[1]-1)`），或数据改成 [10,19]/[5,9]。
8. **M56 夜叉转向间隔范围偏短**
   重制：tools/data/monsters.json:462 `turn_every_frames [24,72]`（1~3 s）。
   原版：Monster56.as:123 `24 * (1 + Math.random()*3)` -> 24..96 帧（1~4 s）。
   修：[24,96]。
9. **M58 刑天近身缺 skill1 兜底**
   重制：brain_58 继承 boss_d，近身(<=150)检查 tick 70% 平砍，30% 走 wander。
   原版：Monster58.as:107-120 近身 30% 分支里 `skillCD1==0` 则放 hit2-1 跳跃（CD 140+int(r*100)），否则 normalWalk。其它模板 D（46/48/77/81）无此兜底。
   修：brain_58 覆盖 `_melee_or_walk`：失败分支先尝试 skill1。
10. **sl31 跳怪(M41)出水位置**
    重制：level/stages/sl31.gd:73 `boat.x ± dx(100)`（只有两个固定点）。
    原版：StageListener31.as:75 `boat.x + (Math.random()-0.5)*200` 连续均匀 [-100,100]。
    修：`Rng.randf_range(-dx, dx)`。
11. **sl31 每次飞鱼数量分布**
    重制：sl31.gd:104 `randi_range(2,4)` 均匀（均值 3）。
    原版：Monster57.as:63 `while(i < int(2 + Math.random()*3))` 每轮循环条件重掷，结果 2:1/3，3:4/9，4:2/9（均值 2.89）。
    修：`n = 2; if randf()<2/3: n=3; if randf()<1/3 (在已到3时): n=4`。差异很小，可忽略。
12. **M69 分身出生偏移**
    重制：brain_69.gd on_call "do_fenshen" 固定 `+20*facing`。
    原版：Monster69.as:195 `x + (Math.random()-0.5)*40` 即 ±20 随机。修：加 `Rng.randf_range(-20,20)`。
13. **M52 初始头**
    重制：brain_52.gd:8 `_head = &"wait1"`，首次随机在 3 s 后。
    原版：Monster52.as:31 构造时 `setRandomHead()`（ceil(r*5) -> 1..5）。修：setup() 里 `_head = HEADS[randi % 5]`。
14. **漫游"每帧"掷骰按 60 Hz 而非 24 Hz**
    重制：monster_brain.gd:154-157 每个物理 tick 掷 `randf()<0.5` 和 `randf()*wander_rest`。
    原版：BaseMonster.as:1180-1200 `waitamonent` 每帧(24 fps)掷：`count >= stopNum + random*30`。
    因为"每帧重掷阈值"，休息时长分布依赖帧率：原版均值约 0.29 s，重制约 0.18 s。影响很小；要精确可用 24 Hz 累加器驱动这两次掷骰。
15. **模板 D 在近/中距离每帧调用 wander**
    重制：boss_d.gd:45-52 `_melee_or_walk` 在两次检查之间（`_check > 0`）每 tick 调 `wander(delta)`，会在 0.5 s 处挑方向开始走。
    原版（46/48/58/77/81）：近/中距离只在 `count%24==0` 的检查帧 30% 分支调一次 normalWalk（而 normalWalk 的方向挑选要求 `count==12`，所以这里基本是空操作）。
    结果：重制里这些 boss 贴脸时可能随机走开，原版基本站桩。建议两次检查之间不调 wander（只在 30% 失败分支或远距离调）。

## B. 原版有、重制没做的随机（已汇总到上面）
- M79 -> 79/80（#1）。
- M52 初始头、M69 分身偏移、M41 出水位置连续抖动（#13 #12 #10）。
- AUtils 残影：静止英雄 `x += (random-0.5)*5`（AUtils.as:115，纯视觉，可不做）。
- BaseRoleProperies / Config / MemoryClass / PackThings / RoleInfo 里的 `+ Math.random()` 是防修改内存的噪声，不需要。
- MonsterAppearPoint.isRandom / randomArray 在原版**没被使用**（刷怪点无随机）。
- Config.getRandomPlayer / Monster49.doHit3_1 / Monster56 转向 随机选玩家：重制只有 1 个英雄，等价。
- 英雄攻击浮动 `10 + round(r*4)`：原版在 upGrade（升级 + 每次进关创建英雄）重掷；重制只在升级/新档掷并写入存档，不会每关重掷（等价性可接受，低）。

## C. 已核对、一致（一行结论）
- brain_38（4~7 发 `3+ceil(r*4)`，±50 x 抖动，y 摆动 (r-0.5)*5 px/帧每 12 帧）：一致。
- brain_39（`ceil(r*3)` 秒的加速攻击间隔）：一致。
- brain_43 / brain_59（构造时一次性 `(1+2r)*24` 转向间隔、59 的偏移 160±40 / 140±60、炸弹 vx 5..44、vy 3..7、50% 攻击）：一致（整数截断忽略）。
- brain_46/48/58/77/81 的 skill2 80% 每帧、skill1 CD `140/240 + int(r*100)`、近身 70%：一致；M48 招式 [1,5,6,7] 等概率、M77 hit2 变体 1..4 等概率：一致。
- brain_49（hit1/hit4 各 50%）、brain_72 hit3-1/3-2 50%：一致。
- brain_52 换头间隔 [2,5) s、头 1..5 等概率：一致（初始头见 #13）。
- brain_60：backType 构造时掷一次（4 个等概率）、投掷间隔 (2+3r) s、无放回选槽位：一致（第 8 球后到第一次召回原版多 2 s 的飞行时间，非随机）。
- brain_64 / StageListener91（65 或 66 各 50%）：一致。
- 泰山 73/75 的 `skillCD2 = 240+random*100` 在原版是对已销毁对象赋值（无效），重制固定 20 s：一致。
- monster_brain 基础 AI：攻击检查 `randomNum(isattback)`（各怪 isattback 已烘焙，逐个核对与原版一致）、漫游方向 50/50、停留 72/96 帧 50/50：一致。
- sl12（hit 点 x±200、y -20..-70、受击特效 50/50）、sl22/sl23（刑天门 3 选 1 等概率）、sl31 的极光 [5,15) s / 跳怪 [3,7) s / 飞鱼间隔 [1,4) s / 飞鱼速度 0.3/0.3/0.4 / y 深度 0~50 / x ±50、sl33 珍珠 20% 掉避水珠：一致。
- loot.gd 灵气位置抖动 (10/20/30/40)、红灵 `2+floor(r*3)`、绿/蓝/白 4%/4%/4% 档：一致。
- forge.gd（强化 `r < allpro`、合成石头 75%、元素 91%/9%、被动 4 档 + whichskill 50/50）：一致；Rng.stepped / Rng.pick 无偏。
- treasure.gd 的伤害公式（`(base+L*k+(r-0.5)*spread)*mul`、木 1.5+0.5r / 非木 0.9~1.1 / 五毒木 1.2+0.3r 非木 1）、英雄暴击 `r<crit`（含 RoleInfo 怒气用的第二次暴击掷骰）、八戒眩晕 `r<deephit`、受击特效 50/50：一致。
- Rng 本身：`randi() % n` 的模偏差 ~n/2^32，可忽略；未发现 roundi/snappedf 作用于均匀浮点当索引的残留偏置。

## D. 处理结果
已改：#1 M79→79/80、#2 泰山王攻击概率读数据、#3 罗刹妖伞毒伤（公式 + 只掷一次）、#6 受击浮动（-4..4，加在减防之前）、#7 闭区间（数据改 [10,19] / [5,9]）、#8 夜叉转向 [24,96]、#10 跳怪出水位置连续、#11 飞鱼数量分布、#12 分身偏移、#13 秦广王傀儡初始头、#15 模板 D 近身不再乱走。
另外（审计之外）：装备属性 / 法宝成长率 / 五行 / 被动数值改成各值等概率；地藏金戒合成改用实际放入的材料数值（原版按名字重新查找并重掷了材料，是 bug）。
保留不改：#4 血海魔童目标保持随机（原版代码取第一个，但技能说明写的是“随机怪物”，按说明实现）；#5 五毒兽目标先过滤再抽（不浪费次数）；#9 刑天近身 skill1 兜底（影响很小）；#14 漫游帧率相关的休息时长（影响很小）。
