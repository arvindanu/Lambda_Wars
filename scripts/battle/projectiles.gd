extends Node3D
## Pooled projectiles for both sides: bullets, lasers, alien energy, missiles, nukes, shells.
## Collision is resolved on the ground plane (x, z); height is purely visual.

signal nuke_detonated(pos: Vector3)
signal shake(amount: float)

const Cfg = preload("res://scripts/core/config.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")
const MeshBuilder = preload("res://scripts/util/mesh_builder.gd")

const POOL: int = 150


class ShotRec extends RefCounted:
	var active: bool = false
	var kind: int = 0
	var friendly: bool = true
	var pos: Vector3 = Vector3.ZERO
	var vel: Vector3 = Vector3.ZERO
	var dmg: float = 0.0
	var pierce: int = 0
	var splash: float = 0.0
	var life: float = 0.0
	var radius: float = 0.8
	var y_goal: float = -999.0
	var y_rate: float = 80.0
	var trail_t: float = 0.0
	var last_hit: int = 0
	var target = null
	var node: MeshInstance3D = null
	var halo: MeshInstance3D = null
	var halo_scale: Vector3 = Vector3.ONE
	var flicker: bool = false


var enemies = null
var player = null
var fx = null
var world = null

var _shots: Array = []
var _cursor: int = 0
var _meshes: Dictionary = {}
var _mats: Dictionary = {}
var _radii: Dictionary = {}
var _snd_t: float = 0.0
var _halo_mesh: Dictionary = {}
var _halo_mat: Dictionary = {}
var _halo_off: Dictionary = {}
var _halo_scale: Dictionary = {}
var halos_enabled: bool = true


func setup(enemies_ref, player_ref, fx_ref, world_ref) -> void:
	enemies = enemies_ref
	player = player_ref
	fx = fx_ref
	world = world_ref


func _ready() -> void:
	_define(Cfg.K_BULLET, _box_mesh(Vector3(0.22, 0.22, 1.7)), MeshKit.glow(Color(1.0, 0.96, 0.75)), 0.8)
	_define(Cfg.K_LASER, _box_mesh(Vector3(0.16, 0.16, 6.0)), MeshKit.glow(Color(0.85, 1.0, 1.0)), 1.0)
	_define(Cfg.K_PLASMA, _sphere_mesh(0.7), MeshKit.glow(Color(0.85, 1.0, 0.65)), 1.7)
	_define(Cfg.K_MISSILE, _missile_mesh(), null, 1.4)
	_define(Cfg.K_NUKE, _bomb_mesh(), null, 1.5)
	_define(Cfg.K_SHELL, _sphere_mesh(0.7), MeshKit.glow(Color(1.0, 0.7, 0.25)), 1.3)
	_define(Cfg.K_EBULLET, _box_mesh(Vector3(0.24, 0.24, 1.5)), MeshKit.glow(Color(1.0, 0.75, 0.5)), 0.8)
	_define(Cfg.K_EPLASMA, _sphere_mesh(0.7), MeshKit.glow(Color(1.0, 0.75, 1.0)), 1.4)

	# additive halos give every projectile a glowing aura
	_halo(Cfg.K_BULLET, _box_mesh(Vector3(0.65, 0.65, 2.9)), MeshKit.glow(Color(1.0, 0.55, 0.15), 0.42, true), Vector3.ZERO, Vector3.ONE)
	_halo(Cfg.K_LASER, _box_mesh(Vector3(0.55, 0.55, 7.6)), MeshKit.glow(Color(0.2, 0.8, 1.0), 0.5, true), Vector3.ZERO, Vector3.ONE)
	_halo(Cfg.K_PLASMA, _sphere_mesh(1.7), MeshKit.glow(Color(0.4, 1.0, 0.2), 0.4, true), Vector3.ZERO, Vector3.ONE)
	_halo(Cfg.K_SHELL, _sphere_mesh(1.5), MeshKit.glow(Color(1.0, 0.3, 0.05), 0.4, true), Vector3.ZERO, Vector3.ONE)
	_halo(Cfg.K_EBULLET, _box_mesh(Vector3(0.6, 0.6, 2.7)), MeshKit.glow(Color(1.0, 0.2, 0.1), 0.5, true), Vector3.ZERO, Vector3.ONE)
	_halo(Cfg.K_EPLASMA, _sphere_mesh(1.7), MeshKit.glow(Color(0.9, 0.2, 1.0), 0.45, true), Vector3.ZERO, Vector3.ONE)
	var flame := CylinderMesh.new()
	flame.top_radius = 0.0
	flame.bottom_radius = 0.38
	flame.height = 2.6
	flame.radial_segments = 6
	flame.rings = 1
	_halo(Cfg.K_MISSILE, flame, MeshKit.glow(Color(1.0, 0.6, 0.15), 0.8, true), Vector3(0.0, 0.0, 2.7), Vector3.ONE)
	var flame2 := CylinderMesh.new()
	flame2.top_radius = 0.0
	flame2.bottom_radius = 0.9
	flame2.height = 4.2
	flame2.radial_segments = 6
	flame2.rings = 1
	_halo(Cfg.K_NUKE, flame2, MeshKit.glow(Color(1.0, 0.5, 0.1), 0.7, true), Vector3(0.0, 0.0, 4.3), Vector3.ONE)

	for i in range(POOL):
		var s := ShotRec.new()
		s.node = MeshInstance3D.new()
		s.node.visible = false
		s.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s.node)
		s.halo = MeshInstance3D.new()
		s.halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.halo.visible = false
		s.node.add_child(s.halo)
		_shots.append(s)


func _halo(kind: int, mesh: Mesh, mat: Material, offset: Vector3, scl: Vector3) -> void:
	_halo_mesh[kind] = mesh
	_halo_mat[kind] = mat
	_halo_off[kind] = offset
	_halo_scale[kind] = scl


func _define(kind: int, mesh: Mesh, mat: Material, radius: float) -> void:
	_meshes[kind] = mesh
	_mats[kind] = mat
	_radii[kind] = radius


func _box_mesh(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _sphere_mesh(r: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m


func _missile_mesh() -> Mesh:
	var b := MeshBuilder.new()
	var grey := Color(0.75, 0.77, 0.80)
	b.frustum(Vector3(0.0, 0.0, 1.4), Vector3(0.0, 0.0, -1.0), 0.4, 0.4, 2.4, 6, grey)
	b.frustum(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -1.0), 0.4, 0.0, 1.0, 6, Color(0.85, 0.2, 0.15))
	b.box(Vector3(0.0, 0.0, 1.1), Vector3(1.8, 0.08, 0.7), Color(0.35, 0.37, 0.4))
	b.box(Vector3(0.0, 0.0, 1.1), Vector3(0.08, 1.8, 0.7), Color(0.35, 0.37, 0.4))
	return b.build(MeshBuilder.model_material())


func _bomb_mesh() -> Mesh:
	var b := MeshBuilder.new()
	var olive := Color(0.30, 0.34, 0.20)
	b.frustum(Vector3(0.0, 0.0, 2.2), Vector3(0.0, 0.0, -1.0), 1.1, 1.1, 3.4, 8, olive)
	b.frustum(Vector3(0.0, 0.0, -1.2), Vector3(0.0, 0.0, -1.0), 1.1, 0.0, 1.6, 8, olive)
	b.frustum(Vector3(0.0, 0.0, 0.3), Vector3(0.0, 0.0, -1.0), 1.14, 1.14, 0.5, 8, Color(0.95, 0.8, 0.1))
	b.box(Vector3(0.0, 0.0, 2.1), Vector3(3.0, 0.1, 1.0), Color(0.2, 0.22, 0.14))
	b.box(Vector3(0.0, 0.0, 2.1), Vector3(0.1, 3.0, 1.0), Color(0.2, 0.22, 0.14))
	return b.build(MeshBuilder.model_material())


# ------------------------------------------------------------------ spawning

func fire(kind: int, pos: Vector3, vel: Vector3, dmg: float, life: float, friendly: bool, pierce: int = 0, splash: float = 0.0, y_goal: float = -999.0, y_rate: float = 80.0, target = null) -> void:
	var s: ShotRec = _shots[_cursor]
	_cursor = (_cursor + 1) % POOL
	s.active = true
	s.kind = kind
	s.friendly = friendly
	s.pos = pos
	s.vel = vel
	s.dmg = dmg
	s.life = life
	s.pierce = pierce
	s.splash = splash
	s.radius = float(_radii[kind])
	s.y_goal = y_goal
	s.y_rate = y_rate
	s.trail_t = 0.0
	s.last_hit = 0
	s.target = target
	s.node.mesh = _meshes[kind]
	s.node.material_override = _mats[kind]
	s.node.position = pos
	s.node.visible = true
	_setup_halo(s, kind)
	_orient(s, vel)


func _setup_halo(s: ShotRec, kind: int) -> void:
	if halos_enabled and _halo_mesh.has(kind):
		s.halo.mesh = _halo_mesh[kind]
		s.halo.material_override = _halo_mat[kind]
		s.halo.position = _halo_off[kind]
		s.halo_scale = _halo_scale[kind]
		s.halo.scale = s.halo_scale
		s.halo.visible = true
		s.flicker = kind == Cfg.K_MISSILE or kind == Cfg.K_NUKE or kind == Cfg.K_PLASMA or kind == Cfg.K_EPLASMA
		if kind == Cfg.K_MISSILE or kind == Cfg.K_NUKE:
			s.halo.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		else:
			s.halo.rotation_degrees = Vector3.ZERO
	else:
		s.halo.visible = false
		s.flicker = false


func _orient(s: ShotRec, dir: Vector3) -> void:
	if dir.length_squared() < 0.01:
		return
	var n: Vector3 = dir.normalized()
	if absf(n.y) > 0.98:
		return
	s.node.look_at(s.node.position + n, Vector3.UP)


func clear() -> void:
	for s in _shots:
		s.active = false
		s.node.visible = false


func _kill_shot(s: ShotRec) -> void:
	s.active = false
	s.node.visible = false
	s.target = null


## Removes hostile projectiles inside a radius (used by nukes).
func clear_hostile(pos: Vector3, radius: float) -> void:
	var r2: float = radius * radius
	for s in _shots:
		if not s.active or s.friendly:
			continue
		var dx: float = s.pos.x - pos.x
		var dz: float = s.pos.z - pos.z
		if dx * dx + dz * dz < r2:
			_kill_shot(s)


# ------------------------------------------------------------------ update

func step(dt: float) -> void:
	_snd_t -= dt
	for s in _shots:
		if not s.active:
			continue
		s.life -= dt
		if s.kind == Cfg.K_MISSILE:
			_steer_missile(s, dt)
		s.pos += s.vel * dt
		if s.y_goal > -900.0:
			s.pos.y = move_toward(s.pos.y, s.y_goal, s.y_rate * dt)
		s.node.position = s.pos
		if s.flicker:
			var fl: float = 1.0 + 0.2 * sin(s.life * 46.0)
			s.halo.scale = s.halo_scale * fl
		_trail(s, dt)
		if s.friendly:
			_check_enemies(s)
		else:
			_check_player(s)
		if s.active and s.life <= 0.0:
			_expire(s)


func _trail(s: ShotRec, dt: float) -> void:
	if s.kind != Cfg.K_MISSILE and s.kind != Cfg.K_NUKE and s.kind != Cfg.K_SHELL:
		return
	s.trail_t -= dt
	if s.trail_t > 0.0:
		return
	var back: Vector3 = -s.vel.normalized()
	if s.kind == Cfg.K_MISSILE:
		s.trail_t = 0.03
		fx.smoke_trail(s.pos + back * 1.6, 0.8)
		fx.puff(s.pos + back * 1.8, Vector3.ZERO, 0.12, 0.9, 0.2, Color(1.0, 0.75, 0.3, 0.9), Color(1.0, 0.3, 0.1, 0.0), 0.0, 0.0, true)
	elif s.kind == Cfg.K_NUKE:
		s.trail_t = 0.04
		fx.smoke_trail(s.pos + back * 2.0, 1.6)
	else:
		s.trail_t = 0.07
		fx.smoke_trail(s.pos + back * 0.8, 0.45)


func _steer_missile(s: ShotRec, dt: float) -> void:
	var spd: float = minf(s.vel.length() + Cfg.MISSILE_ACCEL * dt, 105.0)
	var cur := Vector3(s.vel.x, 0.0, s.vel.z)
	if cur.length_squared() < 0.01:
		cur = Vector3(0.0, 0.0, -1.0)
	cur = cur.normalized()
	var tgt = s.target
	if tgt == null or not is_instance_valid(tgt) or tgt.dead:
		tgt = enemies.find_target(s.pos, 30.0)
		s.target = tgt
	if tgt != null:
		var des := Vector3(tgt.position.x - s.pos.x, 0.0, tgt.position.z - s.pos.z)
		if des.length_squared() > 0.25:
			des = des.normalized()
			cur = cur.slerp(des, minf(1.0, 3.6 * dt)).normalized()
	s.vel = cur * spd
	s.node.position = s.pos
	_orient(s, cur)


func _check_enemies(s: ShotRec) -> void:
	var list: Array = enemies.list
	for e in list:
		if e.dead:
			continue
		var rr: float = e.radius + s.radius
		var dz: float = e.position.z - s.pos.z
		if dz > rr or dz < -rr:
			continue
		var dx: float = e.position.x - s.pos.x
		if dx * dx + dz * dz > rr * rr:
			continue
		if e.get_instance_id() == s.last_hit:
			continue
		_hit_enemy(s, e)
		if not s.active:
			return


func _hit_enemy(s: ShotRec, e) -> void:
	var impact: Vector3 = e.position + Vector3(0.0, e.mid_height, 0.0)
	var gy: float = e.position.y if not e.air else world.height_at(e.position.x, e.position.z)
	enemies.damage_enemy(e, s.dmg)
	if s.kind == Cfg.K_MISSILE:
		_missile_blast(s, e.position, gy, e)
	else:
		var col := Color(1.0, 0.85, 0.4)
		if s.kind == Cfg.K_LASER:
			col = Color(0.4, 0.95, 1.0)
		elif s.kind == Cfg.K_PLASMA:
			col = Color(0.6, 1.0, 0.4)
		fx.hit_spark(impact, col)
		if s.splash > 0.0:
			enemies.splash(e.position, s.splash, s.dmg * 0.6, e)
			fx.flash(impact, s.splash * 0.9, 0.16, Color(0.6, 1.0, 0.4))
		if _snd_t <= 0.0:
			_snd_t = 0.05
			Feedback.play("hit", -14.0, randf_range(0.9, 1.15))
	if s.pierce > 0:
		s.pierce -= 1
		s.last_hit = e.get_instance_id()
	else:
		_kill_shot(s)


func _missile_blast(s: ShotRec, at: Vector3, ground_y: float, skip) -> void:
	fx.explosion(Vector3(at.x, ground_y + 1.2, at.z), 1.5, ground_y)
	enemies.splash(at, Cfg.MISSILE_SPLASH, s.dmg * 0.5, skip)
	Feedback.play("boom", -4.0, randf_range(0.95, 1.1))
	Feedback.vibrate(30)
	shake.emit(0.9)


func _check_player(s: ShotRec) -> void:
	if player == null or not player.alive:
		return
	var rr: float = Cfg.PLAYER_RADIUS + s.radius
	var dx: float = player.position.x - s.pos.x
	var dz: float = player.position.z - s.pos.z
	if dx * dx + dz * dz > rr * rr:
		return
	player.take_damage(s.dmg)
	fx.hit_spark(player.position, Color(1.0, 0.6, 0.2))
	if s.kind == Cfg.K_SHELL:
		fx.explosion(player.position + Vector3(0.0, -1.0, 0.0), 0.8)
	_kill_shot(s)


func _expire(s: ShotRec) -> void:
	var gy: float = world.height_at(s.pos.x, s.pos.z)
	if s.kind == Cfg.K_MISSILE:
		_missile_blast(s, Vector3(s.pos.x, gy, s.pos.z), gy, null)
	elif s.kind == Cfg.K_NUKE:
		nuke_detonated.emit(Vector3(s.pos.x, gy, s.pos.z))
	elif s.kind == Cfg.K_SHELL:
		fx.explosion(Vector3(s.pos.x, gy + 1.0, s.pos.z), 0.8, gy)
	_kill_shot(s)
