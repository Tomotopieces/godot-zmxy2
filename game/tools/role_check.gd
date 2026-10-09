extends Node
## Roles: stats, save round-trip with the role, account unlock. godot --headless --path game res://tools/role_check.tscn
var _fails := 0
func _check(what: String, ok: bool) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
func _ready() -> void:
	var keep_unlock: bool = GameState.unlocked.bajie
	GameState.new_game("tangseng")
	_check("tangseng stats", GameState.hero_data.max_hp(1) == 50 and GameState.hero_data.max_mp(1) == 100 and GameState.hero_data.defense(20) == 19)
	_check("tangseng wears 唐僧 gear only", GameState.can_wear(GameState.make_item("ptsmz")) and not GameState.can_wear(GameState.make_item("ptxzg")))
	GameState.new_game("bajie")
	_check("bajie stats", GameState.hero_data.max_hp(20) == 1430 and GameState.hero_data.max_mp(20) == 320 and GameState.hero_data.defense(20) == 23)
	_check("bajie wears 八戒 gear only", GameState.can_wear(GameState.make_item("ssc")) and not GameState.can_wear(GameState.make_item("ptxzg")))
	GameState.level = 9
	_check("save", GameState.save_to(5))
	GameState.new_game("wukong")
	_check("load restores the role", GameState.load_from(5) and GameState.role == "bajie" and GameState.level == 9 and GameState.hero_data.role == "bajie")
	_check("hero classes", Hero.create() is HeroBajie)
	GameState.new_game("tangseng")
	_check("tangseng class", Hero.create() is HeroTangseng)
	_check("hud icon frames", GameState.hero_data.hud_icon_base() == 6)
	GameState.unlocked.bajie = keep_unlock
	var f := ProjectSettings.globalize_path(SaveGame.SLOT_FILE % 5)
	OS.move_to_trash(f)
	OS.move_to_trash(f + ".bak")
	print("ROLE CHECK ", "FAILED (%d)" % _fails if _fails else "OK")
	get_tree().quit(1 if _fails else 0)
