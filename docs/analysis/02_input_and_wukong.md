# 原作分析 02：输入与悟空（Role1）

帧率 24fps（GMain: `[SWF(width=940,height=590,frameRate=24)]`）。

## 键位（my/KeyBoardControl.as）
- P1：左 A(65) 右 D(68)；keyList=[S(83), J(74), K(75), W(87)] → keyarray 字符串位序 "下 攻 跳 上"。
- P1 技能 [L,U,I,O,空格,H] → sendSkill 0..5（H=法宝）。
- P2：左←右→；keyList=[↓, Num1, Num2, ↑]；技能 Num3,4,5,6,0,7。
- myKeyDown 收到的是 keyarray.join("")，例如 "0100"=只按攻击，"1010"=下+跳，"0101"=攻+上。
- cannextaction：触发一次后需松开该组任一键才能再次触发（keyup 置 true），即「按一次出一招」，长按不连发。

## 悟空 Role1（export/hero/Role1.as）
- horizenSpeed=6（走），run=10，jumpPower=-20，gravity=1.5。
- 属性：HP=80+50(L-1)，MP=50+20(L-1)，攻=10+rand(0..4)+5(L-1)，防=2+2(L-1)（L<15）。
- 指令：
  - "0010" 跳（二段跳）；"1010" 下+跳 = 从单向平台下落。
  - "0100"/"1100" 普攻 normalHit()。
  - "0101" 攻+上（需学技能0，10MP）→ hit8（上挑，击退 [2,-22] 多段）。空中使用会消耗二段跳。
  - "0001" 上 = 进传送门/交互。
  - U: hit7（30MP，冲刺火焰，帧3 addFireEffect: speed.x=±45，无敌12帧；帧10 速度清零；帧12 结束）。
  - I: hit9（40MP，旋风，伤害 1.2×攻，击退 [20,-2]）。
  - O: hit10（50MP，无敌75帧；寻找130px内敌人瞬移连击 hit10-1 → 跃起 hit10-3 → 下砸 hit10-2 ×3伤害，放大2倍）。
  - 跑动中普攻（需学技能1，20MP）→ hit6 冲刺斩（0.5×攻，击退 [35,-2]，可移动攻击）。
  - 空格：怒气满时变身（GXP）。
- 普攻连段 normalHit()：
  - 仅地面、非跑动。timers（冷却帧，myKeyDown 每帧-1）<=0 才响应。
  - 距上次按键 >1000ms 重置为 hit1，否则 hitNum++，>5 回到 1 → hit1..hit5 五段。
  - 冷却：下一段之前 timers=8；第4段后=15，第5段后=18（代码在递增前按旧 hitNum 赋值：hitNum==3→15、==4→18）。
  - 音效：1-2 段 Role1_hit1AndHit2，3-4 段 Role1_hit3AndHit4，5 段 Role1_hit5。
  - 空中普攻：固定 hit3（timers=15，hitNum=0），空中 hit3 时不锁水平移动。
  - hit1~4 播放到 70% 后可以用 hit8 取消（isAttackingButCanAttack）。
- 普攻伤害 = 攻 ×(变身1.5)×(暴击2)；击退 hit1-4 [0.5,-3]，hit5 [25,-4]。
- 地面 hit1-5/9/10 锁水平移动（isCannotMoveWhenAttackOnFloor）。
- attackInterval / hitMaxCount：多段技能的命中间隔帧和最大命中次数（在 BaseMonster.beAttack 中使用，待分析）。

## 动画驱动的时序（重要）
动作时长与判定由 Role_v6.swf 的时间轴决定：英雄 MovieClip 的帧标签 = curAction，每个标签下放一个 body 子 MC（含 stick 攻击判定框），
body 的帧脚本负责：生成特效/子弹、修改速度、在最后一帧把 curAction 设回 wait/jump1（结束动作）。
例：Role_fla/元件17_142（悟空 hit7）：frame3 addFireEffect，frame10 speed=0，frame12 结束 → 回 wait。
⇒ 复刻需导出每个动作 body 的：帧数、帧脚本、每帧 stick/colipse 矩形。
已实现：tools/scripts/swfxml2json.js（FFDec -swf2xml → 时间轴 JSON）、hero_timeline.js（动作/判定框）、frame_scripts.js（帧脚本）。
完整数据：docs/analysis/data/role1_timeline.json（坐标为英雄本地坐标，素材默认朝左，x<0 为前方）。

### 悟空动作时间轴（body 帧数 @24fps，stick=攻击判定帧区间）
碰撞盒 colipse 恒为 [-22.1,-45.1, 45×90]（中心约在原点）。
| 动作 | 帧数 | 判定帧 | 结束/事件 |
|---|---|---|---|
| hit1 | 8 | 3-8 | f8 → wait/walk/jump1 |
| hit2 | 8 | 3-8 | f8 结束 |
| hit3 | 11 | 1-? | f10 结束（也是空中攻击） |
| hit4 | 20 | 1-? | f19 结束 |
| hit5 | 15 | 3-9 | f14 结束 |
| hit6 冲刺斩 | 15 | 1-15 | f1 vx=±15(变身30)，f5/8/11 newAttackId+vx×0.8（多段） |
| hit7 | 12 | 3-12 | f3 冲刺 ±45，f10 停，f12 结束 |
| hit8 升龙 | 15 | 5-15 | f15 结束 |
| hit9 | 14 | 1-10 | f3/5/7 newAttackId（4段） |
| hit10 | 70 | 特效子弹 | f1 失重+锁键；f3 vx±20,vy-50；f7 寻敌瞬移；f47 下冲 vy20；f49-69 落地即 hit10-2 冲击波 |
| hurt | 15 | - | f7 setStatic，f15 回 wait（硬直 15 帧） |
| jump2 | 10 | - | 翻滚 10 帧后 → jump3 |
| walk 16 / run 8 / wait 100 / jump1 1 / jump3 1 | | | 循环 |

### 连段手感关键（无输入缓冲）
- 冷却 timers 与动画帧数的关系：hit1(cd8/anim8) → hit2(8/8) → hit3(8/11，第8帧即可接 hit4，取消尾巴) → hit4(15/20，15帧可接 hit5) → hit5(18/15)。
- cannextaction：按键触发一次后必须松开再按；冷却期内按下的攻击键被「吃掉」(normalHit 不执行但 cannextaction=false)，没有输入缓冲。
  => 原作节奏要求玩家按节拍连按。重制时可考虑加入短缓冲（待与用户讨论）。
- 距上次按攻击 >1000ms 连段重置。
