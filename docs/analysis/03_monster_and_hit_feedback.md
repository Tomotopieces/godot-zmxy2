# 原作分析 03：怪物、受击反馈（base/BaseMonster.as）

## 打击感构成（无 hitstop！）
原作命中时不停帧（stopGame 只用于变身/菜单）。打击感来自：
1. 击退：命中后 speed = (±attackBackSpeed[0], attackBackSpeed[1])，怪物进入 hurt（若已在 hurt 则 body.gotoAndPlay(1) 重播 → 连击时持续硬直）。
2. 击退衰减：BaseMonster.adjustSpeed() 每帧若 |vx| > horizenSpeed 则 vx *= 0.8，降到走速后钳制为 ±走速（滑行感）。
3. 命中特效：MonsterBeHurt1/2（各 50% 随机，Role_v6.swf），放在 colipse 中心；唐僧(Role2)命中特效做 ColorMatrix 色相 160 偏移。
4. 音效：BeattackByRole1 / BeattackByRole2（Music.swf）。
5. 伤害数字：ANumber，普通 "hurtnum" 20px，暴击 "bnum" 16 间距（暴击判定 hurt/basehurt > 1.9）。
6. 血条：怪物头顶 50x5 红条，命中显示并 2 秒淡出。
7. 屏幕震动：ViewControllor.shake(v)：gameSence.x += v，下一帧 -= v（2 帧单次抖动），由特定技能/BOSS 调用。

## 伤害公式
- 物理：max(1, atk - def)；魔法：atk × (1 - mDef)；无 attackBackInfo → 1。
- 物理攻击吸血：eatblood 比例回血。八戒(Role3)特定武器 deephit 概率眩晕 48 帧。
- 同一 attackId 对同一目标只命中一次；多段技能靠帧脚本 newAttackId() 刷新。

## 怪物 AI（基类默认）
- count 0..240 循环计数；bcount（转向后 24 帧思考停顿）。
- 无目标：normalWalk() —— count==12 时随机向左/右走（离屏幕中心 ±400 外则往回走），在 stopNum(72 或 96) 帧后 50% 停下。
  selectTarget()：|dy| <= attackRange 且 |dx| < mysee → 锁定英雄。被打会立即锁定攻击者。
- 有目标：|dy| <= attackRange*2 时：|dx| > attackRange 追击；否则每 36 帧按 isattback% 概率 attackTarget()（hit1，面向目标），否则停下。
- isTurnBack 标记（markArray）：碰到后掉头；noContinueGo：禁止通过。
- backTime：攻击后后撤（飞行怪上升）。
- 技能 CD skillCD1-4 每帧递减。
- 怪物参数 protectedParamsObject：mysee 视野、isattback 攻击概率%、def、mDef、Hp/sHp、exp、gxp(怒气)、probability 掉落、stoneFallRate。
- 怪物攻击力取 attackBackInfoDict[lastHit].power。

## 子弹 BaseBullet
- attackInterval：多段命中间隔帧；hitMaxCount：最大命中次数（攻击信息表字段）。

## 镜头 ViewControllor（my/ViewControllor.as）
- 横版单向卷轴：只有当玩家碰撞盒屏幕 x >= 940*2/3（≈627）时，场景按玩家当前 vx 左移（镜头锁死在玩家推进速度上，不做平滑）。
- 回退：玩家在屏幕 x <= 188 且 canBackward>0 时允许往回卷，速度上限 10。
- 背景 bg1 视差：bg 位移 = 场景位移 × (bg宽-940)/(场景宽-940)。
- StopPoint（关卡中 "stophere" 标记，按 x 排序）：镜头卷到停止点屏幕 x∈[900,980] 时锁定（thisStopX），StopPoint.touch() 刷怪；怪清完才继续。
  isAutoCamera：清完后自动以 min(30, |vx|+10) 卷屏，直到下一停止点。
- 关卡 5-1、6-1、7-1 和第 10 关的镜头固定不动（BOSS 房）。
- 角色不能离开屏幕左右 20px（isCanMoveByStage）。
- shake(v)：两帧 ±v 的 x 抖动。

## 防连控「father」效果（base/BaseAddEffect.as）
- 英雄常驻 buff father{time:48, interval:1000, isForever}：每次受击 updateFather() 计数 +1，
  距上次受击 >= 1000ms 计数清零；累计 5 次 → setYourFather(48)（2 秒无敌），无敌期间角色带脉动发光滤镜。
- 即：原作没有受击无敌帧，只有「1 秒内连续被打 5 下」后的 2 秒保护。

## 子弹 BaseBullet（base/BaseBullet.as）
- 每帧 step2 → checkAttack：对敌方 colipse 与子弹整体做相交 + 像素检测 → 目标.beMagicAttack(bullet, source)。
- attackInterval：首次命中后计数，达到间隔帧数则 newAttackId（可再次命中同一目标）；hitMaxCount 命中次数用完销毁。
- EnemyMoveBullet：每帧 x+=vx, y+=vy，distance 递减，<=0 销毁（Monster32 的 hit2 飞镖 setSpeed(10)、distance 600）。
- SpecialEffectBullet：静止特效判定（Monster32 hit1 近战 = Monster32Bullet2，17 帧后自毁）。
- 击退方向：EnemyMoveBullet 看子弹 vx 符号；SpecialEffectBullet 看子弹与目标 x 的相对位置；角色看朝向。

## 镜头 ViewControllor
- 英雄 colipse 屏幕 x >= 940*2/3 时，以英雄 vx 卷屏（只向右），远景 bg1 按 (bg宽-940)/(场景宽-940) 比例视差。
- 下一个 StopPoint 屏幕 x 进入 [900,980] → touch() 刷怪，镜头锁定；回退范围 canBackward = betweenRandL-940。
- 停止点清空后 setAutoCamera：最左英雄屏幕 x > 450 时自动卷屏 min(max|vx|+10, 30) px/帧，直到下一个停止点进入 [880,1000]。
- 英雄不能走出屏幕 [20,920]。shake(v)：x+=v，下一帧 x-=v。
