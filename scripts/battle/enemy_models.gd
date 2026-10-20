extends RefCounted
## Builds enemy models (front toward -Z). Meshes are cached and shared between instances.

const MeshBuilder = preload("res://scripts/util/mesh_builder.gd")
const HeliModel = preload("res://scripts/battle/heli_model.gd")

static var _cache: Dictionary = {}

const OLIVE := Color(0.34, 0.38, 0.22)
const OLIVE_D := Color(0.24, 0.27, 0.16)
const TAN := Color(0.55, 0.50, 0.35)
const TYRE := Color(0.07, 0.07, 0.08)
const GLASS := Color(0.45, 0.62, 0.70)
const STEEL := Color(0.20, 0.21, 0.23)


static func _mesh(key: String) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var b := MeshBuilder.new()
	match key:
		"jeep_body":
			_jeep_body(b)
		"jeep_gun":
			_jeep_gun(b)
		"truck_body":
			_truck_body(b)
		"truck_rack":
			_truck_rack(b)
		"arty_body":
			_arty_body(b)
		"arty_gun":
			_arty_gun(b)
	var m: ArrayMesh = b.build(MeshBuilder.model_material())
	_cache[key] = m
	return m


static func _jeep_body(b) -> void:
	b.box(Vector3(0.0, 0.9, 0.1), Vector3(2.0, 0.8, 3.6), OLIVE)
	b.box(Vector3(0.0, 0.75, -1.5), Vector3(1.8, 0.5, 1.2), MeshBuilder.shade(OLIVE, 1.1))
	b.box(Vector3(0.0, 1.5, 0.5), Vector3(1.7, 0.7, 1.5), OLIVE_D)
	b.box(Vector3(0.0, 1.55, -0.35), Vector3(1.6, 0.5, 0.1), GLASS)
	for sx in [-1.0, 1.0]:
		for sz in [-1.2, 1.2]:
			b.box(Vector3(float(sx) * 1.15, 0.5, float(sz)), Vector3(0.35, 0.9, 0.9), TYRE)
	b.box(Vector3(0.0, 2.0, 0.9), Vector3(0.3, 0.6, 0.3), STEEL)


static func _jeep_gun(b) -> void:
	b.box(Vector3(0.0, 0.0, 0.0), Vector3(0.5, 0.4, 0.6), STEEL)
	b.box(Vector3(0.0, 0.0, -0.9), Vector3(0.18, 0.18, 1.5), Color(0.1, 0.1, 0.1))


static func _truck_body(b) -> void:
	b.box(Vector3(0.0, 0.85, 0.4), Vector3(2.6, 0.7, 7.0), OLIVE_D)
	b.box(Vector3(0.0, 1.9, -2.4), Vector3(2.5, 1.9, 2.0), OLIVE)
	b.box(Vector3(0.0, 2.2, -3.45), Vector3(2.2, 0.8, 0.1), GLASS)
	b.box(Vector3(0.0, 2.1, 1.6), Vector3(2.6, 2.1, 4.2), TAN)
	for sx in [-1.0, 1.0]:
		for sz in [-2.4, 0.6, 2.8]:
			b.box(Vector3(float(sx) * 1.4, 0.65, float(sz)), Vector3(0.5, 1.3, 1.3), TYRE)


static func _truck_rack(b) -> void:
	b.box(Vector3(0.0, 0.0, 0.0), Vector3(1.8, 0.35, 2.4), STEEL)
	for sx in [-0.55, 0.55]:
		b.box(Vector3(float(sx), 0.4, -0.2), Vector3(0.35, 0.35, 2.6), Color(0.55, 0.18, 0.14))
		b.frustum(Vector3(float(sx), 0.4, -1.5), Vector3(0.0, 0.0, -1.0), 0.18, 0.0, 0.5, 5, Color(0.8, 0.8, 0.8))


static func _arty_body(b) -> void:
	b.box(Vector3(0.0, 0.7, 0.0), Vector3(3.2, 0.7, 3.6), OLIVE_D)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(float(sx) * 1.8, 0.6, 0.4), Vector3(0.5, 1.2, 1.2), TYRE)
	b.box(Vector3(0.0, 0.3, 2.0), Vector3(0.4, 0.3, 1.8), STEEL)


static func _arty_gun(b) -> void:
	b.box(Vector3(0.0, 0.0, 0.0), Vector3(1.8, 0.9, 1.8), OLIVE)
	b.box(Vector3(0.0, 0.3, -1.0), Vector3(2.6, 1.5, 0.25), MeshBuilder.shade(OLIVE, 0.8))
	b.frustum(Vector3(0.0, 0.2, -0.8), Vector3(0.0, 0.0, -1.0), 0.32, 0.26, 4.6, 6, Color(0.12, 0.12, 0.13))
	b.box(Vector3(0.0, 0.2, -5.5), Vector3(0.6, 0.6, 0.5), STEEL)


## Returns {"root": Node3D, "turret": Node3D or null, "rotor": Node3D or null,
## "tail": Node3D or null, "parts": Array[MeshInstance3D], "height": float}
## The root faces -Z; the caller rotates it to the heading.
static func build(type: String) -> Dictionary:
	var root := Node3D.new()
	var parts: Array = []
	var turret: Node3D = null
	var rotor: Node3D = null
	var tail: Node3D = null
	var lights: Array = []
	var height: float = 3.0
	if type == "jeep":
		_add(root, parts, _mesh("jeep_body"))
		turret = Node3D.new()
		turret.position = Vector3(0.0, 2.4, 0.9)
		root.add_child(turret)
		_add(turret, parts, _mesh("jeep_gun"))
		height = 3.2
	elif type == "truck":
		_add(root, parts, _mesh("truck_body"))
		turret = Node3D.new()
		turret.position = Vector3(0.0, 3.4, 1.6)
		root.add_child(turret)
		_add(turret, parts, _mesh("truck_rack"))
		height = 4.2
	elif type == "artillery":
		_add(root, parts, _mesh("arty_body"))
		turret = Node3D.new()
		turret.position = Vector3(0.0, 1.7, 0.0)
		root.add_child(turret)
		_add(turret, parts, _mesh("arty_gun"))
		height = 3.4
	else:
		var pal: Dictionary = {
			"body": Color(0.24, 0.26, 0.30),
			"accent": Color(0.70, 0.12, 0.12),
			"glass": Color(0.90, 0.45, 0.30),
			"glow": 0.0,
			"enemy": true,
		}
		var h: Dictionary = HeliModel.build(pal, 1.0)
		var hroot: Node3D = h["root"]
		root.add_child(hroot)
		rotor = h["rotor"]
		tail = h["tail"]
		for p in h["parts"]:
			parts.append(p)
		lights = h["lights"]
		height = 4.0
	return {"root": root, "turret": turret, "rotor": rotor, "tail": tail, "parts": parts, "lights": lights, "height": height}


static func _add(parent: Node3D, parts: Array, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	parts.append(mi)
	return mi
