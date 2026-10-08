# Original analysis 05: per-monster behaviour (Monster30–81)

Scope: everything a monster does that differs from the plain `BaseMonster` AI described in `03_monster_and_hit_feedback.md`.
Plain stats (hp/def/exp/attackBackInfoDict/fallList) are extracted separately and are NOT repeated here unless they configure behaviour.
Units: frames (24 fps), px, as in source. "invuln N" = `setYourFather(N)` (immune to all damage for N frames).

## 0. Source authority / loading

- All libs are loaded with `LoaderContext(false, ApplicationDomain.currentDomain)` (`loader/Aloader.as`). In AS3 the **first loaded definition of a class wins**, so for the classes compiled into the main swf (`zmxy2_game`: Monster35/38/39/47/52–55/57/60/70–78, identical to Common_v7/Common_v6/OtherMat/backpack copies) the main-swf copy is what actually runs, not the stage-lib copy.
- Normalised diffs (ignoring imports/Embed/trace/try-catch) show **no functional difference** between the stage-lib copies and the main copies, with one exception: main **Monster60** also grants a daily 功勋 reward on death (see 60). Lib 5 vs 5_v7 Monster45 differ slightly (see 45). This doc uses the stage lib copy as the description; behaviour is the same either way.
- Monster30–32, 36, 37, 40–46, 48–51, 56, 58, 59, 61–69, 79–81 only exist in their stage lib.
- Monster→lib/stage used for analysis: 30/31/32/35/52 → `1_v6`; 33/34 → `Common_v7`; 36–40, 53–55 → `2`; 41–44, 47–49, 56, 57 → `3`; 50/51/59/60 → `4`; 45 → `5_v7`; 46 → `6`; 58/81 → `7`; 61–63 → `8`; 64–66 → `9`; 67–78 → `10`; 79/80 → `11`.
- Timeline frame scripts live in `<lib>/scripts/_N_fla/*.as` (`addFrameScript`). Scripts casting to a concrete class (`Monster35(this.parent).doHit3()`) are certain; generic `BaseMonster(parent)` scripts were attributed by Embed symbol-id proximity (child symbols have ids just below the monster's own symbol id) and are marked *(inferred)*. Frame numbers below are 1-based as in the `frameN` function names.

## 1. Shared patterns (implement once, reuse)

- **Hurt guard**: most monsters override `myIntelligence` to `if (!isBeAttacking()) super.myIntelligence()` (no thinking during hurt/afterHurt/dead). Called "hurt guard" below. Monsters WITHOUT it (46, 48, 58, 77, 81 — template D users) can start attacks during hurt = super-armour.
- **Action end**: every attack/hurt clip ends with a frame script `setStatic(); curAction="wait"; gotoAndStop("wait")` → the action length = clip length. Implement as "action finished → wait".
- **Multi-hit**: frame scripts call `newAttackId()` on the monster (or bullet) to allow the same target to be hit again. Listed as "re-hit at frames …".
- **Boss template `hasAttackTarget`** ("template B", used by 35, 40, 45, 47, 49, 61, 64, 67, many others with different numbers):
  - return if `isAttacking()`; require `|dy| <= attackRange*2` else `normalWalk()`.
  - `|dx| > attackRange`: if skillCD1==0 → face target, releSkill1, set CD1; else `followTarget()`.
  - `|dx| <= attackRange`: only on `count % 24 == 0`: if skillCD2==0 → releSkill2, set CD2; else `attackTarget()` (no `isattback` roll).
- **Distance-band template** ("template D", used by 46, 48, 58, 77, 81): ignores |dy|, returns if attacking or in air; bands on |dx|: ≤150 → skill3 (CD) else every 24f 70% hit1 / 30% normalWalk; ≤300 (or 500) → skill2 with **80% roll per frame while CD==0** (failed roll leaves CD at 0 → re-rolls next frame, so it is ~always cast) else same 70/30; ≤800 → skill1 (CD 140+rand·100) else normalWalk; farther → normalWalk. These monsters never call followTarget (they approach only via wandering/skills).
- **Boss death**: `isBoss` monsters are not set to "dead" by `BaseMonster.step`; the killing hit does. Boss "dead" clip blinks `visible` every 2 frames for 24 frames, then frame 25 spawns `BossDead` (Common_v7). `BossDead` frame 12 calls `dropAura(); destroy()` on **every** `isBoss` monster in `monsterArray` (bug: forward-iterating while `destroy` splices → may skip one; also kills any other live boss, e.g. both 无常 in 1-2). Non-boss dead clips end with `dropAura(); destroy()`.
- **Stage exit**: boss `destroy()` usually sets all `TransferDoor`s visible (= level exit). Variants noted per monster.
- **Invulnerable bosses**: `beAttack`/`beMagicAttack` ignore hits when `isYourFather` or (`isBoss && curAction=="dead"`).
- **Hard-coded hooks outside the monster classes**:
  - `BaseMonster.beAttack/beMagicAttack`: Monster38 – if attacker has `deadlink` debuff, attacker takes the same damage; Monster74/76 – attacker always takes the same damage (100 % reflect); Monster70/71 – no lifesteal / no 八戒 stun.
  - `BaseBullet.checkAttack`: bullet `Monster38Bullet2-3` spawns `Bullet2Explode` fx on hit; bullet `Monster56Bullet1` heals its owner by 5 % of missing HP per hero hit.
  - `BaseHero.beAttack`: Monster35 hit while in hit2-1/hit2-2 → chain-lock the hero (see 35). Monster77 `hit4` hit → hero HP := 10 % max, boss `setFullHp()` then loses `(1 - heroHpRatioBeforeHit)` of max (boss HP ratio becomes the hero's former ratio).
  - Role3 (八戒) `doHit8` pull skips: 70, 71, 78, 52, 53, 54, 55, 57, 72 while attacking, 47 while invuln. Magic weapon `Mirror` skips: 78, 52, 53, 54, 55, 57, 60 and invuln monsters. → give these a flag `immovable` / `mirror_immune`.
- **Key typo**: many dicts use `"AttackInterval"` (capital A) but `BaseBullet` reads `attackInterval`; for bullets with that typo the interval is `undefined` → effectively one hit per attackId. Harmless for melee.
- **Real-time timers**: `TweenMax.delayedCall/to` are seconds and are NOT paused by `gc.isStopGame`. Convert to frames (×24) but note they run during pauses in the original.
- **Spawner** (`MonsterAppearPoint`): starts when its StopPoint is touched; after `delay` s, every `interval` s creates one `enemyType` if `monsterArray.length < gc.maxMonsterPerScreen` (6 or 8), until `totalNum`. In stage 9-1 (`isFb`) it only spawns when the array is empty. `StopPoint.isBoss` exists in scene data but is never read. Debug builds force totalNum=1.
- `MainGame.createMonster(id,x,y)`: id 79 → 79 or 80 (50/50). Ids 52, 53, 54, 55, 60 are inserted right above the background layer (behind heroes); others just below the lowest hero.

## 2. Summary table

| id | name (monsterName) | stages | boss? | custom behaviour? |
|---|---|---|---|---|
| 30 | – (stage-1 grunt) | 1-1, 1-2 | no | small: hit1 lunges 15 px/f for 9 f |
| 31 | – (zombie) | 1-1, 1-2, 1-3 | no | no: base AI + hurt guard |
| 32 | 守夜人 | 1-1 (boss), 1-2, 1-3 | only in 1-1 | yes: spinning projectile skill (CD 96), melee effect bullet |
| 33 | 黑无常 | 1-2 (boss), 2-2, 2-3, summoned by 53 | only in 1-2 | no: base AI; boss stats only in 1-2 |
| 34 | 白无常 | 1-2 (boss), 2-2, 2-3, summoned by 53 | only in 1-2 | no: same code as 33 |
| 35 | – (puppet of 秦广王傀儡) | 1-3 (summoned by 52) | no | yes: chain-lock grab, falling homing stabs, invuln on skill |
| 36 | – | 2-1, 2-2, 2-3, summoned by 53 | no | no |
| 37 | – | 2-1, 2-2, 2-3, summoned by 53 | no | no |
| 38 | 秦广王 | 2-1 | yes | yes: projectile, homing bomb orbs, periodic DEADLINK (damage reflect) |
| 39 | 判官 | 2-2 | yes | yes: scripted intro, 90 s fire timer → game over, speed-up mode, 3-shot |
| 40 | 阎罗王 | 2-3 | yes | yes: HP-threshold door summons 53/54/55, wave effect |
| 41 | – | 3-1 (water spawns), 3-2 | no | no (3-1 spawning is level script) |
| 42 | – | 3-2, 3-3 | no | no |
| 43 | – (flyer) | 3-2, 3-3 | no | yes: flying hover AI, 3-bullet mortar, retreat-up |
| 44 | – | 3-3 | no | small: hit1 spawns front effect bullet |
| 45 | 白骨精 | 5-1 | yes | yes: 3 forms with 10 s invulnerable revive, gaze petrify, growing AoE |
| 46 | 红孩儿 | 6-1 | yes | yes: distance-band AI, stats by player level, unlocks 八戒 |
| 47 | 孟婆 | 3-3 | yes | yes: summons 48/49 at 50 %/25 % HP while invulnerable, bounce bullet, global magiclost |
| 48 | 悟空怪 | 3-3 (summoned by 47) | no | yes: distance-band AI, dash, slam, random 4-move combo |
| 49 | 唐僧怪 | 3-3 (summoned by 47) | no | yes: targeted sky strike, shockwave, 2 projectiles |
| 50 | – | 4-1 | no | small: hit2 effect bullet CD 96, wanders in range |
| 51 | 转轮王 (form 2) | 4-1 (spawned by 59's death) | yes | yes: 6 ring traps w/ ammo + recall, AoE |
| 52 | 秦广王傀儡 | 1-3 | yes | yes: static immobile boss, random head swap, spawns 35 |
| 53 | – (summon totem) | 2-3 (summoned by 40) | no | yes: static, summons 37/36/34/33 cyclically every 72 f |
| 54 | – (heal totem) | 2-3 (summoned by 40) | no | yes: static, heals all monsters +50 every 24 f |
| 55 | – (damage totem) | 2-3 (summoned by 40) | no | yes: static, -20 HP to every hero every 24 f |
| 56 | 夜叉 | 3-2 | yes | yes: transforms at 80 % HP into invisible run-ram form, healing jump |
| 57 | – (fish spawner) | 3-1 (level script) | no | yes: invisible invulnerable emitter of fish arcs; its destroy opens exit |
| 58 | 刑天 | 7-1 | yes | yes: leap/hover/slam, pull, heavy invuln; spawns 81 on death |
| 59 | 转轮王 (form 1) | 4-1 | yes, flying | yes: hover AI, aimed shot, bomb rain; death spawns 51 |
| 60 | 转轮王 (form 3) | 4-1 (spawned by 51's death) | yes | yes: immobile turret with 8 orbs to floor slots + recall; death clears stage |
| 61 | 楚江王 | 8-1 | yes | yes: summons ≤5 Monster62, timed ground-burst rows, revive via minions |
| 62 | – (leech) | 8-1 (summoned by 61) | no | yes: leap-latch onto hero, drain/heal boss, sacrifices to revive 61 |
| 63 | – | 8-1 | no | no |
| 64 | 宋帝王 | 9-1 | yes | yes: shadow strike under target, close spell; death → 65/66 |
| 65 | – (loot jxbuff) | 9-1 (after 64) | no | small: static breakable, 100 % drop |
| 66 | – (loot xique) | 9-1 (after 64) | no | small: same as 65 |
| 67 | 五官王 | 10-2 | yes | yes: summons 68 turrets, pillars + poison wave |
| 68 | – (ghost turret) | 10-2 (summoned by 67) | no | yes: immobile, uninterruptible, 360-tick lifetime |
| 69 | 卞城王 | 10-3 | first instance only | yes: clones itself after N knockbacks, 6-shot volley, quake |
| 70 | – (round selector) | 10 hub | no | yes: unkillable prop; each hit advances 5-position pointer |
| 71 | – (hub stone ×2) | 10 hub | no | yes: unkillable prop; "recently hit" flag |
| 72 | 都市王 | 10-5 | yes | yes: net debuff, leap-teleport onto hero, super-armour in leap |
| 73 | 泰山王 (normal) | 10-4 | yes | yes: form switch 73→74 timer, 73→75 at <50 % HP, dash |
| 74 | 泰山王 (reflect) | 10-4 (form) | yes | yes: 100 % damage reflect, back to 73 after 240 ticks |
| 75 | 泰山王 (big) | 10-4 (form) | yes | yes: dash out & back, →76 on timer |
| 76 | 泰山王 (big reflect) | 10-4 (form) | yes | yes: reflect, back to 75 after 240 ticks |
| 77 | 平等王 | 10-6 | yes | yes: 4 random hit2 variants, tombstone summon, HP-swap hit4 |
| 78 | – (墓碑 tombstone) | 10-6 (summoned by 77) | no | yes: no AI, drains 200 HP/50 MP from all heroes every 24 f |
| 79 | 劈天斧 | 11-1 (50 %) | yes | minor: base AI, slides during hit1, event counter on death |
| 80 | 风神盾 | 11-1 (50 %) | yes | minor: same as 79, other counter |
| 81 | 战神刑天 | 7-1 (spawned by 58) | yes | yes: stats scale with heroes, pull, 40 px/f dash, arena clamp |

Count: ~41 of 52 need a behaviour script (plain data: 31, 33, 34, 36, 37, 41, 42, 63; trivial: 30, 44, 50, 65, 66, 79, 80).

## 3. Monsters per scene (`zmxy2_game/scripts/export/gameSence/slXY.as`, sum of `totalNum` per enemyType; `spN` = stopPointIdx)

| scene | spawns (id ×total) | boss / notes |
|---|---|---|
| sl11 (1-1) | 30 ×15, 31 ×25, 32 ×1 (sp4) | 32 is boss (curStage1/curLevel1) |
| sl12 (1-2) | 30 ×13, 31 ×16, 32 ×15, 33 ×1, 34 ×1 (both sp4) | 33+34 bosses |
| sl13 (1-3) | 31 ×14, 32 ×34, 52 ×1 (sp4) | 52 forced to x=3915,y=300; spawns 35 |
| sl21 (2-1) | 36 ×26, 37 ×26, 38 ×1 (sp4) | |
| sl22 (2-2) | 33 ×7, 34 ×7, 36 ×21, 37 ×21, 39 ×1 (sp4) | 33/34 non-boss stats; StageListener22 fire timer |
| sl23 (2-3) | 33 ×8, 34 ×8, 36 ×22, 37 ×22, 40 ×1 (sp4) | 40 summons 53/54/55 |
| sl31 (3-1) | none (boat level) | StageListener31 spawns 41 from water + Monster57 fish emitter |
| sl32 (3-2) | 41 ×36, 42 ×22, 43 ×12, 56 ×1 (sp4) | |
| sl33 (3-3) | 42 ×20, 43 ×20, 44 ×30, 47 ×1 (sp4) | 47 summons 48, 49 |
| sl41 (4-1) | 50 ×40 (sp0, 2×20), 59 ×1 (sp1) | chain 59 → 51 → 60 |
| sl51 (5-1) | 45 ×1 | listener touches sp0 after 4 s |
| sl61 (6-1) | 46 ×1 | listener touches sp0 after 4 s |
| sl71 (7-1) | 58 ×1 | listener touches sp0 after 4 s; 58 → 81 |
| sl81 (8-1) | 63 ×40 (sp0, 2×20), 61 ×1 (sp1) | 61 summons 62 |
| sl91 (9-1) | 64 ×1 | after 64: 65 or 66; isFb spawn rule |
| sl101 (10 hub) | none | StageListener101 creates 70 (450,423), 71 (140,325), 71 (800,325) |
| sl102–sl106 (10-2..10-6) | 67 / 69 / 73 / 72 / 77, ×1 each | listener touches sp0 after 4 s |
| sl111 (11-1) | 79 ×1 (→ 79 or 80) | |

Never placed by a scene: 35 (52), 48/49 (47), 51 (59), 53/54/55 (40), 57 (StageListener31), 60 (51), 62 (61), 65/66 (StageListener91), 68 (67), 74/75/76 (73 chain), 78 (77), 81 (58).

---

## 4. Per-monster spec

### Monster30 — stage-1 grunt
- lib 1_v6; 1-1, 1-2. Not boss.
- `isCanMoveWhenAttack` = hit1 (no speed damping/override during hit1); hurt guard.
- hit1 clip (元件5_6, inferred): frame 11 `speed.x = (matrix.a==1 ? -15 : 15)` (forward lunge), frame 20 `setStatic` + wait → ~9 f × 15 px ≈ 135 px lunge.
- `destroy` opens doors if isBoss (never true; dead code). Dead clip (元件9_11): frame 30 `dropAura+destroy`.

### Monster31 — zombie
- lib 1_v6; 1-1, 1-2, 1-3. Hurt guard only. hit1 22 f (僵S1_30), death 14 f. Data-only.

### Monster32 — 守夜人
- lib 1_v6; 1-1 (boss), 1-2, 1-3 (normal). `isBoss` and stronger hit1/hit2 only when `curStage==1 && curLevel==1`.
- hurt guard; `isAttacking` = hit1|hit2.
- `hasAttackTarget` (replaces base): return if attacking; needs target and on ground; |dy| ≤ 300 else normalWalk; |dx| > 150 → follow; else every 24 f: skillCD1==0 → hit2, CD1=96; else hit1. (No `isattback` roll.)
- hit1 (元件13_41): frame 5 `doHit1` → `SpecialEffectBullet("Monster32Bullet2")` at x∓20 (front), y; ends frame 15.
- hit2 (元件14_42): frame 7 `doHit2` → `EnemyMoveBullet("Monster32Bullet1")` at x∓20, y; `setSpeed(10,0)` forward; distance 600; spins (TweenMax rotation→1024 over 5 s). hit2 attackInterval 999 → 1 hit per target. Ends frame 20.
- Death (元件16_44, inferred): frame 30 `dropAura+destroy` directly (no BossDead blink, also in the 1-1 boss variant). `destroy` → doors visible if boss.

### Monster33 — 黑无常 / Monster34 — 白无常
- Common_v7; 1-2 (both bosses), 2-2/2-3 (normal), also summoned by Monster53. Identical code except stats.
- `isBoss` + monsterName only when `curStage==1 && curLevel==2`. Hurt guard; otherwise base AI (attackRange 240/200, mysee 600).
- `destroy`: doors visible only if boss AND `monsterArray.length == 0` (designed for the two-boss room).
- Oddities: boss version has LESS HP than the normal version (1000/1200 vs 1400/1600). If their death uses BossDead, killing one would destroy the other (see §1).

### Monster35 — puppet of 秦广王傀儡 (no monsterName)
- lib 1_v6; only created by Monster52 in 1-3. Not boss. HP 30000 → effectively not meant to be killed (kill 52 instead).
- hurt guard; `isAttacking` = hit1|hit2-1|hit2-2|hit3.
- `hasAttackTarget` = template B, attackRange 150: far & CD1==0 → face, **hit3**, CD1=180; far → follow; near every 24 f: CD2==0 → `releSkill2` (= invuln 35 + hit2-1, no face/newAttackId), CD2=260; else `attackTarget` (overridden → hit2-1, faces target). hit1 is never used.
- **Chain grab**: `BaseHero.beAttack`: when 35 hits a hero during hit2-1/hit2-2 → `addTielianObject(hero)`: hero `setStatic()` + `setLostKeyboard()` (frozen, no input). Released (`removeAllTielianObject` → `reSetLostKeyboard`) at hit2-2 frame 15, at hurt clip frame 1 and in `destroy`.
  - hit2-1 (元件32_17): knockback [15,0]; frame 26 → switch to hit2-2.
  - hit2-2 (hit2_2_26): knockback [-15,0] (pulls hero back); stick `Monster35Bullet2` calls `newAttackId` at its frame 1 each loop (repeated hits); frame 15 release + wait.
- hit3 (元件34_20): frame 45 `doHit3`: 4 × `StabBullet("Monster35Bullet1", targetPos, turnTime 1 s, source)` at (x + (i−2)·50, 0) for i=0..3 (−100,−50,0,+50) at scene top. Each fades in and rotates toward the target position snapshot over 1 s, then flies along it: speed 1 + accumulating (addSpeed += count·0.05 per frame) → accelerating; dies after 240 f or |y|>1000. hit3 attackInterval 999 → one hit per target.
- Death (元件38_24, inferred): frame 1 setStatic, frame 30 dropAura+destroy.
- Bugs: `doHit3` uses `curAttackTarget` without null check; skill2 attacks in current facing.

### Monster36 / Monster37
- lib 2; 2-1/2-2/2-3, also summoned by 53. Hurt guard, `isAttacking`=hit1, unused `tielian` array (copy-paste). Data-only.

### Monster38 — 秦广王 (2-1 boss)
- lib 2; isBoss. Not flying.
- `hasAttackTarget`: return if attacking or in air; |dy| ≤ 300: |dx| > 150 → follow; else every 24 f: CD1==0 → hit2, CD1=126; else hit1. `isattback` unused.
- **DEADLINK** (in `myIntelligence`, ticks every think tick even while hurt): `specialCountCD` 240 → at 0 every living hero gets `{name:"deadlink", time:120}`; reset to 360. While a hero has deadlink, any damage it deals to 38 is also dealt to itself (BaseMonster hook). Visual `DeadLink` clip.
- hit1 (Timeline_41): frame 7 `doHit1` → `EnemyMoveBullet("Monster38Bullet1")` at own x,y, speed 15 forward, distance 1500; ends frame 14.
- hit2 (Timeline_40): frame 5 `doHit2`: if `flyBulletArray.length >= 10` nothing; else spawn N = 3+ceil(rand·4) (4–7) MovieClips `Monster38Bullet2` at (x + (rand−0.5)·100, y−200). Each clip at its frame 6 dispatches global event `CreateFlyBullet(x,y)` and removes itself; the monster's listener creates `FlyBullet("Monster38Bullet2-2")` (action hit2-2, hitMaxCount 20, attackInterval 24 → re-hit every 24 f). Ends frame 40.
- **FlyBullet** (`Monster38Child/FlyBullet.as`): locks onto boss's target at creation; every 24 f vx = ±5 toward target; every 12 f vy = rand[−2.5,2.5]; after 48 f, if |dx| < 50 → `doHit2_3(x,y)` then self-destroy; lifetime 240 f. `doHit2_3` = `EnemyMoveBullet("Monster38Bullet2-3")` falling vy=10, distance 9999, action hit2-3 (1 hit); on hit → `Bullet2Explode` fx (BaseBullet hook).
- Death: blink + BossDead; `destroy` → doors, clears flyBulletArray.
- Bug: `flyBulletArray` stores the short-lived spawner clips, only `pop()`ed in `doHit2_3`; orbs that time out never free their slot → after a few casts the cap of 10 blocks hit2 (animation plays, nothing spawns). Remake: cap on live FlyBullets instead.

### Monster39 — 判官 (2-2 boss)
- lib 2; isBoss.
- **Intro**: constructor sets action "ready" + invuln 9999. After 4 s (TweenMax) → `StageListener22.start1()`: 6 `isPanguanFire` objects fly from the boss to fixed positions over 2 s, then `start2` → `realStart()`: action wait, invuln 24. "ready" counts as attacking.
- **Fire timer (StageListener22)**: from realStart one fire fades every 360 f; after all 6 gone + 4 s → `destroyGame` + `GameOver`. Kill within ~90 s.
- `myIntelligence` (replaces base): `hit2NeedCount` 72 → at 0, if alive and not hurt: invuln ≥32, play hit2, reset 720. Otherwise, if not hurt/attacking → base AI. Every tick `horizenSpeed` = 20 if has SPEEDUP buff else 4.
- hit2 (Timeline_26, 30 f): frame 30 `doHit2` → self buff `speedup` 480 f (`SpeedUp` fx).
- `followHero` (chase?) = true always during speedup, else |dx| > 200.
- `followTarget` during speedup: `speedUpAttackCount` (start 48) and `moveTime` count down; when moveTime==0 (and not hurt) choose direction to keep ~400 px from target (effectively: move left unless x ≤ target.x−400), moveTime=96; else jump when moveTime%48==0. When speedUpAttackCount hits 0 → `attackTarget`, reset to ceil(rand·3)·24.
- `attackTarget`: invuln 24 + base hit1. Normal mode uses base cadence (every 36 f, isattback 35 %).
- hit1 (Timeline_28, 72 f): frames 10, 31, 52 `doHit1` (if `body.stick`) → `EnemyMoveBullet("Monster39Bullet1")` at x∓50, y, speed 15, distance 1500, action hit1-1 (1 hit) → 3 shots.
- Death: blink + BossDead; destroy → doors.
- Bugs: hit2NeedCount runs during the ~6 s intro → hit2 replaces "ready", boss usually starts already sped up. If moveTime hits 0 while hurt it goes to −1 and never re-picks direction → runs one way at speed 20 for the rest of the buff.

### Monster40 — 阎罗王 (2-3 boss)
- lib 2; isBoss; constructor skillCD1 = 72. Hurt guard.
- `hasAttackTarget` (template B, attackRange 150, |dy| ≤ 300):
  - far & CD1==0: face; `doorTime` 1/2/3 and HP ≤ 80/60/40 % → `releSkill1` (summon); `doorTime > 3` → `attackTarget` (melee swing from range); always CD1=72 (even if nothing cast).
  - far otherwise → follow. Near every 24 f: CD2==0 → hit2, CD2=260; else hit1.
- releSkill1: invuln 28 + hit3 (Timeline_90, 25 f) → frame 25 `doHit3`: `DoorCalled` clip at (hero1.x, boss.y+80), child `door` showing frame `doorTime`; clip self-removes at frame 47. After 2 s (TweenMax) `callDoor` → `createMonster(53|54|55 for doorTime 1|2|3, doorX, doorY−190)`, depth = monsterArray[0]'s, `doorTime++`.
- hit2 (Timeline_93, 21 f): frame 1 `doHit2` → `SpecialEffectBullet("Monster40Bullet1")` at x∓40, y (re-hit at bullet frames 19, 28 → 3 hits; dies frame 40).
- hit1 (Timeline_91): re-hit frame 13 (2 hits), ends 25.
- Death: blink + BossDead; when dead, each summoned door monster gets `reduceHp(9999)`; doors visible.
- Quirks: summons always target hero1 (`getPlayerArray()[0]`); if hit3 interrupted, summon retried later.

### Monster41 / Monster42
- lib 3. 41: 3-2 spawner + 3-1 water spawns; 42: 3-2, 3-3. Hurt guard, base melee. Data-only.
- 3-1 (StageListener31): first spawn after 192 f, then every 24·(3+rand·4) f while under cap; `Monster41Jump` clip at boat.x ±100, boat.y+150 tweens to boat.y−60 over 1.5 s, then `createMonster(41, x, y+10)`. Stops when boat.x ≥ 4129.

### Monster43 — flyer
- lib 3; 3-2, 3-3. `isFly = true`, gravity 0; `directChangeTime` = 24·(1+2·rand) per instance.
- `myIntelligence`: nothing while hurt/attacking; advances turn-cooldown counter.
- `followHero` = |dx| > 180 || |dy| > 200 (base requires |dy| ≤ 900 = attackRange·2).
- `followTarget`: turn toward target at most once per directChangeTime; hover ~200 px above target: vy ±0.5/f capped ±4 (if y < target.y−200 → down, else up).
- `normalWalk` override: `newAttackId()` every call (body contact re-hits); at count 12 follow target if any, else random left/right with vy 0; zero velocity if attacking.
- `setStatic` also zeroes vy. Attack: base cadence (36 f, isattback); `attackTarget` zeroes velocity. `setThisBackTime` → backTime 72: base retreat (keep vx direction, vy −3 until y ≤ 150).
- hit1 (Timeline_29): frame 5 `doHit1`: 3 × `EnemyMoveBullet("Monster43Bullet1")` at (x+30,y), (x−30,y), (x,y), speeds (6,−4), (−6,−4), (0,−4) (vx mirrored by facing), `setAddSpeed(0,0.6)` gravity arc, distance 1000.
- Quirk: offsets not mirrored but speeds are (cosmetic).

### Monster44
- lib 3; 3-3. Hurt guard. mDef 0.8 (80 % magic resist — behaviour-relevant).
- hit1 (Timeline_52): frame 5 `doHit1` → `SpecialEffectBullet("Monster44Bullet1")` at x∓20, y; bullet dies at its frame 29.

### Monster45 — 白骨精 (5-1 boss, 3 forms)
- lib 5_v7 (lib 5 nearly identical); isBoss.
- Form state `{form:1, fullHp:10000}`; `setInfo()` applies per-form stats (fullHp 20000 form 2, 40000 form 3), full HP, then `hideDoor()`.
- Hurt guard. `hasAttackTarget` = template B (attackRange 150): far & CD1==0 → face, hit3 (gaze), CD1=180, invuln 10; near every 24 f: CD2==0 → face, hit2, CD2=260, invuln 25; else hit1.
- hit2 (元件93_11, 45 f): frame 5 `doHit2` → `SpecialEffectBullet("Monster45Bullet1")` at (x, y+80), scale 1+0.4·(form−1); re-hit bullet frames 6, 11, 16 (4 hits); dies frame 41.
- hit3 gaze (元件99_12, 25 f): frame 12 `doHit3`: every living non-invuln hero that is on her facing side AND facing her gets `eyefix` for 120+(form−1)·2 f (no input, static, EyeFix icon at y−20). Unlimited range; turning your back avoids it.
- Death/revive: dead clip (死亡_会复活, 40 f) frame 1 setStatic, frame 40 `checkReBurn()`:
  - form < 3: action "reburn", form++, `showDoor()`, `dropAura()`; reburn clip (复活_18) 240 f, last frame `setInfo()` + wait.
  - form 3: spawn BossDead, hide self → BossDead destroys; destroy → doors.
- Hurt rules: ignores beAttack/beMagicAttack while "dead" or "reburn" (10 s invulnerable). "reburn" counts as attacking. 5_v7 clears all debuffs every frame while HP ≤ 0.
- Visual: child 元件91_5 shows frame = form.
- Bugs: doors visible during each 10 s revive (player can leave); gaze duration only +2 f per form (probably meant seconds).

### Monster46 — 红孩儿 (6-1 boss)
- lib 6; isBoss. Constructor: if any player level > 15 → hard stats + drop "jgj", else easy stats (10000 HP, def 0, no drop).
- `myIntelligence` = base (NO hurt guard → super-armour starts).
- `hasAttackTarget` = template D: ≤150 → CD3==0 → hit4 (CD 360, invuln 20) else 24 f 70 % hit1 / walk; ≤300 → CD2==0 80 % → hit3 (CD 240, invuln 20); ≤800 → CD1==0 → hit2 (CD 140+rand·100, invuln 15). Each skill faces target + newAttackId.
- All attacks are body hitboxes (no bullet classes). Clips (inferred): hit1 Timeline_6 20 f; hit2 Timeline_9 52 f; hit3 Timeline_11 39 f (+nested re-hit frame 16); hit4 Timeline_18 40 f re-hit 9, 16, 24, 32 (5 hits).
- Death: blink + BossDead. `destroy`: if killed and `!gc.openPig` → `gc.openPig = true`, `setOtherStorage` (unlocks 八戒). Doors visible.

### Monster47 — 孟婆 (3-3 boss)
- lib 3; isBoss. Constructor calls `levelListener.start1()` (StageListener33 activates `isHideWall` walls = arena closes).
- `myIntelligence`: nothing while `isStop`; else base AI with hurt guard, then phase check `createMonster()`.
- `hasAttackTarget` = template B (attackRange 150): far CD1 → hit3 (CD 180); near 24 f: CD2 → hit2 (CD 260) else hit1.
- hit1 (Timeline_41): frame 9 `doHit1` → `EnemyMoveBullet("Monster47Bullet2")` at x∓40, y, speed 15, distance 1500.
- hit2 (Timeline_44): frame 15 `doHit2` → `{name:"magiclost", time:120}` on every non-invuln player (screen-wide, no hit test). No gameplay consumer found besides icon → presumably "can't use skills"; remake decides.
- hit3 (Timeline_45): frame 12 `doHit3` → `BounceBullet("Monster47Bullet1", (±15, 15))` at x∓140, y−180; reflects off walls (mirror vector), constant speed, afterimage every 2 f, 1 hit then gone. Bug: no lifetime → bounces forever if it never hits.
- Phases: HP < 50 % → `createMonster(48, x, 400)`; HP < 25 % → 49. While a summon lives: alpha 0.5, invuln 9999 (re-topped when < 100), `setStatic`, wait, `isStop=true`. Summon's "destroy" event → alpha 1, invuln 24, resume. Big hit 50→<25 spawns 48 then 49 after 48 dies.
- Death: blink + BossDead; doors.

### Monster48 — 悟空怪 (summoned by 47)
- lib 3; not boss. No hurt guard (super-armour).
- `hasAttackTarget` = template D: ≤150 → CD3 → hit4 (CD 360, invuln 70) else 70 % attack/30 % walk; ≤300 → CD2 80 % → hit3 (CD 240, invuln 20) else 70 % attack (swings out of range)/walk; ≤800 → CD1 → hit2 dash (CD 140+rand·100, invuln 52, face).
- `attackTarget`: random of hit1/hit5/hit6/hit7, faces target. `isCanMoveWhenAttack` = hit2.
- hit2 dash (Timeline_142, inferred): frame 1 vx = ±30; frames 5, 8, 11 newAttackId + vx·=0.8; ends 15.
- hit4 (Timeline_145): frame 1 `doHit4` → `SpecialEffectBullet("Monster48Bullet1")` at self; bullet shake(25) at its frame 49, dies 70. hit3: body only.
- `destroy` dispatches Event "destroy" (47 listens). Death: dropAura+destroy.

### Monster49 — 唐僧怪 (summoned by 47)
- lib 3; not boss. Hurt guard. Template B (attackRange 150): far CD1 → hit3 (CD 180); near 24 f: CD2 → hit2 (CD 260) else `attackTarget` = random hit1 / hit4.
- hit1 (Timeline_80): frame 7 → `EnemyMoveBullet("Monster49Bullet1")` at self, speed 10, distance 600, scaleX 0.6.
- hit4 (Timeline_95): frame 31 → `EnemyMoveBullet("Monster49Bullet2")`, speed 10, distance 1000, scaleX 0.6, multi-hit (interval 4, ≤99).
- hit2 (Timeline_83): frame 15 → `SpecialEffectBullet("Monster49Bullet3")` at self; bullet shake(15) at frame 1 and at 6, 11, 16, 21 newAttackId+shake (5 hits); dies 46.
- hit3 (Timeline_87): frame 16 `doHit3_1` → random player, warning clip `Monster49MC1` at (player.x, this.y−300) (self-removes at 39); frame 54 `doHit3_2` → `SpecialEffectBullet("hit4FallDown")` (Role_v6 asset) at (marker.x, marker.y+40); ends 65.
- `destroy` dispatches "destroy". Bug: `doHit3_2` reads `hitTop.y` without null check.

### Monster50 — stage-4 mob
- lib 4; 4-1 ×40. Hurt guard.
- `hasAttackTarget`: on ground, |dy| ≤ 600: |dx| > 300 → follow; else every 24 f: CD1==0 → hit2 (CD 96) else hit1; on all other frames `normalWalk` (drifts while in range).
- hit2 (Timeline_58, 16 f): frame 4 → `SpecialEffectBullet("Monster50Bullet1")` 20 px in front, re-hit frame 16 (2 hits), dies 30.

### Monster51 — 转轮王 form 2 (ring thrower)
- lib 4; created by 59's death at (1700,175) (falls in). isBoss, attackRange 400. Hurt guard.
- Template B with attackRange 400, |dy| ≤ 800: far CD1 → hit3 (CD 180, invuln 20); near 24 f: CD2 → hit2 (CD 260, invuln 80) else hit1.
- hit1 (Timeline_46, 20 f): frame 20 `doHit1`. Ammo 6:
  - ammo > 0: `EnemyMoveBullet("Monster51Bullet1")` aimed at target, speed 10, distance = dist to target + 40, action hit1-1 (magic, re-hit every 36 f, ~unlimited). On distance end `doHit1_2` → stationary `SpecialEffectBullet("Monster51Bullet1")` (hit1-2) = permanent trap. ammo--.
  - all 6 traps placed → next hit1 tweens every trap back to the boss over 2 s (still damaging), then destroys them, ammo = 6.
  - HUD children Timeline_35/40 show frame 7−ammo.
- hit2 (Timeline_41, 80 f): frame 36 → `SpecialEffectBullet("Monster51Bullet3")` at boss (hits every frame), destroyed after 12 f.
- hit3 (Timeline_43, 60 f): body melee, re-hit 25, 37, 49 (4 hits).
- Death: blink + BossDead; destroy removes traps, `createMonster(60, 1400, 472)`.
- Bug: ammo 0 with a ring still flying → hit1 does nothing.

### Monster52 — 秦广王傀儡 (1-3 boss)
- lib 1_v6; isBoss. On added to stage forced to (3915, 300).
- `move()` and `checkCanMove()` empty → never moves, no gravity, ignores knockback.
- `isCanMoveWhenAttack` true for wait1..wait5. `mygotoAndStop` does not change labels while curAction=="hurt" (hurt clip finishes, then wait).
- `myIntelligence` (replaces base, no attacks): first tick `createMonster(35, x, y)` (the fighting puppet, stored as `kuilei`); `changeCount` 72 → at 0 `setRandomHead()` (random label wait1..wait5) and reset to (2+rand·3)·24 f.
- Death (死亡_56): blink 24 f then `BossDead`. `destroy`: if dead and puppet alive → destroy puppet; doors visible.
- Remake: a static target boss + one Monster35; the "head" variant is purely visual (no gameplay effect found).

### Monster53 / Monster54 / Monster55 — 阎罗王's door summons (static totems)
- lib 2 (with art); summoned only by Monster40 at 80/60/40 % HP. Not boss. No hurt guard needed (no attacks).
- All: `move()` forces speed.x = 0 (still falls); `isCanMoveWhenAttack` = hit1; `myIntelligence` replaced by a single cooldown action, CD via skillCD1 (counted by base countCD); `destroy` fades alpha 1 s then removes.
  - **53**: CD 72 (start 72): if `monsterArray.length < maxMonsterPerScreen` → `createMonster(cycle [37, 36, 34, 33][callIdx], x, y)`, callIdx wraps 0..3.
  - **54**: CD 24: every monster in `monsterArray` (including itself and the boss) `cureHp(50)`.
  - **55**: CD 24: every player `reduceHp(20)` (flat, ignores defence/invuln, no range).
- Killed automatically (`reduceHp(9999)`) when Monster40 dies. Immune to 八戒 pull and Mirror.

### Monster56 — 夜叉 (3-2 boss)
- lib 3; isBoss, `horizenRunSpeed` 10.
- Phase 1 (HP > 80 %): base AI + hurt guard, hit1 (Timeline_166, re-hit 23 → 2 hits).
- At HP ≤ 80 % (`changeBody`, once): invuln 50, play hit2, horizenSpeed 5. hit2 clip (Timeline_173) frame 43: monster alpha = 0, curAction "run". `mygotoAndStop` ignores label changes while label is hit2.
- Phase 2 (no base AI, no stun check): `isRunning()` = (curAction=="run") → moves at 10 px/f; every 24·int(1+rand·3) f turns toward a random player and keeps running. `beAttackBack` ignored (no knockback), `adjustSpeed` disabled, any "hurt" replaced by "run". Run = body contact attack; `newAttackId` every 48 f.
  - Skill: CD1==0 and any player within 200 px (Euclidean) → hit3, CD1 = 24·int(6+rand·4) (144–216 f).
  - hit3 jump (Timeline_176): frames 3 & 5 vx = ±15, vy = −30; frame 5 `doHit3` → `SpecialEffectBullet("Monster56Bullet1")` at self (dies frame 6); frames 7 & 9 vy = +30; frame 15 → run. Each hero hit heals 56 by 5 % of missing HP (BaseBullet hook). `isCanMoveWhenAttack` = hit3.
- Phase-2 boss is fully transparent (alpha 0, HP bar too) — intentional "invisible" or bug; verify visually.
- Death: blink + BossDead; doors.

### Monster57 — fish emitter (3-1)
- lib 3; created by StageListener31 5 s after start at (500,−500), then **removed from monsterArray** — the listener calls `bmFish.step()` and each bullet's `step2()` itself.
- Constructor: finds wall "Stage31Chuan" (boat), invuln 99999 (never counts down because `step` is fully overridden: no AI, physics, HP, death). `move()` empty.
- `createFish`: `fishCount` 72 → spawn 2+int(rand·3) fish, reset 24·(1+rand·3). Fish = `EnemyMoveBullet("Monster57Bullet1")` at boat right/left edge ±50 (50/50), y = boat.y + rand·50; velocity (10,−20) 30 % / (5,−25) 30 % / (2,−20) 40 %, `setAddSpeed(0,2)`; fish clip dies at frame 28. `setCanBeAttack()` (heroes could destroy them, but 57 is not in monsterArray → probably never).
- Level end: boat.x ≥ 4129 → boat stops, `bmFish.destroy()` → doors visible (3-1 exit).
- Bugs: vx mirrored by 57's fixed facing → fish from both sides fly the same direction; `boat` null not checked.

### Monster58 — 刑天 (7-1 boss)
- lib 7; isBoss. Template D (no |dy| check): ≤150 → CD3 → hit4 (CD 360) else 24 f 70 % hit1, else CD1==0 → leap (CD1 140+rand·100) else walk; 150–300 → CD2 80 % → hit3 pull (CD 240) else 24 f 70 % hit1/walk; 300–800 → CD1 → leap; else walk.
- Invuln: hit1 20 (attackTarget override), leap hit2-1 52, hit3 40, hit4 39, hovering 9999.
- Leap/slam: hit2-1 (Timeline_34): frame 3 vy = −40; frame 40 `inTop()` (invuln 9999, `inTop=true`). While inTop `move()` forces vy = 0 (hover) and `step` sets vx = ±5 toward `gc.getRandomPlayer()` (re-picked each frame → jitters with 2 players). `fallDownCount` 48 first, then 24·(2+rand·2); at 0 → `Monster58Shallow` shadow clip at (x,510) (50 f), action hit2-2, inTop=false. hit2-2 (Timeline_37, inferred): frames 26, 37 newAttackId + `shake(20)`; ends 50.
- hit3 pull (Timeline_43): frame 40 `doHit3` → tween every hero to boss (x,y) over 0.6 s (no damage itself).
- hit1 (Timeline_32): re-hit 26, ends 45. hit4 (Timeline_46, 24 f): nested clip re-hits at 6, 12, 18.
- Death: blink + BossDead. `destroy` when dead: doors visible, then after 5 s (TweenMax) hide doors and `createMonster(81, 500, 300)`.
- Bugs: the 9999 invuln after a slam only ends at the next `setYourFather` call (next attack); doors visible 5 s → player can exit and skip 81.

### Monster59 — 转轮王 form 1 (4-1, flying)
- lib 4; isBoss, `isFly`, gravity 0. mDef set twice (final 0.15).
- `myIntelligence`: base AI only when not hurt/attacking; direction-change timer wraps every 24–72 f (rolled at spawn).
- `hasAttackTarget` (|dy| ≤ 900): outside hover offset → follow, else normalWalk; every 24 f: CD1==0 → hit2 (CD 360) else 50 % hit1.
- Hover `followTarget`: horizontal turn at most once per timer; each turn re-rolls offset x 160±40, y 140±60; vy accelerates ±0.5/f (cap ±4) toward target.y − offset.y.
- `normalWalk` override: `newAttackId()` each call (contact re-hits); at count 12 follow target or random L/R with vy 0.
- hit1 (Timeline_24, 10 f): stop + face; frame 10 → `EnemyMoveBullet("Monster59Bullet1")` scale 0.5, aimed, speed 10, distance = dist+40.
- hit2 bomb rain (Timeline_25, 11 f): frames 3, 5, 7 → `EnemyMoveBullet("Monster59Bullet1")` speed x 5..44 (facing), y 3..7, accel (+1,+2)/f, distance 9999, `setFuncWhenHitWall`: on touching a wall ≥ 800 px wide (floor) → `SpecialEffectBullet("Monster59Bullet2")` at (x, 472) (dies frame 24).
- Death (Timeline_27): blink then `dropAura+destroy` directly (no BossDead); `destroy` → `createMonster(51, 1700, 175)`.
- Bugs: x accel always +1 → left-thrown bombs curve back; explosion y hard-coded 472; `AttackInterval` typo.

### Monster60 — 转轮王 form 3 (immobile orb turret)
- lib 4 / main swf (main copy runs: on death also `gc.gongxun += gc.monster60Reward` if `monster60RewardTimes < MONSTER60_PER_DAY_TIMES`, float tip, save). Created by 51's death at (1400,472), layered behind heroes. isBoss.
- `move()`/`checkCanMove()` empty (no movement/gravity/knockback). `isCanMoveWhenAttack` = wait. On added → `levelListener.start1()`: StageListener41 activates two moving platforms "Monster60FlyFloor" at (1200,340) and (1810,180), speed ±2, wrapping ±1400 px when off-screen.
- `myIntelligence` (no targeting/melee), 2-phase loop:
  - Phase 0: first throw after 96 f, then every 2–5 s: `doHit1` → `SpecialEffectBullet("Monster60Bullet1")` at body centre (re-hit every 36 f, unlimited), tweened over 2 s to a random free floor slot (screen x 70, 185, 300, 415, 530, 645, 760, 875; y 460). 8 out → phase 1.
  - Phase 1 (every 96 f): first recall 4 orbs by index pattern [0–3] / [4–7] / [0,2,4,6] / [1,3,5,7] (pattern rolled once at spawn), next recall all remaining → phase 0. Recalled orbs tween to boss over 1 s and are destroyed.
  - HUD child Timeline_8 shows orb count.
- Death: blink + BossDead. `destroy` → `gameinwhere="通关"`, `ShowOpenAnimation`, `stopAllControl` (stage cleared).
- Oddity: patterns index launch order but slots are random → on-screen pattern effectively random.

### Monster61 — 楚江王 (8-1 boss)
- lib 8; isBoss; constructor skillCD1 = 72.
- Template B (attackRange 150): far & CD1==0 → face; < 5 children → hit3 summon, else `attackTarget` (melee from range); CD1=120. Near 24 f: CD2 → hit2 (CD 260) else hit1.
- hit3 (Timeline_29, invuln 28): frame 18 `doHit3` → `createMonster(62, x, y)`, `setSourceMonster(this)`, push to `childRenArray` (max 5).
- hit2 (Timeline_28, invuln 15): frame 5 `doHit2` → 5 × `Monster61Bullet1Pre` at fixed scene x 1050, 1250, 1450, 1650, 1850, y 500; after 2.5 s second row at x 900, 1100, 1300, 1500, 1700.
- **Monster61Bullet1Pre** (`Monster61Child`, warning clip): on last frame spawns `SpecialEffectBullet("Monster61Bullet1")` at its position (action hit2, owner 61) and removes itself. Bullet re-hits at 5, 10, 15, 20 (≤5 hits), dies 25, knockback [0,−15].
- hit1 (Timeline_22): re-hit 14, ends 25.
- Death clip (Timeline_30): blink 24 f, frame 25 `destroy()` (no BossDead). `destroy`:
  - dead with live children: invisible, invuln 60, every child `goToReburn()`; does NOT super.destroy (stays in array in "dead").
  - dead without children: dropAura, dropStone, super.destroy, doors.
  - not dead (fell out): super.destroy.
- Bugs: second burst row fires even if boss died; positions hard-coded to sl81 arena.

### Monster62 — 楚江王's leech (summoned by 61)
- lib 8; not boss. mDef 0.99 (magic-immune in practice).
- hit1 (hit1_6): frame 7 vx = ±10, vy = −15 (leap; `isCanMoveWhenAttack` = hit1); frame 20 `doHit1`: first hero within 100 px centre distance, not invuln (and not Role3 in "hit7-1") → invuln 9999, action "fixed", `stickyHero = hero`; else wait.
- Attached `step` (skips super.step entirely: no physics/AI/CD/invuln countdown): position = (hero.x, hero.y−30); every 24 f up to 10 times: `hero.reduceHp(100)` + `source.cureHp(1000)` (skipped while Role3 in hit7-1). After 10 ticks: invuln 10, release, wait. Hero dies → just clears stickyHero.
- `isAttacking` = hit1|fixed|reburn; `mygotoAndStop` never leaves "reburn".
- `goToReburn()` (from dying 61): 61 gets invuln 50 + setStatic; child releases hero, invuln 50, setStatic, plays "reburn" (frozen). Reburn clip (Timeline_7) frame 48 `doReBurn()`: if 61 still dead → 61 moves to child x, visible, `setFullHp()`, wait; then child `reduceHp(9999)`. Net: any live children → boss revives at full HP once, all children die.
- Death (Timeline_11): dropAura+destroy; `destroy` → `source.removeFromChildRenArray(this)`.
- Bugs: if the latched hero dies, invuln ~9999 and "fixed" persist → nearly unkillable minion; `sourceMonster` not null-checked.

### Monster63
- lib 8; 8-1 ×40. Hurt guard, base AI. Data-only. Death Timeline_40 frame 20 dropAura+destroy.

### Monster64 — 宋帝王 (9-1 boss)
- lib 9; isBoss. Template B (attackRange 150): far CD1 → face, hit3 (CD 180, invuln 20); near 24 f: CD2 → hit2 (CD 260, invuln 15) else hit1.
- hit1 (Timeline_15): frame 7 → `SpecialEffectBullet("Monster64Bullet3")` at self, boss facing; re-hit 7 (2 hits); dies 11.
- hit2 (Timeline_14): frame 11 `doHit2Pre` stores (target.x, 480); frame 22 `doHit2` → `SpecialEffectBullet("Monster64Bullet1")` there; re-hit 11, 19, 27, 34 (≤5 hits), dies 40, knockback [0,−15]. y 480 = hard-coded floor.
- hit3 (Timeline_16): frame 15 → `SpecialEffectBullet("Monster64Bullet2")` at self; dies 16.
- Death: blink + BossDead. `destroy` → `StageListener91.start1()` (2 s later `createMonster(65 + round(rand), 1450, 310)`), doors.

### Monster65 / Monster66 — loot objects (9-1)
- lib 9; spawned after 64. horizenSpeed 0, attackRange 0, drop probability 1 (65 drops "jxbuff", 66 "xique").
- `attackTarget`/`normalWalk` no-ops; `move()` forces vx = 0 (vy 0 on ground). Death clip: dropAura at frame 25, destroy at 72 (65) / 80 (66). Implement as static breakable with guaranteed drop.

### Monster67 — 五官王 (10-2 boss)
- lib 10; isBoss. Hurt guard.
- Template B (attackRange 150): far CD1 → face, hit3 summon (CD 180, invuln 20); near 24 f: CD2 → hit2 (CD 260, invuln 42) else hit1 (invuln 10).
- hit2: frame 20 `doHit2Pre` → 3 × `SpecialEffectBullet("Monster67Bullet2")` at front offsets 138, 100, 72, y−80 (action hit2-1, 9 f); frame 43 `doHit2` → `SpecialEffectBullet("Monster67Bullet1")` 160 px in front, y+60 (action hit2, poison 120 f power 100, 23 f).
- hit3: frame 8 `doHit3` → `createMonster(68, x ± 70 front, y−30)` only if `monsterArray.length < 4`; ends 14. hit1 20 f.

### Monster68 — ghost turret (summoned by 67)
- lib 10; not boss; mDef 0.99. `move()` forces vx = 0 (turns/plays walk but never moves).
- `mygotoAndStop` only changes label when current label is wait/hurt/dead → attacks can't be interrupted (no try/catch).
- `myIntelligence`: base AI (hit1 with isattback roll) when not hurt; `liveCount` 360 ticks → `destroy()` (no exp, no death anim).
- hit1: frame 25 `doHit1` → face target, `SpecialEffectBullet("Monster68Bullet1")` ±10 front, y−30 (26 f). Dead clip frame 17 destroy (no aura).

### Monster69 — 卞城王 (10-3 boss) + clones
- lib 10. `isBoss` only if `monsterArray` empty at construction (first = boss; clones: not boss, exp 0).
- `beAttackBack` override: each knockback `fenshenCount--` (start 20).
- `hasAttackTarget` (return if attacking; "fenshen" counts): fenshenCount==0 → action "fenshen", invuln 34, reset 10+rand·10; far & CD2 → face, hit2 (CD 180, invuln 10); far → follow; near 24 f: CD1 → hit3 (CD 260, invuln 55) else hit1 (invuln 10). |dy| > 300 → normalWalk.
- fenshen clip frame 32 `doFenshen`: if `monsterArray.length < 5` → clone Monster69 at x±20, `setDisAppearCount(480)` (dies via reduceHp(huge) after 480 AI ticks). Boss tracks clones, kills them on destroy.
- hit2: `doHit2` at frames 4, 7, 11, 14, 17, 20 → `SpecialEffectBullet("Monster69Bullet1")` at (x, y−20+rand±40), 16 f each (6 shots).
- hit3: re-hit at 18, 23, 28, 33, 39, 44, 50 (7 hits), `shake(15)` at 18, 28, 39, 50; ends 55. hit1 30 f.
- Quirk: clones have full HP and AI and can clone themselves (untracked, but they time out).

### Monster70 — hub round selector (10 hub)
- lib 10; created by StageListener101 at (450,423). Not boss.
- `step` fully overridden: only invuln countdown + HP refill (HP < 100000 → 1,000,000). No physics/AI/HP bar/damage numbers; `gotoAndStop/gotoAndPlay/move/attackTarget/faceToTarget` no-ops. No lifesteal.
- `beAttackBack` → `pointMc.play()` (5-frame pointer, stops each frame → +1 per hit, wraps 5→1) + invuln 24. `getDoorIdx()` = pointMc.currentFrame − 1 (0..4).
- StageListener101: when both 71 stones `isInBeattack()`, door idx 0–3 → open TransferDoor[idx] (→ levels 10-2..10-5 via W), idx 4 → remove 70 from display (not from monsterArray — bug) and open the statue (10-6).

### Monster71 — hub stone (×2)
- lib 10; at (140,325) and (800,325). Same unkillable-prop overrides as 70.
- `beAttackBack` → `beAttackCount = 12` (−1/f); `isInBeattack()` = count > 0. Both must be hit within 12 f of each other to trigger the selected door.

### Monster72 — 都市王 (10-5 boss)
- lib 10; isBoss. `upCount` 10, −1 per knockback (knockback ignored while label hit3).
- `hasAttackTarget` (return if attacking): upCount==0 → forced hit3, reset 5+rand·5; far & CD1 → face, hit3 (CD 140); far → follow; near 24 f: CD2 → hit2 net (CD 260, invuln 35) else hit1.
- During hit3: hurt swallowed (label stays), no knockback, `move()` zeroes vx, `isCanMoveWhenAttack` true.
- hit3: frame 10 `createLight` → `Monster72Light2` fx at (x, y−100) (25 f); frame 30 vy = −40; frame 36 setStatic; frame 50 `doHit3`: x = target.x, y = 430 (teleport), then 50 % hit3-1 (invuln 46; 46 f, nested re-hit every 3 f, 9 hits, no knockback) / 50 % hit3-2 (invuln 30; 30 f, knockback 15).
- hit2: frame 5 → `SpecialEffectBullet("Monster72Bullet1")` 150 px front, y; attackInterval 1, hitMaxCount 50; applies "net" debuff 24·99 f; bullet lives 192 f and on its last frame calls `cureDebuff()` on hero1 and hero2 (= net release). hit1 15 f.
- Bugs: release clears ALL hero debuffs; boss death before frame 192 destroys bullet → net lasts 99 s; landing y hard-coded 430.

### Monster73 — 泰山王 normal form (10-4)
- lib 10; isBoss. `myIntelligence` skipped while hurt/attacking; clamp x ≥ −20; y > 1000 → respawn (500,300). Constructor skillCD2 = 480.
- `hasAttackTarget` order: HP < 50 % → `turnBig`: `createMonster(75, x, y−50)`, `setInitHp(curHp)`, destroy self. Else CD2==0 → `createMonster(74, x, y−10)` with cur HP, destroy self. Else (|dy| ≤ 600, attackRange 300): far & CD1 → face, hit2 dash (CD 180, invuln 28); far → every 24 f 50 % attack / follow; near 24 f: 50 % hit1 (invuln 15) / stop.
- hit2 dash: frame 1 setStatic, frame 21 vx = ±40 forward (`isCanMoveWhenAttack` = hit2 → undamped), frame 31 setStatic, frame 45 wait. hit1 15 f.
- `destroy` opens doors only if actually dead (form changes don't). Old form fades 1 s ("ghost") while new is active; target/facing not carried over.
- Bug: CD2 assignment after form change goes to the destroyed object (dead code).

### Monster74 — 泰山王 reflect form
- lib 10; from 73. isBoss. Same AI as 73 minus form changes; isattback 70, attackRange 200; hit2 dash invuln 28 CD 180 (nested clip: setStatic 1, vx ±40 at 21, setStatic 32; 40 f); hit1 invuln 15.
- `timeCount` 240 AI ticks → if alive `createMonster(73, x, y−10)` with cur HP, destroy self.
- **100 % damage reflect** to attacker (BaseMonster hook).

### Monster75 — 泰山王 big form
- lib 10; from 73 (<50 %) or 76. isBoss; double damage. Constructor skillCD2 = 480.
- `hasAttackTarget`: CD2==0 (any distance) → `createMonster(76)` with cur HP, destroy self. Else 73's AI (attackRange 300, isattback 50); hit2 invuln 65, hit1 invuln 20. Never returns to 73.
- hit2 out-and-back dash: frame 1 static, 16 vx = 40 forward, 25 static, 40 newAttackId, 55 vx = 40 backward, 65 static, 79 end.

### Monster76 — 泰山王 big reflect form
- lib 10; from 75. isBoss. AI as 74 (isattback 70, attackRange 200); hit2 (75's dash clip) invuln 70; hit1 invuln 20. After 240 AI ticks → back to 75 with cur HP. 100 % reflect.

### Monster77 — 平等王 (10-6 boss)
- lib 10; isBoss. `myIntelligence`: sets `body.back` frame = `hit2Index` (telegraphs next hit2 variant), clears `mubei` ref when tombstone dead, then base AI.
- `hasAttackTarget` = template D (ignores |dy|, never follows):
  - ≤150: HP ≤ 10 % and CD3 → hit4 (CD 360, invuln 15); else 24 f 70 % hit1 / walk.
  - ≤300: CD2 → 80 % per frame hit3 (CD 240, invuln 70); else 70/30.
  - ≤800: CD1 → hit2 (CD 240+rand·100, invuln 26, `hit2Index` = 1..4 random); else CD4==0 and no tombstone → hit5 (CD 1440, invuln 15); else walk.
- Timelines: hit1 45 f, re-hit 22, 37; hit2 wind-up frame 25 `doHit2` → face, invuln 15, action "hit2-N"; hit2-1/2/3 frame 7, hit2-4 frame 9 → `doHit2_N`; hit3 70 f re-hit 46; hit4 20 f; hit5 frame 7 `doHit5`, ends 26.
- `doHit2_N` → `SpecialEffectBullet("Monster77Bullet<N>")` 100 px front, y, attackInterval 999: Bullet1 30 f; Bullet2 14 f; Bullet3 48 f re-hit 9, 21, 33, 45 (≤5); Bullet4 12 f.
- `doHit5` → `createMonster(78, 470, y−300)` if none.
- hit4 HP-swap (BaseHero hook): hero HP := 10 % max; boss HP := max · heroRatioBeforeHit (full heal if hero was at full HP).
- Bug: `destroy` drops the tombstone ref but doesn't kill it; 78 isn't boss → survives BossDead and keeps draining after 77 dies.

### Monster78 — 墓碑 tombstone (summoned by 77)
- lib 10; not boss. Constructor: action "fall", invuln 24, skillCD1 24. `move()`: in air vx = 0, on ground no movement.
- `myIntelligence` (replaces AI): "fall" + standing → wait; CD1==0 → every living hero `reduceHp(200)` + `reduceMp(50)` (global, ignores defence), CD1 = 24. `isAttacking` = fall. Dead clip frame 9 dropAura+destroy. Immune to pull/Mirror.

### Monster79 — 劈天斧 / Monster80 — 风神盾 (11-1)
- lib 11; one of them per run (`createMonster(79)` → 79 or 80). isBoss; `stoneFallRate` 1.
- Base AI + hurt guard; `isCanMoveWhenAttack` = hit1 (keeps walking speed/slides during hit1).
- `destroy`: if dead → `gc.setGuoqingAtkCount()` (79) / `gc.setGuoqingDefCount()` (80) (National-Day event counters); doors visible regardless.
- Clips: hurt 7/6 f, hit1 15 f, dead frame 7/8 dropAura+destroy (direct, no BossDead).

### Monster81 — 战神刑天 (7-1, after 58)
- lib 7; created by 58 at (500,300) 5 s after 58's death. isBoss.
- Constructor scales with heroes (averaged): Hp = 500000 + avg(maxHP·50); def = 400 + avg(def); hit1 power 600 + avg(atk); hit3 power 2000 + avg(atk).
- `myIntelligence`: base AI then clamp x to [−100, 1050].
- Template D variant: ≤150 → CD3 → hit4 else 70 % hit1/walk; 150–500 → CD2 80 % → hit3 (CD 480) else 70/30; 500–800 → CD1 (140+rand·100) → hit2 pull; else walk.
- hit2 pull (Timeline_10, invuln 48): frame 7 `doHit2` → tween all heroes to boss over 0.6 s; ends 30.
- hit3 (Timeline_14, invuln 35): re-hit 18, ends 35.
- hit4 (Timeline_21, invuln 50): re-hit 6, 11, 16, 21, 27, 38; frame 40 invuln 25 + vx = ±40 forward; frame 54 setStatic; frame 64 wait. `isCanMoveWhenAttack` true in hit4 from body frame 40 → ~14 f × 40 px ≈ 560 px dash.
- hit1 = base attackTarget (20 f), no invuln. Death: blink + BossDead; doors visible.
