class_name Layers
extends RefCounted
## Screen size and draw order shared by gameplay and UI (kept out of Level so nothing depends on the level for them).
## Draw order (z_index), back to front, follows the child order of the original gameSence: monsters are inserted under
## the hero (MainGame.createMonster), pickups / effects / bullets are added on top. Everything that is part of the
## stage's machinery (the 机关 layer: exit portal, entrances, doors, statue, boss walls, fires, boat, platforms) sits above
## the background art and below the ground, so the ground's edge covers their feet.

const VIEW := Vector2(940, 590)
const MAX_MONSTERS := 6

const Z_BEHIND_ART := -12   ## shows through holes of the stage art (10-1 doors)
const Z_ART := -10          ## background art, with the decoration standing on the ground
const Z_MECHANISM := -8     ## 机关
const Z_GROUND := -7        ## the floor strip (and anything else the scene lists above the mechanisms)
const Z_MONSTER := -1
const Z_HERO := 0
const Z_PICKUP := 1         ## dropped items, potions, soul orbs
const Z_TREASURE := 2       ## the hero's magic treasure
const Z_EFFECT := 3         ## projectiles and effects
const Z_NUMBER := 100       ## damage numbers
const Z_DEBUG := 200        ## debug overlay
const Z_TIP := 10           ## item tooltip over a screen
const Z_TOAST := 50         ## notices
