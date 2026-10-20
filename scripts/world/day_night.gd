extends RefCounted
## Smooth morning -> day -> evening -> dusk -> night -> dawn cycle with a distinct mood per phase.
## Drives sun / moon light, sky shader, ambient light, fog, tonemapping and the colour grade.
## Updated about five times per second: the sky reflection only re-renders when the sky changes.

const Cfg = preload("res://scripts/core/config.gd")

var t: float = 0.02
var light: DirectionalLight3D = null
var env: Environment = null
var sky_mat: ShaderMaterial = null

## Read by the main script to drive the screen-space layers.
var grade: Color = Color(1, 1, 1, 1)
var vignette: float = 0.2
var mote: Color = Color(1, 1, 1, 0.2)
var night_factor: float = 0.0

var _keys: Array = []
var _acc: float = 0.0
var _cloud_off: Vector2 = Vector2.ZERO


func _init() -> void:
	_keys = [
		{"t": 0.00, "pitch": 16.0, "yaw": -55.0, "sun": Color(1.0, 0.78, 0.55), "sun_e": 1.25,
			"top": Color(0.34, 0.52, 0.82), "hor": Color(0.98, 0.74, 0.55), "ground": Color(0.36, 0.30, 0.30),
			"amb": Color(0.55, 0.58, 0.70), "amb_e": 0.60, "fog": Color(0.82, 0.70, 0.62), "fog_d": 0.0042,
			"grade": Color(1.02, 0.95, 0.88), "vig": 0.28, "stars": 0.0, "cloud": 0.45, "cloud_col": Color(1.0, 0.85, 0.75),
			"sat": 1.08, "con": 1.05, "expo": 1.0, "mote": Color(1.0, 0.85, 0.60, 0.30), "scatter": 0.35, "night": 0.0},
		{"t": 0.18, "pitch": 62.0, "yaw": -35.0, "sun": Color(1.0, 0.97, 0.90), "sun_e": 1.5,
			"top": Color(0.22, 0.48, 0.92), "hor": Color(0.72, 0.85, 0.97), "ground": Color(0.35, 0.38, 0.40),
			"amb": Color(0.62, 0.70, 0.84), "amb_e": 0.70, "fog": Color(0.70, 0.80, 0.92), "fog_d": 0.0030,
			"grade": Color(1.0, 1.0, 1.02), "vig": 0.18, "stars": 0.0, "cloud": 0.50, "cloud_col": Color(1.0, 1.0, 1.0),
			"sat": 1.05, "con": 1.04, "expo": 1.0, "mote": Color(1.0, 1.0, 0.90, 0.14), "scatter": 0.10, "night": 0.0},
		{"t": 0.40, "pitch": 20.0, "yaw": 38.0, "sun": Color(1.0, 0.55, 0.25), "sun_e": 1.3,
			"top": Color(0.28, 0.34, 0.66), "hor": Color(1.0, 0.55, 0.30), "ground": Color(0.30, 0.22, 0.22),
			"amb": Color(0.60, 0.48, 0.52), "amb_e": 0.50, "fog": Color(0.92, 0.58, 0.40), "fog_d": 0.0046,
			"grade": Color(1.05, 0.90, 0.80), "vig": 0.34, "stars": 0.0, "cloud": 0.55, "cloud_col": Color(1.0, 0.60, 0.40),
			"sat": 1.15, "con": 1.08, "expo": 1.0, "mote": Color(1.0, 0.65, 0.35, 0.40), "scatter": 0.50, "night": 0.0},
		{"t": 0.52, "pitch": 8.0, "yaw": 55.0, "sun": Color(0.95, 0.35, 0.22), "sun_e": 0.65,
			"top": Color(0.12, 0.12, 0.32), "hor": Color(0.70, 0.28, 0.30), "ground": Color(0.18, 0.12, 0.16),
			"amb": Color(0.30, 0.26, 0.42), "amb_e": 0.38, "fog": Color(0.42, 0.26, 0.32), "fog_d": 0.0050,
			"grade": Color(0.92, 0.82, 0.95), "vig": 0.40, "stars": 0.25, "cloud": 0.50, "cloud_col": Color(0.70, 0.40, 0.50),
			"sat": 1.12, "con": 1.10, "expo": 1.0, "mote": Color(1.0, 0.50, 0.40, 0.30), "scatter": 0.40, "night": 0.3},
		{"t": 0.62, "pitch": 40.0, "yaw": 20.0, "sun": Color(0.50, 0.62, 0.95), "sun_e": 0.32,
			"top": Color(0.015, 0.025, 0.09), "hor": Color(0.05, 0.08, 0.18), "ground": Color(0.02, 0.03, 0.05),
			"amb": Color(0.16, 0.22, 0.38), "amb_e": 0.42, "fog": Color(0.04, 0.06, 0.12), "fog_d": 0.0040,
			"grade": Color(0.72, 0.82, 1.05), "vig": 0.45, "stars": 1.0, "cloud": 0.30, "cloud_col": Color(0.15, 0.20, 0.30),
			"sat": 0.92, "con": 1.12, "expo": 1.1, "mote": Color(0.70, 1.0, 0.50, 0.55), "scatter": 0.10, "night": 1.0},
		{"t": 0.84, "pitch": 40.0, "yaw": 20.0, "sun": Color(0.50, 0.62, 0.95), "sun_e": 0.32,
			"top": Color(0.015, 0.025, 0.09), "hor": Color(0.05, 0.08, 0.18), "ground": Color(0.02, 0.03, 0.05),
			"amb": Color(0.16, 0.22, 0.38), "amb_e": 0.42, "fog": Color(0.04, 0.06, 0.12), "fog_d": 0.0040,
			"grade": Color(0.72, 0.82, 1.05), "vig": 0.45, "stars": 1.0, "cloud": 0.30, "cloud_col": Color(0.15, 0.20, 0.30),
			"sat": 0.92, "con": 1.12, "expo": 1.1, "mote": Color(0.70, 1.0, 0.50, 0.55), "scatter": 0.10, "night": 1.0},
		{"t": 0.93, "pitch": 9.0, "yaw": -62.0, "sun": Color(0.95, 0.55, 0.55), "sun_e": 0.55,
			"top": Color(0.18, 0.22, 0.46), "hor": Color(0.88, 0.52, 0.52), "ground": Color(0.20, 0.16, 0.20),
			"amb": Color(0.36, 0.36, 0.52), "amb_e": 0.42, "fog": Color(0.58, 0.45, 0.52), "fog_d": 0.0046,
			"grade": Color(0.98, 0.88, 0.98), "vig": 0.36, "stars": 0.3, "cloud": 0.45, "cloud_col": Color(1.0, 0.70, 0.70),
			"sat": 1.08, "con": 1.06, "expo": 1.0, "mote": Color(1.0, 0.70, 0.70, 0.30), "scatter": 0.40, "night": 0.3},
		{"t": 1.00, "pitch": 16.0, "yaw": -55.0, "sun": Color(1.0, 0.78, 0.55), "sun_e": 1.25,
			"top": Color(0.34, 0.52, 0.82), "hor": Color(0.98, 0.74, 0.55), "ground": Color(0.36, 0.30, 0.30),
			"amb": Color(0.55, 0.58, 0.70), "amb_e": 0.60, "fog": Color(0.82, 0.70, 0.62), "fog_d": 0.0042,
			"grade": Color(1.02, 0.95, 0.88), "vig": 0.28, "stars": 0.0, "cloud": 0.45, "cloud_col": Color(1.0, 0.85, 0.75),
			"sat": 1.08, "con": 1.05, "expo": 1.0, "mote": Color(1.0, 0.85, 0.60, 0.30), "scatter": 0.35, "night": 0.0},
	]


func setup(l: DirectionalLight3D, e: Environment, s: ShaderMaterial) -> void:
	light = l
	env = e
	sky_mat = s
	apply()


func step(dt: float) -> void:
	t = fposmod(t + dt / Cfg.DAY_LENGTH, 1.0)
	_cloud_off += Vector2(0.9, 0.35) * dt * 0.01
	_acc += dt
	if _acc >= 0.2:
		_acc = 0.0
		apply()


func phase_name() -> String:
	if t < 0.10:
		return "MORNING"
	if t < 0.32:
		return "DAYLIGHT"
	if t < 0.48:
		return "EVENING"
	if t < 0.58:
		return "DUSK"
	if t < 0.88:
		return "NIGHT"
	return "DAWN"


func _lv(a: Dictionary, b: Dictionary, k: String, f: float) -> Variant:
	var x: Variant = a[k]
	if x is Color:
		return (x as Color).lerp(b[k], f)
	return lerpf(float(x), float(b[k]), f)


func apply() -> void:
	if light == null or env == null or sky_mat == null:
		return
	var i: int = 0
	while i < _keys.size() - 2 and t >= float(_keys[i + 1]["t"]):
		i += 1
	var a: Dictionary = _keys[i]
	var b: Dictionary = _keys[i + 1]
	var span: float = float(b["t"]) - float(a["t"])
	var f: float = 0.0
	if span > 0.0001:
		f = smoothstep(0.0, 1.0, clampf((t - float(a["t"])) / span, 0.0, 1.0))

	light.rotation_degrees = Vector3(-float(_lv(a, b, "pitch", f)), float(_lv(a, b, "yaw", f)), 0.0)
	light.light_color = _lv(a, b, "sun", f)
	light.light_energy = float(_lv(a, b, "sun_e", f))

	var top: Color = _lv(a, b, "top", f)
	var hor: Color = _lv(a, b, "hor", f)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", _lv(a, b, "ground", f))
	sky_mat.set_shader_parameter("cloud_color", _lv(a, b, "cloud_col", f))
	sky_mat.set_shader_parameter("cloud_amount", float(_lv(a, b, "cloud", f)))
	sky_mat.set_shader_parameter("star_amount", float(_lv(a, b, "stars", f)))
	sky_mat.set_shader_parameter("cloud_offset", _cloud_off)

	env.ambient_light_color = _lv(a, b, "amb", f)
	env.ambient_light_energy = float(_lv(a, b, "amb_e", f))
	env.fog_light_color = _lv(a, b, "fog", f)
	env.fog_density = float(_lv(a, b, "fog_d", f))
	env.fog_sun_scatter = float(_lv(a, b, "scatter", f))
	env.tonemap_exposure = float(_lv(a, b, "expo", f))
	env.adjustment_enabled = true
	env.adjustment_saturation = float(_lv(a, b, "sat", f))
	env.adjustment_contrast = float(_lv(a, b, "con", f))

	grade = _lv(a, b, "grade", f)
	vignette = float(_lv(a, b, "vig", f))
	mote = _lv(a, b, "mote", f)
	night_factor = float(_lv(a, b, "night", f))
