extends RefCounted
## Builds a low-poly helicopter (nose toward -Z) from code.
## Palette keys: body, accent, glass (Colors), glow (float 0..1 underglow) and optional "enemy" (bool).

const MeshBuilder = preload("res://scripts/util/mesh_builder.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")

static var _cache: Dictionary = {}
static var _blade_mat: StandardMaterial3D = null
static var _disc_mat: StandardMaterial3D = null


static func _body_mesh(pal: Dictionary) -> ArrayMesh:
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var glass: Color = pal["glass"]
	var key: String = "%s|%s|%s" % [body.to_html(false), accent.to_html(false), glass.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var dark := Color(0.12, 0.12, 0.14)
	var b := MeshBuilder.new()
	# fuselage (belly in shadow) and nose
	b.box(Vector3(0.0, 0.0, 0.2), Vector3(2.1, 1.7, 3.6), body, Basis.IDENTITY, 0.35)
	b.frustum(Vector3(0.0, -0.05, -1.6), Vector3(0.0, 0.0, -1.0), 0.95, 0.3, 1.6, 6, MeshBuilder.shade(body, 0.92), 0.0, 0.25)
	# livery stripes along both flanks
	b.box(Vector3(0.0, 0.12, 0.3), Vector3(2.16, 0.14, 2.6), accent)
	b.box(Vector3(0.0, -0.42, 0.3), Vector3(2.14, 0.08, 2.9), MeshBuilder.shade(accent, 0.85))
	# canopy with a brighter forward pane
	b.box(Vector3(0.0, 0.62, -0.95), Vector3(1.8, 0.9, 1.9), glass, Basis(Vector3.RIGHT, deg_to_rad(12.0)))
	b.box(Vector3(0.0, 0.58, -1.9), Vector3(1.5, 0.6, 0.12), MeshBuilder.shade(glass, 1.25), Basis(Vector3.RIGHT, deg_to_rad(-35.0)))
	# engine hump with intakes and exhaust
	b.box(Vector3(0.0, 1.05, 0.9), Vector3(1.3, 0.7, 1.8), accent)
	b.box(Vector3(0.0, 1.0, -0.12), Vector3(1.0, 0.45, 0.2), dark)
	b.frustum(Vector3(0.0, 1.0, 1.8), Vector3(0.0, 0.0, 1.0), 0.28, 0.2, 0.5, 6, dark)
	# sensor turret under the nose
	b.frustum(Vector3(0.0, -0.85, -1.9), Vector3(0.0, -1.0, 0.0), 0.32, 0.26, 0.4, 6, dark)
	b.frustum(Vector3(0.0, -1.2, -1.9), Vector3(0.0, -1.0, 0.0), 0.26, 0.0, 0.18, 6, Color(0.1, 0.3, 0.4))
	# tail boom, fin, stabiliser
	b.frustum(Vector3(0.0, 0.25, 1.9), Vector3(0.0, 0.0, 1.0), 0.5, 0.2, 4.6, 6, body, 0.0, 0.2)
	b.box(Vector3(0.0, 0.95, 6.3), Vector3(0.14, 1.5, 1.1), accent)
	b.box(Vector3(0.0, 0.35, 6.0), Vector3(1.6, 0.1, 0.6), accent)
	# stub wings, weapon pods with rocket tubes
	b.box(Vector3(0.0, -0.15, 0.4), Vector3(4.8, 0.16, 0.9), accent, Basis.IDENTITY, 0.25)
	for side in [-1.0, 1.0]:
		var sx: float = float(side)
		b.frustum(Vector3(sx * 2.1, -0.25, 0.9), Vector3(0.0, 0.0, -1.0), 0.32, 0.3, 1.8, 6, dark, 0.0, 0.2)
		b.frustum(Vector3(sx * 2.1, -0.25, -0.9), Vector3(0.0, 0.0, -1.0), 0.3, 0.0, 0.5, 6, accent)
		for k in range(3):
			b.frustum(Vector3(sx * 2.45, -0.3 - float(k) * 0.05, 0.8 - float(k) * 0.28), Vector3(0.0, 0.0, -1.0), 0.07, 0.07, 1.0, 4, Color(0.55, 0.55, 0.58))
		# skids and struts
		b.box(Vector3(sx * 1.0, -1.25, 0.3), Vector3(0.14, 0.14, 3.6), dark)
		b.box(Vector3(sx * 1.0, -1.0, -0.9), Vector3(0.12, 0.5, 0.12), dark)
		b.box(Vector3(sx * 1.0, -1.0, 1.3), Vector3(0.12, 0.5, 0.12), dark)
	# rotor mast and hub
	b.box(Vector3(0.0, 1.5, 0.2), Vector3(0.25, 0.5, 0.25), dark)
	b.frustum(Vector3(0.0, 1.72, 0.2), Vector3.UP, 0.35, 0.28, 0.16, 6, MeshBuilder.shade(accent, 0.8))
	var mesh: ArrayMesh = b.build(MeshBuilder.model_material())
	_cache[key] = mesh
	return mesh


static func _nav_light(root: Node3D, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshKit.sphere(root, 0.17, pos, MeshKit.glow(col), Vector3.ONE, 6)
	MeshKit.no_shadow(mi)
	var halo: MeshInstance3D = MeshKit.sphere(mi, 0.5, Vector3.ZERO, MeshKit.glow(col, 0.35, true), Vector3.ONE, 6)
	MeshKit.no_shadow(halo)
	return mi


## Returns {"root": Node3D, "rotor": Node3D, "tail": Node3D, "parts": [MeshInstance3D], "lights": [MeshInstance3D]}.
static func build(pal: Dictionary, scale_f: float = 1.0) -> Dictionary:
	var root := Node3D.new()
	root.scale = Vector3.ONE * scale_f
	var parts: Array = []

	var bm := MeshInstance3D.new()
	bm.mesh = _body_mesh(pal)
	root.add_child(bm)
	parts.append(bm)

	if _blade_mat == null:
		_blade_mat = StandardMaterial3D.new()
		_blade_mat.albedo_color = Color(0.10, 0.10, 0.12)
		_blade_mat.roughness = 0.7
		_disc_mat = StandardMaterial3D.new()
		_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_disc_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.09)

	var rotor := Node3D.new()
	rotor.position = Vector3(0.0, 1.8, 0.2)
	root.add_child(rotor)
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(9.6, 0.06, 0.5)
	for k in range(2):
		var bl := MeshInstance3D.new()
		bl.mesh = blade_mesh
		bl.material_override = _blade_mat
		bl.rotation_degrees = Vector3(0.0, 90.0 * float(k), 0.0)
		bl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rotor.add_child(bl)
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 4.8
	disc_mesh.bottom_radius = 4.8
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 14
	disc_mesh.rings = 1
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = _disc_mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rotor.add_child(disc)

	var tail := Node3D.new()
	tail.position = Vector3(0.3, 0.85, 6.3)
	root.add_child(tail)
	var tb1 := BoxMesh.new()
	tb1.size = Vector3(0.05, 1.7, 0.16)
	var tb2 := BoxMesh.new()
	tb2.size = Vector3(0.05, 0.16, 1.7)
	for tm in [tb1, tb2]:
		var tmi := MeshInstance3D.new()
		tmi.mesh = tm
		tmi.material_override = _blade_mat
		tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tail.add_child(tmi)

	# navigation lights: red port, green starboard, white tail strobe (enemies only show red)
	var lights: Array = []
	var enemy: bool = bool(pal.get("enemy", false))
	lights.append(_nav_light(root, Vector3(-2.45, -0.1, 0.4), Color(1.0, 0.15, 0.1)))
	if enemy:
		lights.append(_nav_light(root, Vector3(2.45, -0.1, 0.4), Color(1.0, 0.15, 0.1)))
	else:
		lights.append(_nav_light(root, Vector3(2.45, -0.1, 0.4), Color(0.2, 1.0, 0.3)))
	lights.append(_nav_light(root, Vector3(0.0, 1.75, 6.3), Color(1.0, 1.0, 1.0)))

	var glow_amt: float = float(pal.get("glow", 0.0))
	if glow_amt > 0.0:
		var gc: Color = pal["accent"]
		var gmesh := CylinderMesh.new()
		gmesh.top_radius = 2.8
		gmesh.bottom_radius = 2.8
		gmesh.height = 0.03
		gmesh.radial_segments = 14
		gmesh.rings = 1
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.albedo_color = Color(gc.r, gc.g, gc.b, 0.22 + glow_amt * 0.3)
		var gi := MeshInstance3D.new()
		gi.mesh = gmesh
		gi.material_override = gm
		gi.position = Vector3(0.0, -1.5, 0.4)
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gi)

	return {"root": root, "rotor": rotor, "tail": tail, "parts": parts, "lights": lights}
