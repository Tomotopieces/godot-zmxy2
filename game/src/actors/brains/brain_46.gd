extends "res://src/actors/brains/boss_d.gd"
## Monster46 红孩儿 (6-1 boss). Template D, but the constructor checks the hero's level: above `hard_level` he gets the
## hard numbers (more HP, defence, attack power) and drops 金刚甲 (八戒's armour); otherwise the easy ones in the data.

func setup() -> void:
	var hard: Dictionary = param("hard", {})
	if hard.is_empty() or GameState.level <= int(param("hard_level", 15)):
		return
	var d: MonsterData = m.data.duplicate()
	d.attacks = {}
	for k in m.data.attacks:
		var a: AttackData = m.data.attacks[k].duplicate()
		a.flat = int(hard.powers.get(String(k), a.flat))
		d.attacks[k] = a
	d.def = int(hard.def)
	d.equip_drops = PackedStringArray(hard.drops)
	m.data = d
	m.max_hp = int(hard.hp)
	m.hp = m.max_hp

## The first kill of 红孩儿 unlocks 猪八戒 for the account (Monster46.destroy: openPig).
func on_died() -> void:
	super()
	if not GameState.unlocked.get("bajie", false):
		GameState.unlock("bajie")
		m.world.toast("解锁新角色：猪八戒")
