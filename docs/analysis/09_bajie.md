# 原作分析 09：猪八戒（Role3）——实现所需的全部数据

范围：只做单人 MODE1 的八戒。源码：`decomp/game/scripts/scripts/export/hero/Role3.as`（下文 `R3:行号`）、`base/BaseHero.as`（`BH:`）、`base/BaseMonster.as`（`BM:`）、`base/BaseRoleProperies.as`（`BRP:`）。
美术：**Pig9.swf**（`decomp/res/Pig9`，时间轴 `decomp/timeline/Pig9.json`，帧脚本 `decomp/res/Pig9/scripts/Pig8_fla/*.as`），不在 Role_v6。帧率 24fps，下文「帧」=原作帧，数值用法同 `tools/data/wukong.json`（px/帧，bake 时转 px/s）。
对悟空版的约定沿用 02/07 文档：`timers` = 普攻输入锁（帧），技能只看 `isAttacking()`，不看 timers（R3:179-235 等）。

---

## 1. 基础数值

| 项 | 八戒 | 悟空(参考) | 代码 |
|---|---|---|---|
| 走速 horizenSpeed | 6 | 6 | R3:25 |
| 跑速 / 重力 / 跳力 | 10 / 1.5 / -20（基类默认） | 同 | BaseObject.as:41-47 |
| 二段跳 | 有（jump1→jump2） | 同 | BH:905-921 |
| 变身(怒气) | 重力 3.75，速度/跳力 ×1.5 | 同 | BH:1011-1020 |
| HP(L) | **100 + 70(L-1)** | 80+50(L-1) | R3:546 |
| MP(L) | **35 + 15(L-1)** | 50+20(L-1) | R3:549 |
| 攻击 | **10 + 5(L-1)**（见下勘误） | 10+rand(0..4)+5(L-1) | BRP:269, R3:551-553 |
| 防御 | **4 + (L-1)**，无 15 级拐点 | 2+2(L-1)，L≥15 后 +5/级 | R3:555 |
| 经验表 / 满级 | 同悟空（levelexp 19 项，之后 5000+(L-19)*5000；L75） | | R3:556-563, BH:36 |
| 暴击/被动/回血回魔 | 通用（装备+被动技能） | | BRP |

**勘误（重要）**：`Role3.upGrade` 里的 `setPower(10+round(rand*10)+6*(L-1))`（R3:554）是死代码——`BRP.getPower()` 每次读取都重算 `setPower(baselowerpower + baseadd*(L-1))`（BRP:269），而 Role3 设的是 `baselowerpower=10+rand(0..1)`、`baseadd=5+rand/1000`（R3:551,553）。所以**八戒实际攻击 = 10 + 5(L-1) + 装备 addPower**，和悟空完全相同（Role1.as:576-578 同值）；没有 rand(0..10)、没有 6/级。`baseuppower` 无处使用。
→ `tools/data/bajie.json` 的 stats：`hp_base 100, hp_per_level 70, mp_base 35, mp_per_level 15, atk_base 10, atk_rand 0, atk_per_level 5, def_base 4, def_per_level 1, def_cap_level 999`（`def_per_level_after` 不用）。
示例：L1 HP100/MP35/攻10/防4；L20 HP1430/MP320/攻105/防23；L75 HP5178/MP1145/攻380/防78。

受击减伤差异（变身时）：伤害减半——`toBlood`（R3:663-680）、`setBlood`（R3:682）、伤害数字（R3:691）都 `/2`；且 BH:605 变身时**不吃击退**（悟空同样）。悟空版 `toBlood` 无此项。受击击退/防连控/出生无敌等其余逻辑通用（BH:401-511）。
防连控发光色：金色 0xFFCC33（BaseAddEffect.as:196-211，悟空红）。

---

## 2. 键位与技能总表（isstudyskill 下标 → 键 → 动作）

`sendSkill`：0=L 1=U 2=I 3=O 4=空格 5=H（BH:303-329）；方向键组合 `keyarray` 位序「下 攻 跳 上」。
HUD 提示 `r3skillbtn = [U, I, O, WJ, L]`（RoleInfo.as:71），即 skill1..5 = U/I/O/W+J/L。

| 学习序 i | 键 | 动作 | 学习价(魂) | MP | timers(普攻锁) | 伤害（×变身1.5 ×暴击2） | 类型 | 击退[vx,vy] | hitMax/interval | 代码 |
|---|---|---|---|---|---|---|---|---|---|---|
| — | J | hit1/hit2/hit3 普攻 | — | 0 | 13 | 1.0×攻 | physics | [0.5,-3] | 1 / 4 | R3:448-488, 26-43, 592 |
| 0 | U | **hit4 地刺** | 100 | 15 | 15 | 0.7×攻（每段） | magic | [8,-3] | 100 / 999 | R3:331-355, 44-49, 594 |
| 1 | I | **hit6 旋转防御** | 200 | 10 | 14 | 2.0×攻 | physics | [0,-2] | 99 / 5 | R3:378-398, 56-61, 598 |
| 2 | O | **hit5 冲撞** | 500 | 35 | 30 | 1.0×攻（每段） | magic | [15,-2] | 100 / 999 | R3:400-419, 50-55, 596 |
| 3 | W+J ("0101") | **hit8 聚怪** | 1000 | 20 | 40 | 0（无伤害） | magic | [2,-22]（无判定框，实际不生效） | 100 / 2 | R3:210-234, 74-79, 604 |
| 4 | L | **hit7-1 反伤架势 / hit7-2 飞刺** | 2000 | 30 + 30 | 200 / 30 | hit7-1 反射；hit7-2 0.5×攻+3%当前HP | magic | [0,-2] | 1 / 4 | R3:255-288, 62-73, 599-602 |

价格是 `SkillControl.buy` 通用表（100/200/500/1000/2000，SkillControl.as:125-173），被动技能与悟空完全相同（07 文档 §1.2，n×5000 魂，hp/mp/crit/回血/回魔）。商店选人页 `BuySkill.player3` = 八戒（BuySkill.as:68-76,127-130），`instrmc` 跳帧标签 `"八戒"`（SkillControl.as:43）。HUD 技能图标帧 = i+12（RoleInfo.as:129-140），头像 `head.gotoAndStop("八戒")`（RoleInfo.as:93）。
未学/MP 不足：U/I/O/L 直接无反应；W+J MP 不足退化为普攻（R3:228-233）；未学 W+J：`return`（R3:211-214）。
伤害类型为 magic 的受怪物魔抗 `dmg*(1-mDef)`，physics 减防（BM:824-860，07 文档 §公式）。

### 2.1 普攻（hit1-hit3，3 段）
- 地面且非跑动：`timers<=0` 才响应；与上次按键间隔 >1500ms 重置为 hit1，否则 hitNum++，>3 回 1（R3:458-465）；**每段 timers 固定 13**（悟空 8/15/18）。
- 连段动画 12 帧/段，音效 `Role3_hit{n}`（R3:466）。可从 hit1-5 任一普攻/技能状态再接普攻（`isNormalHit` 含 hit1-5，R3:495-498）。
- 空中普攻：固定 hit3，timers=15，hitNum=0（R3:477-485）。
- 跑动中攻击：**没有**冲刺技，`doubleCount=0` 后当普攻打（R3:471-475；`runAttack` 私有方法从未被调用）。
- 地面 hit1/hit2/hit3(jumpCount==0)/hit4/hit7-1/hit7-2 锁水平移动（R3:707-710）；hit5 允许移动（速度由帧脚本给，R3:717-719）；hit6/hit8 不在锁列表（`setSpeed` 仍写走速，但 `move()` 只在 walk/run/空中/受击/CanMoveWhenAttack 时才应用 x，BaseObject.as:431，所以地面上只有双击跑状态才会滑动）。
- 取消：`isAttackingButCanAttack`（hit1-4 进度≥70% 或 hit7-1 帧>40，R3:702-705）**只给 L 键用**（R3:261）；八戒没有「普攻取消成 hit8」（W+J 要求 `!isAttacking`）。

### 2.2 动作详表（Pig9 `export.hero.Role3`=symbol 357，130 帧；`body` 子 MC；stick=攻击框，坐标为英雄本地、素材朝左 x<0 为前）
`rect` = `tools/rig/extract_rig.js` 逐帧模拟出的 [x,y,w,h]（可直接取 rig.json 的 `hit`）。

| 动作 | body 类/帧数 | 帧脚本与判定 |
|---|---|---|
| hit1 | 元件5_20 / 12 | f3-12 rect [-93.6,12.4,81.5,30]；f12 回 wait/walk/jump1 |
| hit2 | 元件8_24 / 12 | f5-6 [-76.4,-69.8,70,100.2]；f7-12 [-96.1,-42.2,70,100.2]；f12 结束 |
| hit3 | 元件11_27 / 12 | f1 [-146.6,-49.3,184.1,128.7]，f4..f7 x 依次 -159.5/-172.4/-185.2/-198.1，f8 回 -146.6（大范围横扫）；f12 结束（空中也用） |
| **hit4** 地刺 | 元件21_39 / 35 | stick=`地刺_41`(31帧)：f3 起 [-94.9,25.1,17.9,33.5]，之后逐帧向前伸长（前缘 x：f3 -122.6 → f5 -198.9 → f7 -275 → f9 -351 → f11 -428 → f19 -522 → f27 -620，高 ≈160，y -24..+139，合并宽最大 ≈880）；**f11 和 f19 `newAttackId`**（`地刺_41` 帧9/17 脚本）→ 每个敌人最多吃 3 次；f35 结束。地面限定（R3:333）。 |
| **hit5** 冲撞 | 元件22_45 / 36 | f5：`setYourFather(25)` + vx=±15；f10/16/22/26：vx 再设 ±15 并 `newAttackId`（共 5 段）；f30 `setStatic`；f36 结束。stick f5-29 固定 [-77.8,-61.7,150,150]。变身时速度**不**×1.5（脚本写死 15）。可在空中放。 |
| **hit6** 旋转 | 元件23_47 / 14 | stick f1-14 随动画绕身一圈：f1 [-60.7,-18,23.7,28.5]、f3 [-96.7,-13.6,47.9,57.4]、f5 [-74.5,-6.8,54,64.8]、f7 [-29.8,-11.2,70.1,84.2]、f9 [36.9,-12.1,53.9,64.8]、f11 [63.8,-21.8,53.1,63.7]、f13 [45.3,-21.7,23.7,28.5]；无 newAttackId → 每敌 1 次；f14 结束。可在空中。 |
| **hit7-1** 架势 | 元件30_55 / 271 | 无 stick；f271 才回 wait（约 11.3s）。 |
| **hit7-2** | 元件34_57 / 10 | f10：`createStab()`（见 §3）后回 wait。 |
| **hit8** | 元件1_61 / 15 | f15：`doHit8()` 后回 wait。 |
| wait 85 / walk 16 / run 8 / jump1 1 / jump2 10 / jump3 1 / hurt 8 | | jump2 f10 → jump3；hurt f8 `setStatic`+回 wait（硬直 8 帧，悟空 15 帧）；wait/walk/run/jump1/jump3 循环 |
| colipse（受击框） | | [-22.25,-41.8,45,90]（同悟空） |

时长（秒）：hit1-3 0.5；hit4 1.46；hit5 1.5；hit6 0.58；hit7-1 11.3（可 L 打断）；hit7-2 0.42；hit8 0.62。

---

## 3. 特殊机制（各技能行为）

**hit4 地刺（U）**：见 §2.2。`magic 0.7×攻`，无位移，音效 `Role3_hit4` 循环 3 次（SoundManager.as:210-212）。

**hit5 冲撞（O）**：前冲约 24 帧×15px≈360px，期间无敌 25 帧（f5→f30），5 次独立命中，每次击退 [15,-2]（方向取自英雄朝向，BaseObject.as:588-608）；怪物被 `ssc/jcdp` 眩晕判定包含此技能（物理或 hit6 的 magic，BM:520-534）。

**hit6 旋转防御（I）**：期间被「物理」攻击且攻击者与自己**面对面**（`transform.a` 乘积<0）时，基础伤害置 0（`canMissAttack`，R3:430-446，BH:441-444），再过 `toBlood` 最小为 **1**；但**照常进入 hurt 硬直并被击退**（beAttackDoing 正常路径，hit6 被打断）；magic 不挡。自己造成 2.0×攻 physics。

**hit7-1 反伤架势（L，首次）**：30 MP，timers=200。期间
 - `beAttackDoing` 被重写：不进 hurt、不重播、不计防连控，只 `resetGraity`+受击特效（R3:151-168），即**霸体**；但**仍然扣血**（beAttack 的伤害照算，BH:441-473）。
 - `checkAttackBack` 被重写：对攻击者造成 `攻击者.getRealPower(其招式)` 的反射伤害，走 `getHurtByPig8` = **×2、无视防御与魔抗、无击退/无眩晕**（R3:136-149，BM:629-634；`MonsterIsBeat` 事件给怒气，反射伤害也会涨怒）。弹幕/子弹同样（BH:576）。
 - 地面锁移动（R3:709）；Monster62 的粘人技对 hit7-1 免疫（`res/8/.../Monster62.as:85,129`）。
 - 动画 frame>40 后再按 L → 转 hit7-2（再花 30 MP，timers=30，`SoundManager Role3_hit7-2`）；不按则 271 帧后结束。MP 不足时第二次按 L 无反应。

**hit7-2 飞刺（L，第二次）**：f10 `createStab()`（R3:290-329）：
 - 数量 10（变身 20），均布在英雄周围半径 100 的圆上（角度 360/n·i，0°=正上方，位置 `(x+sin·100, y-cos·100)`），旋转 `i·360/n`。
 - 目标 = `monsterArray` 里**最后一个**非「Monster47 无敌态 / Monster52」的怪的当前位置快照（无怪=null）。
 - 子弹类 `StabBullet("Role3Bullet_hit7", target, turnTime=1, source)`（`export/bullet/StabBullet.as`，Pig9 symbol 7，与 Monster35 飞刺同一个类，05 文档 Monster35 hit3 已有实现可复用）：alpha 0→1 且旋转到指向目标共 1s（Tween），然后 `rush`：沿单位向量以 `1 + addSpeed` px/帧前进，`addSpeed:int += count*0.05`（int 截断：count 0-19 加 0，20-39 加 1，40-59 加 2…，即逐渐加速），count>240 或 |y|>1000 销毁；穿过目标不停。无目标时 vx=0，vy 每帧 +0.5 下落。
 - 伤害 hit7-2：`0.5×攻 + 0.03×英雄当前HP`（R3:602），magic，kb [0,-2]，hitMax 1（每根只命中一个敌人一次）。

**hit8 聚怪（W+J）**：f15 `doHit8()`（R3:357-376）：把所有怪 1s Tween（TweenMax 默认缓动）拉到 `(英雄x, 英雄y-100)`；排除 Monster70/78/60/71/53/54/55/52/57、攻击中的 Monster72、处于 isYourFather 的怪。**不造成伤害**（R3:604 返回 0），也没有 stick。可在空中放，不消耗二段跳（悟空会）。

**怒气变身（空格）**：`showSkillKongGe`（R3:421-428）与悟空相同，满 100 怒气→`turnToGXP`，`WsEffect.Role3Mc` 显示八戒无双（Role_v6 symbol 34 `八戒无双_182`，WsEffect 里 Role1Mc/Role2Mc 隐藏，BH:850-870）。变身差异：伤害×1.5（getRealPower，R3:572-575）、受伤/伤害数字 /2、不吃击退、飞刺 20 根；没有悟空的 hit6 冲刺加速项（八戒无此技）。残影、怒气消耗/衰减（每 4 帧 -1）通用。

**无敌**：出生 48 帧、防连控（1s 内 5 击→48 帧）通用；仅 hit5 额外 25 帧无敌（f5）。无其它无敌帧。

**死亡**：音效 `Role3_dead`（BRP:156-159），余下通用。

---

## 4. 武器/防具/时装/翅膀（userType = "八戒"）

`MyEquipObj.user == "八戒"` 才可穿（PackThings.as:188）；`getEquipNum`：`zbfj`（衣服）= 时装 showid>1 ? 时装 : 衣服 showid，`zbwq`/`zbcb` 同理，默认全 1（User.as:69-102）。`protectedEquipObject.curClothId=8`（R3:128）会被 `setShowEquip` 覆盖，无意义。八戒新档无初始装备。
数据已在 `tools/data/equipment.json`（`user:"八戒"` 共 18 件），rig 变体 = `show`：

| 类型 | show → id 名称 |
|---|---|
| 武器 weapon (6 变体) | 1 ptsf 普通的石斧；2 gtb 古藤棒；3 lcld 罗刹镰刀；4 **ssc 三生锤**（史诗，atk70-92，deephit 5%）；5 **jcdp 九齿钉耙**（传说，atk150，deephit 5%）；6 syc 殇月锤（传说，100 个月饼 xyb 兑换） |
| 衣服 cloth (6) | 2 ptmlf 普通的墨兰服；3 lcgy 罗刹鬼衣；4 bszj 白霜重甲；5 **jgj 金刚甲**（史诗，HP800-940/MP185-251/防14-18/魔抗0.1，6-1 红孩儿 Monster46 掉落，05 文档）；6 tpzy 天蓬战衣（传说，boss_loot） |
| 时装 fashion (rig 的 cloth 变体 7-12) | 7 bjmrz 黄头装；8 bjwdg 西装；9 bjbsz 红头装(+掉率)；10 bjzyf 状元服；11 jbjwdg 绝·西装；12 jbjzyf 绝·状元服 |
| 翅膀 wing (3 变体，无 user 限制) | 1 无；2 xtzy 刑天之翼；3 ttzy 天庭之翼（`getWingId`：zbcb==3 → 帧 21，BH:1071-1087） |

**ssc/jcdp 眩晕**：八戒持这两把且物理命中（或 hit6 的 magic）时，以 `deephit`（装备+强化 dhit）概率给怪 `stun` 48 帧（BM:518-534 `addStunEffect`）。非这两把武器无此效果；悟空无。装备数据里 `deephit` 字段必须保留。
装备商店/合成/强化：同悟空（07 文档），八戒时装与悟空时装同价；ssc 合成=qssp+jssp+lssp（1000 魂）。

---

## 5. 美术/rig 需求

库：`Pig9`（Pig9.swf）。角色：`export.hero.Role3`=symbol 357（`Pig8` symbol 358 只是 Embed 壳，不用）。已验证 `node tools/rig/extract_rig.js Pig9 export.hero.Role3 bajie out.json` 可直接出 rig：fps 24，241 贴图，16 个动作，9 个装备槽，只有 1 条无害的 `元件4copy_42 f16: stop(); stop();` unknown script。

加入 `tools/rig/specs_stage1.txt`（或新 specs）并跑 `batch.sh`：
```
Pig9 export.hero.Role3 bajie
Pig9 Role3Bullet_hit7 bajie_stab
```
动作标签（Role3 帧标签）：`walk run hit1 hit2 hit3 wait jump1 jump2 jump3 hurt hit4 hit5 hit6 hit7-1 hit7-2 hit8`（**无 dead 标签**，死亡走通用「隐藏+墓碑」；悟空的 hit7/hit9/hit10 没有）。Godot 动作名里 `-` 保持与 rig 一致（建议动作名 `hit7_1` 在 json 里统一）。
extract_rig 事件（rig.json `events`，帧 0 起）：
 `hit1-3: [11 finished]`；`jump2: [9 finished]`；`hurt: [7 stop_move, 7 finished]`；
 `hit4: [10 new_hit, 18 new_hit, 34 finished]`；
 `hit5: [4 set_vx_forward 360, 4 call set_your_father 25, 9/15/21/25 set_vx_forward 360 (+new_hit 在 9/15/21/25 同帧), 29 stop_move, 35 finished]`；
 `hit6: [13 finished]`；`hit7-1: [270 finished]`；`hit7-2: [9 call create_stab, 9 finished]`；`hit8: [14 call do_hit8, 14 finished]`。
 （`set_vx_forward 360` = 15px/帧×24；`call` 名 `set_your_father`/`create_stab`/`do_hit8` 是 events.js 从脚本里认出来的，需要在 `Hero._on_rig_event` 的 `match args[0]` 补上分支，`events.js` 如未识别 `setYourFather(25)` 需确认。）
装备槽（slot，均按 `getCurClothId/getCurWeaponId/getWingId` 选帧，extract_rig 已识别）：
 - cloth ×7（slot id 22,40,49,61,69,77,86：身体各部件），12 变体（1 无甲…12，见 §4）；
 - weapon ×1（slot 30），6 变体；
 - wing ×1（slot 14，`元件4sdsdaaa_4` 39 帧），变体 1/2/3。
 `Rig.set_equip("cloth"/"weapon"/"wing", show)`，`GameState.appearance()` 需按角色返回 8 戒的 show。
其它子件：`levelupmc`(Pig8_fla.sj1_17，28 帧升级特效，已被 extract 为 marker，与悟空一致处理)；`Role3Bullet_hit7`（飞刺，symbol 7，shape 1 为 7.35×28.7 判定条，shape 6 为贴图，0.73 缩放，朝向由旋转决定）。
共用（Role_v6/Common）：受击特效 `HeroBeHurt`、怪受击 `MonsterBeHurt1/2`、WsEffect 八戒无双 `Role3Mc`（Role_v6 symbol 34）、背包头像 `OtherMat_fla.八戒_31`（OtherMat_v10 symbol 360，类比 `bag_wukong`）、HUD 头像帧 "八戒"、选人界面 btn3。
音效（Music.swf，已有 SoundManager 条目）：`Role3_hit1/2/3/4(循环3次)/5/6/7-1/7-2/8, Role3_jump, Role3_beAttack, Role3_dead`（SoundManager.as:56-78,162-226）。命中音 `BeattackByRole1/2` 对八戒**没有**（BM:491-499 只处理 Role1/Role2），即八戒命中怪无专属命中音。
注：`BaseMonster` 中唯一对 Role3 的特判是眩晕（BM:520）；`BaseAddEffect` 仅发光色；`Monster62` 对 hit7-1 免疫。

---

## 6. 重制中需要覆盖/参数化的 Hero 部分（相对 `game/src/actors/hero.gd`）

1. **数据**：新建 `tools/data/bajie.json` → `data/bajie.tres`；`HeroData.rig="bajie"`；`GameState.HERO_DATA/CHARACTER` 改为按所选角色（"悟空"/"八戒"）取值，存档增加 `role`（原 `User.roleid` 1/2/3，User.as:25,364,408）。`learn_active = ["hit4","hit6","hit5","hit8","hit7"]`、`active_cost [100,200,500,1000,2000]`、被动同悟空。
2. **COMBO** 改 3 段（`hit1..hit3`），`combo_cooldowns [13,13,13]`，`air_cooldown 15`，`combo_reset 1.5s`，空中固定 hit3。去掉 `CANCEL_INTO_HIT8` 与跑动攻击（hit6 dash）分支；取消窗口只给 L（hit1-4 进度≥0.7 或 hit7-1 帧>40）。
3. **输入映射**（`_read_input`）：U→hit4、I→hit6、O→hit5、W+J→hit8（`!attacking`）、L→hit7（状态机：`hit7_1` 期间且已播过 40 帧再按 L → hit7_2）；U 地面限定；技能不检查 cooldown，只检查「不在攻击/受击」；`SCRIPTED_MOTION=[hit5]`（速度由事件给）。
4. **hit5**：事件里 `set_vx_forward`、`set_your_father 25`→`invincible`、`new_hit`；允许空中；移动 `CanMoveWhenAttack`。
5. **hit6**：加 `defending` 判定：`take_hit` 时若当前 hit6 且攻击为 physics 且攻击者面向我 → 伤害按 0 计后取最小 1（原作 toBlood 保底 1）；其余流程（硬直、击退、防连控计数）照常，所以它不是无敌格挡。
6. **hit7-1 霸体+反伤**：`take_hit` 内：不进 hurt，不触发防连控计数，仍扣血；对攻击者（`Hit.source`）造成 `2 × source.outgoing_raw` 的 TRUE 伤害（无视防御/魔抗/击退），并走 `add_rage`；怪物粘人技免疫需在 brain_62 判断 `hero.attack_action == &"hit7_1"`。
7. **hit7-2 飞刺**：新建 `StabProjectile`（可复用 brain_35 的 Stab 实现），参数 count 10/20、半径 100、转向 1s、加速表见 §3、伤害 `0.5×atk + 0.03×hp`，magic，hitMax 1。
8. **hit8**：只做拉怪（1s tween 到 `(x, y-100)`，排除表见 §3），无伤害、无判定。
9. **属性**：`outgoing_damage` 里变身 ×1.5（通用）；`take_hit`：变身时 `dmg/=2`（物理在减防后除，魔法在乘魔抗后除，原作 toBlood 减防→/2；setBlood 直接 /2）、变身时跳过击退（悟空同）。
10. **眩晕**：命中怪时若持 `ssc/jcdp` 且（物理，或 hit6 的 magic）按 `deephit` 概率给怪 stun 48 帧（2s）；`Monster` 需要 stun 状态（若已有 `fx_stun` 可复用）。
11. **hurt 硬直** 8 帧（rig 自带），防连控发光改金色 0xFFCC33。
12. 装备：`wearable_by(character)` 已支持；`appearance()` 返回按角色的 show；`TEST_GEAR` 增加八戒装备。

---

## 7. 解锁与选人/新游戏流程（原作）

- 状态位：`Config.openPig:Boolean`（Config.as:104；`initData` 置 false，:256）。**账号级**，不在存档槽里：`MemoryClass.setOtherStorage()` 把 `{openPig}` 存到服务器 key "other"（`saveData("other", ..., 7)`，MemoryClass.as:337-342），读取 `storageValue(7)` 设回 `gc.openPig`（:296-300）。
- **解锁点**：6-1 红孩儿 `Monster46.destroy()`（`decomp/res/6/scripts/export/monster/Monster46.as:227-236`）：`isBoss && !gc.openPig && protectedParamsObject.Hp <= 0` → `gc.openPig = true; gc.memory.setOtherStorage()`。即**第一次击杀红孩儿**即永久解锁（不论用哪个角色/难度）。
- 流程：主菜单 `GameMenu.newGameClick`（GameMenu.as:178-210）→ `showSelectNum`（单人/双人，`selectNum` 设 `playNum=1/2`，`gameMode=MODE1/2`，:225-248）→ `doAfterChangeOut` 新游戏发 `StartSelectRole`（:370-380）→ `GMain.selectRole` → 场景 `SelectRole`（GMain.as:264,503-511）：
  - `btn1`=悟空、`btn2`=唐僧、`btn3`=八戒，`btn3` 默认 disabled + `lockmc` 锁图标；`openPig==true`（或调试模式 `!isHideDebug`）才启用并隐藏锁（SelectRole.as:33-58）。
  - 点击：`w = 按钮名第4字符`(1/2/3)，`gameMode=MODE1`；`w==3` 时若 `Pig8` 类未加载先 `loader.loadByName("Pig9")` 异步载入再继续（:90-121）；`newRole(w)`：`player1.roleid=w; player2.roleid=0`，`gc.newRole()` 用 `AUtils.getNewObj("export.hero.Role"+roleid)` 实例化（Config.as:340-355，:166-176）→ `SelectOver` → 开场漫画 / 关卡地图（GMain.as:458-470）。
  - 读档：`User.roleid` 随存档保存，读到 3 时同样先加载 Pig9（MemoryClass.as:197-205）。`BuySkill`/`StrengthEquip` 按 `roleName=="八戒"` 显示对应人物页。
- 重制建议：`GameState.unlocked_bajie`（全局 profile，不随存档槽）；`Monster46`（brain 红孩儿）死亡时置位并立即写盘；选人界面在「新游戏」后增加（悟空 / 八戒；唐僧不做，保持锁灰），八戒按钮未解锁则灰显；`new_game(role)` 加载 `data/<role>.tres`，存档存 `role`；无需异步加载 Pig9（rig 直接在 `assets/rigs/bajie`）。

---

## 8. 未决/风险

- hit6 受击硬直、hit7-1 被「怪物弹幕」类攻击的反射（`param1.getRealPower(param2)` 对子弹来源是怪物本体，读 `param1.curAction`）细节需和 `Hit` 结构对齐；反射伤害按 `source.getRealPower(lastHit)` 取招式伤害的最终值（已含暴击，若怪物有暴击则同样）。
- `attackBackInfoDict[hit8]` / `hit6.attackInterval=5` 对英雄近战没有实际作用（近战只看帧脚本 `newAttackId`）；只有子弹类（hit7-2）使用 hitMax。
- 八戒没有「命中音」条目（只有怪的受击音由 Role1/2 决定），可沿用 `BeattackByRole1` 作替代。
