extends RefCounted
## Low-poly mesh and material helpers. All geometry in Lambda Wars is built from code.

static var _mats: Dictionary = {}


## Shaded PBR-ish material (cached by parameters).
static func mat(color: Color, rough: float = 0.85, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	var key: String = "%s|%.2f|%.2f|%.2f" % [color.to_html(true), rough, metal, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


## Unshaded glowing material, optionally translucent and/or additive (cached).
static func glow(color: Color, alpha: float = 1.0, additive: bool = false) -> StandardMaterial3D:
	var key: String = "g|%s|%.2f|%s" % [color.to_html(false), alpha, str(additive)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 0.999 or additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mats[key] = m
	return m


static func instance(mesh: Mesh, m: Material, parent: Node, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	if parent != null:
		parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, pos: Vector3, m: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi: MeshInstance3D = instance(mesh, m, parent, pos)
	mi.rotation_degrees = rot_deg
	return mi


static func cyl(parent: Node, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, rot_deg: Vector3 = Vector3.ZERO, segs: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = segs
	mesh.rings = 1
	var mi: MeshInstance3D = instance(mesh, m, parent, pos)
	mi.rotation_degrees = rot_deg
	return mi


static func sphere(parent: Node, r: float, pos: Vector3, m: Material, scale_v: Vector3 = Vector3.ONE, segs: int = 8) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = segs
	mesh.rings = maxi(3, int(segs * 0.5))
	var mi: MeshInstance3D = instance(mesh, m, parent, pos)
	mi.scale = scale_v
	return mi


static func no_shadow(mi: GeometryInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
