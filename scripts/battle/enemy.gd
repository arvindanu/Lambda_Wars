extends Node3D
## One enemy unit. The manager (enemies.gd) drives movement and firing; this node holds state and visuals.

const Cfg = preload("res://scripts/core/config.gd")
const EnemyModels = preload("res://scripts/battle/enemy_models.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")

static var _flash_mat: StandardMaterial3D = null

var type: String = "jeep"
var hp: float = 10.0
var max_hp: float = 10.0
var radius: float = 2.0
var points: int = 0
var speed: float = 0.0
var air: bool = false
var dead: bool = false
var mid_height: float = 1.5
var age: float = 0.0
var fire_t: float = 1.5
var burst_left: int = 0
var burst_t: float = 0.0
var warn_t: float = 0.0
var phase: float = 0.0
var amp: float = 16.0
var hover_ahead: float = 45.0
var on_road: bool = false
var lane_off: float = 0.0
var flash_t: float = 0.0
var model_root: Node3D = null
var turret: Node3D = null
var rotor: Node3D = null
var tail: Node3D = null
var lights: Array = []
var parts: Array = []
var bar: MeshInstance3D = null

var _bar_w: float = 4.0


func setup(t: String, hp_mult: float, rng: RandomNumberGenerator) -> void:
	type = t
	var d: Dictionary = Cfg.ENEMIES[t]
	max_hp = float(d["hp"]) * hp_mult
	hp = max_hp
	radius = float(d["radius"])
	points = int(d["score"])
	speed = float(d["speed"])
	air = bool(d["air"])
	phase = rng.randf() * TAU
	amp = rng.randf_range(10.0, 22.0)
	hover_ahead = rng.randf_range(38.0, 62.0)
	fire_t = rng.randf_range(0.8, 2.2)

	var built: Dictionary = EnemyModels.build(t)
	model_root = built["root"]
	add_child(model_root)
	turret = built["turret"]
	rotor = built["rotor"]
	tail = built["tail"]
	lights = built["lights"]
	parts = built["parts"]
	var height: float = float(built["height"])
	mid_height = height * 0.5
	if not air:
		model_root.rotation.y = PI

	_bar_w = radius * 1.8
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.12, 0.4)
	bar = MeshInstance3D.new()
	bar.mesh = bm
	bar.material_override = MeshKit.glow(Color(1.0, 0.3, 0.25))
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position = Vector3(0.0, height + 1.2, radius + 0.6)
	bar.scale = Vector3(_bar_w, 1.0, 1.0)
	bar.visible = false
	add_child(bar)


func hit_flash() -> void:
	flash_t = 0.07
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1.0, 1.0, 1.0)
	for p in parts:
		p.material_override = _flash_mat
	var frac: float = clampf(hp / max_hp, 0.0, 1.0)
	bar.visible = frac < 0.999 and not dead
	var w: float = maxf(_bar_w * frac, 0.05)
	bar.scale = Vector3(w, 1.0, 1.0)
	bar.position.x = -(_bar_w - w) * 0.5


func update_visual(dt: float) -> void:
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0:
			for p in parts:
				p.material_override = null
	if rotor != null:
		rotor.rotation.y += 34.0 * dt
	if tail != null:
		tail.rotation.x += 40.0 * dt
	for i in range(lights.size()):
		var l: MeshInstance3D = lights[i]
		l.visible = fmod(age * 1.7 + float(i) * 0.4, 1.0) < 0.35
