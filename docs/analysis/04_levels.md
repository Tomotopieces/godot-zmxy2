# 原作分析 04：关卡结构

## 加载
- MainGame.GameStart(stage, level)：若 files{stage} 类不存在则加载资源 SWF：stage 1→"1_v6"，5→"5_v7"(随后再载 "1")，其他→"{stage}"。
- 场景类 export.gameSence.sl{stage}{level}（继承 BaseGameSence，在主 SWF 中定义，美术/元件在关卡 SWF）。
- 背景：floorBg{stage}（BitmapData）作为远景 bg1，按视差滚动。
- 英雄出生点 (200,200)，P2 (300,200)。
- 每屏最大怪数 maxMonsterPerScreen：单人 6，双人 8。
- 关卡逻辑：export.level.StageListener{stage}{level}（BOSS 战、机关、剧情）。

## 场景内对象（PhysicsWorld.addSubObj 按子对象名识别）
- isWall：墙/地面（rotation≠0 为斜坡，像素检测）；isThroughWall：单向平台；isTurnBack：怪物掉头标记；
  noContinueGo：怪物禁止通行；isTransferDoor：过关传送门（按上键）；isthron：地刺；monsterDisapperaPoint：刷怪点；
  isFb：副本入口；isHideWall 等特殊机关；stophere：镜头停止点（按 x 排序）。

## 刷怪：StopPoint + MonsterAppearPoint
- StopPoint：idx、betweenRandL（默认 1150；第 1 大关 1450；4-1、9-1 为 940）= 停止后允许回退的范围。
  镜头卷到停止点 → touch() → 激活所有 stopPointIdx==idx 的刷怪点；全部刷完且场上无怪 → destroy()，出现 "GOGO" 提示，自动卷屏到下一个。
- MonsterAppearPoint：enemyType（→ export.monster.Monster{N}）、delay（秒）、interval（秒）、totalNum、isRandom、stopPointIdx。
  场上怪物数 < maxMonsterPerScreen 才生成。
- 1-1 示例：5 个停止点；Monster30/31 普通怪，Monster32 在最后。

## 怪物示例 Monster30（1_v6，第一关小怪）
- 走速 5，HP 80，视野 300，攻击概率 50%，攻击距离 80，防 2，经验 5，怒气 1。
- hit1：power 8，physics，击退 [2,-5]；攻击中可移动（扑击）；受击时不思考。
- 掉落：普通装备列表。
