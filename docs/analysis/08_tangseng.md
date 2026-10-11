# 原作分析 08：唐僧（export.hero.Role2 + Role2Shadow）实现所需的全部数据

目的：把唐僧做成第二个可玩角色，与悟空（Role1，见 02 / 07 文档、`tools/data/wukong.json`、`game/src/actors/hero.gd`）并列。
单位：帧 = 1/24 秒（Role_v6 fps=24），速度 px/帧。源码根：`decomp/game/scripts/scripts/`（下称 `S/`）；时间轴 `decomp/timeline/Role_v6.json`；
帧脚本 `decomp/res/Role_v6/scripts/Role_fla/*.as`。已用 `tools/rig/extract_rig.js Role_v6 export.hero.Role2` 试跑过，结论见 §9。

**一句话概括**：唐僧**没有近战判定框**（身体里没有 `stick`），全部伤害来自子弹/特效（`EnemyMoveBullet` / `SpecialEffectBullet`），
普攻不是连招而是「单发光弹，冷却 18 帧」，长按攻击蓄力放大招弹；5 个主动技是 蓄力弹 / 冰柱 / 分身 / 群体回血 / 落柱。

---

## 1. 与悟空相同、可直接复用的部分
| 项 | 值 | 出处 |
|---|---|---|
| 走速 / 跑速 | 6 / 10（`horizenSpeed=6`，`horizenRunSpeed` 沿用基类 10）；双击方向键跑（<500ms） | S/export/hero/Role2.as:30；S/base/BaseObject.as:41-47 |
| 重力 / 跳力 / 跳跃次数 | 1.5 / -20 / 2 段（jump1、jump2 翻滚、jump3 下落） | BaseObject.as:45-47；BaseHero.as:905-921 |
| 变身（空格，怒气满 100）速度 ×1.5、跳力 ×1.5、重力 3.75、顿帧 1000ms、每 4 帧 -1 怒气 + 残影 | 同悟空 | BaseHero.as:1011-1020, 729-757 |
| 出生无敌 48 帧、5 连击防锁（father buff）、下+跳 穿单向板 | 同悟空 | BaseHero.as:90-108 |
| 经验表 `levelexp`、最高 75 级、怒气获得/衰减、MP/HP 回复、暴击 ×2、闪避 | 同悟空 | BaseHero / BaseRoleProperies |
| 被动技能（生命 / 魔法 / 暴击 / 回血 / 回魔，n×5000 灵魂，同公式） | 同悟空，见 07 §1.2 | BaseRoleProperies.as:538-568 |
| 死亡：隐藏主角 + 墓碑；音效换成 `Role2_dead` | | BaseRoleProperies.as:152-154 |
| 碰撞盒 colipse | 45×90（`[-22.1,-45.1,45,90]`，与悟空同） | Role_v6 sprite 1217 `colipse` |

---

## 2. 每级属性（Role2.upGrade，S/export/hero/Role2.as:545-578）
L = 等级（1..75）。**注意与悟空公式不同**（悟空 HP 80+50/级，MP 50+20/级）。

| 属性 | 公式 | L=1 | L=20 | L=75 |
|---|---|---|---|---|
| HP 上限 | `50 + 20(L-1)` | 50 | 430 | 1510 |
| MP 上限 | `100 + 40(L-1)` | 100 | 860 | 3060 |
| 攻击 | `12 + 8(L-1)`（见下注） | 12 | 164 | 604 |
| 防御 | `L - 1`（**无 L≥15 的分段**，线性） | 0 | 19 | 74 |
| 经验 | `levelexp[L-1]`(L≤19)，之后 `5000+(L-19)*5000`（同悟空） | | | |
- 装备 / 被动在其上累加（同悟空）。联机 MODE3 的 ×500 血量忽略。
- **攻击实际取值**：`upGrade` 里 `setPower(12+8(L-1))` 会被 `getPower()` 覆盖（BaseRoleProperies.as:267-280：每次取值 `setPower(int(baselowerpower + baseadd*(L-1)))`，
  `baselowerpower=12+rand`、`baseadd=8+rand/1000` 在升级时定下，再 `+Math.random()`，最后 int 截断）⇒ 实际 ≈ `12+8(L-1)+装备攻击`，噪声仅 0~1。
  （同理 `wukong.json` 的 `atk_rand=4` 并非实际噪声，悟空实际也只有 0~1 的随机；如要对齐，唐僧 `atk_rand` 取 1 即可。）
- HeroData 映射：`hp_base=50, hp_per_level=20, mp_base=100, mp_per_level=40, atk_base=12, atk_rand=1, atk_per_level=8, def_base=0, def_per_level=1, def_cap_level=999`（`HeroData.defense()` 分段不要触发）。
- 回血技能的治疗量用的是**含装备的最大 MP**（`getSMMP()/8+8`），所以 MP 装备(权杖/袈裟)直接加治疗。

---

## 3. 按键与输入规则（Role2.myKeyDown，Role2.as:228-281；RoleInfo.as:69）
`keyarray` 位序 = 下、攻、跳、上。HUD 提示文字 `r2skillbtn = ["长按J","U","I","O","L",…]`。

| 键 | 条件 | 行为 |
|---|---|---|
| 跳 K（"0010"） | 不在攻击/受击中 | 跳；**攻击中不可跳** |
| 攻 J（"0100"/"1100"） | 不在攻击/受击中（悟空是只挡受击） | `normalHit()`：见 §4.1 |
| 下+跳（"1010"） | 同上 | 下穿单向板（getFallDown） |
| 攻+上（"0101"）、攻+跳（"0110"） | — | **没有任何响应**（唐僧没有升龙斩、跑动攻击） |
| 上 W（"0001"） | | 进传送门 / 关卡交互（同悟空） |
| L（sendSkill 0） | 学会 isstudyskill[4] | hit4 落柱，见 §4.5 |
| U（sendSkill 1） | 学会 isstudyskill[1] | hit3 冰柱，§4.3 |
| I（sendSkill 2） | 学会 isstudyskill[2] | 分身，§5 |
| O（sendSkill 3） | 学会 isstudyskill[3] | hit5 群体回血，§4.4 |
| 空格 | 怒气满 | 变身（BaseHero.turnToGXP） |
| H | 法宝 | 同悟空，但**天煞古剑伤害不同**（§8） |
- 技能键在 KEY_DOWN 时触发一次（KeyBoardControl.as:60-72）。Godot 里 **需要新增 `skill_l` 动作**：键盘 L，手柄 LT（controls.gd 注释写明 LT 未使用）。
- 受击（hurt）会打断一切；没有任何技能带无敌帧（悟空 hit7/hit10 才有）。

---

## 4. 攻击 / 技能动作

### 4.0 总表（伤害 = `getRealPower(action)` = 基础 ×(变身 1.5)×(暴击 2)，S/export/hero/Role2.as:580-612）
`P` = 当前攻击力。`attackBackInfoDict` 在 Role2.as:31-61。击退为 [水平, 垂直] px/帧，方向由子弹飞行方向（EnemyMoveBullet）或子弹相对目标的位置（SpecialEffectBullet）决定（BaseObject.as:561-588）。
| 动作 | 键 / 学习序号 | MP | 实体 | 伤害 | 类型 | 击退 | 最大命中 / 重复间隔 |
|---|---|---|---|---|---|---|---|
| hit1 光弹 | J | 0 | Role2Bullet1 | `1.0×P` | physics（减防御，至少 1） | [4,-7] | 1 / 4 帧；**溅射 attackRange=60** |
| hit2 蓄力弹 | 长按 J，序 0（100 灵魂） | 20（放出时扣） | Role2Bullet2 | `P/5`（每次命中） | magic | [20,-5] | 200（穿透）/ 每 4 帧可重复命中 |
| hit3 冰柱 | U，序 1（200） | 40 | Role2Bullet3 | `0.8×P`（每轮） | magic | [6,-7] | 200 / 靠 newAttackId 分轮（999 不自动重复） |
| 分身 | I，序 2（500） | 30 | Role2Shadow | — | — | — | — |
| hit5 回血 | O，序 3（1000） | 60 | cureRoleMc | 治疗 `(SMMP/8+8)`×变身×暴击 | — | — | — |
| hit4 / hit4-1 落柱 | L，序 4（2000） | 100 | hit4FallDown | hit4 本身无伤害；hit4-1 = `8×P` | magic | [25,-5] | 200 / 999 |
- 学习价（SkillControl.as:126-175，所有角色通用）：序 0..4 = 100 / 200 / 500 / 1000 / 2000 灵魂；一次性、无等级要求；调试模式默认全会。
- 暴击：在 `getRealPower` 内每次取值掷骰（`Math.random()<crit`），所以**回血也会暴击翻倍**（Role2.as:590, 613）。
- `isAttacking()` = hit1~hit5（Role2.as:682）；技能键在攻击/受击中无效（L 的二段除外）。
- 敌人受击音 `BeattackByRole2`；唐僧受击音 `Role2_beAttack`；受击/命中特效 HeroBeHurt / MonsterBeHurt 被**色相旋转 160°**（`adjustColor(0,0,0,160)`：BaseHero.as:639-643、BaseMonster.as:618-620）。

### 4.1 hit1 普攻光弹（normalHit，Role2.as:513-526；body 攻击一_43，11 帧）
- `timers<=0` 才响应；响应时 `timers=18`（0.75 秒冷却，`myKeyDown` 每帧 -1，BaseHero.as:960-966），`hitNum=1`，`curAction=lastHit="hit1"`，音效 `Role2_hit1`。**无连招，无 hitNum 递增，无 1000ms 重置**。
- 帧：f2 蓄力检测（见 4.2）；**f7 发射** `doHit1()`（按下后 6 帧=0.25s）；f11 结束（空中→jump1，否则→walk）。
- 子弹（Role2.as:116-128）：`EnemyMoveBullet("Role2Bullet1")`，生成在**英雄原点** (x,y)，`speed 8`（朝向）、`distance 300`、`setScale(0.6,1)`（横向 ×0.6）、`setAction("hit1")`；
  飞满 300px（≈37.5 帧）消失或命中 1 个怪就消失（hitMaxCount=1），命中后 60px 内的其他怪也会受同等伤害（BaseBullet.as `attackRange` 段）。
- 地面：施放期间不能移动（`isCannotMoveWhenAttackOnFloor` 仅 jumpCount==0 时，Role2.as:672-675）；空中可以施放且可移动。
- 美术：`Role2Bullet1`(sym 781)=单帧，贴图 111.6×28.6（sym 780）+ 命中框 stick0 100×30；横向缩放 0.6。

### 4.2 hit2 蓄力弹（长按 J）
- 触发：hit1 的**第 2 帧**脚本（攻击一_43 f2）：`isstudyskill[0]==1`（`judgexq()`）且 `MP>=20` 且 J 仍按住（`keyarray[1]==1`）⇒ `curAction="hit2"; gotoAndStop("hit2")`。
- hit2 body（攻击二_76，9 帧）：f1 若 `MP>=20` 则 `stop()` 停住蓄力；**松开 J**（`__keyBoardUp`，Role2.as:533-543）→ `body.play()`；f2 发射；f9 结束。
- 蓄力计数 `hit2Count`（Role2.as:19-21, 161-176）：`curAction=="hit2"` 且 body 在第 1 帧时每帧 +1，上限 `hit2NeedCount=30`（1.25 秒）；离开 hit2 清零。头顶进度条 `ExceedPower(width, 9, 30)`（my/ExceedPower.as）：红框 1px、绿色填充（`0x00FF00`），满时在 `0x112233`/`0xAABBCC` 间每帧交替闪烁；0→>0 时 0.5 秒淡入，回 0 淡出；随朝向镜像；位置 `x - width/2, y - height/2 - 30`。
- 松手时（f2）：`hit2Count>=30` 且 `MP>=20` → 音效 `Role2_hit2`，`doHit2()`，扣 20 MP；**否则**（未蓄满或 MP 不足）退化为一发 hit1（`lastHit="hit1"`，不扣 MP，伤害/击退/溅射按 hit1）。
- 子弹（Role2.as:130-142）：`Role2Bullet2`，`speed 15`、`distance 600`（40 帧）、`setScale(0.8,1)`、`setAction("hit2")`，穿透。贴图 132×59（sym 776）+ stick0 90×40。
- 蓄力期间地面不可移动（hit2 在 isCannotMoveWhenAttackOnFloor），空中可移动。

### 4.3 hit3 冰柱（U，Role2.as:372-393；body 元件6_46，48 帧）
- 条件：已学序 1、非攻击/受击、`MP>=40`（**空中也能放**）。`lastHit=curAction="hit3"`，扣 40 MP；若有分身，分身同时 `doHit3()` 并**消耗分身引用**（`this.shadow=null`）。
- `isCannotMoveWhenAttack` 含 hit3/hit5（Role2.as:677-680）：施放期间 `speed.x=speed.y=0`，**空中悬停不受重力**，48 帧。
- **f15 生成**特效（`SpecialAttack`，Role2.as:497-511）：音效 `Role2_hit3`，`SpecialEffectBullet("Role2Bullet3")` 在英雄原点，朝向同英雄；变身时 `setScale(1.8,1.8)`，而 SpecialEffectBullet.setScale 在 x 缩放>1 时再乘 0.7（S/export/bullet/SpecialEffectBullet.as:34-41）⇒ 实际 **x×1.26、y×1.8**。
- 子弹动画（Role2Bullet3，46 帧）：4 根冰柱（sym 794，各 30 帧）出现在局部 x=-81.4（f1）、+65.4（f6）、-157.85（f11）、+149.45（f21）（素材朝左，x<0 为前方；随朝向镜像），覆盖约 310px 宽；每帧 `shake(15)` 镜头震动（f1/6/11/16/21）。
- **伤害轮次**：`newAttackId()` 在 f6/f11/f16/f21 ⇒ 共 **5 轮**（f1 起一轮 + 4 轮）；**变身时 f26/f31 也重置 ⇒ 7 轮**。每轮每个怪 1 次，`0.8×P`，击退 [6,-7] 把怪推离冰柱中心（子弹 x 在怪右侧→推向左）。f46 销毁。
- 同一动作的 `getRealPower("hit3")` 在子弹生成时取（每轮 `crit` 重掷由怪侧每次调用 getRealPower 决定）。

### 4.4 hit5 群体回血（O，Role2.as:449-473、288-322、484-495；body 加血技能_62，34 帧）
- 条件：已学序 3、非攻击/受击、`MP>=60`。音效 `Role2_hit5`，`lastHit=curAction="hit5"`，扣 60 MP；同时 `doHit5Effect()`：在 `(x, y-60)` 生成 `cureRoleMc`（sym 768→767，34 帧），变身时放大 ×1.6。若有分身：分身 `doHit5()`（也播放一次 `Role2_hit5`）并清空引用。
- 动作 34 帧，期间不动、悬停（isCannotMoveWhenAttack）；变身时**不出残影**（BaseHero.as:740）。
- **治疗在特效第 34 帧**（~1.4 秒后）：`cureRoleMc` 的 f34 脚本派发 `cureRole` 事件，数据 = 特效位置（英雄 x, y-60）。每个 Role2 的监听 `__cureRole`：自己无条件治疗；队友（单人模式没有）在 |dx|≤200 且 |dy|≤200 内治疗。治疗量 `getRealPower("hit5") = (getSMMP()/8 + 8) × (变身1.5) × (暴击2)`（`cureHp`，显示绿色数字 `bunum`，死亡者除外）。
- 分身版（Role2Shadow.cureRole，Role2Shadow.as:84-111）：分身 hit5 动画（加血_112，50 帧）f50 治疗**分身周围** |dx|≤200 且 |dy|≤160 的所有英雄（含主角），量 `(SMMP/8+8)×变身`（**无暴击**），然后分身销毁。⇒ 主角若还在分身旁会得到两份治疗。

### 4.5 hit4 落柱（L，Role2.as:324-370；body 元件7_50，65 帧；资源 `hit4FallDown`）
**两段式**：
1. 第一次按 L：已学序 4、**不在空中**（`isInSky()` 直接 return，两个分支都先检查）、非攻击/受击、`MP>=100` ⇒ `lastHit=curAction="hit4"`，扣 100 MP，`newAttackId()`。动画：f1~9 起手；f10~f42 一个**标记球 `roundMc`**（球图 150×144）向前飞（局部 x 从 -78.5 起每帧 -13.65px，y≈+51，扁平 scaleY 0.1875 的地面光圈）；f42 脚本 `gotoAndStop(65)` ⇒ 若不按第二下直接收招（**球本身没有伤害**，100MP 白费）；f65 结束。
2. 球存在期间（f10~f41，`body.roundMc` 在显示列表里）再按 L（**免费**）：生成 `SpecialEffectBullet("hit4FallDown")`，`setAction("hit4-1")`，`lastHit="hit4-1"`；位置 `x = 英雄x ± roundMc.x`（朝左 `+`，朝右 `-`，即球当前位置），`y = 英雄y + roundMc.y - 300`；移除球并 `body.gotoAndPlay(43)`（后半段收招 23 帧）。
   - 美术 `hit4FallDown`（sym 851，25 帧；**已在 Godot 中提取为 `hit4falldown` rig，Monster49 在用**）：从细线展开成约 260 宽 × 420 高的光柱，局部 y -95..+325（f1..21 展开、f22+ 消失），生成点在地面上方 ≈250px，所以光柱从屏幕上方一直罩到脚下。f25 销毁。
   - 伤害 `8×P`（hit4-1，Role2.as:610-611）、magic、击退 [25,-5]，`hitMaxCount 200`，`attackInterval 999` ⇒ 光柱存在期间每个怪只吃 **1 次**（若 `newAttackId` 没再被调）。是本角色最高伤害技能。
- `Role2Bullet4`（sym 773，43 帧，f6/13/20/26/32/38 各 `newAttackId`、f43 销毁）在代码里**从未实例化**，是遗留未用素材，可忽略。
- `Role2_hit4` 音效存在（SoundManager.as:44）但 Role2.as 不播放；重制可在第二次 L 时播放。
- 变身时 hit4/hit5 不出残影，其余同普通。

### 4.6 冷却一览
唐僧的技能**没有独立冷却计时**：只有 hit1 设置 `timers=18`；技能受「动画播放期间=isAttacking」限制（hit3 48 帧、hit5 34 帧、hit4 ≤65 帧、hit1 11 帧、hit2 蓄力期间一直算攻击）。
Godot 里 `cooldown` 字段：hit1 = 0.75s，其余技能可设 0（或设成动画时长）。

---

## 5. 分身（Role2Shadow，I 键；Role2.as:406-447，Role2Shadow.as）
- 学习序 2（500 灵魂），`MP>=30`，非攻击/受击。
- 没有分身时：音效 `Role2_hit6`，在英雄位置 new `Role2Shadow`（`gc.otherList`，不是怪物的攻击目标），朝向 = 英雄朝向，`isLeft/isRight` 置位 ⇒ **持续朝前走**，`horizenSpeed=8`（比英雄 6 快；受重力/地形，不转身），扣 30 MP。
- 寿命 `maxCount=192` 帧（8 秒），到时 `source.shadow=null` 并销毁。
- 已有分身再按 I：音效 `Role2_hit6`，**英雄瞬移到分身的 (x,y)**，分身销毁，**不扣 MP**（需非攻击/受击）。
- 联动：U → 分身同时在原地放 hit3（分身 `setStatic`，动画「冰柱_109」50 帧，f15 `SpecialAttack`，f50 销毁；伤害 `0.8×源英雄P×变身`，**无暴击**，分身 `isCannotMoveWhenAttack`）；O → 分身放 hit5（治疗见 4.4）。联动不额外耗 MP，且之后分身引用清空（只能触发一次）。
- 分身的子弹由分身自己 step（Role2Shadow.as:31-48）；分身销毁后子弹不再检测（冰柱 f15+36 帧超过分身寿命 50 帧，但 7 轮在 f46 内已结束，不受影响）。
- 分身对怪物的 `curAttackTarget` 取 `source`（BaseMonster.as:702-708）→ 怪物仇恨/经验归主角。
- 美术：`export.hero.Role2Shadow`（Role_v6 sym 695，15 帧，标签 `walk`(0) / `hit3`(5) / `hit5`(10)），三个 body：walk=sym 613（16 帧循环）、hit3=冰柱_109(sym 644, 50f)、hit5=加血_112(sym 694, 50f，内含 55 帧特效 sym 689)；碰撞盒同英雄。**半透明/幽灵外观需看原图确认**，没有装备槽（BaseHero.setWing/setMagicWeapon 对 Shadow 直接跳过，BaseHero.as:201, 218）。

---

## 6. 变身（怒气）与悟空的差异（落实到 Hero 代码要改的点）
| 项 | 悟空 | 唐僧 | 出处 |
|---|---|---|---|
| 受击硬直 / 击退 | 变身时**霸体**（无受击动画、无击退）`Role1.beAttackDoing`/`checkAttackBack` | **无霸体**：变身时照样 hurt + 击退（Role2 不覆写 beAttackDoing，`checkAttackBack` 对 Role2 无 `!isGXP` 条件） | Role1.as:242-259；BaseHero.as:605, 616-633 |
| 伤害 | ×1.5 | ×1.5（含回血量） | Role2.as:585-588 |
| hit3 冰柱 | — | 缩放 x1.26/y1.8，轮次 5→7 | §4.3 |
| hit5 特效 | — | 特效放大 1.6 倍 | Role2.as:489-493 |
| 残影 | 每 4 帧 | hit4/hit5 期间不出 | BaseHero.as:740 |
| 变身全屏特效 | WsEffect 里 Role1Mc | WsEffect 里 **Role2Mc**（sym 28 `唐僧无双_178`；背景 bg=sym 25）；`extract_rig.js` 的 SEPARATE_CLIPS 当前把 Role2Mc/Role3Mc 排除，需另导出 | BaseHero.as:850-871 |
| 防锁无敌光晕色 | 红 `0xFF0000` | **蓝 `0x0000FF`**（255） | BaseAddEffect.as:187-213 |
| 无敌复活等 | 同 | 同 | |

---

## 7. 技能商店、HUD 与存档差异
- 商店：`BuySkill` 按 `roleName=="唐僧"` 选 player2 页，`SkillControl.instrmc.gotoAndStop("唐僧")`（OtherMat_v10 `技能說明_34` sym 697 的帧标签 `孙悟空/唐僧/八戒`，唐僧=第 2 帧；主动技能图标同 `skill1..5`）。价格/一次性规则同悟空：

| 序 | 学习价 | 技能 | HUD 提示 |
|---|---|---|---|
| 0 | 100 | hit2 蓄力弹 | "长按J" |
| 1 | 200 | hit3 冰柱 | "U" |
| 2 | 500 | 分身 | "I" |
| 3 | 1000 | hit5 回血 | "O" |
| 4 | 2000 | hit4 落柱 | "L" |
- 被动技能：同悟空（5 项，n 级 n×5000，公式 07 §1.2）。
- HUD（RoleInfo.as:67-69, 133-137, 404-406）：技能图标帧 = `i + 7`（Flash 帧号，悟空是 i+2），即图标 `skill1..5` 的 Flash 帧 7..11（Godot 的 0 基帧 = 6..10；hud.gd:175-177 现在写死 `[hit8,hit6,hit7,hit9,hit10]`，要按角色改成 `[hit2,hit3,shadow,hit5,hit4]`）；头像 `head` 帧 2（OtherMat_v10 `_2233_145` sym 252 的 frame2 = sym 249）；怒气条同悟空。
- 背包立绘：`backpack_v5` `人物_107`(sym 439，标签 孙悟空/唐僧/八戒) 的第 2 帧 = **sym 366**（悟空是 sym 290 → `bag_wukong`，唐僧应建 `bag_tangseng`，spec 行 `backpack_v5 #366 bag_tangseng`）。
- 存档：`roleid`=2 即唐僧；`GameState.CHARACTER` 由 "悟空" 改为 "唐僧"（`Item.wearable_by` 用它过滤 `user` 字段，game_state.gd:15, 306）；`save_game.gd:22` 的标题里的角色名也要改。
- 技能存档名：现有 `GameState.skills` 以动作名为键（hit8…），唐僧可用 `hit2/hit3/shadow/hit5/hit4`。

---

## 8. 装备 / 时装 / 翅膀（`tools/data/equipment.json` 的 `user=="唐僧"`；AllEquipment.as:240-540）
`getEquipNum()` 规则同悟空：衣服 id = `时装.showid>1 ? 时装.showid : 衣服.showid`，武器 = `武器.showid`，翅膀 = `翅膀.showid`（User.as:69-102）。
**唐僧专属**（其余饰品、法宝、翅膀、强化石通用）：

| 槽 | id | 名称 | show | 品质 | 属性 | 获取（来自 docs/items.md） |
|---|---|---|---|---|---|---|
| 武器 | ptsmz | 普通的松木杖 | 3 | 普通 | 攻 2~11 | 小怪 #30/#31/#32 1-x 22.5% |
| 武器 | dsqz | 地煞权杖 | 4 | 优秀 | 魔 100~140 攻 20 | 黑/白无常 #33/#34 1-2 67.5% |
| 武器 | bsyz | 白霜妖杖 | 5 | 精良 | 魔 260~300 攻 44~52 回魔 2 | 白骨精掉落 / 白霜重甲×3 合成 |
| 武器 | xhxh | 血海邪皇 | 6 | 史诗 | 魔 500~580 攻 92~108 回魔 2 | 孟婆 #47 3-3 22.5% |
| 武器 | jhcz | 轮回杖 | 7 | 传说 | 魔 900 攻 180 回魔 5 | 刑天 #58 7-1 22.5% |
| 武器 | myz | 明月杖 | 8 | 传说 | 魔 800~1000 攻 140~200 暴击 5% 回魔 3~7 | 无（中秋小月饼×100，活动） |
| 衣服 | ptjs | 普通的袈裟 | 2 | 普通 | 血 12~38 魔 25~75 防 1~3 | 同松木杖 |
| 衣服 | lzp | 老者袍 | 3 | 优秀 | 血 50 魔 100 | 守夜人 #32 1-1 75% |
| 衣服 | tsyp | 天煞羽袍 | 5 | 精良 | 血 130~150 魔 260~300 防 4 | 秦广王 #38 2-1 52.5% |
| 衣服 | qcp | 七彩袍 | 4 | 史诗 | 血 250~290 魔 500~580 防 10~12 魔抗 10% | 炼丹炉：红+绿+紫花瓣 |
| 衣服 | zljs | 锦阑袈裟 | 6 | 传说 | 血 500 魔 1000 防 20 回魔 5 | 刑天 #58 7-1 22.5% |
| 时装 | tsmrz 唐僧黄头装 | | 7 | | | 商店 800 功勋 |
| 时装 | tswdg 唐僧西装 | | 8 | | 掉率 +10% | 商店 800 |
| 时装 | tsbsz 唐僧红头装 | | 9 | | 掉率 +18% | 商店 870 |
| 时装 | tszyf 唐僧状元服 | | 10 | | 掉率 +20% | 商店 900 |
| 时装 | jtswdg 绝·唐僧西装 | | 11 | | 原作匹配失败=0（同 07 §9 bug 2） | 活动，未做 |
| 时装 | jtszyf 绝·唐僧状元服 | | 12 | | 同上 | 活动，未做 |
- 掉率加成与价格：User.as:185-196、AllEquipment.as:859-880。
- 衣服 showid 分两路渲染（Role2.setEquips，Role2.as:183-226）：`curClothId<=3` 用 body 内的 `bodyEquip` 帧（1 裸 / 2 袈裟 / 3 老者袍），`>3` 隐藏 `bodyEquip`，改由各 body 里的选择器槽 `cloth_ex`（帧=衣服 id）绘制；武器槽 `weapon` 变体 1..8；翅膀槽 `wing` 变体 1..3。`tools/rig/extract_rig.js` 已能识别这些选择器（试跑得到 11 个槽：wing×1(116)、weapon×1(862)、cloth_ex×8、cloth×1(918)），与悟空同一套机制，`Rig.set_equip("cloth"/"weapon"/"wing", id)` 即可。
- **法宝差异**：Role2.getRealPower 的 `fabao-sword`（天煞古剑）伤害为 `400 + 60·L ±10`（悟空 `200 + 30·L`），其余法宝公式相同（Role2.as:621-627 对比 Role1.as:652-658）。`treasures.tsgj.damage/per_level` 需按角色覆盖。

---

## 9. 美术 / Rig 需求（全部在 **Role_v6** 库，fps 24）
### 9.1 主体：`export.hero.Role2`（sym 1217，116 帧，帧标签 → body 子 MC）
| 标签 | 起始帧 | 帧数 | body sym（类） | body 帧数 | 关键帧脚本 |
|---|---|---|---|---|---|
| wait | 0 | 9 | 1005 `等待_4` | 91 | f1、f61 setEquips；循环 |
| walk | 9 | 12 | 1023 `元件2_36` | 16 | 循环 |
| run | 21 | 11 | 1045 `奔跑_39` | 8 | 循环 |
| hit1 | 32 | 11 | 1061 `攻击一_43` | 11 | f2 蓄力检测→hit2；f7 `doHit1`；f11 结束 |
| hit3 | 43 | 13 | 1093 `元件6_46` | 48 | f15 `SpecialAttack`；f48 结束 |
| hit4 | 56 | 12 | 1129 `元件7_50` | 65 | f10~42 内有 `roundMc`(sym 1119，20 帧循环)；f42→跳 65；f65 结束；二段 `gotoAndPlay(43)` |
| hit5 | 68 | 12 | 1181 `加血技能_62` | 34 | f34 结束 |
| hit2 | 80 | 9 | 1188 `攻击二_76` | 9 | f1 条件 stop（蓄力）；f2 `doHit2`/`doHit1`；f9 结束 |
| jump1 | 89 | 7 | 1195 `弹跳1_77` | 1 | 循环 |
| jump2 | 96 | 7 | 1203 `弹跳2_80` | 11 | f11→jump3 |
| jump3 | 103 | 7 | 1209 `弹跳_落下_84` | 1 | 循环 |
| hurt | 110 | 6 | 1216 `元件44_86` | 15 | f7 `setStatic`；f15 结束 |
| 其他子节点 | | | `levelupmc`(253，升级光效，各动作都有，`SEPARATE_CLIPS` 已处理，可共用 `fx_levelup`)；`colipse`(255) | | |
- 唐僧**没有** hit6~hit10、没有 `stick` 攻击框；所有动作的 body 都带 `bodyEquip`/`weaponEquip` 装备槽。
- **extract_rig.js 试跑结果与需要手工处理的点**（输出：`unknownScripts=[]`，226 张贴图）：
  1. `hit1` 被导成 **2 帧**：因为 f2 脚本含 `Role2.gotoAndStop("hit2")` 被误判为「动作结束」。需要把 hit1 当 11 帧导出，f2 作为条件事件（`charge_check`）、f7 `do_hit1`、f11 `finished`；
  2. `hit2` 的 f1 `if(MP>=20) stop()`、f2 `do_hit2/do_hit1` 需自定义事件（蓄力保持 / 松手发射）；
  3. `hit4` f42 的 `gotoAndStop(totalFrames)` 在 rig 里要变成「跳到 65 帧结束」，并导出 `roundMc` 的位置标记（现为 marker `roundMc`），二段按 L 时 `seek` 到第 43 帧；
  4. `hit3` 的 `special_attack`（f15）、`hit5` 无事件（治疗由 `cureRoleMc` 触发）。
### 9.2 需新增的 rig（`tools/rig/specs_*.txt` 新增行，格式 `lib 类/#id[@帧] 名称`）
| rig 名 | 来源 | 说明 |
|---|---|---|
| tangseng | `Role_v6 export.hero.Role2` | 主体，11 个装备槽 |
| tangseng_shadow | `Role_v6 export.hero.Role2Shadow` | 分身，动作 walk/hit3/hit5 |
| tangseng_bullet1 | `Role_v6 Role2Bullet1` | 单帧光弹 |
| tangseng_bullet2 | `Role_v6 Role2Bullet2` | 单帧大光弹 |
| tangseng_bullet3 | `Role_v6 Role2Bullet3` | 冰柱，46 帧；f1/6/11/16/21（变身再加 26/31）`new_hit`，f46 销毁；`shake` 事件 |
| tangseng_cure | `Role_v6 cureRoleMc`（sym 768→767） | 回血光效，34 帧；f34 触发治疗并自毁 |
| hit4falldown | 已有（`specs_bullets.txt` 的 `Role_v6 hit4FallDown`） | 落柱，25 帧 |
| fx_rage_tangseng | `Role_v6 #28`（`唐僧无双_178`，另加背景 `#25`） | 变身全屏特效，需在 extract 里不排除 Role2Mc，或单独 spec |
| bag_tangseng | `backpack_v5 #366` | 背包立绘 |
| fx_hero_hurt / fx_monster_hurt1/2 | 已有 | 唐僧攻击命中时叠色相 +160°（滤镜 ColorMatrix hue 160） |
- 其余共用：`fx_levelup`、墓碑、法宝、药水等。分身与子弹 rig 不含装备。
- 音效（Music 库）：`Role2_hit1`(31) 光弹 / `Role2_hit2`(32) 蓄力弹 / `Role2_hit3`(33) 冰柱 / `Role2_hit4`(11) / `Role2_hit5`(30) 回血 / `Role2_hit6`(27) 分身 / `Role2_jump`(39，原作不播) / `Role2_beAttack`(36) / `Role2_dead`(47) / `BeattackByRole2` 命中怪物。

---

## 10. 对 Hero 代码的覆写清单（hero.gd 目前是悟空专用）
1. **数据**：新建 `tools/data/tangseng.json` → `game/data/tangseng.tres`（`HeroData`，`rig="tangseng"`）。stats 见 §2，move 同悟空，`combo.cooldowns` 不再使用（改为 hit1 单一冷却 0.75s）。`learn.active=[hit2,hit3,shadow,hit5,hit4]`，`active_cost=[100,200,500,1000,2000]`，被动同悟空。`treasures` 复制并把 `tsgj.damage=400, per_level=60`。
2. **输入**：新增 `skill_l`（键盘 L / 手柄 LT）；`_read_input` 里去掉「上+攻」「跑动+攻」分支；`attack` 按下 = 普攻光弹，**按住**状态用 `Input.is_action_pressed("attack")` 判定蓄力。U/I/O/L 分别绑定 hit3/分身/hit5/hit4。
3. **普攻**：重写 `_normal_attack`：仅在非攻击/受击时响应、`cooldown=0.75s`、播放 `hit1`，不用 `COMBO`、`combo_step`、`CANCEL_INTO_HIT8`；在动画事件（f7）发射 `tangseng_bullet1`（朝向 8px/帧→192px/s，射程 300，x 缩放 0.6，命中 1 个、溅射 60px）；f2 事件检查「已学 hit2 + MP≥20 + 攻击键仍按住」→ 转入 `hit2` 并停在第 1 帧；记蓄力帧数（秒数 30/24=1.25s，满则变色闪）；松手继续播放；f2 事件按蓄满与否发射 bullet2（扣 20 MP）或 bullet1。头顶蓄力条（红框绿填充）可以放在 Hero 子节点。
4. **投射物**：不走 `scan_hits`（没有近战判定框），全部用 `Projectile`；hit1/hit2 需要 `Projectile` 支持**溅射半径**（hit1）与**穿透 + 重复命中间隔**（hit2，`rehit_interval=4/24`, `max_hits=200`，已有字段）。`SpecialEffectBullet` 类（冰柱、落柱）的击退方向 = 远离子弹中心，`Projectile._deliver` 在 `velocity.x==0` 时已是此逻辑。冰柱的多轮 = `rig` 的 `new_hit` 事件（已支持）；变身时多出 f26/f31 两次 `new_hit` 与缩放要由 Hero 控制（`Projectile.rig.scale`）。
5. **动作约束**：`SCRIPTED_MOTION`/`_no_gravity`：hit3、hit5 期间速度清零且**无重力**（悬停）；hit1/hit2/hit4 在地面时水平不动，空中可动；hit4 仅限地面；hit3/hit5/分身可空中施放；攻击动作期间不能跳、不能再出招（`_can_act` 去掉「COMBO 内可接招」）。
6. **hit4 二段**：第一次按 L 扣 100 MP 并播放 `hit4`；rig 里 `roundMc` 标记（f10~f41，局部 x 起点 -78.5，每帧 -13.65）→ Godot 用 marker 位置取球坐标；窗口内再按 L：在 `hero.x + facing*|球x|`、`hero.y + 51 - 300` 生成 `hit4falldown`（`hit4_1`：`power_mul=8`，magic，击退 [25,-5]，`max_hits=200`，`interval=999`），隐藏球，rig `seek` 到第 43 帧。
7. **分身**：新增 `Shadow` Actor（可以做成 Hero 之外的轻量节点）：寿命 8s、朝前走 8px/帧（192px/s）、受重力和地形、无敌（不是目标）；`I` 键三态（生成 −30 MP / 已有则互换位置 / 攻击中无效）；`U`、`O` 同步让分身播放 hit3 / hit5 并清空引用；分身 hit3 伤害 `0.8×P×变身`、无暴击；分身 hit5 在其位置 50 帧后治疗范围内英雄。
8. **回血**：`hit5` 施放时在 `(x,y-60)` 生成 `tangseng_cure` 特效，特效第 34 帧调用 `heal`：`int((max_mp/8 + 8) × (1.5 若变身) × (2 若暴击))`（含装备的最大 MP）；半径 200×200，单人只需治疗自己。
9. **受击 / 变身**：`take_hit` 里 `if transformed: return true`（霸体）**必须对唐僧去掉**；`_spawn_afterimage` 在 `hit4/hit5` 时跳过；`outgoing_damage` 的 1.5/暴击不变。受击光晕颜色换蓝，受击/命中特效叠加色相 +160°。`_on_equipment_changed`/`appearance()` 用 `CHARACTER="唐僧"`。
10. **HUD / UI**：`hud.gd` 技能图标帧偏移与学习列表按角色；`backpack.gd` 的立绘 rig 名与「孙悟空」文字；`game_state.gd` 的 `CHARACTER`/`HERO_DATA`；`save_game.gd` 标题的角色名；Wukong 专属的 `Role1_*` 音效名按角色表替换（`SOUNDS` 字典、`Role1_dead`、`Role1_beAttack`）。

---

## 11. 原作注意事项 / 待决定的小问题
1. hit4 第一段无伤害，不按第二下 100 MP 白扣（保留原作行为，或给提示）。
2. 蓄力不满松手 = 免费 hit1 一发（且仍占用 hit2 动画 9 帧）；MP<20 时无法进入蓄力，长按 J 只是 hit1。
3. `Role2_hit4` 音效从未播放；`Role2Bullet4`、`Role2_jump` 遗留未用。
4. 回血会暴击；分身的 hit3/hit5 不暴击。
5. 键盘 KEY_DOWN 在 Flash 里会随系统连发，导致按住 L 可能自动触发第二段；Godot 用 `is_action_just_pressed` 即可，不复刻。
6. 绝·唐僧时装掉率加成与悟空版一样是 0（名称匹配 bug）。
7. 联机相关（MODE3 PK、队友治疗、给予）忽略。
