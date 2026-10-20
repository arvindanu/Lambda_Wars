extends Node3D
## Drifting atmospheric particles around the flight path: pollen and dust by day, warm embers at
## dusk, fireflies at night. A single small CPU particle emitter, cheap enough for phones.

var enabled: bool = true

var _p: CPUParticles3D = null
var _mat: StandardMaterial3D = null
var _last: Color = Color(0, 0, 0, 0)


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_color = Color(1, 1, 1, 1)
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.material = _mat

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])

	_p = CPUParticles3D.new()
	_p.mesh = mesh
	_p.amount = 48
	_p.lifetime = 7.0
	_p.preprocess = 7.0
	_p.local_coords = false
	_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_p.emission_box_extents = Vector3(62.0, 9.0, 55.0)
	_p.direction = Vector3(0.4, 0.3, 1.0)
	_p.spread = 180.0
	_p.initial_velocity_min = 0.3
	_p.initial_velocity_max = 1.4
	_p.gravity = Vector3(0.25, 0.12, 0.35)
	_p.scale_amount_min = 0.5
	_p.scale_amount_max = 1.3
	_p.color_ramp = ramp
	_p.color = Color(1, 1, 1, 1)
	_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_p)


func follow(pos: Vector3) -> void:
	position = pos + Vector3(0.0, 8.0, -32.0)


func set_enabled(on: bool) -> void:
	enabled = on
	if _p != null:
		_p.visible = on and _last.a > 0.02


## Colour rgb tints the particles, alpha is the overall intensity for the current time of day.
func set_style(c: Color) -> void:
	if _p == null or c.is_equal_approx(_last):
		return
	_last = c
	_p.color = Color(c.r, c.g, c.b, 1.0)
	_mat.albedo_color = Color(1, 1, 1, clampf(c.a * 1.8, 0.0, 1.0))
	_p.visible = enabled and c.a > 0.02
