extends Node3D
## Floating collectibles: weapon upgrades, missile crates (~every 3 min), nukes (~every 8 min) and repair kits.
## Timers only advance during active play. A missed missile/nuke crate is re-dropped shortly after.

signal collected(kind: int)

const Cfg = preload("res://scripts/core/config.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")

const COLORS: Array = [
	Color(0.25, 0.85, 1.0),
	Color(1.0, 0.75, 0.15),
	Color(1.0, 0.22, 0.15),
	Color(0.3, 1.0, 0.45),
]


class PickupItem extends RefCounted:
	var kind: int = 0
	var node: Node3D = null
	var crate: Node3D = null
	var ring_a: Node3D = null
	var ring_b: Node3D = null
	var halo: MeshInstance3D = null
	var base_y: float = 0.0
	var t: float = 0.0


var player = null
var world = null
var fx = null

var _items: Array = []
var _elapsed: Array = [0.0, 0.0, 0.0, 0.0]
var _next: Array = [25.0, 180.0, 480.0, 60.0]
var _rng := RandomNumberGenerator.new()


func setup(player_ref, world_ref) -> void:
	player = player_ref
	world = world_ref
	_rng.randomize()
	reset()


func reset() -> void:
	for it in _items:
		it.node.queue_free()
	_items.clear()
	_elapsed = [0.0, 0.0, 0.0, 0.0]
	_next = [25.0, Cfg.MISSILE_SPAWN_INTERVAL, Cfg.NUKE_SPAWN_INTERVAL, 60.0]


func _interval(kind: int) -> float:
	var base: float = Cfg.WEAPON_SPAWN_INTERVAL
	if kind == Cfg.P_MISSILE:
		base = Cfg.MISSILE_SPAWN_INTERVAL
	elif kind == Cfg.P_NUKE:
		base = Cfg.NUKE_SPAWN_INTERVAL
	elif kind == Cfg.P_REPAIR:
		base = Cfg.REPAIR_SPAWN_INTERVAL
	return base * _rng.randf_range(0.9, 1.1)


## Seconds until the next supply drop of this kind (0 while one is on the field).
func time_left(kind: int) -> float:
	if has_active(kind):
		return 0.0
	return maxf(0.0, float(_next[kind]) - float(_elapsed[kind]))


func has_active(kind: int) -> bool:
	for it in _items:
		if it.kind == kind:
			return true
	return false


func step(dt: float) -> void:
	var pp: Vector3 = player.position
	for k in range(4):
		_elapsed[k] = float(_elapsed[k]) + dt
		if float(_elapsed[k]) >= float(_next[k]):
			_spawn(k, pp)
			_elapsed[k] = 0.0
			_next[k] = _interval(k)
	var i: int = _items.size() - 1
	while i >= 0:
		var it: PickupItem = _items[i]
		it.t += dt
		it.node.position.y = it.base_y + sin(it.t * 2.4) * 0.6
		it.crate.rotation.y += dt * 1.4
		it.ring_a.rotation.y += dt * 2.2
		it.ring_b.rotation.x += dt * 1.6
		it.halo.scale = Vector3.ONE * (1.0 + 0.14 * sin(it.t * 4.0))
		if fx != null and _rng.randf() < dt * 5.0:
			var pc: Color = COLORS[it.kind]
			fx.puff(it.node.position + Vector3(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-1.0, 2.0), _rng.randf_range(-2.0, 2.0)), Vector3(0.0, 1.5, 0.0), 0.7, 0.3, 0.05, Color(pc.r, pc.g, pc.b, 0.9), Color(pc.r, pc.g, pc.b, 0.0), 0.0, 0.0, true)
		var dx: float = pp.x - it.node.position.x
		var dz: float = pp.z - it.node.position.z
		var dist: float = sqrt(dx * dx + dz * dz)
		if dist < 13.0 and dist > 0.01:
			var pull: float = clampf(1.0 - dist / 13.0, 0.0, 1.0) * 16.0 * dt
			it.node.position.x += dx / dist * pull
			it.node.position.z += dz / dist * pull
		if player.alive and dist < 4.8:
			collected.emit(it.kind)
			it.node.queue_free()
			_items.remove_at(i)
		elif it.node.position.z > pp.z + 22.0:
			if it.kind == Cfg.P_MISSILE or it.kind == Cfg.P_NUKE:
				_next[it.kind] = float(_elapsed[it.kind]) + 14.0
			it.node.queue_free()
			_items.remove_at(i)
		i -= 1


func _spawn(kind: int, pp: Vector3) -> void:
	var spread: float = 22.0 if (kind == Cfg.P_MISSILE or kind == Cfg.P_NUKE) else Cfg.LANE_HALF - 6.0
	var x: float = clampf(pp.x + _rng.randf_range(-spread, spread), -Cfg.LANE_HALF + 4.0, Cfg.LANE_HALF - 4.0)
	var z: float = pp.z - Cfg.PICKUP_SPAWN_AHEAD
	var alt: float = Cfg.HELI_HOVER
	var gy: float = world.height_at(x, z)
	var col: Color = COLORS[kind]

	var it := PickupItem.new()
	it.kind = kind
	it.base_y = alt
	it.node = Node3D.new()
	it.node.position = Vector3(x, alt, z)
	add_child(it.node)

	it.crate = Node3D.new()
	it.node.add_child(it.crate)
	MeshKit.box(it.crate, Vector3(2.6, 2.6, 2.6), Vector3.ZERO, MeshKit.mat(col.darkened(0.55), 0.5, 0.3, 0.0))
	_icon(it.crate, kind, col)

	it.ring_a = Node3D.new()
	it.node.add_child(it.ring_a)
	_ring(it.ring_a, 3.3, col)
	it.ring_b = Node3D.new()
	it.ring_b.rotation_degrees = Vector3(70.0, 0.0, 0.0)
	it.node.add_child(it.ring_b)
	_ring(it.ring_b, 2.7, col)

	# vertical beam down to the ground gives a depth cue from the high-angle camera
	var beam_h: float = maxf(2.0, alt - gy)
	var beam := MeshKit.cyl(it.node, 0.1, 0.1, beam_h, Vector3(0.0, -beam_h * 0.5, 0.0), MeshKit.glow(col, 0.4, true), Vector3.ZERO, 5)
	MeshKit.no_shadow(beam)
	# soft glow around the crate and a landing marker on the ground below
	var hm := SphereMesh.new()
	hm.radius = 3.2
	hm.height = 6.4
	hm.radial_segments = 8
	hm.rings = 4
	it.halo = MeshInstance3D.new()
	it.halo.mesh = hm
	it.halo.material_override = MeshKit.glow(col, 0.18, true)
	it.halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	it.node.add_child(it.halo)
	var gr := TorusMesh.new()
	gr.inner_radius = 2.6
	gr.outer_radius = 3.0
	gr.rings = 20
	gr.ring_segments = 4
	var gmi := MeshInstance3D.new()
	gmi.mesh = gr
	gmi.material_override = MeshKit.glow(col, 0.55, true)
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gmi.position = Vector3(0.0, -(alt - gy) + 0.35, 0.0)
	gmi.scale = Vector3(1.0, 0.3, 1.0)
	it.node.add_child(gmi)
	_items.append(it)


func _ring(parent: Node3D, r: float, col: Color) -> void:
	var tor := TorusMesh.new()
	tor.inner_radius = r - 0.12
	tor.outer_radius = r
	tor.rings = 16
	tor.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = tor
	mi.material_override = MeshKit.glow(col, 0.85, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _icon(parent: Node3D, kind: int, col: Color) -> void:
	var bright: StandardMaterial3D = MeshKit.mat(col, 0.4, 0.0, 1.2)
	if kind == Cfg.P_WEAPON:
		for k in range(3):
			MeshKit.box(parent, Vector3(0.3, 0.3, 1.5), Vector3((float(k) - 1.0) * 0.7, 1.45, 0.0), bright)
	elif kind == Cfg.P_MISSILE:
		MeshKit.cyl(parent, 0.28, 0.28, 1.6, Vector3(0.0, 1.5, 0.0), bright, Vector3(90.0, 0.0, 0.0), 6)
		MeshKit.cyl(parent, 0.0, 0.28, 0.6, Vector3(0.0, 1.5, -1.0), bright, Vector3(90.0, 0.0, 0.0), 6)
	elif kind == Cfg.P_NUKE:
		MeshKit.sphere(parent, 0.75, Vector3(0.0, 1.6, 0.0), bright, Vector3.ONE, 8)
	else:
		MeshKit.box(parent, Vector3(1.4, 0.4, 0.4), Vector3(0.0, 1.5, 0.0), bright)
		MeshKit.box(parent, Vector3(0.4, 0.4, 1.4), Vector3(0.0, 1.5, 0.0), bright)
