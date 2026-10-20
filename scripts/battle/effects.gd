extends Node3D
## Pooled visual effects: smoke (alpha blended), fire / sparks / muzzle flashes (additive), debris,
## flashes, shock rings, scorch marks and burning wrecks.
## Everything lives in fixed pools and is advanced manually in step(dt), so nothing is allocated mid-game.

const Cfg = preload("res://scripts/core/config.gd")
const MeshKit = preload("res://scripts/util/mesh_kit.gd")

const PUFFS: int = 90
const GLOWS: int = 90
const DEBRIS: int = 36
const FLASHES: int = 12
const RINGS: int = 3
const SMALL_RINGS: int = 8
const SCORCH: int = 8
const BURNERS: int = 6


class FxPuff extends RefCounted:
	var active: bool = false
	var node: MeshInstance3D = null
	var mat: StandardMaterial3D = null
	var pos: Vector3 = Vector3.ZERO
	var vel: Vector3 = Vector3.ZERO
	var life: float = 0.0
	var max_life: float = 1.0
	var s0: float = 1.0
	var s1: float = 1.0
	var c0: Color = Color.WHITE
	var c1: Color = Color.WHITE
	var grav: float = 0.0
	var drag: float = 0.0


class FxDebris extends RefCounted:
	var active: bool = false
	var node: MeshInstance3D = null
	var pos: Vector3 = Vector3.ZERO
	var vel: Vector3 = Vector3.ZERO
	var spin: Vector3 = Vector3.ZERO
	var life: float = 0.0
	var max_life: float = 1.0
	var size: float = 1.0
	var floor_y: float = 0.0
	var trail: float = 0.0


class FxGlow extends RefCounted:
	var active: bool = false
	var node: MeshInstance3D = null
	var mat: StandardMaterial3D = null
	var life: float = 0.0
	var max_life: float = 1.0
	var r0: float = 0.0
	var r1: float = 1.0
	var color: Color = Color.WHITE
	var alpha: float = 1.0


class FxBurn extends RefCounted:
	var active: bool = false
	var pos: Vector3 = Vector3.ZERO
	var t: float = 0.0
	var dur: float = 4.0
	var size: float = 1.0
	var acc: float = 0.0
	var tick: int = 0


var density: float = 1.0

var _puffs: Array = []
var _glows: Array = []
var _debris: Array = []
var _flashes: Array = []
var _rings: Array = []
var _small_rings: Array = []
var _scorch: Array = []
var _burners: Array = []
var _pc: int = 0
var _gc: int = 0
var _dc: int = 0
var _fc: int = 0
var _rc: int = 0
var _src: int = 0
var _sc: int = 0
var _bc: int = 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 6
	sph.rings = 3
	for i in range(PUFFS):
		var p := FxPuff.new()
		p.mat = _alpha_mat(false)
		p.node = _make_node(sph, p.mat)
		_puffs.append(p)
	for i in range(GLOWS):
		var p2 := FxPuff.new()
		p2.mat = _alpha_mat(true)
		p2.node = _make_node(sph, p2.mat)
		_glows.append(p2)

	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var dmats: Array = [MeshKit.mat(Color(0.18, 0.17, 0.16), 0.9), MeshKit.mat(Color(0.35, 0.30, 0.22), 0.9), MeshKit.mat(Color(0.12, 0.12, 0.13), 0.8)]
	for i in range(DEBRIS):
		var c := FxDebris.new()
		c.node = _make_node(cube, dmats[i % dmats.size()])
		_debris.append(c)

	var big := SphereMesh.new()
	big.radius = 1.0
	big.height = 2.0
	big.radial_segments = 10
	big.rings = 5
	for i in range(FLASHES):
		var g := FxGlow.new()
		g.mat = _alpha_mat(true)
		g.node = _make_node(big, g.mat)
		_flashes.append(g)

	var tor := TorusMesh.new()
	tor.inner_radius = 0.94
	tor.outer_radius = 1.0
	tor.rings = 24
	tor.ring_segments = 4
	for i in range(RINGS):
		var g2 := FxGlow.new()
		g2.mat = _alpha_mat(true)
		g2.node = _make_node(tor, g2.mat)
		_rings.append(g2)
	for i in range(SMALL_RINGS):
		var g3 := FxGlow.new()
		g3.mat = _alpha_mat(true)
		g3.node = _make_node(tor, g3.mat)
		_small_rings.append(g3)

	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.05
	disc.radial_segments = 10
	disc.rings = 1
	for i in range(SCORCH):
		var g4 := FxGlow.new()
		g4.mat = _alpha_mat(false)
		g4.node = _make_node(disc, g4.mat)
		_scorch.append(g4)

	for i in range(BURNERS):
		_burners.append(FxBurn.new())


func _alpha_mat(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1, 1, 1, 0)
	return m


func _make_node(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _n(x: float) -> int:
	return maxi(1, int(x * density))


# ------------------------------------------------------------------ primitives

## additive = true draws a bright glowing puff (fire, sparks, flashes); false draws soft smoke.
func puff(pos: Vector3, vel: Vector3, life: float, s0: float, s1: float, c0: Color, c1: Color, grav: float = 0.0, drag: float = 0.0, additive: bool = false) -> void:
	var p: FxPuff
	if additive:
		p = _glows[_gc]
		_gc = (_gc + 1) % GLOWS
	else:
		p = _puffs[_pc]
		_pc = (_pc + 1) % PUFFS
	p.active = true
	p.pos = pos
	p.vel = vel
	p.life = life
	p.max_life = maxf(life, 0.01)
	p.s0 = s0
	p.s1 = s1
	p.c0 = c0
	p.c1 = c1
	p.grav = grav
	p.drag = drag
	p.node.position = pos
	p.node.scale = Vector3.ONE * s0
	p.mat.albedo_color = c0
	p.node.visible = true


func debris(pos: Vector3, vel: Vector3, size: float, life: float, floor_y: float) -> void:
	var c: FxDebris = _debris[_dc]
	_dc = (_dc + 1) % DEBRIS
	c.active = true
	c.pos = pos
	c.vel = vel
	c.spin = Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0))
	c.life = life
	c.max_life = maxf(life, 0.01)
	c.size = size
	c.floor_y = floor_y
	c.trail = 0.0
	c.node.position = pos
	c.node.scale = Vector3.ONE * size
	c.node.visible = true


func _start_glow(pool: Array, cursor: int, pos: Vector3, r0: float, r1: float, life: float, color: Color, alpha: float) -> void:
	var g: FxGlow = pool[cursor]
	g.active = true
	g.life = life
	g.max_life = maxf(life, 0.01)
	g.r0 = r0
	g.r1 = r1
	g.color = color
	g.alpha = alpha
	g.node.position = pos
	g.node.visible = true


func flash(pos: Vector3, radius: float, life: float, color: Color) -> void:
	var idx: int = _fc
	_fc = (_fc + 1) % FLASHES
	_start_glow(_flashes, idx, pos, radius * 0.3, radius, life, color, 0.9)


## small = true uses the pool reserved for ordinary explosions so it never cuts a nuke shockwave short.
func ring(pos: Vector3, radius: float, life: float, color: Color, small: bool = false) -> void:
	if small:
		var si: int = _src
		_src = (_src + 1) % SMALL_RINGS
		_start_glow(_small_rings, si, pos, 1.0, radius, life, color, 0.75)
	else:
		var idx: int = _rc
		_rc = (_rc + 1) % RINGS
		_start_glow(_rings, idx, pos, 1.0, radius, life, color, 0.85)


func scorch(pos: Vector3, radius: float, life: float) -> void:
	var idx: int = _sc
	_sc = (_sc + 1) % SCORCH
	_start_glow(_scorch, idx, pos, radius, radius, life, Color(0.05, 0.04, 0.04), 0.55)


## A smoking, flickering wreck that stays where it fell (the terrain scrolls past it).
func burning(pos: Vector3, duration: float, size: float) -> void:
	if density < 0.6:
		return
	var b: FxBurn = _burners[_bc]
	_bc = (_bc + 1) % BURNERS
	b.active = true
	b.pos = pos
	b.t = 0.0
	b.dur = duration
	b.size = size
	b.acc = 0.0
	b.tick = 0


# ------------------------------------------------------------------ composed effects

func muzzle(pos: Vector3, color: Color) -> void:
	puff(pos, Vector3.ZERO, 0.07, 0.85, 0.25, Color(color.r, color.g, color.b, 0.95), Color(color.r, color.g, color.b, 0.0), 0.0, 0.0, true)


func hit_spark(pos: Vector3, color: Color) -> void:
	for i in range(_n(4.0)):
		var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.2, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(5.0, 11.0)
		puff(pos, d, 0.26, 0.32, 0.08, Color(color.r, color.g, color.b, 1.0), Color(color.r, color.g, color.b, 0.0), 16.0, 2.0, true)
	puff(pos, Vector3.ZERO, 0.09, 0.9, 0.3, Color(1.0, 1.0, 0.9, 0.8), Color(color.r, color.g, color.b, 0.0), 0.0, 0.0, true)


func smoke_trail(pos: Vector3, size: float = 0.7) -> void:
	puff(pos, Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.2, 1.0), rng.randf_range(-0.6, 0.6)), 0.6, size * 0.6, size * 1.9, Color(0.78, 0.75, 0.70, 0.5), Color(0.3, 0.3, 0.3, 0.0))


func splash(pos: Vector3) -> void:
	for i in range(_n(10.0)):
		var d := Vector3(rng.randf_range(-3.5, 3.5), rng.randf_range(5.0, 10.0), rng.randf_range(-3.5, 3.5))
		puff(pos, d, 0.75, 0.8, 0.3, Color(0.85, 0.93, 1.0, 0.85), Color(0.6, 0.8, 0.95, 0.0), 14.0, 0.5)
	ring(pos + Vector3(0.0, 0.2, 0.0), 6.0, 0.6, Color(0.8, 0.95, 1.0), true)


## ground_y: terrain height under the blast (for scorch marks and debris floor); pass -999 for an air burst.
func explosion(pos: Vector3, size: float = 1.0, ground_y: float = -999.0) -> void:
	flash(pos, 2.6 * size, 0.16, Color(1.0, 0.96, 0.75))
	flash(pos, 4.4 * size, 0.34, Color(1.0, 0.55, 0.15))
	# fire ball
	for i in range(_n(6.0 + 3.0 * size)):
		var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.2, 1.2), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(2.0, 7.0) * size
		puff(pos, d, rng.randf_range(0.4, 0.85), 1.4 * size, 0.5 * size, Color(1.0, 0.82, 0.35, 0.95), Color(0.9, 0.22, 0.05, 0.0), 0.0, 1.5, true)
	for i in range(_n(3.0)):
		puff(pos + Vector3(rng.randf_range(-0.5, 0.5), 0.3, rng.randf_range(-0.5, 0.5)), Vector3(0.0, 2.0, 0.0), 0.25, 1.6 * size, 0.6 * size, Color(1.0, 1.0, 0.9, 0.9), Color(1.0, 0.7, 0.3, 0.0), 0.0, 0.0, true)
	# rising smoke
	for i in range(_n(4.0 + 2.0 * size)):
		var v := Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(2.5, 5.0), rng.randf_range(-2.0, 2.0))
		puff(pos, v, rng.randf_range(1.2, 2.0), 1.3 * size, 3.4 * size, Color(0.26, 0.25, 0.24, 0.78), Color(0.10, 0.10, 0.10, 0.0), 0.0, 0.8)
	# flying sparks
	for i in range(_n(6.0 + 4.0 * size)):
		var sv := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.4, 1.4), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(8.0, 18.0)
		puff(pos, sv, rng.randf_range(0.5, 0.95), 0.28, 0.05, Color(1.0, 0.85, 0.35, 1.0), Color(1.0, 0.35, 0.05, 0.0), 18.0, 1.0, true)
	var floor_y: float = ground_y if ground_y > -900.0 else pos.y - 14.0
	for i in range(_n(3.0 + 3.0 * size)):
		var dv := Vector3(rng.randf_range(-7.0, 7.0), rng.randf_range(7.0, 15.0), rng.randf_range(-7.0, 7.0)) * clampf(size, 0.6, 1.8)
		debris(pos, dv, rng.randf_range(0.3, 0.7) * size, rng.randf_range(0.9, 1.4), floor_y)
	if ground_y > -900.0:
		scorch(Vector3(pos.x, ground_y + 0.08, pos.z), 2.4 * size, 10.0)
		if size >= 1.0:
			ring(Vector3(pos.x, ground_y + 0.5, pos.z), 5.5 * size, 0.38, Color(1.0, 0.72, 0.38), true)
			for i in range(_n(4.0)):
				var a: float = TAU * float(i) / 4.0 + rng.randf() * 0.6
				puff(Vector3(pos.x, ground_y + 0.6, pos.z), Vector3(cos(a) * 7.0, 0.6, sin(a) * 7.0), 0.8, 1.2 * size, 3.4 * size, Color(0.58, 0.50, 0.40, 0.5), Color(0.5, 0.45, 0.38, 0.0), 0.0, 2.0)


func nuke(pos: Vector3) -> void:
	flash(pos + Vector3(0.0, 4.0, 0.0), 46.0, 0.9, Color(1.0, 0.94, 0.7))
	flash(pos + Vector3(0.0, 2.0, 0.0), 26.0, 1.5, Color(1.0, 0.55, 0.15))
	flash(pos + Vector3(0.0, 12.0, 0.0), 16.0, 1.9, Color(1.0, 0.45, 0.12))
	var life: float = Cfg.NUKE_RADIUS / Cfg.NUKE_SHOCK_SPEED
	ring(pos + Vector3(0.0, 1.0, 0.0), Cfg.NUKE_RADIUS, life, Color(1.0, 0.88, 0.55))
	ring(pos + Vector3(0.0, 1.0, 0.0), Cfg.NUKE_RADIUS * 0.7, life * 1.15, Color(1.0, 0.5, 0.2))
	ring(pos + Vector3(0.0, 1.0, 0.0), Cfg.NUKE_RADIUS * 0.4, life * 1.3, Color(1.0, 0.95, 0.8))
	scorch(Vector3(pos.x, pos.y + 0.1, pos.z), 15.0, 22.0)
	# stalk and cap in fire colours (additive) with smoke behind
	for i in range(14):
		var h: float = float(i) / 13.0
		var v := Vector3(rng.randf_range(-1.5, 1.5), 8.0 + h * 11.0, rng.randf_range(-1.5, 1.5))
		puff(pos + Vector3(rng.randf_range(-1.5, 1.5), 1.0, rng.randf_range(-1.5, 1.5)), v, 3.2 + h * 1.2, 2.6, 5.5, Color(1.0, 0.62, 0.22, 0.85), Color(0.5, 0.2, 0.08, 0.0), 0.0, 0.5, true)
		puff(pos + Vector3(rng.randf_range(-1.5, 1.5), 1.0, rng.randf_range(-1.5, 1.5)), v * 0.9, 4.2 + h * 1.4, 3.0, 7.0, Color(0.30, 0.26, 0.24, 0.7), Color(0.12, 0.11, 0.10, 0.0), 0.0, 0.5)
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		var v2 := Vector3(cos(a) * 9.0, 14.0 + rng.randf_range(-2.0, 2.0), sin(a) * 9.0)
		puff(pos + Vector3(0.0, 8.0, 0.0), v2, 3.6, 4.0, 8.5, Color(1.0, 0.5, 0.15, 0.85), Color(0.35, 0.15, 0.08, 0.0), 0.0, 1.3, true)
		puff(pos + Vector3(0.0, 8.0, 0.0), v2 * 0.8, 4.4, 4.5, 9.5, Color(0.26, 0.23, 0.22, 0.7), Color(0.12, 0.11, 0.10, 0.0), 0.0, 1.3)
	for i in range(_n(30.0)):
		var sv := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.3, 1.2), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(14.0, 34.0)
		puff(pos + Vector3(0.0, 2.0, 0.0), sv, rng.randf_range(0.9, 1.8), 0.5, 0.08, Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.3, 0.05, 0.0), 22.0, 0.6, true)
	for i in range(20):
		var dv := Vector3(rng.randf_range(-22.0, 22.0), rng.randf_range(14.0, 30.0), rng.randf_range(-22.0, 22.0))
		debris(pos + Vector3(0.0, 1.0, 0.0), dv, rng.randf_range(0.5, 1.2), rng.randf_range(1.4, 2.2), pos.y - 1.0)


func clear() -> void:
	for p in _puffs:
		p.active = false
		p.node.visible = false
	for p2 in _glows:
		p2.active = false
		p2.node.visible = false
	for c in _debris:
		c.active = false
		c.node.visible = false
	for pool in [_flashes, _rings, _small_rings, _scorch]:
		for g in pool:
			g.active = false
			g.node.visible = false
	for b in _burners:
		b.active = false


# ------------------------------------------------------------------ update

func step(dt: float) -> void:
	_step_puffs(_puffs, dt)
	_step_puffs(_glows, dt)

	for c in _debris:
		if not c.active:
			continue
		c.life -= dt
		if c.life <= 0.0:
			c.active = false
			c.node.visible = false
			continue
		c.vel.y -= 32.0 * dt
		c.pos += c.vel * dt
		if c.pos.y < c.floor_y:
			c.pos.y = c.floor_y
			c.vel = Vector3.ZERO
			c.spin = Vector3.ZERO
		elif density >= 0.6 and c.size >= 0.55:
			c.trail -= dt
			if c.trail <= 0.0:
				c.trail = 0.07
				puff(c.pos, Vector3.ZERO, 0.4, 0.5, 1.3, Color(0.3, 0.28, 0.26, 0.4), Color(0.2, 0.2, 0.2, 0.0))
		c.node.position = c.pos
		c.node.rotation += c.spin * dt
		var f: float = clampf(c.life / c.max_life * 3.0, 0.0, 1.0)
		c.node.scale = Vector3.ONE * (c.size * f)

	_step_glow(_flashes, dt, 0)
	_step_glow(_rings, dt, 1)
	_step_glow(_small_rings, dt, 1)
	_step_glow(_scorch, dt, 2)

	for b in _burners:
		if not b.active:
			continue
		b.t += dt
		if b.t >= b.dur:
			b.active = false
			continue
		b.acc += dt
		if b.acc >= 0.11:
			b.acc = 0.0
			b.tick += 1
			var fade: float = 1.0 - clampf(b.t / b.dur, 0.0, 1.0)
			var jit := Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8))
			puff(b.pos + jit, Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(2.5, 4.5), rng.randf_range(-0.5, 0.5)), 1.7, b.size * 0.9, b.size * 3.0, Color(0.13, 0.13, 0.13, 0.6 * fade), Color(0.06, 0.06, 0.06, 0.0), 0.0, 0.6)
			if b.tick % 2 == 0 and fade > 0.25:
				puff(b.pos + jit, Vector3(0.0, 1.8, 0.0), 0.4, b.size * 0.9, b.size * 0.2, Color(1.0, 0.62, 0.15, 0.85), Color(1.0, 0.2, 0.05, 0.0), 0.0, 0.5, true)


func _step_puffs(pool: Array, dt: float) -> void:
	for p in pool:
		if not p.active:
			continue
		p.life -= dt
		if p.life <= 0.0:
			p.active = false
			p.node.visible = false
			continue
		var t: float = 1.0 - p.life / p.max_life
		p.vel.y -= p.grav * dt
		p.vel *= maxf(0.0, 1.0 - p.drag * dt)
		p.pos += p.vel * dt
		var sz: float = lerpf(p.s0, p.s1, t)
		p.node.position = p.pos
		p.node.scale = Vector3(sz, sz, sz)
		p.mat.albedo_color = p.c0.lerp(p.c1, t)


func _step_glow(pool: Array, dt: float, mode: int) -> void:
	for g in pool:
		if not g.active:
			continue
		g.life -= dt
		if g.life <= 0.0:
			g.active = false
			g.node.visible = false
			continue
		var t: float = 1.0 - g.life / g.max_life
		var r: float = lerpf(g.r0, g.r1, t)
		var a: float = g.alpha
		if mode == 0:
			r = lerpf(g.r0, g.r1, sqrt(t))
			a = g.alpha * (1.0 - t)
			g.node.scale = Vector3(r, r, r)
		elif mode == 1:
			a = g.alpha * (1.0 - t * t)
			g.node.scale = Vector3(r, maxf(0.4, r * 0.12), r)
		else:
			a = g.alpha * clampf(g.life / (g.max_life * 0.4), 0.0, 1.0)
			g.node.scale = Vector3(r, 1.0, r)
		g.mat.albedo_color = Color(g.color.r, g.color.g, g.color.b, a)
