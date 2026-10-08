# 原作分析 01：物理、移动、受击（来源：decomp/game/scripts/scripts）

所有数值以「帧」为单位（Flash 帧率见 02 文档，待确认，通常 24fps：代码中大量 `24 * 秒数`）。
舞台 940x590。

## BaseObject（base/BaseObject.as）
- 默认：horizenSpeed=5，horizenRunSpeed=10，graity=1.5（px/帧²），jumpPower=-20，speed 初值 (0,4)。
- 每帧 step()：
  1. gotoAndStop(curAction)（动作=时间轴帧标签）
  2. 非受击时 setSpeed()：按 isLeft/isRight 设置 speed.x = ±walk/run；攻击中可被子类锁定。
  3. checkCanMove()：遍历墙体，墙 bounds 与「下一帧碰撞盒(colipse 偏移 speed)」相交时：
     - 斜墙（rotation≠0 且≠90）：位图像素 hitTest，命中后 wall.setYByRole(this) 返回新 speed（沿坡）。
     - 普通墙 nearToWall()：
       - 落地：speed.y>0 且 底边 <= 墙顶 + (8 + max(|vy|, |墙vy|)) → 贴到墙顶-0.1，vy=0，getDownFloor()。
       - ThroughWall（单向平台）只做落地判定，不挡头/左右。
       - 顶头：vy<=0 且 碰撞盒顶 > 墙底 → 贴底，vy=0。
       - 左右：贴边 ±2px，vx=0，要求 底边 > 墙顶+5。
  4. move()：x += vx（仅在走/跑/空中/受击/可移动攻击时）；y += vy；vy += gravity；再加 enforceSpeed。
     站在移动墙上且 wait 时继承墙 speedX。
- 下跳：getFallDown() 站在 isThroughWall 上 → y += 20，进入 jump1，jumpCount=1。
- 击退 beAttackBack(src, vx, vy)：方向由攻击者朝向（transform.matrix.a==1 表示朝左→向左击退）或子弹位置决定；直接设 speed=(±vx, vy)。
- 朝向：AUtils.flipHorizontal(this, 1)=左，-1=右（素材默认朝左）。
- 动作判定：isJump = jump1/2/3；isAttacking = hit1/2/3（Hero 覆写为 false，由 Role 覆写）；isBeAttacking = hurt/afterHurt/dead。
- 无敌：isYourFather + fatherCount 帧计数。

## BaseHero（base/BaseHero.as）
- 升级经验 levelexp=[135,145,155,165,175,185,625,675,725,775,825,875,1950,2050,2150,2250,2350,2450,5000]。
- 出生无敌 buff "father" 48 帧（24*2）。
- 输入：keydown/keyup 写入 keyarray（与 keyList 对应位 0/1），每帧 executeKeyCode() → myKeyDown(keyarray.join(""))，子类按字符串匹配技能。
- 双击跑：同方向键「松开后再按」间隔 < 500ms → doubleCount=1 → isRunning（run 速度 10）。松开方向键 doubleCount=0。
- executeLastDirKey：非攻击时每帧按最后方向键强制转向（65/37 左，68/39 右）。
- 跳跃：jumpCount<2 且非攻击非受击 → vy=jumpPower；第一段 jump1，第二段 jump2（二段跳）。jump1 且 vy>0 → jump3（下落）。落地 jumpCount=0。
- 受击 beAttack(attacker)：
  - 攻击判定框为 attacker.body.stick，先 hitTestObject 再 HitTest.complexHitTestObject（像素级）。
  - 同一 attackId 只命中一次（beAttackIdArray）。
  - 闪避 miss 概率；伤害 = getRealPower(lastHit) + rand(-5,5)。
  - attackBackInfoDict[lastHit] 决定：attackKind magic（×(1-magicdef)）/physics（减防御，最少 1）/其他（直接）；attackBackSpeed=[vx,vy] 击退；addEffect 附加状态。
  - 进入 hurt；已在受击中则 body.gotoAndPlay(1) 重播。
- 掉出 y>=1500 即死亡。
- 变身 GXP（怒气模式）：gravity 3.75，速度/跳跃 ×1.5，stopGame(1000) 顿帧 + 全屏特效；每 4 帧残影并消耗怒气。
- 技能键映射 sendSkill：0=L,1=U,2=I,3=O,4=空格,5=法宝。
