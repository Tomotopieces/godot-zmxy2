extends StageScript
## 10-1 (StageListener101), the hub of the underworld: four doors and a statue. Hitting the round selector moves
## its pointer; hitting both stones at (nearly) the same time opens what the pointer shows: door 1-4 lead to
## 10-2 .. 10-5, the fifth position opens the statue to 10-6. Press up in an open door to go.

## The doors are scenes of their own (scenes/objects/hub_door.tscn) placed in the stage scene (Objects/HubDoor1..4) behind
## the hall art, so they show through its arches; the statue (Objects/HubStatue) stands in front of it. Their z_index and
## their open timings are the scene's business, here only the selector / stones are still built from data/stages.json.

var _doors: Array[HubDoor] = []  ## the four doors, in the selector's order
var _statue: HubStatue
var _selector: Monster
var _stones: Array[Monster] = []
var _cfg: Dictionary

func setup() -> void:
	_cfg = param("hub", {})
	for i in _cfg.get("levels", [2, 3, 4, 5]).size():
		var door := level.world.get_node_or_null("Objects/HubDoor%d" % (i + 1)) as HubDoor
		if door != null:
			_doors.append(door)
	_statue = level.world.get_node_or_null("Objects/HubStatue") as HubStatue
	var sel: Array = _cfg.get("selector", [70, 450, 423])
	_selector = _prop(sel)
	for st in _cfg.get("stones", []):
		_stones.append(_prop(st))

func _prop(spec: Array) -> Monster:
	var md := level.monster_data(int(spec[0]))
	if md == null:
		return null
	var m := Monster.create(md)
	m.position = Vector2(spec[1], spec[2])
	level.add_prop(m)
	return m

func _physics_process(_delta: float) -> void:
	if _stones.size() < 2 or _selector == null:
		return
	for s in _stones:
		if not is_instance_valid(s) or not s.brain.recently_hit():
			return
	var idx: int = (_selector.brain as HubPropBrain).pointer
	if idx < _doors.size():
		_open_door(idx)
	else:
		_open_statue()

func _open_door(i: int) -> void:
	if _doors[i].is_open():
		return
	_doors[i].open()

func _open_statue() -> void:
	if _statue == null or _statue.is_open():
		return
	if is_instance_valid(_selector):
		_selector.queue_free()
	_statue.open()

func on_up(_hero: Hero) -> bool:
	var levels: Array = _cfg.get("levels", [2, 3, 4, 5])
	for door in _doors:
		if door.ready_to_enter and door.index < levels.size() and door.hero_inside(_hero):
			level.go_to(Vector2i(10, int(levels[door.index])))
			return true
	if _statue != null and _statue.ready_to_enter and _statue.hero_inside(_hero):   # its "colipse" box is the central slot
		level.go_to(Vector2i(10, int(_cfg.get("statue_level", 6))))
		return true
	return false
