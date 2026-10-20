extends Node3D
## The player's helicopter: horizontal strafing, banking, primary weapon tiers, missiles, nukes and armour.
## Forward motion is along -Z; the helicopter strafes along X inside the lane.

signal damaged(amount: float)
signal died

const Cfg = preload("res://scripts/core/config.gd")
const HeliModel = preload("res://scripts/battle/heli_model.gd")

var projectiles = null
var fx = null
var world = null
var enemies = null

var alive: bool = true
var hp: float = Cfg.HELI_MAX_HP
var max_hp: float = Cfg.HELI_MAX_HP
var vx: float = 0.0
var fwd_speed: float = Cfg.FWD_SPEED_MIN
var tier: int = 0
var power_t: float = 0.0
var missiles: int = Cfg.START_MISSILES
var nukes: int = Cfg.START_NUKES
var missile_cd: float = 0.0
var nuke_cd: float = 0.0
var fire_cd: float = 0.0
var invuln: float = 0.0
var showcase: bool = false

var _holder: Node3D = null
var _model: Dictionary = {}
var _shadow: MeshInstance3D = null
var _t: float = 0.0
var _show_yaw: float = 0.0
var _fx_t: float = 0.0
var _smoke_t: float = 0.0


func setup(projectiles_ref, fx_ref, world_ref, enemies_ref) -> void:
	projectiles = projectiles_ref
	fx = fx_ref
	world = world_ref
	enemies = enemies_ref
	_holder = Node3D.new()
	add_child(_holder)
	var disc := CylinderMesh.new()
	disc.top_radius = 2.8
	disc.bottom_radius = 2.8
	disc.height = 0.04
	disc.radial_segments = 12
	disc.rings = 1
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.0, 0.0, 0.0, 0.35)
	_shadow = MeshInstance3D.new()
	_shadow.mesh = disc
	_shadow.material_override = sm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	apply_skin(GameState.selected_skin)


func apply_skin(index: int) -> void:
	var i: int = clampi(index, 0, GameState.SKINS.size() - 1)
	var skin: Dictionary = GameState.SKINS[i]
	if not _model.is_empty():
		var old: Node3D = _model["root"]
		old.queue_free()
	var pal: Dictionary = {
		"body": skin["body"],
		"accent": skin["accent"],
		"glass": skin["glass"],
		"glow": skin["glow"],
	}
	_model = HeliModel.build(pal, 0.85)
	_holder.add_child(_model["root"])


func set_model_visible(v: bool) -> void:
	_holder.visible = v
	_shadow.visible = v and not GameState.shadows


func reset(pos: Vector3) -> void:
	position = pos
	hp = max_hp
	vx = 0.0
	tier = 0
	power_t = 0.0
	missiles = Cfg.START_MISSILES
	nukes = Cfg.START_NUKES
	missile_cd = 0.0
	nuke_cd = 0.0
	fire_cd = 0.0
	invuln = 0.0
	alive = true
	showcase = false
	_holder.rotation = Vector3.ZERO
	set_model_visible(true)


func current_tier() -> Dictionary:
	return Cfg.TIERS[tier]


# ------------------------------------------------------------------ per-frame

func step(dt: float, move_x: float, fire_held: bool, distance: float) -> void:
	_t += dt
	fwd_speed = lerpf(Cfg.FWD_SPEED_MIN, Cfg.FWD_SPEED_MAX, clampf(distance / 6000.0, 0.0, 1.0))
	vx = move_toward(vx, clampf(move_x, -1.0, 1.0) * Cfg.STRAFE_SPEED, Cfg.STRAFE_ACCEL * dt)
	position.x += vx * dt
	if position.x > Cfg.LANE_HALF:
		position.x = Cfg.LANE_HALF
		vx = minf(vx, 0.0)
	elif position.x < -Cfg.LANE_HALF:
		position.x = -Cfg.LANE_HALF
		vx = maxf(vx, 0.0)
	position.z -= fwd_speed * dt
	_animate(dt)

	missile_cd = maxf(0.0, missile_cd - dt)
	nuke_cd = maxf(0.0, nuke_cd - dt)
	invuln = maxf(0.0, invuln - dt)
	if tier > 0:
		power_t -= dt
		if power_t <= 0.0:
			tier -= 1
			power_t = Cfg.WEAPON_POWER_TIME if tier > 0 else 0.0
	fire_cd -= dt
	if fire_held and alive and fire_cd <= 0.0:
		_fire_primary()
		fire_cd = float(Cfg.TIERS[tier]["rate"])


## Title-screen flight: gentle automatic sweeping, no weapons.
func step_attract(dt: float) -> void:
	_t += dt
	fwd_speed = 14.0
	var nx: float = sin(_t * 0.45) * 20.0
	vx = (nx - position.x) / maxf(dt, 0.0001)
	position.x = nx
	position.z -= fwd_speed * dt
	_animate(dt)


## Hangar: the helicopter hovers in place and slowly turns.
func step_showcase(dt: float) -> void:
	_t += dt
	_show_yaw += dt * 0.7
	_holder.rotation = Vector3(-0.05, _show_yaw, 0.0)
	position.y = Cfg.HELI_HOVER + sin(_t * 1.6) * 0.3
	_spin_rotors(dt)


func _animate(dt: float) -> void:
	position.y = Cfg.HELI_HOVER + sin(_t * 2.1) * 0.35
	var bank: float = -vx / Cfg.STRAFE_SPEED * 0.45
	var k: float = 1.0 - exp(-9.0 * dt)
	_holder.rotation.z = lerpf(_holder.rotation.z, bank, k)
	_holder.rotation.x = lerpf(_holder.rotation.x, -0.14, k)
	_holder.rotation.y = lerpf(_holder.rotation.y, -vx * 0.008, k)
	_spin_rotors(dt)
	if not GameState.shadows:
		var gy: float = world.height_at(position.x, position.z)
		_shadow.position = Vector3(0.0, gy + 0.3 - position.y, 0.0)
	_shadow.visible = _holder.visible and not GameState.shadows
	_visual_fx(dt)


## Purely cosmetic: engine exhaust shimmer and trailing smoke when badly damaged.
func _visual_fx(dt: float) -> void:
	if fx == null or not alive or not _holder.visible:
		return
	_fx_t -= dt
	if _fx_t <= 0.0:
		_fx_t = 0.07
		var tail_pos: Vector3 = position + Vector3(0.0, 1.2, 4.9)
		fx.puff(tail_pos, Vector3(0.0, 0.4, 5.0), 0.28, 0.35, 0.9, Color(1.0, 0.75, 0.45, 0.35), Color(0.8, 0.8, 0.85, 0.0), 0.0, 0.0, true)
	if hp < max_hp * 0.4:
		_smoke_t -= dt
		if _smoke_t <= 0.0:
			_smoke_t = 0.06 if hp < max_hp * 0.2 else 0.11
			fx.puff(position + Vector3(0.6, 1.4, 0.8), Vector3(0.0, 2.5, 3.0), 0.9, 0.7, 2.2, Color(0.12, 0.12, 0.12, 0.7), Color(0.06, 0.06, 0.06, 0.0), 0.0, 0.4)
			if hp < max_hp * 0.2:
				fx.puff(position + Vector3(0.4, 1.0, 1.0), Vector3(0.0, 1.0, 2.0), 0.3, 0.7, 0.2, Color(1.0, 0.5, 0.15, 0.9), Color(1.0, 0.2, 0.05, 0.0), 0.0, 0.0, true)


func _spin_rotors(dt: float) -> void:
	if _model.is_empty():
		return
	var rotor: Node3D = _model["rotor"]
	var tail: Node3D = _model["tail"]
	rotor.rotation.y += 36.0 * dt
	tail.rotation.x += 46.0 * dt
	var lights: Array = _model["lights"]
	for i in range(lights.size()):
		var l: MeshInstance3D = lights[i]
		if i == 2:
			l.visible = fmod(_t * 1.3, 1.0) < 0.12
		else:
			l.visible = fmod(_t * 0.9 + float(i) * 0.5, 1.0) < 0.7


# ------------------------------------------------------------------ weapons

func _ground_goal(x: float, z: float) -> float:
	return maxf(world.height_at(x, z - 40.0) + 3.0, 4.0)


func _fire_primary() -> void:
	var t: Dictionary = Cfg.TIERS[tier]
	var kind: int = int(t["kind"])
	var nb: int = int(t["barrels"])
	var spd: float = float(t["speed"])
	var dmg: float = float(t["damage"])
	var pierce: int = int(t["pierce"])
	var splash: float = float(t["splash"])
	var offsets: Array = [0.0]
	if nb == 2:
		offsets = [-1.4, 1.4]
	elif nb == 3:
		offsets = [-2.0, 0.0, 2.0]
	var life: float = 1.7
	var flash_col := Color(1.0, 0.85, 0.35)
	if kind == Cfg.K_BULLET:
		life = 1.1
	elif kind == Cfg.K_LASER:
		life = 0.9
		flash_col = Color(0.4, 0.95, 1.0)
	else:
		flash_col = Color(0.6, 1.0, 0.4)
	var goal: float = _ground_goal(position.x, position.z)
	for k in range(nb):
		var ang: float = 0.0
		if nb == 3:
			ang = float(k - 1) * 0.05
		var origin: Vector3 = position + Vector3(float(offsets[k]), -0.4, -2.6)
		var vel := Vector3(sin(ang) * spd + vx * 0.2, 0.0, -cos(ang) * spd - fwd_speed)
		projectiles.fire(kind, origin, vel, dmg, life, true, pierce, splash, goal, 80.0)
		fx.muzzle(origin + Vector3(0.0, 0.0, -0.6), flash_col)
	if kind == Cfg.K_BULLET:
		Feedback.play("shot", -11.0, randf_range(0.92, 1.1))
	elif kind == Cfg.K_LASER:
		Feedback.play("laser", -12.0, randf_range(0.95, 1.1))
	else:
		Feedback.play("plasma", -11.0, randf_range(0.9, 1.05))


func try_missile() -> bool:
	if not alive or missiles <= 0 or missile_cd > 0.0:
		return false
	missiles -= 1
	missile_cd = Cfg.MISSILE_COOLDOWN
	var origin: Vector3 = position + Vector3(0.0, -0.8, -3.0)
	var target = enemies.find_target(position, 30.0)
	projectiles.fire(Cfg.K_MISSILE, origin, Vector3(0.0, 0.0, -(fwd_speed + 30.0)), Cfg.MISSILE_DAMAGE, 3.2, true, 0, 0.0, _ground_goal(position.x, position.z), 30.0, target)
	fx.muzzle(origin, Color(1.0, 0.7, 0.3))
	Feedback.play("missile", -3.0, randf_range(0.95, 1.05))
	Feedback.vibrate(35)
	return true


func try_nuke() -> bool:
	if not alive or nukes <= 0 or nuke_cd > 0.0:
		return false
	nukes -= 1
	nuke_cd = Cfg.NUKE_COOLDOWN
	var origin: Vector3 = position + Vector3(0.0, -1.0, -3.5)
	projectiles.fire(Cfg.K_NUKE, origin, Vector3(0.0, 0.0, -(fwd_speed + 32.0)), 0.0, 1.3, true, 0, 0.0, world.height_at(position.x, position.z - 70.0) + 2.0, 9.0)
	Feedback.play("missile", -2.0, 0.6)
	Feedback.vibrate(60)
	return true


# ------------------------------------------------------------------ health and pickups

func take_damage(amount: float) -> void:
	if not alive or invuln > 0.0:
		return
	hp = maxf(0.0, hp - amount)
	invuln = 0.12
	damaged.emit(amount)
	if hp <= 0.0:
		alive = false
		died.emit()


## Applies a collected pickup and returns the message to show on the HUD.
func apply_pickup(kind: int) -> String:
	if kind == Cfg.P_WEAPON:
		if tier < Cfg.MAX_TIER:
			tier += 1
			power_t = Cfg.WEAPON_POWER_TIME
			var t: Dictionary = Cfg.TIERS[tier]
			return "WEAPON UPGRADE: %s x%d" % [String(t["name"]), int(t["barrels"])]
		power_t = Cfg.WEAPON_POWER_TIME
		return "WEAPON POWER MAXED"
	if kind == Cfg.P_MISSILE:
		missiles = mini(Cfg.MAX_MISSILES, missiles + Cfg.MISSILE_PICKUP_AMOUNT)
		return "+%d MISSILES" % Cfg.MISSILE_PICKUP_AMOUNT
	if kind == Cfg.P_NUKE:
		nukes = mini(Cfg.MAX_NUKES, nukes + Cfg.NUKE_PICKUP_AMOUNT)
		return "TACTICAL NUKE ACQUIRED"
	hp = minf(max_hp, hp + Cfg.REPAIR_AMOUNT)
	return "ARMOR REPAIRED"
