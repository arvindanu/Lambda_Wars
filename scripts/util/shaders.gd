extends RefCounted
## Procedural shaders and cached ShaderMaterials. Everything is generated in code (no asset files).
## All shaders are written for the Compatibility (OpenGL) renderer used on Android.

static var _noise_tex: ImageTexture = null
static var _terrain_shader: Shader = null
static var _terrain_mat: ShaderMaterial = null
static var _props_mat: ShaderMaterial = null
static var _water_mat: ShaderMaterial = null
static var _sky_mat: ShaderMaterial = null

## Terrain and props. Vertex colour carries baked ambient occlusion; vertex alpha = 1 - wind sway weight.
const TERRAIN_CODE := """
shader_type spatial;

uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform float detail_strength = 0.5;
uniform float sway_amount = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (sway_amount > 0.0) {
		float w = 1.0 - COLOR.a;
		float s1 = sin(TIME * 1.7 + world_pos.x * 0.35 + world_pos.z * 0.27);
		float s2 = sin(TIME * 2.9 + world_pos.z * 0.5 + world_pos.x * 0.2);
		VERTEX.x += (s1 * 0.22 + s2 * 0.07) * w * sway_amount;
		VERTEX.z += s1 * 0.12 * w * sway_amount;
	}
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float n1 = texture(detail_tex, world_pos.xz * 0.045).r;
	float n2 = texture(detail_tex, world_pos.xz * 0.21 + vec2(0.31, 0.57)).r;
	float d = n1 * 0.6 + n2 * 0.4;
	ALBEDO = c * (1.0 + (d - 0.5) * detail_strength);
	ROUGHNESS = 0.92;
	SPECULAR = 0.12;
}
"""

## Water: per-vertex colour/alpha encode depth and shoreline foam; analytic waves bend the normal
## so the sun and sky reflect in moving glints.
const WATER_CODE := """
shader_type spatial;

uniform float wave_strength = 0.28;

varying vec3 world_pos;

vec2 wave_grad(vec2 p, vec2 k, float speed, float amp, float t) {
	return k * (cos(dot(p, k) + t * speed) * amp);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	vec2 g = wave_grad(p, vec2(0.62, 0.38), 1.3, 0.5, t);
	g += wave_grad(p, vec2(1.25, -0.85), 1.9, 0.3, t);
	g += wave_grad(p, vec2(0.28, 1.15), 2.4, 0.22, t);
	g += wave_grad(p, vec2(-2.1, 1.4), 3.1, 0.12, t);
	vec3 n = normalize(vec3(-g.x * wave_strength, 1.0, -g.y * wave_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float crest = clamp(length(g) * 0.9, 0.0, 1.0);
	ALBEDO = c + vec3(crest * 0.05);
	METALLIC = 0.35;
	ROUGHNESS = mix(0.08, 0.45, clamp(1.0 - COLOR.a, 0.0, 1.0));
	SPECULAR = 0.9;
	ALPHA = COLOR.a;
}
"""

## Sky: gradient, stars, clouds, sun / moon disc. Mostly seen through water reflections.
const SKY_CODE := """
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.3, 0.5, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.8, 0.9);
uniform vec3 ground_color : source_color = vec3(0.1, 0.1, 0.1);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float star_amount = 0.0;
uniform float cloud_amount = 0.5;
uniform vec2 cloud_offset = vec2(0.0, 0.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.5));
	} else {
		col = mix(horizon_color, ground_color, pow(clamp(-h, 0.0, 1.0), 0.4));
	}
	if (h > 0.0 && star_amount > 0.0) {
		float r = hash13(floor(dir * 220.0));
		float star = step(0.9965, r) * smoothstep(0.0, 0.25, h);
		col += vec3(star * star_amount);
	}
	if (h > 0.02 && cloud_amount > 0.0) {
		vec2 uv = dir.xz / (h + 0.25) * 1.6 + cloud_offset;
		float cl = fbm(uv);
		float cov = smoothstep(1.0 - cloud_amount, 1.0, cl) * smoothstep(0.02, 0.25, h);
		col = mix(col, cloud_color, cov * 0.85);
	}
	if (LIGHT0_ENABLED) {
		vec3 ld = normalize(LIGHT0_DIRECTION);
		float d = max(dot(dir, ld), 0.0);
		float disc = smoothstep(0.9985, 0.9995, d);
		float glow = pow(d, 64.0) * 0.5 + pow(d, 8.0) * 0.12;
		col += LIGHT0_COLOR * (disc * 3.0 + glow);
	}
	COLOR = col;
}
"""


static func noise_texture() -> ImageTexture:
	if _noise_tex != null:
		return _noise_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.04
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.seed = 7
	var img: Image = n.get_seamless_image(256, 256)
	img.generate_mipmaps()
	_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex


static func _terrain_shader_obj() -> Shader:
	if _terrain_shader == null:
		_terrain_shader = Shader.new()
		_terrain_shader.code = TERRAIN_CODE
	return _terrain_shader


static func terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		var m := ShaderMaterial.new()
		m.shader = _terrain_shader_obj()
		m.set_shader_parameter("detail_tex", noise_texture())
		m.set_shader_parameter("detail_strength", 0.55)
		m.set_shader_parameter("sway_amount", 0.0)
		_terrain_mat = m
	return _terrain_mat


static func props_material() -> ShaderMaterial:
	if _props_mat == null:
		var m := ShaderMaterial.new()
		m.shader = _terrain_shader_obj()
		m.set_shader_parameter("detail_tex", noise_texture())
		m.set_shader_parameter("detail_strength", 0.28)
		m.set_shader_parameter("sway_amount", 1.0)
		_props_mat = m
	return _props_mat


static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		var sh := Shader.new()
		sh.code = WATER_CODE
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("wave_strength", 0.28)
		_water_mat = m
	return _water_mat


static func sky_material() -> ShaderMaterial:
	if _sky_mat == null:
		var sh := Shader.new()
		sh.code = SKY_CODE
		var m := ShaderMaterial.new()
		m.shader = sh
		_sky_mat = m
	return _sky_mat
