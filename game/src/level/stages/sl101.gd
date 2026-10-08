extends StageScript
## 10-1 (StageListener101), the hub of the underworld: four doors and a statue. Hitting the round selector moves
## its pointer; hitting both stones at (nearly) the same time opens what the pointer shows: door 1-4 lead to
## 10-2 .. 10-5, the fifth position opens the statue to 10-6. Press up in an open door to go.

## The doors and the statue sit behind the hall art and show through its arches (added under the scene in the original).
const BEHIND_ART := -12

var _doors: Array[Rig] = []      ## closed or open door rigs
var _ready_doors := {}           ## door index -> true once it can be entered
var _statue: Rig
var _statue_ready := false
var _selector: Monster
var _stones: Array[Monster] = []
var _cfg: Dictionary

func setup() -> void:
	_cfg = param("hub", {})
	var y := float(_cfg.get("doors_y", 5))
	for x in _cfg.get("doors_x", []):
		_doors.append(place_rig("hub_door", Vector2(x, y), BEHIND_ART))
	_statue = place_rig("hub_statue", Vector2(float(_cfg.get("statue_x", 220)), float(_cfg.get("statue_y", 5))), BEHIND_ART)
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
		if not is_instance_valid(s) or not (s.brain as Object).call("recently_hit"):
			return
	var idx: int = (_selector.brain as Object).get("pointer")
	if idx < _doors.size():
		_open_door(idx)
	else:
		_open_statue()

func _open_door(i: int) -> void:
	if _ready_doors.has(i):
		return
	_ready_doors[i] = false
	var pos := _doors[i].position
	_doors[i].queue_free()
	_doors[i] = place_rig("hub_door_open", pos, BEHIND_ART)
	get_tree().create_timer(float(_cfg.get("door_open", 0.65)), false).timeout.connect(func(): _ready_doors[i] = true)

func _open_statue() -> void:
	if _statue_ready or _statue == null or not _statue.is_inside_tree():
		return
	if is_instance_valid(_selector):
		_selector.queue_free()
	var pos := _statue.position
	_statue.queue_free()
	_statue = place_rig("hub_statue_open", pos, BEHIND_ART)
	get_tree().create_timer(float(_cfg.get("statue_open", 1.0)), false).timeout.connect(func(): _statue_ready = true)

func on_up(_hero: Hero) -> bool:
	var levels: Array = _cfg.get("levels", [2, 3, 4, 5])
	for i in _doors.size():
		if _ready_doors.get(i, false) and hero_in(_doors[i].hit_rect()):
			level.go_to(Vector2i(10, int(levels[i])))
			return true
	if _statue_ready and hero_in(_statue.hit_rect()):
		level.go_to(Vector2i(10, int(_cfg.get("statue_level", 6))))
		return true
	return false
