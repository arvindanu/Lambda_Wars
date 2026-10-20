extends Node3D
## Infinite procedural war terrain, streamed in chunks along the flight path (-Z).
## Height, road and river are pure functions of (x, z), so neighbouring chunks always line up.
##
## Visual features: per-vertex baked ambient occlusion, slope-based rock, biome patches, crisp road ribbon
## with markings and bridges, translucent shoreline water with foam, wind-swayed vegetation,
## contact shadows and war-torn props. Each chunk is built in two cheap stages (terrain, then props).

const Cfg = preload("res://scripts/core/config.gd")
const MeshBuilder = preload("res://scripts/util/mesh_builder.gd")
const Shaders = preload("res://scripts/util/shaders.gd")

const ROAD_HALF: float = 3.2
const ROAD_FLAT: float = 3.6
const WATER_Y: float = -0.4

const C_GRASS := Color(0.34, 0.52, 0.22)
const C_LUSH := Color(0.24, 0.50, 0.20)
const C_FOREST := Color(0.15, 0.33, 0.17)
const C_DRY := Color(0.76, 0.65, 0.40)
const C_SCRUB := Color(0.55, 0.50, 0.28)
const C_DIRT := Color(0.46, 0.37, 0.24)
const C_ROCK := Color(0.47, 0.45, 0.43)
const C_SNOW := Color(0.92, 0.94, 0.97)
const C_SAND := Color(0.80, 0.73, 0.52)
const C_WET := Color(0.52, 0.46, 0.34)
const C_BED := Color(0.16, 0.28, 0.34)
const C_BED_DEEP := Color(0.07, 0.15, 0.22)
const C_GRAVEL := Color(0.52, 0.48, 0.42)
const C_ASPHALT := Color(0.17, 0.18, 0.20)
const C_LINE := Color(0.78, 0.76, 0.66)

var _hill := FastNoiseLite.new()
var _mount := FastNoiseLite.new()
var _biome := FastNoiseLite.new()
var _patch := FastNoiseLite.new()
var _seed: int = 1
var _road_p1: float = 0.0
var _road_p2: float = 0.0
var _river_p1: float = 0.0
var _river_p2: float = 0.0
var _chunks: Dictionary = {}
var _chunk_root: Node3D = null
var _quality: int = 2
var _mat_ground: Material = null
var _mat_props: Material = null
var _mat_water: Material = null


func setup(seed_value: int) -> void:
	_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_road_p1 = rng.randf() * TAU
	_road_p2 = rng.randf() * TAU
	_river_p1 = rng.randf() * TAU
	_river_p2 = rng.randf() * TAU
	_configure(_hill, seed_value, 0.0075, 3)
	_configure(_mount, seed_value + 11, 0.0022, 2)
	_configure(_biome, seed_value + 29, 0.0035, 2)
	_configure(_patch, seed_value + 53, 0.05, 2)
	_chunk_root = Node3D.new()
	_chunk_root.name = "Chunks"
	add_child(_chunk_root)
	_mat_water = Shaders.water_material()
	apply_quality(GameState.quality)


func _configure(n: FastNoiseLite, s: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves


## Quality 0 uses plain vertex-colour materials; 1 and 2 use the detail / wind shaders.
func apply_quality(q: int) -> void:
	_quality = q
	if q <= 0:
		_mat_ground = MeshBuilder.vertex_material()
		_mat_props = MeshBuilder.vertex_material()
	else:
		_mat_ground = Shaders.terrain_material()
		_mat_props = Shaders.props_material()
	for key in _chunks.keys():
		var e: Dictionary = _chunks[key]
		if e.has("ground"):
			(e["ground"] as MeshInstance3D).material_override = _mat_ground
		if e.has("props"):
			(e["props"] as MeshInstance3D).material_override = _mat_props


# ------------------------------------------------------------------ terrain functions

func road_x(z: float) -> float:
	return sin(z * 0.011 + _road_p1) * 34.0 + sin(z * 0.0043 + _road_p2) * 26.0


func river_x(z: float) -> float:
	return sin(z * 0.0085 + _river_p1) * 45.0 + cos(z * 0.0033 + _river_p2) * 30.0


func height_at(x: float, z: float) -> float:
	var h: float = _hill.get_noise_2d(x, z) * 5.5 + 3.0
	var m: float = maxf(0.0, _mount.get_noise_2d(x, z) - 0.05)
	h += m * 16.0
	h = minf(h, 13.0)
	var rw: float = 1.0 - smoothstep(3.5, 13.0, absf(x - river_x(z)))
	h = lerpf(h, -2.2, rw)
	var roadw: float = 1.0 - smoothstep(ROAD_FLAT, 7.5, absf(x - road_x(z)))
	h = lerpf(h, 1.0, roadw)
	return h


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < Cfg.WATER_LEVEL - 0.3


func _rand01(ix: int, iz: int, salt: int) -> float:
	var h: int = ((ix * 73856093) ^ (iz * 19349663) ^ (salt * 83492791)) & 0x7FFFFFFF
	h = ((h >> 13) ^ h) & 0x7FFFFFFF
	h = (h * 1103515245 + 12345) & 0x7FFFFFFF
	return float(h) / 2147483647.0


func _biome_color(x: float, z: float, h: float) -> Color:
	var b: float = _biome.get_noise_2d(x, z)
	var p: float = _patch.get_noise_2d(x, z)
	var dry: float = smoothstep(0.12, 0.42, b)
	var forest: float = 1.0 - smoothstep(-0.5, -0.18, b)
	var grass: Color = C_GRASS.lerp(C_LUSH, smoothstep(-0.1, 0.5, p) * 0.7)
	grass = grass.lerp(C_DIRT, smoothstep(0.32, 0.6, p) * 0.75)
	var desert: Color = C_DRY.lerp(C_SCRUB, smoothstep(0.0, 0.5, p) * 0.8)
	var col: Color = grass.lerp(desert, dry).lerp(C_FOREST, forest)
	if h > 8.5:
		col = col.lerp(C_ROCK, smoothstep(8.5, 10.5, h))
	if h > 12.0:
		col = col.lerp(C_SNOW, smoothstep(12.0, 13.0, h))
	return col


func _vertex_color(x: float, z: float, h: float, ao: float) -> Color:
	var col: Color = _biome_color(x, z, h)
	var rw: float = 1.0 - smoothstep(3.5, 13.0, absf(x - river_x(z)))
	if h < -0.05:
		col = C_BED.lerp(C_BED_DEEP, clampf(-h / 2.2, 0.0, 1.0))
	elif rw > 0.1 and h < 1.8:
		col = col.lerp(C_SAND, 0.8 * smoothstep(0.1, 0.5, rw))
		if h < 0.4:
			col = col.lerp(C_WET, 0.55)
	var dd: float = absf(x - road_x(z))
	var verge: float = smoothstep(ROAD_HALF - 1.2, ROAD_HALF, dd) * (1.0 - smoothstep(ROAD_HALF + 0.8, ROAD_HALF + 3.0, dd))
	col = col.lerp(C_GRAVEL, verge * 0.6)
	if dd < ROAD_HALF - 0.6:
		col = col.lerp(C_ASPHALT, 0.9)
	var lift: float = clampf((h - 4.0) * 0.012, -0.05, 0.10)
	return MeshBuilder.shade(col, ao + lift)


# ------------------------------------------------------------------ streaming

func _row_order(row_c: int) -> Array:
	var rows: Array = [row_c]
	var span: int = maxi(Cfg.ROWS_AHEAD, Cfg.ROWS_BEHIND)
	for k in range(1, span + 1):
		if k <= Cfg.ROWS_AHEAD:
			rows.append(row_c + k)
		if k <= Cfg.ROWS_BEHIND:
			rows.append(row_c - k)
	return rows


## Builds up to `budget` chunk stages (terrain first, then props) and frees chunks left behind.
func update(focus: Vector3, budget: int = 1) -> void:
	var row_c: int = int(floorf(-focus.z / Cfg.CHUNK_SIZE))
	var rows: Array = _row_order(row_c)
	var used: int = 0
	for r in rows:
		for c in range(Cfg.COL_MIN, Cfg.COL_MAX + 1):
			if used >= budget:
				break
			var key := Vector2i(c, int(r))
			if not _chunks.has(key):
				_make_terrain(c, int(r))
				used += 1
	if used < budget:
		for r in rows:
			for c in range(Cfg.COL_MIN, Cfg.COL_MAX + 1):
				if used >= budget:
					break
				var key2 := Vector2i(c, int(r))
				if _chunks.has(key2):
					var e: Dictionary = _chunks[key2]
					if not bool(e["props_done"]):
						_make_props(key2)
						used += 1
	var stale: Array = []
	for key3 in _chunks.keys():
		var kv: Vector2i = key3
		if kv.y < row_c - Cfg.ROWS_BEHIND - 1 or kv.y > row_c + Cfg.ROWS_AHEAD + 2:
			stale.append(kv)
	for key4 in stale:
		var entry: Dictionary = _chunks[key4]
		_chunks.erase(key4)
		(entry["root"] as Node3D).queue_free()


## Builds everything around the focus immediately.
func prebuild(focus: Vector3) -> void:
	update(focus, 100000)


## 0..1 progress of the chunk ring around the focus (used by the loading screen).
func progress(focus: Vector3) -> float:
	var row_c: int = int(floorf(-focus.z / Cfg.CHUNK_SIZE))
	var needed: int = 0
	var done: int = 0
	for r in _row_order(row_c):
		for c in range(Cfg.COL_MIN, Cfg.COL_MAX + 1):
			needed += 2
			var key := Vector2i(c, int(r))
			if _chunks.has(key):
				done += 1
				var e: Dictionary = _chunks[key]
				if bool(e["props_done"]):
					done += 1
	return float(done) / float(maxi(needed, 1))


# ------------------------------------------------------------------ terrain stage

func _hg(hs: PackedFloat32Array, i: int, j: int, n: int, stride: int, x0: float, z0: float, cell: float) -> float:
	if i >= 0 and i <= n and j >= 0 and j <= n:
		return hs[j * stride + i]
	return height_at(x0 + float(i) * cell, z0 - float(j) * cell)


func _make_terrain(col: int, row: int) -> void:
	var n: int = Cfg.CHUNK_CELLS
	var cell: float = Cfg.CHUNK_SIZE / float(n)
	var x0: float = float(col) * Cfg.CHUNK_SIZE
	var z0: float = -float(row) * Cfg.CHUNK_SIZE
	var stride: int = n + 1
	var hs := PackedFloat32Array()
	hs.resize(stride * stride)
	for j in range(stride):
		for i in range(stride):
			hs[j * stride + i] = height_at(x0 + float(i) * cell, z0 - float(j) * cell)

	# per-vertex colour with baked ambient occlusion (valleys darker, ridges lighter)
	var vc := PackedColorArray()
	vc.resize(stride * stride)
	for j in range(stride):
		for i in range(stride):
			var h: float = hs[j * stride + i]
			var avg: float = (_hg(hs, i - 1, j, n, stride, x0, z0, cell) + _hg(hs, i + 1, j, n, stride, x0, z0, cell) + _hg(hs, i, j - 1, n, stride, x0, z0, cell) + _hg(hs, i, j + 1, n, stride, x0, z0, cell)) * 0.25
			var ao: float = clampf(1.0 - (avg - h) * 0.10, 0.60, 1.08)
			vc[j * stride + i] = _vertex_color(x0 + float(i) * cell, z0 - float(j) * cell, h, ao)

	var tb := MeshBuilder.new()
	var wb := MeshBuilder.new()
	for j in range(n):
		for i in range(n):
			var xa: float = x0 + float(i) * cell
			var xb: float = xa + cell
			var za: float = z0 - float(j) * cell
			var zb: float = za - cell
			var i00: int = j * stride + i
			var i10: int = i00 + 1
			var i01: int = i00 + stride
			var i11: int = i01 + 1
			var p00 := Vector3(xa, hs[i00], za)
			var p10 := Vector3(xb, hs[i10], za)
			var p01 := Vector3(xa, hs[i01], zb)
			var p11 := Vector3(xb, hs[i11], zb)
			var gi: int = col * n + i
			var gj: int = -row * n - j
			if ((i + j + col + row) & 1) == 0:
				_ground_tri(tb, p00, p10, p01, vc[i00], vc[i10], vc[i01], gi, gj, 0)
				_ground_tri(tb, p10, p11, p01, vc[i10], vc[i11], vc[i01], gi, gj, 1)
			else:
				_ground_tri(tb, p00, p10, p11, vc[i00], vc[i10], vc[i11], gi, gj, 2)
				_ground_tri(tb, p00, p11, p01, vc[i00], vc[i11], vc[i01], gi, gj, 3)
			var lowest: float = minf(minf(hs[i00], hs[i10]), minf(hs[i01], hs[i11]))
			if lowest < WATER_Y + 0.15:
				_water_cell(wb, xa, xb, za, zb, hs[i00], hs[i10], hs[i01], hs[i11])

	_road_ribbon(tb, x0, z0)

	var root := Node3D.new()
	var entry: Dictionary = {"root": root, "props_done": false}
	var gmesh: ArrayMesh = tb.build(null)
	if gmesh != null:
		var gm := MeshInstance3D.new()
		gm.mesh = gmesh
		gm.material_override = _mat_ground
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gm)
		entry["ground"] = gm
	var wmesh: ArrayMesh = wb.build(null)
	if wmesh != null:
		var wm := MeshInstance3D.new()
		wm.mesh = wmesh
		wm.material_override = _mat_water
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wm)
		entry["water"] = wm
	_chunk_root.add_child(root)
	_chunks[Vector2i(col, row)] = entry


func _ground_tri(tb, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, gi: int, gj: int, sub: int) -> void:
	var nrm: Vector3 = (b - a).cross(c - a)
	var ny: float = 1.0
	if nrm.length_squared() > 0.000001:
		ny = absf(nrm.normalized().y)
	var mid: Vector3 = (a + b + c) / 3.0
	var sl: float = 0.0
	if mid.y > 1.6:
		sl = (1.0 - smoothstep(0.66, 0.88, ny)) * 0.75
	var jit: float = 0.94 + _rand01(gi, gj, sub + 7) * 0.12
	var ra: Color = MeshBuilder.shade(ca.lerp(C_ROCK, sl), jit)
	var rb: Color = MeshBuilder.shade(cb.lerp(C_ROCK, sl), jit)
	var rc: Color = MeshBuilder.shade(cc.lerp(C_ROCK, sl), jit)
	tb.tri_up3(a, b, c, ra, rb, rc)


func _water_vertex_color(h: float) -> Color:
	var d: float = maxf(0.0, WATER_Y - h)
	var shallow := Color(0.22, 0.52, 0.56)
	var deep := Color(0.04, 0.19, 0.30)
	var col: Color = shallow.lerp(deep, smoothstep(0.0, 1.8, d))
	var foam: float = 1.0 - smoothstep(0.0, 0.5, d)
	col = col.lerp(Color(0.88, 0.94, 0.96), foam * 0.8)
	col.a = lerpf(0.55, 0.94, smoothstep(0.0, 0.9, d))
	return col


func _water_cell(wb, xa: float, xb: float, za: float, zb: float, h00: float, h10: float, h01: float, h11: float) -> void:
	var a := Vector3(xa, WATER_Y, za)
	var b := Vector3(xb, WATER_Y, za)
	var c := Vector3(xa, WATER_Y, zb)
	var d := Vector3(xb, WATER_Y, zb)
	var ca: Color = _water_vertex_color(h00)
	var cb: Color = _water_vertex_color(h10)
	var cc: Color = _water_vertex_color(h01)
	var cd: Color = _water_vertex_color(h11)
	wb.tri_up3(a, b, c, ca, cb, cc)
	wb.tri_up3(b, d, c, cb, cd, cc)


## Crisp asphalt ribbon with edge lines laid just above the flattened road terrain.
func _road_ribbon(tb, x0: float, z0: float) -> void:
	var step: float = 2.0
	var count: int = int(Cfg.CHUNK_SIZE / step)
	for k in range(count):
		var za: float = z0 - float(k) * step
		var zb: float = za - step
		var xa: float = road_x(za)
		var xb: float = road_x(zb)
		if maxf(xa, xb) < x0 - 4.0 or minf(xa, xb) > x0 + Cfg.CHUNK_SIZE + 4.0:
			continue
		var y: float = 1.045
		var dark: Color = MeshBuilder.shade(C_ASPHALT, 0.92 + _rand01(k, int(z0), 3) * 0.16)
		_ribbon_quad(tb, xa - ROAD_HALF, xa + ROAD_HALF, xb - ROAD_HALF, xb + ROAD_HALF, za, zb, y, dark)
		_ribbon_quad(tb, xa - ROAD_HALF + 0.35, xa - ROAD_HALF + 0.65, xb - ROAD_HALF + 0.35, xb - ROAD_HALF + 0.65, za, zb, y + 0.012, C_LINE)
		_ribbon_quad(tb, xa + ROAD_HALF - 0.65, xa + ROAD_HALF - 0.35, xb + ROAD_HALF - 0.65, xb + ROAD_HALF - 0.35, za, zb, y + 0.012, C_LINE)


func _ribbon_quad(tb, xa0: float, xa1: float, xb0: float, xb1: float, za: float, zb: float, y: float, col: Color) -> void:
	var p0 := Vector3(xa0, y, za)
	var p1 := Vector3(xa1, y, za)
	var p2 := Vector3(xb0, y, zb)
	var p3 := Vector3(xb1, y, zb)
	tb.tri_up(p0, p1, p2, col)
	tb.tri_up(p1, p3, p2, col)


# ------------------------------------------------------------------ props stage

func _make_props(key: Vector2i) -> void:
	var entry: Dictionary = _chunks[key]
	entry["props_done"] = true
	var col: int = key.x
	var row: int = key.y
	var x0: float = float(col) * Cfg.CHUNK_SIZE
	var z0: float = -float(row) * Cfg.CHUNK_SIZE
	var rng := RandomNumberGenerator.new()
	rng.seed = (col * 92821 + row * 68917 + _seed * 13) & 0x7FFFFFFF
	var pb := MeshBuilder.new()
	_add_props(pb, rng, x0, z0)
	_add_tufts(pb, rng, x0, z0)
	_add_road_details(pb, rng, x0, z0)
	_add_river_details(pb, rng, x0, z0)
	var pmesh: ArrayMesh = pb.build(null)
	if pmesh != null:
		var pm := MeshInstance3D.new()
		pm.mesh = pmesh
		pm.material_override = _mat_props
		(entry["root"] as Node3D).add_child(pm)
		entry["props"] = pm


func _add_props(pb, rng: RandomNumberGenerator, x0: float, z0: float) -> void:
	for k in range(34):
		var x: float = x0 + rng.randf() * Cfg.CHUNK_SIZE
		var z: float = z0 - rng.randf() * Cfg.CHUNK_SIZE
		var roll: float = rng.randf()
		var s: float = rng.randf_range(0.8, 1.5)
		var h: float = height_at(x, z)
		if h < 0.3:
			continue
		if absf(x - road_x(z)) < 9.0:
			continue
		var b: float = _biome.get_noise_2d(x, z)
		var base := Vector3(x, h - 0.3, z)
		if h > 9.5:
			if roll < 0.7:
				_rock(pb, base, s * 1.4, rng)
		elif b > 0.28:
			if roll < 0.30:
				_rock(pb, base, s, rng)
			elif roll < 0.46:
				_cactus(pb, base, s)
			elif roll < 0.56:
				_house(pb, base, s, rng, true)
			elif roll < 0.64:
				_crater(pb, Vector3(x, h + 0.04, z), s)
			elif roll < 0.70:
				_tank_wreck(pb, base, rng)
			elif roll < 0.76:
				_tent(pb, base, rng)
			elif roll < 0.84:
				_bush(pb, base, s, rng, true)
		elif b < -0.25:
			if roll < 0.62:
				_pine(pb, base, s, rng)
			elif roll < 0.72:
				_bush(pb, base, s, rng, false)
			elif roll < 0.80:
				_rock(pb, base, s, rng)
			elif roll < 0.86:
				_wreck(pb, base, rng)
			elif roll < 0.88:
				_tower(pb, base, rng)
		else:
			if roll < 0.24:
				_round_tree(pb, base, s, rng)
			elif roll < 0.38:
				_pine(pb, base, s, rng)
			elif roll < 0.48:
				_bush(pb, base, s, rng, false)
			elif roll < 0.55:
				_rock(pb, base, s, rng)
			elif roll < 0.65:
				_house(pb, base, s, rng, rng.randf() < 0.5)
			elif roll < 0.71:
				_wreck(pb, base, rng)
			elif roll < 0.76:
				_tank_wreck(pb, base, rng)
			elif roll < 0.81:
				_tent(pb, base, rng)
			elif roll < 0.85:
				_sandbags(pb, base, rng)
			elif roll < 0.92:
				_crater(pb, Vector3(x, h + 0.04, z), s)


func _add_tufts(pb, rng: RandomNumberGenerator, x0: float, z0: float) -> void:
	for k in range(16):
		var x: float = x0 + rng.randf() * Cfg.CHUNK_SIZE
		var z: float = z0 - rng.randf() * Cfg.CHUNK_SIZE
		var h: float = height_at(x, z)
		if h < 0.4 or h > 8.0 or absf(x - road_x(z)) < 6.0:
			continue
		var b: float = _biome.get_noise_2d(x, z)
		var base := Vector3(x, h - 0.1, z)
		if b > 0.3:
			pb.frustum(base, Vector3.UP, 0.4, 0.0, 0.8, 3, Color(0.62, 0.55, 0.30), rng.randf() * TAU, 0.3, 0.0, 1.0)
		elif k % 4 == 0:
			var fc: Color = [Color(0.95, 0.85, 0.25), Color(0.95, 0.55, 0.65), Color(0.95, 0.95, 0.9)][rng.randi() % 3]
			pb.frustum(base + Vector3(0.0, 0.5, 0.0), Vector3.UP, 0.22, 0.05, 0.25, 4, fc)
			pb.frustum(base, Vector3.UP, 0.05, 0.05, 0.5, 3, Color(0.25, 0.45, 0.18))
		else:
			pb.frustum(base, Vector3.UP, 0.5, 0.0, 0.9, 3, Color(0.30, 0.55, 0.22), rng.randf() * TAU, 0.3, 0.0, 1.0)


func _add_road_details(pb, rng: RandomNumberGenerator, x0: float, z0: float) -> void:
	var step: float = 6.0
	for k in range(int(Cfg.CHUNK_SIZE / step)):
		var z: float = z0 - (float(k) + 0.5) * step
		var rx: float = road_x(z)
		if rx < x0 or rx >= x0 + Cfg.CHUNK_SIZE:
			continue
		var slope: float = (road_x(z - 1.0) - road_x(z + 1.0)) * 0.5
		var basis := Basis(Vector3.UP, atan2(slope, 1.0))
		pb.box(Vector3(rx, 1.12, z), Vector3(0.28, 0.08, 2.4), Color(0.88, 0.80, 0.35), basis)
		var rw: float = 1.0 - smoothstep(3.5, 13.0, absf(rx - river_x(z)))
		if rw > 0.3:
			# bridge parapets and posts where the road crosses the river
			for side in [-1.0, 1.0]:
				var sx: float = float(side)
				pb.box(Vector3(rx + sx * (ROAD_HALF + 0.25), 1.55, z), Vector3(0.45, 0.9, 6.2), Color(0.62, 0.60, 0.56), basis, 0.35)
				pb.box(Vector3(rx + sx * (ROAD_HALF + 0.25), 0.2, z), Vector3(0.9, 1.2, 1.0), Color(0.45, 0.44, 0.42), basis, 0.4)
		elif k % 2 == 0:
			var sd: float = 1.0 if (k % 4) == 0 else -1.0
			_post(pb, Vector3(rx + sd * (ROAD_HALF + 1.6), height_at(rx + sd * (ROAD_HALF + 1.6), z), z))
		var cr: float = rng.randf()
		if cr < 0.10:
			_hedgehog(pb, Vector3(rx + rng.randf_range(-2.0, 2.0), 1.0, z), rng)
		elif cr < 0.17:
			_barrels(pb, Vector3(rx + (ROAD_HALF + 2.4) * (1.0 if rng.randf() < 0.5 else -1.0), height_at(rx + 5.6, z), z), rng)


func _add_river_details(pb, rng: RandomNumberGenerator, x0: float, z0: float) -> void:
	for k in range(7):
		var z: float = z0 - rng.randf() * Cfg.CHUNK_SIZE
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		var x: float = river_x(z) + side * rng.randf_range(5.5, 10.5)
		if x < x0 or x >= x0 + Cfg.CHUNK_SIZE or absf(x - road_x(z)) < 8.0:
			continue
		var h: float = height_at(x, z)
		if h < -0.1 or h > 2.2:
			continue
		if rng.randf() < 0.65:
			_reeds(pb, Vector3(x, h - 0.1, z), rng)
		else:
			_rock(pb, Vector3(x, h - 0.2, z), rng.randf_range(0.6, 1.1), rng)


# ------------------------------------------------------------------ prop shapes

func _contact(pb, base: Vector3, r: float) -> void:
	pb.frustum(base + Vector3(0.0, 0.38, 0.0), Vector3.UP, r, r * 0.88, 0.05, 8, Color(0.07, 0.08, 0.05))


func _pine(pb, base: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var g: float = rng.randf_range(0.85, 1.15)
	var green := Color(0.13 * g, 0.34 * g, 0.16 * g)
	_contact(pb, base, 1.7 * s)
	pb.frustum(base, Vector3.UP, 0.4 * s, 0.3 * s, 1.6 * s, 5, Color(0.30, 0.20, 0.12), 0.0, 0.35, 0.0, 0.08)
	pb.frustum(base + Vector3.UP * (1.1 * s), Vector3.UP, 2.1 * s, 0.2 * s, 3.2 * s, 6, green, 0.0, 0.40, 0.10, 0.55)
	pb.frustum(base + Vector3.UP * (2.8 * s), Vector3.UP, 1.5 * s, 0.1 * s, 2.6 * s, 6, MeshBuilder.shade(green, 1.18), 0.0, 0.2, 0.45, 1.0)


func _round_tree(pb, base: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var g: float = rng.randf_range(0.85, 1.2)
	var green := Color(0.28 * g, 0.50 * g, 0.20 * g)
	_contact(pb, base, 1.9 * s)
	pb.frustum(base, Vector3.UP, 0.4 * s, 0.32 * s, 1.8 * s, 5, Color(0.34, 0.23, 0.14), 0.0, 0.35, 0.0, 0.08)
	pb.frustum(base + Vector3.UP * (1.4 * s), Vector3.UP, 1.9 * s, 1.2 * s, 1.6 * s, 6, green, 0.0, 0.40, 0.10, 0.6)
	pb.frustum(base + Vector3.UP * (3.0 * s), Vector3.UP, 1.2 * s, 0.1 * s, 1.0 * s, 6, MeshBuilder.shade(green, 1.15), 0.0, 0.1, 0.6, 1.0)


func _bush(pb, base: Vector3, s: float, rng: RandomNumberGenerator, dry: bool) -> void:
	var c: Color = Color(0.45, 0.45, 0.24) if dry else Color(0.20, 0.42, 0.18)
	c = MeshBuilder.shade(c, rng.randf_range(0.85, 1.15))
	pb.frustum(base, Vector3.UP, 1.0 * s, 0.4 * s, 1.0 * s, 6, c, rng.randf() * TAU, 0.45, 0.1, 0.5)
	pb.frustum(base + Vector3(0.9 * s, 0.0, 0.5 * s), Vector3.UP, 0.7 * s, 0.3 * s, 0.8 * s, 5, MeshBuilder.shade(c, 1.1), rng.randf() * TAU, 0.45, 0.1, 0.5)


func _rock(pb, base: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var g: float = rng.randf_range(0.8, 1.15)
	var c := Color(0.46 * g, 0.44 * g, 0.42 * g)
	_contact(pb, base, 1.9 * s)
	pb.frustum(base, Vector3.UP, 1.7 * s, 0.9 * s, 1.5 * s, 5, c, rng.randf() * TAU, 0.45)
	pb.frustum(base + Vector3(1.2 * s, 0.0, 0.5 * s), Vector3.UP, 0.9 * s, 0.4 * s, 0.9 * s, 5, MeshBuilder.shade(c, 0.9), rng.randf() * TAU, 0.45)


func _cactus(pb, base: Vector3, s: float) -> void:
	var c := Color(0.25, 0.46, 0.22)
	pb.frustum(base, Vector3.UP, 0.45 * s, 0.38 * s, 3.2 * s, 5, c, 0.0, 0.3)
	pb.frustum(base + Vector3(0.0, 1.6 * s, 0.0), Vector3.RIGHT, 0.26 * s, 0.24 * s, 1.0 * s, 5, c)
	pb.frustum(base + Vector3(1.0 * s, 1.6 * s, 0.0), Vector3.UP, 0.24 * s, 0.2 * s, 1.1 * s, 5, c)


func _house(pb, base: Vector3, s: float, rng: RandomNumberGenerator, ruined: bool) -> void:
	var w: float = 4.6 * minf(s, 1.3)
	var hgt: float = 2.6
	var wall := Color(0.74, 0.68, 0.57)
	var roof := Color(0.58, 0.22, 0.16)
	if ruined:
		wall = Color(0.32, 0.29, 0.27)
		hgt = 1.7
	_contact(pb, base, w * 0.85)
	pb.box(base + Vector3(0.0, hgt * 0.5, 0.0), Vector3(w, hgt, w), wall, Basis.IDENTITY, 0.35)
	var dark := Color(0.10, 0.10, 0.12)
	pb.box(base + Vector3(w * 0.22, hgt * 0.55, w * 0.5 + 0.02), Vector3(0.9, 0.9, 0.08), dark)
	pb.box(base + Vector3(-w * 0.22, hgt * 0.55, w * 0.5 + 0.02), Vector3(0.9, 0.9, 0.08), dark)
	pb.box(base + Vector3(0.0, hgt * 0.35, -w * 0.5 - 0.02), Vector3(0.9, hgt * 0.7, 0.08), Color(0.28, 0.2, 0.14))
	if ruined:
		pb.box(base + Vector3(w * 0.3, hgt + 0.5, w * 0.2), Vector3(w * 0.4, 1.0, 0.4), MeshBuilder.shade(wall, 0.8))
		pb.box(base + Vector3(-w * 0.2, 0.15, -w * 0.6), Vector3(w * 0.6, 0.3, w * 0.5), Color(0.14, 0.13, 0.12))
		pb.box(base + Vector3(w * 0.7, 0.2, -w * 0.3), Vector3(0.9, 0.4, 0.7), Color(0.30, 0.27, 0.25), Basis(Vector3.UP, 0.6), 0.3)
	else:
		pb.frustum(base + Vector3(0.0, hgt, 0.0), Vector3.UP, w * 0.78, 0.0, 1.7, 4, roof, PI * 0.25)
		pb.box(base + Vector3(w * 0.28, hgt + 1.3, -w * 0.15), Vector3(0.5, 1.2, 0.5), Color(0.40, 0.30, 0.26))
	if rng.randf() < 0.5:
		pb.box(base + Vector3(w * 0.9, 0.5, 0.0), Vector3(1.6, 1.0, 1.6), Color(0.45, 0.35, 0.22), Basis.IDENTITY, 0.3)


func _wreck(pb, base: Vector3, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	_contact(pb, base, 3.0)
	pb.box(base + Vector3(0.0, 0.7, 0.0), Vector3(2.2, 1.0, 4.2), Color(0.13, 0.12, 0.11), basis, 0.4)
	pb.box(base + basis * Vector3(0.2, 1.4, 0.6), Vector3(1.6, 0.8, 1.6), Color(0.22, 0.17, 0.12), basis)
	pb.frustum(base + Vector3(0.0, 1.2, 0.0), Vector3.UP, 0.5, 0.05, 2.2, 5, Color(0.2, 0.2, 0.2), 0.0, 0.0, 0.0, 0.8)


func _tank_wreck(pb, base: Vector3, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	var hull := Color(0.20, 0.19, 0.17)
	_contact(pb, base, 3.6)
	pb.box(base + Vector3(0.0, 0.9, 0.0), Vector3(3.2, 1.1, 5.4), hull, basis, 0.4)
	pb.box(base + Vector3(0.0, 0.4, 0.0), Vector3(3.6, 0.7, 5.8), Color(0.10, 0.10, 0.10), basis, 0.3)
	pb.box(base + basis * Vector3(0.0, 1.8, 0.3), Vector3(2.0, 0.8, 2.2), MeshBuilder.shade(hull, 0.9), basis * Basis(Vector3.RIGHT, 0.12))
	var barrel_dir: Vector3 = basis * Vector3(0.1, 0.35, -1.0)
	pb.frustum(base + basis * Vector3(0.0, 1.9, -0.8), barrel_dir, 0.2, 0.17, 3.2, 5, Color(0.12, 0.12, 0.12))
	pb.box(base + Vector3(0.0, 2.2, 0.0), Vector3(0.9, 0.3, 0.9), Color(0.08, 0.07, 0.06), basis)


func _tent(pb, base: Vector3, rng: RandomNumberGenerator) -> void:
	var yaw: float = rng.randf() * PI * 0.5
	var c := Color(0.40, 0.44, 0.28)
	_contact(pb, base, 3.0)
	pb.frustum(base, Vector3.UP, 2.4, 0.0, 2.0, 4, c, PI * 0.25 + yaw, 0.35)
	pb.box(base + Vector3(0.0, 0.6, 0.0), Vector3(0.9, 1.2, 0.9), Color(0.12, 0.12, 0.10), Basis(Vector3.UP, yaw), 0.0)


func _sandbags(pb, base: Vector3, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	var c := Color(0.58, 0.52, 0.38)
	for i in range(6):
		var o := Vector3(float(i) * 1.05 - 2.6, 0.25, 0.0)
		pb.box(base + basis * o, Vector3(1.0, 0.5, 0.6), MeshBuilder.shade(c, 0.9 + 0.2 * float(i % 2)), basis, 0.4)
	for i in range(4):
		var o2 := Vector3(float(i) * 1.05 - 2.1, 0.75, 0.0)
		pb.box(base + basis * o2, Vector3(1.0, 0.5, 0.6), MeshBuilder.shade(c, 1.0 + 0.1 * float(i % 2)), basis, 0.2)
	pb.box(base + basis * Vector3(0.0, 1.3, 0.2), Vector3(0.5, 0.35, 0.9), Color(0.14, 0.14, 0.15), basis)


func _hedgehog(pb, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var steel := Color(0.22, 0.23, 0.25)
	var yaw: float = rng.randf() * TAU
	for k in range(3):
		var basis: Basis = Basis(Vector3.UP, yaw + float(k) * PI / 3.0) * Basis(Vector3.RIGHT, 0.55)
		pb.box(pos + Vector3(0.0, 0.9, 0.0), Vector3(0.22, 0.22, 2.6), steel, basis)


func _barrels(pb, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var cols: Array = [Color(0.55, 0.16, 0.12), Color(0.22, 0.34, 0.20), Color(0.30, 0.31, 0.33)]
	for k in range(3):
		var o := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		pb.frustum(pos + o, Vector3.UP, 0.45, 0.45, 1.0, 6, cols[k], 0.0, 0.35)


func _post(pb, pos: Vector3) -> void:
	pb.frustum(pos, Vector3.UP, 0.12, 0.1, 1.3, 4, Color(0.80, 0.80, 0.78), 0.0, 0.3)
	pb.box(pos + Vector3(0.0, 1.35, 0.0), Vector3(0.28, 0.25, 0.28), Color(0.85, 0.15, 0.12))


func _reeds(pb, base: Vector3, rng: RandomNumberGenerator) -> void:
	for k in range(5):
		var o := Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8))
		pb.frustum(base + o, Vector3.UP, 0.07, 0.01, rng.randf_range(1.0, 1.9), 4, Color(0.45, 0.55, 0.25), 0.0, 0.3, 0.0, 1.0)


func _tower(pb, base: Vector3, rng: RandomNumberGenerator) -> void:
	var wood := Color(0.34, 0.25, 0.16)
	_contact(pb, base, 3.4)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pb.frustum(base + Vector3(float(sx) * 1.3, 0.0, float(sz) * 1.3), Vector3.UP, 0.2, 0.16, 5.4, 5, wood, 0.0, 0.3)
	pb.box(base + Vector3(0.0, 5.4, 0.0), Vector3(3.4, 0.25, 3.4), wood)
	pb.box(base + Vector3(0.0, 6.4, 0.0), Vector3(2.8, 1.8, 2.8), MeshBuilder.shade(wood, 1.15), Basis.IDENTITY, 0.2)
	pb.frustum(base + Vector3(0.0, 7.3, 0.0), Vector3.UP, 2.5, 0.0, 1.3, 4, Color(0.30, 0.22, 0.16), PI * 0.25)
	pb.box(base + Vector3(0.0, 6.5, 1.42), Vector3(1.6, 0.5, 0.08), Color(0.05, 0.05, 0.06))


func _crater(pb, pos: Vector3, s: float) -> void:
	pb.frustum(pos, Vector3.UP, 3.4 * s, 2.5 * s, 0.14, 8, Color(0.16, 0.14, 0.12))
	pb.frustum(pos + Vector3(0.0, 0.02, 0.0), Vector3.UP, 2.3 * s, 1.6 * s, 0.13, 8, Color(0.08, 0.07, 0.06))
