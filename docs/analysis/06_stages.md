# 原作分析 06：游戏流程、关卡逐场景规格、场景机关、存档

来源：`decomp/res/zmxy2_game/scripts`（主 SWF 代码，权威）；怪物类在各关卡 SWF（`decomp/res/{1_v6,2,3,…}/scripts/export/monster`，Monster33/34 在 Common_v6/v7）。
场景布局（墙/停止点/刷怪点坐标）取自 `decomp/timeline/zmxy2_game.json`（sl 符号 id：sl11=338 … sl111=240，帧 0 的子对象 + 矩阵）。
单位：帧（24fps）、像素；舞台 940x590。已在 01/03/04 中写过的内容（镜头卷屏、StopPoint/MonsterAppearPoint 机制、墙体碰撞）不再重复，只补充与更正。

---

## 0. 对 04/03 文档的更正
- **场景里摆放的 StopPoint 实例的属性（idx/betweenRandL/isBoss）全部无效**。`PhysicsWorld.addSubObj` 发现含子对象 `stophere` 的 MC（即 export.StopPoint 实例）时会 `new StopPoint()` 另建一个，只取其 x,y，并按 x 升序插入；`pWorldStart` 再把 idx 重设为排序序号。所以：
  - idx = 按 x 排序的序号（各 sl 的 `stopPointIdx` 与之一致，sl31 例外：场景写 idx=4，实际为 0，且该场景没有刷怪点）。
  - betweenRandL 取构造函数默认值：第 1 大关 1450；4-1、9-1 为 940；其余 1150（sl13 的 940、sl33 的 960 不生效）。
  - StopPoint.isBoss 从未被读取。
- MainGame.GameStart：stage 5 只加载 "5_v7"。之后那段“再加载 1”的代码不可达（`name` 已被改成 "5_v7"）。
- 镜头固定的关卡：5-1、6-1、7-1、整个第 10 大关（ViewControllor.step 开头直接 return，只保留震屏）。

---

## 1. 游戏流程

### 1.1 启动
`GMain`（940x590，24fps）→ Aloader 依次加载 `OtherMat_v10, Role_v6, Music, Common_v7, backpack_v5` → "LoadOver" → `switchSence("GameMenu")`。

### 1.2 主菜单 GameMenu（构造时 `gc.initData()`，进度全部清零；循环播放 BGM "begin"；版本文字 V2.4）
| 按钮 | 作用 |
|---|---|
| newGame | `gc.newGameClick()`：curBigStage/BigLevel/curStage/curLevel=1、saveId=-1、各种 buff 计时随机初始化。（需登录）读一次 7 号槽（openPig）→ 显示 1P/2P 按钮 |
| continueGame | （需登录）打开存档面板 SaveInter，state="read" |
| simpleGame / doubleGame | playNum=1/2，gameMode=1/2。新游戏 → "StartSelectRole"；读档 → "SelectOver" |
| backbtn | 返回按钮布局 |
| gameHelp / aboutUs | 帮助 / 关于面板 |
| btnquit | 4399 登出 |
| btn_solution / btn_forum / btnCadpa / btnGoBack | 外链 / 适龄提示 / AIR 返回（重制版可删） |

### 1.3 选角 SelectRole
btn1=悟空(Role1)、btn2=唐僧(Role2)、btn3=八戒(Role3，未 openPig 时锁定；需加载 Pig9.swf)。1P：选完直接 "SelectOver"；2P：依次给 P1、P2 选，P2 选完 gameMode=2。每次选择都会 `gc.newRole()` 重建 Hero。
重制版只有悟空：跳过此界面，直接 roleid=1。
"SelectOver" → 若 `gc.opening` 为 false（新游戏）先播开场漫画 GameCartoon "开场"（3 页，点击翻页，第 3 页点击 → "ShowOpenAnimationOver"）→ 关卡地图。读档时 storageValue 已把 opening 设为 true，所以直接进地图。

### 1.4 关卡地图 SelectPLace（BGM "begin"）
- 关卡按钮 MC：s1_1..s1_3, s2_1..s2_3, s3_1..s3_3, s4_1（s4_2/s4_3 存在但永远不可用）。帧 1=普通，帧 2=当前进度点（s{curBigStage}_{curBigLevel}），帧 3=悬停。
- **解锁规则**：stage < curBigStage 的 3 个小关全部可点，stage == curBigStage 的 1..curBigLevel 可点，其余不挂监听（看起来一样，只是点不动）。调试模式（!isHideDebug）curBigStage=4。
- 点击 → gameMode=playNum、curStage/curLevel = 按钮名 → "selectStageOver" → `new MainGame().GameStart()`。
- 其他按钮：showBuySkill（技能商店）、ldl（强化）、scgm（商城）、savebtn（手动存档，冷却 30 秒，saveInterval 文本显示倒计时）、submitbtn（提交总分）、btnback（回主菜单并 initData）、huodongbtn（活动）、
  **btnnmg → 6-1 红孩儿**（无任何解锁检查；首次进入先播漫画 "红孩儿副本"，openinghhe=false 后不再播）、
  **lxdy → 10-1 地府枢纽**（无解锁检查）、arena（仅 2P，gameMode=3 对战）。
- 没有难度选择。“难度”只有 1P/2P：maxMonsterPerScreen 6/8（MODE3 对战 HP×500）。

### 1.5 进度（Config，不在 User）
`curBigStage`, `curBigLevel` = 最远解锁关。`MainGame.__levelClear`（所有过关都会走这里）：
```
if curStage == curBigStage:
  if curBigStage <= 3 and curLevel == curBigLevel:
     if curLevel == 3: curBigStage++, curBigLevel = 1      # 3 → 下一大关 -1
     else:             curBigLevel++
  elif curBigStage == 4: curBigLevel = 1
```
解锁链：1-1→1-2→1-3→2-1→2-2→2-3→3-1→3-2→3-3→4-1（终点）。隐藏关（5～11）不影响进度。只有通关“最前沿”那一关才会推进；重打旧关不推进。
然后：播 "begin" 和 "Game_Victory"，destroyGame，若 isHideDebug 则 `memory.setStorage(saveId)`（自动存档，见 §4）。

### 1.6 关卡内
- `MainGame.newGame`：floorBg{stage} 远景 + 场景 `sl{stage}{level}`，hero1 放在 (200,200)（P2 放在 (300,200)），`hero.start()`，监听器 `StageListener{stage}{level}`（`pWorldStart` 里 new，然后立即调用 `start()`），BGM 见下。
- **每次进关 HP/MP 都回满**：`start() → initPopertits() → upGrade()` 把 HHP/MMP 设为最大值，`initAll → addAllEquip()` 再 setHHP(max)。所以 sl11→sl12→sl13 之间不会保留伤血，只保留等级/经验/背包（保存在 User.protectedObject 和各列表里，实时更新）。出生时有 48 帧 father 无敌。
- 关内回复：每 24 帧 +hx HP、+hl MP（装备属性）。
- 暂停菜单 SetMenu（从 HUD RoleInfo 打开）：继续 / 回地图（destroyGame）/ 回主菜单（destroyMode=destroyGame+initData）/ 帮助 / 声音开关。

### 1.7 过关：传送门 → GameWin
- 场景里的传送门（子对象 isTransferDoor，167x163）在 addSubObj 时 `visible=false`。**BOSS 的 destroy()（死亡动画播完）把所有传送门设为可见**（无 BOSS 的关卡见各场景说明）。
- 英雄按“上”（keyarray "0001"）：先调用 `listener.keyBoardDownForW(hero)`，然后若 `!isLevelClear` 且门可见且 `door.hitTestObject(hero.colipse)` → isLevelClear=true，键盘销毁，gameInfo 和 gameSence 1 秒淡出 → "LevelClear"（进度 + 存档）+ "LevelVictor" → GameWin。
- GameWin：用时、最大连击 User.biggestbatterNum、状态% = (HP%+MP%)/2、总分。按钮：
  - nextStageButton（curStage ≥ 4 时隐藏）：stage ≤ 3：level 3 → 下一大关 1，否则 level+1；然后直接开始（"selectStageOver"）。
  - backTochooseButton → 地图。

### 1.8 失败：GameFail（export/lose）
英雄 HP ≤ 0：若装备 zbsp="csgs" 且 y < 1200 → 复活（HP/MP 回到一半，24 帧无敌，消耗该装备）；否则 "heroDead" → 尸体动画 deadmb（78 帧）→ `MainGame.gameOver()`：所有英雄都死了 → destroyGame → GameFail（BGM "over"）。掉落到 y ≥ 1500 也算死亡。
- rePlayButton（curStage ≥ 5 时隐藏）→ "ReStart"，用同样的 curStage/curLevel 重开。
- backTochooseButton → 地图。
- 失败不会回滚：本关获得的经验/物品留在 User 里，下次存档时会被存进去。

### 1.9 隐藏关 / 副本入口（全部汇总到 "fbfbfbfb" 事件 → `MainGame.__fbfbfbfb`）
| 当前关 | 跳转 | 触发方式 |
|---|---|---|
| 1-2 | 5-1 白骨精 | 白骨门：打 3 下后站在门里 120 帧 |
| 2-2、2-3、11-1 | 7-1 刑天 | 刑天门：背包里有阎罗令 yll，碰门 24 帧后进门（消耗 yll） |
| 3-1 | 8-1 楚江王 | 极光 AuroraLight：持有避水珠 bsz 时碰到（消耗 bsz） |
| 10-1 | 10-2..10-6 | 枢纽传送门（listener 设置 curLevel 后走 else 分支） |
| 其他 | 重开当前 curStage/curLevel | — |

跳转方式：destroyGame → 改 curStage/curLevel → "ReStart"。不经过结算，也不存档。
- 6-1 红孩儿：地图按钮 btnnmg。
- 9-1 宋帝王（副本模式 isFb）：七夕活动面板，每天一次（日期 md5 记在 hdInfo）。
- 10-x：地图按钮 lxdy。
- 11-1：原版从同一个活动面板（`SelectPLace.huodongbtn` → ChineseValentinesDay，国庆版 curStage=11）进入，每天一次。重制版地图上的「活动」按钮打开 `ActivityPanel`，七夕（9-1，+10 功勋）/ 国庆（11-1）两页，每天各一次。
- 阎罗令 yll：Monster53/54/55 掉落（50%，阎罗王 M40 在 2-3 召唤）。避水珠 bsz：3-3 的宝珠 20% 掉落。
- 隐藏关通关后同样走传送门 → LevelClear（不推进进度）→ GameWin（没有“下一关”）。

### 1.10 终局
4-1 最终形态转轮王 Monster60 死亡：每天第一次 功勋 +50 并存档；gameinwhere="通关"，播 GameCartoon "通关"（6 页），键盘全部停用；漫画的 gotoStageMap() 派发 "LevelClear" 并切到地图。

---

## 2. 逐场景规格

共用默认值：关卡资源库 = `{stage}.swf`（1→1_v6，5→5_v7；Common_v7 常驻，含 Monster33/34）；BGM = `bg{stage}`（stage ≤ 7），stage > 7 用 bg4，全部无限循环；远景 = floorBg{stage}；
近景 = bg{stage}{level}，放在 bgClips 里，y=65，作为 bgContainer 第 0 个子对象。
标准边界墙（ObsWall，scaleX 拉伸）：地面 y≈501..529、20 高；天花板 y≈-139；左墙 x≈-10（转 90°）；右墙在场景末端。

### 2.1 共用监听器模式
- **A. 空监听器**（11、13、21、32）：完全靠 StopPoint/刷怪推进，BOSS 死后开门。
- **B. 4 秒后自动 touch**（51、61、71、102～106）：`TweenMax.delayedCall(4)` → `stopPointArray[0].touch()`。用于 BOSS 房，镜头不用卷到停止点就会刷怪。
  （81 也有 createMonster 方法，但从未被调用 → 实际属于模式 A。）
- **C. 存档监听器**：91、111 的 `start()` 在进关时调用 `memory.setStorage(saveId)`。
- 独有监听器：12（白骨门）、22（判官火焰限时 + 刑天门）、23/111（刑天门）、31（行船）、33（宝珠 + 孟婆隐藏墙）、41（循环浮台）、91（BOSS 死后刷宝箱怪）、101（枢纽门）。

### 2.2 刷怪表
格式：`SP 序号 x=停止点x：M类型 x 数量 @(刷怪点x,y) d延迟秒`。所有刷怪点 interval=1 秒、isRandom=false。

**1-1 sl11**（宽≈5433，地面 y 519，右墙 4750，门 (4392,459)）
- SP0 x=1105: M30x3@(1244,366)d1
- SP1 x=1852: M30x2@(801,297)d2, M30x3@(1950,369)d1, M31x5@(1457,369)d1
- SP2 x=2856: M30x2@(2136,410)d2, M30x3@(2427,410)d4, M31x3@(2747,390)d6
- SP3 x=3584: M30x1@(2986,267)d2, M30x1@(3470,267)d2, M31x4@(3220,443)d2, M31x2@(3067,374)d2, M31x2@(3387,366)d2
- SP4 x=4580: M31x5@(3712,267)d2, M31x4@(4598,195)d2, M32x1@(4386,371)d6
- BOSS：Monster32 守夜人。只有在 1-1 中它才是 isBoss（HP 700，hit1 16 物理，hit2 30 魔法，掉 lzp 50%）；在其他关是普通怪（HP 300）。镜头卷屏，监听器为空。

**1-2 sl12**（宽≈6494，右墙 4795，门 (4627,464)）
- SP0 x=999: M30x4@(387,396)d2
- SP1 x=1745: M30x2@(1077,415)d4, M32x1@(1110,279)d2, M32x1@(1628,286)d2, M30x5@(1372,396)d2, M31x2@(872,415)d6, M31x2@(1923,415)d6
- SP2 x=2749: M31x3@(1648,415)d2, M32x1@(2268,279)d2, M30x2@(2531,383)d2, M32x1@(2140,383)d6, M32x5@(2704,428)d4
- SP3 x=3725: M31x4@(2686,324)d2, M31x4@(3636,343)d2, M31x1@(3100,415)d2, M32x3@(3344,311)d8, M32x3@(2864,311)d8
- SP4 x=4741: M33x1@(4674,343)d3, M34x1@(3706,358)d3
- BOSS：双 BOSS 黑无常 M33（HP 1000）+ 白无常 M34（HP 1200），只有在 1-2 中才是 isBoss。门在“BOSS 死亡且 monsterArray 为空”时打开，即两个都要打死。
- **白骨门**（Main_fla.白骨门_31，子对象 colipse/enter/isBaiguDoor，帧 1 停，帧 2..50 开门动画，停在帧 50），见 §3.6。

**1-3 sl13**（门 (4155,453)）
- SP0 x=1093: M31x4@(1172,396)d2
- SP1 x=1839: M32x5@(1044,396)d2, M32x3@(1900,409)d2, M31x3@(1934,294)d6, M31x3@(1024,260)d6
- SP2 x=2844: M32x5@(2369,422)d2, M32x3@(1776,366)d8, M31x4@(2926,409)d8, M32x2@(2369,195)d4
- SP3 x=3572: M32x4@(3534,438)d2, M32x3@(3675,294)d6, M32x3@(2760,281)d6
- SP4 x=4287: M32x3@(4328,409)d1, M32x3@(3464,332)d1, M52x1@(4181,332)d1
- BOSS：M52 秦广王傀儡（HP 3000，def 0，exp 0；会召唤 Monster35），生成在 bgContainer 之上（在英雄后面一层）。监听器为空。

**2-1 sl21**（门 (4383,467)）
- SP0 x=1099: M37x5@(1183,354)d2, M36x5@(103,370)d2
- SP1 x=1845: M37x6@(2039,382)d2, M36x6@(959,398)d2
- SP2 x=2713: M37x7@(2888,406)d2, M36x7@(1807,422)d2
- SP3 x=3369: M37x8@(3560,398)d2, M36x8@(2632,414)d2
- SP4 x=4589: M38x1@(4497,370)d3（秦广王，HP 5000，def 25）
- 监听器为空。

**2-2 sl22**（门 (4290,465)）
- SP0 x=1240: M37x3@(145,366)d2, M36x3@(1161,358)d2, M36x3@(81,402)d6, M37x3@(1227,394)d6
- SP1 x=1987: M37x4@(1319,395)d2, M36x4@(2023,402)d2, M36x3@(1255,431)d6, M37x3@(2089,438)d6
- SP2 x=2991: M37x4@(1949,367)d2, M36x4@(2942,403)d2, M33x3@(1921,403)d6, M34x3@(2914,367)d6
- SP3 x=3719: M37x4@(3037,374)d2, M36x4@(3837,381)d2, M33x4@(3010,410)d6, M34x4@(3782,374)d6
- SP4 x=4555: M39x1@(4491,381)d2（判官，HP 6000，def 28）
- **判官战（独有）**：M39 出生时 "ready" 姿态 + setYourFather(9999)（无敌）；4 秒后调用 listener.start1()：6 个隐藏的判官火焰（Main_fla.判官火焰_39，子对象 isPanguanFire，帧 1 燃烧 / 帧 2 熄灭，场景初始位置约在 x 3921..4387）被移到判官所在位置并设为可见，用 2 秒 Tween 飞到 [[3927,148],[4044,134],[4100,123],[4257,123],[4297,134],[4423,148]]；第一个火焰飞到后调用 start2() → `panguan.realStart()`（转为 wait 状态，24 帧无敌，开始战斗），同时启动计时器 Stage22Count=1。
  之后每 360 帧（15 秒）熄灭 fireArray 的第一个火焰（1 秒 alpha→0，然后 gotoAndStop(2)）；最后一个熄灭后 4 秒 → **GameOver（失败）**。即**限时 6×15+4 = 94 秒**（从判官开战算起）。
- **刑天门**（Main_fla.刑天门_40，子对象 colipse/enter/isXingtianDoor）：随机放在 [(471,200),(1832,202),(3238,205)] 之一，见 §3.7。

**2-3 sl23**（宽≈5690，地面墙 5500 宽，右墙 5276，门 (5080,449)）
- SP0 x=1323: M37x3@(227,338)d2, M36x3@(1243,330)d2, M36x3@(163,374)d6, M37x3@(1310,366)d6
- SP1 x=2181: M37x4@(1401,367)d2, M36x4@(2217,374)d2, M36x3@(1337,403)d6, M37x3@(2283,410)d6
- SP2 x=3157: M37x4@(2144,339)d2, M36x4@(3108,375)d2, M33x3@(2116,375)d6, M34x3@(3080,339)d6
- SP3 x=4226: M37x5@(3204,346)d2, M36x5@(4224,353)d2, M33x5@(3176,382)d6, M34x5@(4168,346)d6
- SP4 x=5225: M40x1@(5134,353)d2（阎罗王，HP 10000，def 31；召唤 M53/54/55，召唤物 50% 掉阎罗令 yll）
- 刑天门随机位置 [(483,200),(1886,200),(3288,200)]。

**3-1 sl31 行船关（独有）**（宽≈5013）
- 墙：天花板 y≈-46，左墙 x -10，右墙 x 4666；**没有地面**，掉下去 y≥1500 即死。终点码头：斜坡 ObsWall rot -45 @(4325,500) 49x49 + 平台 (4335..4655, y 476)。
- 船 export.Boat（ObsWall 子类，isWall）：@(272,495)，380x20，speedX=2，speedY=1（只表示“上下浮动”，具体见 §3.2），moveTime=1（未使用），userDataName "Stage31Chuan"（船的贴图 MC，每帧跟随船的 x,y）。英雄站在上面会继承 speedX（见 01 文档）。
- 停止点 1 个，x=4610，没有刷怪点。镜头随英雄卷动；touch 后立即清空，且是最后一个停止点，所以不会自动卷屏。
- 监听器 31：
  - 跳鱼兵：计数从 192 开始，之后每次 24×(3..7) 帧（随机）；场上怪 < maxMonsterPerScreen 时生成 Monster41Jump 动画 @(船.x ± 100, 船.y+150)，1.5 秒 Tween 到 y=船.y-60 → 在 (x, y+10) 生成 Monster41（等待期间计数停在 0）。
  - 鱼群发射器 Monster57：开场 5 秒后在 (500,-500) 生成，**从 monsterArray 中移除**（不计数、打不到），由监听器负责 step。setYourFather(99999)。每 72 帧，之后每 24×(1..4) 帧，生成 2～4 条跳鱼 EnemyMoveBullet "Monster57Bullet1"：随机从船的右端或左端出现（x = 船.x ± 船宽/2 + rand(±50)，y = 船.y + 0..50），速度 (10,-20)、(5,-25) 或 (2,-20)（概率 30/30/40%），重力 +2/帧，可被打掉，伤害 90 物理，击退 [10,-2]。
  - 船.x ≥ 4129 → 船 speedX=0，停止刷跳鱼兵，鱼群发射器 destroy() → **传送门出现**（本关的“BOSS”就是 Monster57）。
  - 极光 AuroraLight：在 24×(5..15) 帧时出现一次，放在屏幕坐标 (1000,600) 并播放动画，存活 360 帧；持有 bsz 的英雄的 colipse 碰到它 → 消耗 bsz → 进入 8-1。消失时调用 listener.start2() 把引用清空。

**3-2 sl32**（门 (4428,262)）
- 地形：出生点下方是低台 (-2..218, y 510)；斜坡 rot -37° 中心 (343,424)（矩形 201..485 × 314..535）通往主地面 (471..4771, y 316)。
- SP0 x=1144: M43x2@(253,43)d2, M42x2@(1094,215)d2, M41x4@(598,175)d6, M41x4@(877,175)d6
- SP1 x=1931: M43x5@(1013,43)d2, M42x5@(1982,155)d2, M41x4@(1358,175)d6, M41x4@(1637,175)d6
- SP2 x=2944: M42x5@(1853,98)d2, M41x4@(2243,155)d6, M41x4@(2675,154)d6, M41x2@(2451,175)d12, M42x5@(2841,132)d2
- SP3 x=3760: M43x5@(2868,-2)d2, M42x5@(3855,32)d2, M41x4@(3231,189)d6, M41x4@(3663,188)d6, M41x2@(3439,209)d12
- SP4 x=4616: M56x1@(4518,146)d2（夜叉，HP 40000，def 83）。监听器为空。

**3-3 sl33**（门 (4359,436)；右墙为转 90° 的 ObsWall，x 4738）
- SP0 x=1089: M43x5@(282,186)d4, M42x5@(1139,306)d6, M44x2@(1033,419)d2
- SP1 x=1835: M43x5@(1020,161)d6, M42x5@(1900,290)d6, M44x4@(1794,403)d2, M44x4@(1399,411)d2
- SP2 x=2839: M44x5@(1799,166)d6, M44x5@(2879,296)d6, M42x5@(2774,408)d2, M43x5@(2098,388)d2
- SP3 x=3567: M44x5@(2670,186)d6, M44x5@(3750,316)d6, M42x5@(3645,428)d2, M43x5@(2969,408)d2
- SP4 x=4703: M47x1@(4540,347)d2（孟婆，HP 60000，def 94）
- 宝珠 FB81Pearl ×5，位置 (1765,160)、(2238,160)、(2722,160)、(3196,160)、(3653,160)，见 §3.8。
- 孟婆隐藏墙（类 `孟婆障碍` 继承 ObsWall，子对象 isHideWall，竖墙 @(3532,193)，矩形 x 3522..3542、y -207..593）：起初只放在 otherArray（不碰撞，release 版不可见）；M47 构造时调用 listener.start1() → 加入 wallArray → 变成实体墙，把玩家关在右侧 BOSS 区。

**4-1 sl41 转轮王（独有）**（宽≈2193，地面 y 463，右墙 2078；betweenRandL 940，即不能回退）
- SP0 x=1094: M50x20@(226,260)d2, M50x20@(967,254)d2
- SP1 x=1926: M59x1@(1685,254)d2
- BOSS 链：M59 转轮王（HP 100000，def 200）死亡 → 在 (1700,175) 生成 M51 → M51 死亡 → 在 (1400,472) 生成 M60 转轮王最终形态（HP 500000，def 400，horizenSpeed 0）。M60 的 __added 调用 listener.start1()。M60 死亡 → 通关漫画（§1.10）。
- 浮台：2 个 ThroughWall（#__id213_ @(1234,-424)、#__id214_ @(1818,-424)，235x20，场景设定 speedX=2、speedY=0），监听器构造时把 speed 清零（停在屏幕外上方）。
  start1：根据原来的 x 决定方向（x < 1500 → +2，否则 -2），依次移到 (1200,340)、(1810,180)，userDataName="Monster60FlyFloor"（贴图）。
  监听器每帧做循环：屏幕 x < -w/2 → x += 1400；屏幕 x > 940 + w/2 → x -= 1400。（ThroughWallBullet 不参与。）

**5-1 白骨精 / 6-1 红孩儿 / 7-1 刑天**（监听器模式 B；镜头固定；场景约 1200 宽，单屏；右墙 ≈1070；门在 (767..775,445)）
- 5-1：SP0 x=882 → M45x1@(819,320)（白骨精，多形态 20000/40000…）
- 6-1：M46x1@(833,320)（红孩儿，HP 50000/10000 两种形态）
- 7-1：M58x1@(833,320)（刑天，HP 100000；死亡时生成 M81 (500,300)）
- 失败界面没有“重玩”（curStage ≥ 5）。

**8-1 楚江王 sl81**（宽≈1904，镜头卷屏，监听器为空）
- SP0 x=1044: M63x20@(905,308)d2, M63x20@(133,326)d2
- SP1 x=1772: M61x1@(1718,302)d2（楚江王，HP 200000，会生成 M62）

**9-1 宋帝王 sl91（副本，isFb）**（betweenRandL 940）
- SP0 x=1040: M64x1@(902,302)d2；SP1 x=1716 没有刷怪。
- 副本规则：刷怪点只有在 monsterArray 为空时才刷。监听器 start() 进关时存档。M64 死亡（destroy）→ start1 → 2 秒后在 (1450,310) 生成 M65 或 M66（各 50%）。

**10-1 sl101 地府枢纽（独有）**（固定镜头，无停止点）
- 监听器生成：4 个 TransferDoor(idx 0..3) 放在 x=[5,155,660,810]、y=5（插在 gameSence 第 0 层）；FinalTransferDoor（雕像）x=220（第 5 层）；M70 轮盘 @(450,423)；M71 石像 ×2 @(140,325)、(800,325)。
- 每帧：两个石像同时处于 isInBeattack()（同时在受击状态）时，读取 `轮盘.getDoorIdx()`：0..3 → 若该门 state==1 则 open()；4 → 移除轮盘，雕像 open()。
- keyBoardDownForW：碰到 state==3 的门 → curLevel = idx+2（10-2..10-5）；碰到雕像（其 colipse）→ curLevel=6。然后 isLevelClear=true，派发 "fbfbfbfb"。
- 10-2 五官王 M67（HP 280000）、10-3 卞城王 M69（HP 350000，会分裂，只有第一只是 isBoss）、10-4 泰山王 M73（HP 500000）、10-5 都市王 M72（HP 330000）、10-6 平等王 M77（HP 500000）；均为模式 B（4 秒后刷怪），单停止点 x≈921 / 890，镜头固定。

**11-1 sl111**（卷屏）：SP0 x=1064 → M79 x1（createMonster 对 79 做 +round(random)：50% 劈天斧 M79 HP 3000 / 50% 风神盾 M80 HP 30000）；SP1 x=1772 没有刷怪。刑天门固定在 (1433,200)。进关存档。

### 2.3 独有机制数量
有独有机制的场景：12、22、23、31、33、41、91、101、111（23 与 111 是 22 刑天门的简化复制）→ 9 个；共用模式：11/13/21/32/81（空监听器）、51/61/71/102～106（4 秒自动刷怪）。
**没有 SayInfo 对话/过场**：SayInfo 只是 HUD 里的文本框（RoleInfo 使用）。剧情只有 GameCartoon（开场 / 红孩儿副本 / 通关）。

---

## 3. 场景对象类

### 3.1 Wall（base/Wall.as）
字段 speedX/speedY/moveTime/userDataName。`isStatic()` = speedX==0 && speedY==0。step()：若有 userDataName，首次 new 该类的 MC 加到 gameSence，之后每帧对齐到墙的 x,y（墙本身在 release 版不可见，用 userData 作为贴图）。斜坡数学（equationX = tan(rot)、setYByRole）见 01 文档。

### 3.2 ObsWall（isWall，实体墙）
非静止时：x += speedX；若 speedY != 0 → 上下浮动：每帧 y += speedArray[i]，按下面的数组先向下走 23 帧、再向上走 23 帧（方向 1/2 交替）：
`[0.95,0.9,0.85,0.75,0.65,0.55,0.5,0.45,0.4,0.35,0.3,0.25,0.2,0.15,0.1,0.15,0.1,0.05,0,0,0,0,0]`（总位移 7.65 px，周期约 46 帧）。speedY 的初值只作为开关。
Boat 继承 ObsWall，另有 stopMove/continueMove（未被调用）。`孟婆障碍` 继承 ObsWall。

### 3.3 ThroughWall（isThroughWall，单向平台）
x += speedX；若 speedY ≠ 0：用 2 秒把 speedY Tween 到 0，然后反向（往复缓动）。本作只在 4-1 使用，且 speedY=0。

### 3.4 ThroughWallBullet（BOSS 生成的临时平台）
继承 ThroughWall，自己加 isThroughWall 子对象，visible=false，userData 按 speedX 方向翻转；英雄站上去时 isStop=true，0.5 秒 y+10（下沉）…（属于 BOSS 技能，细节见怪物文档）。

### 3.5 Thron（export/scene/Thron.as，子对象 isthron，地刺/落石）
每 5 帧检测一次英雄：|dx| < 80 时——若 isUp 且英雄在其宽度范围内（各边留 5px）→ gotoAndPlay(2)（开始坠落，坠落由时间轴设置 isfalling）；若 |dy| < 90 且像素碰撞 colipse → 击退 (10,10)，扣 30 HP，同一 attackId 只伤一次。
坠落：每帧 gravity++、y += gravity；y ≥ 500 时隐藏，y ≥ 1000 时复位到原位并换新 attackId。非 isUp 的地刺每 24 帧换一次 attackId（站在上面每秒受伤一次）。
**本作 22 个场景里都没有摆放 Thron**（保留给以后/其他作品用）。

### 3.6 白骨门（1-2）—— StageListener12
- 位置固定改为 (2270,336)；colipse 子对象的偏移随机：x ∈ ±200，y ∈ -20..-70。
- 帧 1 时：英雄 body.stick 碰到 colipse（hitTestObject），或英雄的子弹碰到 colipse，且该 attackId 是新的 → 播放 MonsterBeHurt1/2 特效，fbHitCount--（初值 3）。到 0 → gotoAndPlay(2)（开门动画，到 50 帧停）。
- 打开后：英雄 hitTestObject(enter) 时每帧 enterCount--（初值 120）；离开就重置为 120。减到 0 → "fbfbfbfb" → 5-1。

### 3.7 刑天门（2-2 / 2-3 / 11-1）—— StageListener22/23/111
- 门只对**背包（dj 或 zb 列表）里有 "yll"** 的英雄生效。门始终可见。
- 帧 1 时：colipse.hitTestObject(hero) 每帧 count--（每扇门初值 24，离开**不重置**）；到 0 → gotoAndPlay(2)。
- 播到最后一帧后：进入判定矩形 = enter 的 bounds，高度 /2，宽度 /5，中心放在 (门.x, 门.y-100)；与英雄 bounds 相交 → 消耗一个 yll → "fbfbfbfb" → 7-1。

### 3.8 FB81Pearl 宝珠（3-3）
5 点生命；每个**新的** attackId 命中扣 1（英雄 stick 用 hitTestObject，英雄子弹用 hitTest + 像素检测）；每次命中出 MonsterBeHurt 特效；生命到 0 → 20% 掉落 bsz 避水珠，1 秒淡出后移除。

### 3.9 TransferDoor / FinalTransferDoor（10-1）
TransferDoor：state 1 关闭 → open()：gotoAndStop(2)，state=2，0.65 秒后 state=3（可进入）。FinalTransferDoor：open() 播放 2..26 帧，1 秒后 state=3。

### 3.10 标记 MC（PhysicsWorld.addSubObj，release 版全部不可见）
isWall、isThroughWall（进 wallArray；转角 ≠0 的墙放到数组头部）、isTurnBack/noContinueGo（怪物 AI）、isTransferDoor（初始隐藏）、monsterDisapperaPoint（刷怪点）、isFb（副本入口：英雄 colipse 碰到 → 键盘销毁，1 秒淡出，"fbfbfbfb"；**本作没有场景使用**）、isBaiguDoor/isXingtianDoor/isPanguanFire/isHideWall（进 otherArray，由监听器处理）、stophere。

### 3.11 其他
- GOGO 提示：停止点清空且不是最后一个、且 idx < 4 时，加到 gameInfo (860,300)，缩放 0.7。
- 生成层级：怪物插在英雄下面一层；M52～M55、M60 插在 bgContainer 之上（在英雄后面）。
- BOSS 血条：isBoss 怪每帧调用 `gameInfo.addBossBlood(monsterName, 已损失%)`。
- BOSS 掉落：fallMoonCake → "xyb" 道具；dropStone 按关卡和最低英雄等级判定（例如 1-1 需 ≤4 级，1-2 ≤7，1-3 ≤10，…）。

---

## 4. 存档

- 后端：4399 云存档，`serviceHold.saveData(title, data, false, index)`。**玩家存档槽 0..5（6 个）**；槽 6 = 防多开 md5；槽 7 = "other" {openPig}。SharedObject "DreamWork_XYCS" 虽然打开了但没有使用。标题 = 英雄 roleName 拼接（为空时拒绝存档）。
- `MemoryClass.setStorage` 保存的字段：
  `playerNum, player1_obj, player2_obj, curBigStage, curBigLevel, gameScore{sl1_1..sl9_1}, dropRateCount, buffHpAddRateCount, gongxun, lastDate, monster60RewardTimes, zhuwei_1..3_times, moonCake{Atk,Def,Hp,Lucky,Mp}AddCount, guoqing{Atk,Def,HuiHuang}Count, hasGetZhuanyuanPresent2, hdInfo(逗号串), qhsInfo(逗号串)`。
- `User.getSaveObj`：`controlPlayer, lhValue, myscore, curExp, curLevel, roleid, tarray, propsArray, isstudyskill[5], ispassiveskill[5], bagSaveString(zb), curSaveString(已装备), bagdjSaveString(道具), bagrwSaveString(任务)`。读档时 curLevel > 75 → 重置为 33 级、0 经验（防作弊）。
- 读档：同一天则保留每日计数，日期变化则清零每日计数（monster60RewardTimes、zhuwei）。读档后直接进地图。
- **何时存档**：(1) 每次 LevelClear（任何关，包括隐藏关和通关漫画），存到 saveId；saveId == -1（新游戏还没存过）时弹出槽位选择面板（state "save"，已占用的槽要确认覆盖）。(2) 地图上的存档按钮（冷却 30 秒）。(3) 进入 9-1 / 11-1 时。(4) M60 每日奖励、商城、活动。
- 重制版至少需要：进度（curBigStage/curBigLevel）、角色等级/经验、装备/背包、学会的技能、功勋、各关最高分、每日计数 + 日期；多槽位（6 个）；“过关自动存档 + 新档首次过关选槽”的行为。隐藏关的道具钥匙（yll/bsz）存在背包里。

---

## 5. 疑似原作 bug / 怪癖（重制版需决定是否复刻）
1. 场景里 StopPoint 实例的属性被忽略（§0）。sl13 的 brl 940 和 sl33 的 960 从未生效。
2. 2-2 判官的限时在判官死后仍在计时：BOSS 死后一直不进传送门，开战约 94 秒后会被判 GameOver。离开关卡时 destroyGame 的 `TweenMax.killAll` 会取消这个延迟调用。另外 start1 用 otherArray 的下标去取目标坐标（恰好火焰排在前 6 个）；`fireArray.sortOn("x")` 排序时所有火焰都在同一个 x，所以熄灭顺序实际是插入顺序。
3. 刑天门监听器 22/23/111 取玩家时用了内层（门）循环的下标：P1 没有 yll 时，P2 的检查会再次用到 P1。仅 2P 受影响。
4. 白骨门 enterCount 会被不在门里的另一名英雄重置 → 2P 时两人必须同时站在门里。
5. FB81Pearl：子弹命中时记录的是英雄的 attackId 而不是子弹的。
6. GameWin：时间分 `(300+t)/(t*50)` 几乎总是 0；“状态%”在 2P 时把 hero1 的数值加了两次；暂停时间只扣最后一次暂停（而且可能是上一关的）。
7. ObsWall 浮动在方向 2→1 切换的那一帧会两个分支都执行（跳过一个数组项，导致轻微的不对称/漂移）。
8. 竞技场按钮不从地图上移除自己，也不设置关卡（使用上一次的 curStage/curLevel）。
9. 地图上 s4_2/s4_3 存在但永远不会解锁；6-1 和 10-x 的按钮没有任何进度门槛。
10. 11-1 的入口是活动面板（国庆版），不在主流程里；重制版同样放在「活动」面板。
11. 调试模式（!isHideDebug）下，每个刷怪点在 touch 1 秒后 totalNum 会被改成 1（release 版不影响）。
12. SL101 中的 `getCurIdx() <= 4` 恒为真。
13. 3-1 的极光放在屏幕坐标 (1000,600)（屏幕外右下角），靠它自己的时间轴动画飞进画面。
