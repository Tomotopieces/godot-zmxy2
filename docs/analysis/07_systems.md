# 原作分析 07：成长与外围系统（技能学习 / 法宝 / 强化合成 / 时装翅膀 / 道具 / 商城 / 菜单）

范围：只做孙悟空（Role1）、单人。源码：`decomp/res/zmxy2_game/scripts`（逻辑），UI 元件类所在 SWF 见每节「美术」。
单位：帧（24fps）。`lh` = `User.protectedObject.lhValue` = **灵魂**（游戏内唯一的通用货币）。
物品基础数据（名称/品质/属性/强化增量 aStrengthen/外观 showid）已在 `tools/data/equipment.json`，本文只引用 id。

---

## 0. 货币与存档字段

### 0.1 灵魂 lh 的来源（全部）
| 来源 | 数值 | 代码 |
|---|---|---|
| 怪物死亡红色光球 auraRed | 每颗 +`monster.protectedParamsObject.gxp`，每只怪 2~4 颗（`2+floor(rand*3)`），需怪物有 curAttackTarget | BaseMonster.dropAura / aura/auraRed → AuraEvent[3] |
| 出售（背包「卖」bmd） | +`int(item.value)`：粗糙10 / 普通20 / 优秀40 / 精良80 / 史诗160 / 传说320 | PackThings.mdClick, MyEquipObj.transValue |
| 活动礼包 ZMPresent2025 | 100/500/2000/5000（4399 兑换码，范围外） | huodong |
lh 同时累加到 `myscore`（积分，仅用于 4399 排行，范围外）。

> **勘误（03 文档 / monsters.json）**：`gxp` 不是怒气，是**每颗红球给的灵魂**。AuraEvent 数组为 `[hero, +HP, +MP, +lh, +怒气]`：
> 绿球 auraGreen=+HP（`max(10, int(maxHP/20))`），蓝球 auraBlue=+MP（`max(10,int(maxMP/20))`），
> 红球 auraRed=+lh(gxp)，**白球 auraWhile=+5 怒气**（wsValue）。绿/蓝/白各自 4%→3 颗、8%→2 颗、12%→1 颗（累积判定，即 4%/4%/4%）。

### 0.2 功勋 gongxun（Config.gongxun，全局，存档）
只用于商城（§6）。来源：Monster60（4-1 BOSS）死亡 +50（`monster60Reward`），**每天 1 次**（`MONSTER60_PER_DAY_TIMES=1`，按存档 lastDate 重置）；其余来自 4399 活动（范围外）。

### 0.3 User 存档字段（user/User.getSaveObj）
`lhValue, myscore, curExp, curLevel(>75 读档重置为 33), roleid, isstudyskill[5], ispassiveskill[5], propsArray, tarray,`
`bagSaveString(zblist 装备/法宝), bagdjSaveString(djlist 道具/强化石), bagrwSaveString(rwlist 时装/翅膀), curSaveString(curarray 已装备)`。
单件物品序列化：`MyEquipObj.getEquipSaveObj()` 35 个字段用 `|` 连接（含 eprob 五行、changeObj{elevel,eupdata,num}、strengthValue、pskillobj）。
Config 全局另存：buff 计时器（§5）、gongxun、monster60RewardTimes、qhsInfo（强化日志，可忽略）。
已装备槽（curarray，每类 1 件）：`zbwq 武器, zbfj 衣服, zbsp 饰品, zbfb 法宝, zbsz 时装, zbcb 翅膀`。

---

## 1. 技能学习（主动 5 个 + 被动 5 个）

入口：关卡内 HUD `RoleInfo.btn_study` 或 **V 键(86)** → 事件 `showBuySkill{state:"gameing"}`（暂停游戏）；地图 `SelectPLace.showBuySkill`（state "maping"）。
C 键(67)=背包。面板：`BuySkill`（选人，单人只显示 player1=悟空）→ `SkillControl(role)`：`activebtn`/`passivebtn` 两页，`txtlh` 显示灵魂。
**没有等级要求，没有升级，没有冷却**——主动技能只有「学会/未学」，一次性花费灵魂。

### 1.1 主动技能（User.isstudyskill[i]，0/1）
| i | UI 槽 | 按键（RoleInfo 提示 r1skillbtn） | 动作 | 学习价 lh | MP | 伤害（Role1.getRealPower，×变身1.5 ×暴击2） | 击退 / 多段 |
|---|---|---|---|---|---|---|---|
| 0 | skill1 | W+J（"WJ"） | hit8 升龙斩 | 100 | 10 | 2.0×攻 | [2,-22]，间隔2，最多100 |
| 1 | skill2 | 双击方向跑动+J（"DDJ"） | hit6 火炎突击 | 200 | 20 | round(0.5×攻) | [35,-2]，间隔5 |
| 2 | skill3 | U | hit7 烈焰闪 | 500 | 30 | **固定 100**（不随攻击成长） | [0,-2]，无敌12帧 |
| 3 | skill4 | I | hit9 烈焰风暴 | 1000 | 40 | round(1.2×攻) | [20,-2]，间隔2 |
| 4 | skill5 | O | hit10 火魔斩 | 2000 | 50 | hit10-1 1×攻；hit10-3 1×攻；hit10-2 3×攻 | 无敌75帧 |
- 未学：按键无反应；W+J 未学时不执行（"0101" 直接 return）；跑动+J 未学时退化为普攻。MP 不足：W+J/跑动J 退化为普攻，U/I/O 无反应。
- 所有技能伤害类型 `magic`（受怪物魔抗），普攻 physics。L 键（showSkillL）对悟空为空。空格=变身（怒气满 100）。
- 学习后 HUD `RoleInfo.skillN` 跳到帧 N+1（悟空图标帧 2..6；帧1=未学空槽），鼠标悬停显示按键提示（SayInfo）。
- 调试模式（!isHideDebug）默认全学会 [1,1,1,1,1]。新档全 0。

### 1.2 被动技能（User.ispassiveskill[i]，等级 0..5）
UI：`SkillControl` 被动页，`instrmc` 帧4 内 5 个 `PassiveSkill`（实例名 pskill1..5，帧号=类型），字段 `curslevel/wantlh/lastvalue/attvalue/btn`。
- 升到 n 级（当前 n-1）花费 **n×5000 lh**（1→5 级合计 75000）。满 5 级隐藏按钮。
- 第 n 级（n≥1）效果（BaseRoleProperies.analyPassive，替换上一级的值，不叠加）：

| i | 名称 | 第 n 级加成 | Lv1 / Lv5 |
|---|---|---|---|
| 0 | 生命上限 | maxHP + (100n+100) | +200 / +600 |
| 1 | 魔法上限 | maxMP + (100n+100) | +200 / +600 |
| 2 | 暴击率 | crit + (n+1)% | +2% / +6% |
| 3 | 每秒回血 | hpRegen + (n+1) /24帧 | +2 / +6 |
| 4 | 每秒回魔 | mpRegen + (n+1) /24帧 | +2 / +6 |
回复每 24 帧结算一次（BaseRoleProperies.step：tcount≥24 → HP+=selfhp, MP+=selfmp）。

美术（OtherMat_v10）：BuySkill=symbol361，SkillControl=symbol706，PassiveSkill=symbol600，技能背景 `OtherMat_fla/技能背景_33`、技能说明 `技能說明_34`、`悟空_27`（instrmc 帧"孙悟空"）、`按鍵_40`；HUD RoleInfo=symbol339。

---

## 2. 法宝（zbfb，H 键 = sendSkill(5)）

### 2.1 获得：只能合成（§3.3），无掉落、无商店
| id | 名称 | 品质 | 合成材料（各 1，1000 lh，100%） | 成长率 eupdata 范围（toFixed(1)） | 技能 |
|---|---|---|---|---|---|
| dshl | 地煞葫芦 | 精良 | dslj+dsyj+dsqz | 0.5~1.0 | 烈火咒：前方火焰 |
| tsgj | 天煞古剑 | 史诗 | tsgl+tsyp+tsyj | 0.6~1.2 | 御剑飞行：飞剑，可站立 |
| bsj | 白霜镜 | 史诗 | bsxj+bszj+bsyz | 0.7~1.4 | 邪灵寄生：吸血 15 秒后回血 |
| lsys | 罗刹妖伞 | 史诗 | lcgy+lcld+lczh | 0.8~1.6 | 暴雨梨花：8 根毒刺 |
| xhmt | 血海魔童 | 史诗 | xhyk+xhxh+xhmj | 1.0~1.8 | 魔童连击：多次攻击 |
| wds | 五毒兽 | 传说 | mzyj+szyj+dcyj（dcyj=xzyj+zzyj+gzyj 合成） | 1.2~2.0 | 自动攻击 + 雷/火咒 |
- 合成出的法宝：`elevel=1`；属性 hp/mp/atk/def = 3 件材料各自（基础+强化加成）之和 `int(/3)`；**wds 固定** hp250 mp250 atk50 def25。
- 五行 eprob（initRondomPro）：91% 单属性，9% 双属性（第二个从剩余 4 个里 `round(rand*3)` 取）。索引用 `round(rand*4)` → 金 12.5% / 木 25% / 水 25% / 火 25% / 土 12.5%（非等概率）。
- wds 额外：`pskill = 1+round(rand*4)`（被动，见 2.5），`whichskill = round(rand)`（0 雷 / 1 火）。
- 装备：背包法宝槽 zbfb，属性像普通装备一样加到角色（addEquip）。装备后英雄身边生成法宝 MC，每 12 帧用 1 秒 Tween 跟随到 (hero.x±60, hero.y-50)（面朝方向前方）。

### 2.2 使用规则（BaseMagicWeapon）
- H 键：`if(!curMagicWeapon.isUsing()) doHit1()`。**可在任何状态释放**（攻击中、受击中、空中都行）。
- MP 消耗 = **30 + 10×elevel**（Lv1 40 … Lv10 130），MP 不足不释放。
- **无冷却计时**：isUsing=true 期间不能再放，动画/行为结束 hitOver() 后立即可再放（下表「占用时长」即实际冷却）。
- 伤害类型全部 magic，命中参数见 Role1.attackBackInfoDict["fabao-*"]（击退 [2,-2]）。
- 「木」属性（getWX 含"木"）：技能伤害 ×(1.5~2.0)（wds hit2 为 ×(1.2~1.5)）；非木多为 ×(0.9~1.1) 浮动。

| 法宝 | 行为 | 伤害 | 占用时长 |
|---|---|---|---|
| dshl 葫芦 | 动画 hit1（元件10_87）帧3 在法宝位置生成 SpecialEffectBullet "CucurbitFire"，帧14 结束 | 300+50L ±10（hitMaxCount 1：每目标 1 次） | 14 帧 |
| tsgj 古剑 | 法宝隐身；在英雄位置生成 ThroughWallBullet（单向平台，贴图 MagicUmbrellaHit1）+ 跟随特效 "SwordEffect"（造成伤害）。初速 ±18（面朝方向），每帧向回减速 0.5 → **回旋镖**。英雄站上去：停住（下沉10再上浮4），伤害特效消失，变成可站平台，最多 6 秒（144 帧）；总寿命 8 秒（192 帧） | 200+30L ±10，hitMaxCount 99 | 至平台销毁（≤192 帧） |
| bsj 镜 | 飞向最近的非无敌怪（排除 Monster52/53/54/55/57/60/78；无目标不消耗 MP），速度 5 起每帧+1 最大15；附身后每 24 帧扣怪 `(0.3+0.2L)% × 英雄最大HP` 并累计，共 360 帧（15 次）或怪死；然后飞回英雄，`cureHp(累计值)` | 每秒 (0.3+0.2L)%×maxHP（不受防御） | 飞行+360 帧+返回 |
| lsys 伞 | Tween 1 秒（24 帧）升到英雄上方 300px，播放 hit1（元件17_65）帧7 生成 8 根 StabBullet "umbrellaStab"（x=伞x+(i-4)×25，射向 伞x+(i-4)×80, y+300），帧29 结束 | 每根命中 10 + 附加中毒：每 24 帧扣 `50+15L×(0.9~1.1)`（木 ×1.5~2.0），持续 240 帧（10 跳）。（描述写减速，代码无减速） | 24+29=53 帧 |
| xhmt 魔童 | 先解除英雄所有 debuff（cureDebuff）；begin 动画 15 帧 → setTarget：取 monsterArray 中第一个非无敌怪（排除 57/60/70），0.5 秒 Tween 到其身侧 30px，播放 hit1（35 帧，帧3/12/28 各发射 MagicPearlBullet1/2/3）→ 再 setTarget，直到攻击次数达 `int(3+L/3)` 或无目标 | 每发 0.05×L×攻（±10%） | ≈15+次数×(12+35) 帧 |
| wds 五毒兽 | 见 2.5 | | |
- 「木」魔童设计上 +2 次攻击，但代码判断 `getWX()=="木"` 而 getWX 返回 "木 "（带空格）→ **原作永不生效**（重制可修正或保留）。

### 2.3 法宝升级（SutraInterface，HUD `RoleInfo.btn_fb`，需已装备法宝；打开时暂停）
- 当前等级 L → L+1 花费 **L²×1000 lh**（1→2: 1000，… 9→10: 81000），**最高 10 级**。按钮 `btn_sj`。
- 每升 1 级 growth(f)（f=getGrowthByName）：
  `atk += floor(fatk×eupdata) + (金 ? fatk : 0)`；`mp += floor(fmp×eupdata) + (水 ? fmp:0)`；`hp += floor(fhp×eupdata) + (火 ? fhp:0)`；`def += floor(fdef×eupdata) + (土 ? fdef:0)`；木无属性加成（只加技能伤害）。

| id | fhp | fmp | fatk | fdef |
|---|---|---|---|---|
| dshl | 20 | 20 | 4 | 2 |
| tsgj | 30 | 30 | 5 | 2 |
| bsj | 30 | 50 | 5 | 2 |
| lsys | 50 | 30 | 5 | 4 |
| xhmt | 30 | 30 | 9 | 2 |
| wds | 50 | 50 | 10 | 5 |
- 升级在克隆体上进行，**关闭面板时**才 removeEquip(旧)/addEquip(新) 生效。
- 面板字段：txt_fbname 名称 / txt_fbdj 等级 / txt_fbczl 成长率 / txt_fbwx 五行 / txt_fbatk / txt_fbdef / txt_fbhx(hp) / txt_fbhl(mp) / txt_fblh「lh/下一级需求」；`lhmc` 进度条 50 帧（backpack_fla/法宝升级经验_75），帧 = int(lh/(需求+1)×50)；`showmc`/`introducemc` 按 ename 帧标签显示法宝图与说明；wds 时 introducemc.skill1/txt1（主动咒）、skill2/txt2（被动）。

### 2.4 五行小结（getWX，显示为 "金 木 " 这样的串）
| 元素 | 效果 |
|---|---|
| 金 jin | 升级时 atk 额外 +fatk |
| 木 mu | 法宝技能伤害 ×1.5~2.0（wds ×1.2~1.5），伞中毒同 |
| 水 shui | 升级时 mp 额外 +fmp |
| 火 huo | 升级时 hp 额外 +fhp |
| 土 tu | 升级时 def 额外 +fdef |

### 2.5 五毒兽 wds
- **自动攻击**（不耗 MP，但要求 MP 足够 30+10L 才触发）：首次 72 帧后，之后每 72 帧，若场上有怪且未在使用：hit1（元件32_110，22 帧）帧7 向随机怪发射 EnemyMoveBullet "WuDuBullet1"（初速=方向×3，每帧加速 方向×1，射程 1500），伤害 = 1.0×攻（目标为 Monster70 时不发）。
- **主动 H**（耗 MP）：
  - 未强化：飞向随机怪侧面 40px（0.5 秒），播 hit2-1（元件35_111，45 帧），帧5 生成：whichskill0 → "WuDuBullet2_1" 初级雷咒（0.25×L×攻），whichskill1 → "WuDuBullet2_3" 初级火咒（0.3×L×攻，偏移 40/40）。场上无怪不能放。
  - 已强化（五毒丹 wdd 使用后 `pskillobj.isstrskill=true`，永久）：原地播 hit2-2（元件36_112，60 帧），帧10 在屏幕中心生成全屏咒：雷 "WuDuBullet2_2"（0.3×L×攻，屏幕(480,235)）/ 火 "WuDuBullet2_4"（0.6×L×攻，y=500）。无怪也能放。
- 被动 pskill（装备时加到属性）：1 狂暴 crit+2~5%；2 嗜血 吸血+2~5%；3 顽固 魔抗+2~5%；4 永恒 回血+2~5/秒；5 辉煌 回魔+2~5/秒。

美术：法宝 MC 类在 **Common_v7**：Cucurbit=symbol349，Sword=symbol320，Mirror=symbol312，MagicUmbrella=symbol446，MagicPearl=symbol408，WuDu=symbol194（帧标签 walk / hit1 / begin / back / hit2-1 / hit2-2）；特效类 CucurbitFire、SwordEffect、MagicUmbrellaHit1、umbrellaStab、MirrorBloodEffect、MagicPearlBullet1~3、MagicPearlLight、WuDuBullet1、WuDuBullet2_1~4、poisonHead/poisonUp（Common_v7 根目录）。SutraInterface=backpack_v5 symbol564。

---

## 3. 炼丹炉：强化 + 合成（StrengthEquip → StrengthPack）

入口：仅地图 `SelectPLace.ldl`（事件 showStrengthEquip{state:"maping"}）。StrengthPack 两页 `strengthbtn`(Strength) / `mixturebtn`(Fusion)，右侧 5×5 背包格（`btn_zb` 装备 zblist / `btn_dj` 道具 djlist / `btn_sz` 时装 rwlist），点击格子把物品放入槽位（事件 SimpleClick）。`txtlh` 灵魂。

### 3.1 强化 Strength（槽：zbmc 装备，qhmc1~3 强化石，luckmc 幸运符，baodimc 保底符，按钮 qhbtn，txt_success 成功率）
- 可强化：zbwq / zbfj / zbsp / zbcb（翅膀）。**法宝、时装不可强化**。强化**不花灵魂**（txt_needlh 未使用）。
- 成功率 = Σ(每块石头按 石头等级×当前强化等级 查表)，上限 1；放幸运符再 ×1.25（上限 1）。

| 石头 \ 当前+N | +0 | +1 | +2 | +3 | +4 | +5 | +6 | ≥+7 |
|---|---|---|---|---|---|---|---|---|
| wpqhs1 1级 | 37.5% | 9.37% | 2.34% | 0.58% | 0 | 0 | 0 | 0 |
| wpqhs2 2级 | 100% | 37.5% | 9.37% | 2.34% | 0.58% | 0 | 0 | 0 |
| wpqhs3 3级 | 100% | 100% | 37.5% | 9.37% | 2.34% | 0.58% | 0 | 0 |
| wpqhs4 4级 | 100% | 100% | 100% | 37.5% | 9.37% | 2.34% | 0.58% | 0 |
| wpqhs5 5级 | 0（getStrengthNumber 没有 case 5，原作 bug：5 级石无用） |||||||
  ⇒ 实际上限 **+7**。
- 结算：`rand < 成功率` → strengthValue+1「强化成功」；否则「强化失败」，若当前 ≥+3 且**未放保底符** → -1。
- 无论成败：所有放入的石头、幸运符、保底符**全部消耗**；装备退回背包。
- 效果：每 +1 级按该装备 `aStrengthen`（equipment.json 的 strengthen）累加：`satk=N×att, sdef=N×def, shp=N×hp, smp=N×mp, scrit=N×crit, smiss=N×miss, sehp=N×ehp, semp=N×emp, smdef=N×mdef, sebol=N×ebol, sdhit=N×dhit`；装备时与基础属性一起加到角色。aStrengthen 为空 {} 的装备强化无属性收益。

### 3.2 强化石 / 符 来源
| id | 来源 |
|---|---|
| wpqhs1 | BOSS 死亡（dropStone）：当玩家等级 ≤ 该关上限时，以 `stoneFallRate×(1+时装加成)×(双倍2)×(芒果月饼1.5)` 掉落。等级上限：1-1≤4, 1-2≤7, 1-3≤10, 2-1≤13, 2-2≤16, 2-3≤19, 3-1≤22, 3-2≤25, 3-3≤28, 5-1/6-1 <28, 4-1/7-1/11-1 无限制，其他关不掉。另：部分 BOSS fallList 含 wpqhs1。商店 30 |
| wpqhs2/3/4 | 合成 3 个低一级 → 1 个高一级，75%，不耗灵魂；wpqhs3/4 商店 270/700 |
| wpqhs5 | 合成表没有 4→5，商店不卖 → 实际不可得（且无用） |
| wpxyf 幸运符 / wpbdf 保底符 | 仅商店 300 / 500 |

### 3.3 合成 Fusion（槽 material1~3，produce 产物，preview 预览，rlbtn 合成，btn_help → FusionHelp；txt_name/txt_needlh/txt_success）
配方（AllEquipment.mixProduce，3 件无序）：
| 产物 | 材料 | 消耗 | 成功率 |
|---|---|---|---|
| dshl/tsgj/bsj/lsys/xhmt/wds 法宝 | 见 §2.1 | 1000 lh | 100% |
| ssc 三生锤（八戒武器） | qssp 前生碎片 + jssp 今生碎片 + lssp 来生碎片 | 1000 | 100% |
| gwj 鬼王剑（悟空武器） | fygwj 封印鬼王剑 + yzfw 阳之符文 + yinzfw 阴之符文 | 1000 | 100% |
| qcp 七彩袍（唐僧衣） | hshb 红 + lshb 绿 + zshb 紫色花瓣 | 1000 | 100% |
| dzjj 地藏金戒（饰品） | dzj 地藏戒 + 任意两件 {t 贪, c 嗔, ch 痴}（可重复） | 1000 | 100% |
| bszj 白霜重甲 | bsxj ×3 | 1000 | 100% |
| bsyz 白霜妖杖 | bszj ×3 | 1000 | 100% |
| bsxj 白霜胸甲 | bsyz ×3 | 1000 | 100% |
| dcyj 毒虫印记 | xzyj 蝎 + zzyj 蛛 + gzyj 蚣之印记 | 1000 | 100% |
| wpqhs2/3/4 | 3×低一级强化石 | 0 | 75%（失败材料也消耗） |
- 产物属性：ssc/gwj/qcp 取模板新随机值；dzjj = 3 件材料**模板**属性（hp/mp/atk/def/crit/miss/回血/回魔/魔抗）之和；法宝见 §2.1；其余（白霜系、dcyj）走 getSutraValue = 材料 hp/mp/atk/def 平均。
- 灵魂不足提示「灵魂值不够」。产物放 produce 槽，点击取回背包。
- 贪/嗔/痴（t/c/ch）本身是 zbwp 道具但带属性（不可装备，只作材料）。

美术（OtherMat_v10）：StrengthEquip=symbol707，StrengthPack=symbol587，Strength=symbol730，Fusion=symbol217，FusionHelp=symbol188；格子 PackThings=backpack_v5 symbol598。物品图标 `AUtils.getImageObj(fillName)`（位图类名=物品 id），地面掉落 MC = `fall_{id}`（Common_v7 / OtherMat_v10）。

---

## 4. 时装 zbsz / 翅膀 zbcb（背包「时装」页 btn_rw = rwlist）

### 4.1 时装（只换外观 + 掉落率，无属性；悟空可用的为 wk*）
外观：`getEquipNum().zbfj = 时装.showid>1 ? 时装.showid : 衣服.showid` → 英雄衣服帧（Role_v6 身体部件 `gotoAndPlay(getCurClothId())`）。
| id | 名称 | showid | 掉落加成 getCurFashionEquipFallThingProbability | 获得 / 价格 |
|---|---|---|---|---|
| wkmrz | 悟空黄头装 | 7 | 0 | 商店 800 |
| wkwdg | 悟空西装 | 8 | +10% | 商店 800 |
| wkbsz | 悟空红头装 | 9 | +18% | 商店 870 |
| wkzyf | 悟空状元服 | 10 | +20% | 商店 900 |
| jwkwdg | 绝·悟空西装 | 11 | 0（代码只匹配 wkwdg，"绝"版无效） | 活动限定（范围外） |
| jwkzyf | 绝·悟空状元服 | 12 | 0（同上） | 活动限定 |
- 加成用法（BaseMonster.fallEquip）：装备掉落率 `p = probability ×(双倍爆率 2)×(芒果月饼 1.5)×1.5 ×(1+时装加成)`；强化石掉率同样 ×(1+时装加成)。
- 读档时 zblist/djlist 中的 wkmrz 与 sbbl 会被删除（防刷），rwlist 不受影响。时装不可强化、不可出售（bmd 禁用）。

### 4.2 翅膀
外观：英雄 body 内子 MC `chibang.gotoAndStop(翅膀.showid)`（1=无）。getWingId 中 showid 3 映射为 21（另一套资源帧）。
| id | 名称 | showid | 属性 | aStrengthen（每+1） | 获得 |
|---|---|---|---|---|---|
| xtzy | 刑天之翼 | 2 | crit+1%, miss+1%, 回血+1 | crit .01, miss .01, ehp 1 | Monster81（第 7 大关 BOSS 刑天）掉落，probability 0.1 |
| ttzy | 天庭之翼 | 3 | crit+1%, miss+1%, 回魔+1 | crit .01, miss .01, emp 1 | 商店 800 |
可强化（§3.1）。

---

## 5. 道具 zbwp（djlist）

### 5.1 可使用道具（背包道具页点击 → simplebtn：buse 使用 / bthrow 丢弃）
计时单位：帧，**86400 帧 = 1 小时游戏内时间**（HeroBuff.step 每帧 -1，只在关卡中走；存档保存剩余值）。重复使用 = 重置为 86400（不叠加）。
HUD：`HeroBuff`（GameInfo 内）每个 buff 一行：图标位图缩放 0.3 + 红色 20 号 "时:分:秒"，行距 30px。
| id | 名称 | 效果 | 计时器 / 图标 | 获得 |
|---|---|---|---|---|
| sbbl | 双倍爆率 | 装备与强化石掉率 ×2 | dropRateCount / sbbl_buff | 商店 600 |
| xique | 幸运的喜鹊 | 同 sbbl（共享计时器） | dropRateCount | Monster66（第 9 关）掉落 100% |
| jxbuff | 顽固的水牛 | 最大 HP ×1.5（getSHHP），装/卸装备时 HP 增减也 ×1.5 | buffHpAddRateCount / hn_buff | Monster65（第 9 关）掉落 100% |
| hhbuff | 辉煌 | 每秒回魔 +10 | guoqingHuiHuangCount / hh_guoqing_buff | 商店 250 |
| jxdyb | 玫瑰月饼 | 最大 HP +600 | moonCakeHpAddCount / buff_moon_hp | 中秋活动（小月饼兑换） |
| jmdyb | 蓝莓月饼 | 最大 MP +600 | moonCakeMpAddCount / buff_moon_mp | 同上 |
| jgjdyb | 绿橘月饼 | 攻击 +100 | moonCakeAtkAddCount / buff_moon_atk | 同上 |
| jfydyb | 坚果月饼 | 防御 +50 | moonCakeDefAddCount / buff_moon_def | 同上 |
| jbldyb | 芒果月饼 | 装备/强化石掉率 ×1.5 | moonCakeLuckyCount / buff_moon_lucky | 同上 |
| wdd | 五毒丹 | 已装备 wds 时永久强化其主动技（§2.5）；未装备 wds 或已强化则不消耗（提示「您没有装备五毒兽」/「已经强化」） | — | 商店 500 |
- 另有国庆 buff guoqingAtkCount（攻+100）/ guoqingDefCount（防+50），由击杀 11-1 的劈天斧 / 风神盾获得，无道具。**重制版已实现**（`rules.kill_buffs`，持续 1 小时，可与大月饼叠加）。
- 其余道具「使用」按钮置灰。小月饼 xyb：专用按钮 zqsimplebtn——10 个换随机一种大月饼、100 个换中秋武器（悟空 nyd 凝月刀）。小月饼掉落函数 fallMoonCake 在反编译代码里**从未被调用**；按 4399 官方文章（2011-09）「每关 BOSS 100% 掉小月饼」补上。**重制版已实现**：每个 BOSS 单位死亡掉 1 个（`Loot.drop`），背包兑换菜单 `item_menu_zq`（`GameState.exchange_moon_cake`），大月饼 buff 与国庆 buff 都可叠加（`buff_sum / buff_mul`）。

### 5.2 任务 / 材料道具（不可使用）
| id | 名称 | 来源（库目录=大关；probability 为怪物基础掉率，实际再 ×1.5 等） | 用途 |
|---|---|---|---|
| qssp / jssp / lssp | 前生/今生/来生碎片（三生石） | Monster41 / Monster44 / Monster42（第 3 大关小怪，p 0.1/0.02/0.07，fallList 随机一件） | 合成 ssc 三生锤 |
| fygwj | 封印鬼王剑 | Monster40（第 2 大关 BOSS，p 0.25） | + 阴阳符文合成 gwj 鬼王剑（悟空武器，攻 60~74，吸血5%） |
| yzfw / yinzfw | 阳之/阴之符文 | Monster41 / Monster43（第 3 大关） | 同上 |
| hshb / lshb / zshb | 红/绿/紫色花瓣（彼岸花） | Monster43 / Monster42 / Monster44（第 3 大关） | 合成 qcp 七彩袍（唐僧用，对悟空只能卖） |
| t / c / ch | 贪 / 嗔 / 痴 | Monster63（第 8 大关，p 0.08） | dzj + 两件 → dzjj 地藏金戒 |
| dzj | 地藏戒（饰品，可装备） | Monster61（第 8 大关 BOSS，p 0.1） | 同上 |
| szyj / xzyj / zzyj / gzyj / mzyj | 蛇/蝎/蛛/蚣/蟾之印记 | Monster67 / Monster69 / Monster72 / Monster77(专属判定) / Monster73~76（第 10 大关，p 0.1~0.15） | xzyj+zzyj+gzyj → dcyj；mzyj+szyj+dcyj → wds 五毒兽 |
| dcyj | 毒虫印记 | 合成 | 合成 wds |
| yll | 阎罗令 | Monster53/54/55（p 见各类） | 2-2、2-3、11-1：持有阎罗令时与刑天门（xingtianDoor 的 colipse）重叠累计 24 帧 → 门播放开门动画；开完后进入门的 enter 区域 → **消耗 1 个**，事件 "fbfbfbfb" 进入刑天副本 |
| bsz | 避水珠 | 3-3 场景物件 FB81Pearl 被打碎 20% 掉落 | 3-1 中触碰 AuroraLight 时**消耗 1 个** → 事件 "fbfbfbfb" 开启忘川河底副本（StageListener31.start2） |
| csgs | 苍生挂饰（饰品） | Monster45（第 5 大关 BOSS） | 装备后死亡时复活一次：无敌 24 帧，HP/MP 恢复一半，**挂饰被消耗**（y≥1200 掉坑不触发） |
（关卡机关细节归 04 关卡文档；这里只给物品侧规则。）

美术：背包 BackPack=backpack_v5 symbol446（槽 zbwq/zbsp/zbfj/zbfb/zbsz/zbcb，tab btn_zb/btn_dj/btn_rw，文本 txt_hp/mp/att/def/baoji/sb(闪避)/hx/hl/lh/zg(功勋)/exp），操作菜单 threebtn（bzb 装备 / bgy 给予(单人置灰) / bmd 卖）、simplebtn（buse/bthrow）、zqsimplebtn；buff 图标位图类 sbbl_buff、hn_buff、buff_moon_*、atk/def/hh_guoqing_buff（zmxy2_game 根目录）。

---

## 6. 商城 Micropayment（地图 `SelectPLace.scgm` → showShoping）

- 价格单位「点券」（4399 充值币，`GMain.serviceHold.decMoney_As3`）；**点券不足部分自动用功勋 gongxun 抵扣**（ShopThing.getAllHuobi = 点券 + 功勋）。充值按钮 btn_cz 已关闭（"充值已关闭，功勋可以通过活动获得"）。
  ⇒ 重制版：**只用功勋购买**，价格 = findSellPrice。
- 页签：btn_buyzb「全部」（道具+个性）/ btn_buydj「道具」/ btn_buygx「个性」；每页 6 格 st0~st5（ShopThing：txt_name 品质色、txt_price、txt_num + btn_up/btn_down 数量、btn_buy）；确认框 SumInterface（btn_ok / btn_change）。买到：时装/翅膀 → rwlist，其他 → djlist（同名叠加）。
| 页 | id | 价格(功勋) |
|---|---|---|
| 道具 | hhbuff 辉煌 | 250 |
| 道具 | wdd 五毒丹 | 500 |
| 道具 | wpqhs4 4级强化石 | 700 |
| 道具 | wpqhs1 1级强化石 | 30 |
| 道具 | wpqhs3 3级强化石 | 270 |
| 道具 | sbbl 双倍爆率 | 600 |
| 道具 | wpxyf 幸运符 | 300 |
| 道具 | wpbdf 保底符 | 500 |
| 个性 | ttzy 天庭之翼 | 800 |
| 个性 | wkmrz 黄头装 | 800 |
| 个性 | wkbsz 红头装 | 870 |
| 个性 | wkzyf 状元服 | 900 |
| 个性 | wkwdg 西装 | 800 |
（唐僧/八戒时装同价，单人悟空版只列出悟空的。findSellPrice 中 wpqhs2 价格为 0 但不在货架上。）
美术（backpack_v5）：Micropayment=symbol840，ShopThing=symbol622，SumInterface=symbol594，人物 personmc（商场人物sc_29）。

---

## 7. 菜单 / 设置 / 帮助

### 7.1 关卡内 HUD（RoleInfo，OtherMat_v10 symbol339）
hpline/mpline/expline（各 101 帧，帧 = round(100×(1-当前/最大))+1），txthp/txtmp/txtexp/txtlevel，wsmc 怒气（帧=wsValue 0..100，满 100 时 shows 帧2 提示可变身；未满每 24 帧 -1），head 头像（帧标签=roleName），skill1~5 技能图标，按钮：
`btn_bb` 背包（=C 键），`btn_study` 技能（=V 键），`btn_fb` 法宝升级，`btn_set` 设置。角色死亡时背包/法宝按钮提示「您的角色已经死亡」。

### 7.2 设置/暂停 SetMenu（btn_set；OtherMat_v10 symbol184）
打开即 `MainGame.stopGame()`（暂停）。**没有键盘暂停键**。
| 按钮 | 功能 |
|---|---|
| btn_continue / btn_x | 继续游戏 |
| btn_back_selectmap | 结束本关回地图（不结算） |
| btn_back_menu | 回主菜单 |
| btn_help | 打开帮助（事件 GameHelp） |
| btn_sound_open / btn_sound_close | 声音开关（SoundManager.controlSound，二者互斥显示） |

### 7.3 帮助 Help（OtherMat_v10 symbol733）
纯图片说明页 + btnback 关闭。

### 7.4 主菜单 GameMenu（OtherMat_v10 symbol153，版本号 "V2.4"）
newGame 新游戏 → simpleGame 单人 / doubleGame 双人（**双人删除**）→ 选角（只保留悟空，可跳过）；continueGame 读档（SaveInter 存档位界面，Common_v7 symbol681）；gameHelp 帮助；aboutUs 关于（AboutUs symbol240）；btnquit 退出登录；btn_forum/btn_solution 4399 论坛链接；btnCadpa 适龄提示（CadpaView symbol233）；btnGoBack（AIR 版返回）。

### 7.5 地图 SelectPLace（OtherMat_v10 symbol493）
关卡按钮 s1_1…s4_3（帧1 普通 / 帧2 当前），btnnmg（第 6 关红孩儿副本）、lxdy（第 10 关），showBuySkill 技能、ldl 炼丹炉、scgm 商城、savebtn 存档（30 秒冷却，saveInterval 倒计时）、btnback 回主菜单。
范围外：submitbtn 提交 4399 积分、arena 竞技场（gameMode 3 双人 PK）、huodongbtn 活动。

---

## 8. 范围外（4399 平台 / 活动 / 双人）——只列不做
- 活动 huodong：ZMPresent2025（兑换码礼包：灵魂+功勋，Common_v7 symbol591）、NightYears（年夜，功勋+10）、ChineseValentinesDay（七夕，功勋+10/天）、中秋月饼（xyb/大月饼/nyd 凝月刀）、国庆 buff（guoqingAtk/Def/HuiHuang 计时器）、绝·时装、zhuwei_1~3 助威次数。
- 4399 服务：serviceHold 登录/LoginAlert、云存档 SaveInter + 多开检测（ManyOpenAlert，"请不要多开网页"，强化/合成前 STOREREADOK 校验）、点券余额/充值/扣费（PayMoneyVar、decMoney_As3）、积分排行 showRefer/myscore、论坛链接、防修改器（BaseRoleProperies.step 属性超限 96 帧后重置）、Pig9 库（openPig，7 日数据）。
- 双人：player2/hero2、Role2(唐僧)/Role3(八戒) 及其时装/武器、「给予」bgy、竞技场 MODE3、商城 btn_play2。

---

## 9. 原作 bug / 注意事项汇总（重制时决定是否修正）
1. wpqhs5 强化成功率恒 0，且无法合成/购买。
2. 绝·时装（jwkwdg/jwkzyf）掉率加成为 0（名称匹配失败）。
3. 血海魔童「木」+2 次攻击永不生效（`=="木"` vs "木 "）。
4. hit7 烈焰闪伤害固定 100，后期几乎无用。
5. 法宝从 1 级合成，升到 2 级需 1000（公式 L²×1000，L=当前级）；0 级不存在。
6. 被动技能等级显示 curslevel = skilllevel-1，购买判定 `<=5` 但 setRole 在 >5 时隐藏按钮，实际最高 5。
7. 罗刹妖伞描述「减缓移动速度」未实现。
8. 03 文档 / monsters.json 把 gxp 记为怒气：实为红球灵魂；白球才是 +5 怒气（见 §0.1）。
