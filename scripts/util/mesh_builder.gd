extends RefCounted
## Accumulates flat-shaded, vertex-coloured triangles and bakes them into one ArrayMesh.
## Faces are flat shaded but each vertex has its own colour, which is used for baked ambient
## occlusion (darker near the ground) and gradients. Vertex alpha = 1 - wind sway weight.
## Callers describe solids; the builder fixes winding so faces point away from the solid's centre
## (Godot front faces are clockwise).

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()

static var _vmat: StandardMaterial3D = null
static var _mmat: StandardMaterial3D = null


## Matte material for terrain and props (fallback when shaders are off).
static func vertex_material() -> StandardMaterial3D:
	if _vmat == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.9
		_vmat = m
	return _vmat


## Slightly glossy material for vehicles and helicopters.
static func model_material() -> StandardMaterial3D:
	if _mmat == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.5
		m.metallic = 0.25
		_mmat = m
	return _mmat


static func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


func is_empty() -> bool:
	return verts.is_empty()


func _emit3(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	# a, b, c are counter-clockwise seen from outside; Godot wants clockwise, so swap b and c.
	verts.append(a)
	verts.append(c)
	verts.append(b)
	norms.append(n)
	norms.append(n)
	norms.append(n)
	cols.append(ca)
	cols.append(cc)
	cols.append(cb)


## Triangle of a convex solid whose centre is `center`; faces always point outward.
func tri_out3(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, center: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 0.0000001:
		return
	var mid: Vector3 = (a + b + c) / 3.0
	if n.dot(mid - center) < 0.0:
		var t: Vector3 = b
		b = c
		c = t
		var tc: Color = cb
		cb = cc
		cc = tc
		n = -n
	_emit3(a, b, c, n.normalized(), ca, cb, cc)


func tri_out(a: Vector3, b: Vector3, c: Vector3, col: Color, center: Vector3) -> void:
	tri_out3(a, b, c, col, col, col, center)


## Terrain / water triangle: face always points up.
func tri_up3(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 0.0000001:
		return
	if n.y < 0.0:
		var t: Vector3 = b
		b = c
		c = t
		var tc: Color = cb
		cb = cc
		cc = tc
		n = -n
	_emit3(a, b, c, n.normalized(), ca, cb, cc)


func tri_up(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	tri_up3(a, b, c, col, col, col)


## Quad given as a perimeter loop a-b-c-d with a colour per corner.
func quad_out3(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color, center: Vector3) -> void:
	tri_out3(a, b, c, ca, cb, cc, center)
	tri_out3(a, c, d, ca, cc, cd, center)


func quad_out(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, center: Vector3) -> void:
	quad_out3(a, b, c, d, col, col, col, col, center)


## ao darkens the lower half of the box (0 = none, 0.4 = strong ground contact shadow).
func box(center: Vector3, size: Vector3, col: Color, basis: Basis = Basis.IDENTITY, ao: float = 0.0) -> void:
	var h: Vector3 = size * 0.5
	var low: Color = shade(col, 1.0 - ao)
	var p: Array = []
	var c: Array = []
	for i in range(8):
		var sx: float = 1.0 if (i & 1) != 0 else -1.0
		var sy: float = 1.0 if (i & 2) != 0 else -1.0
		var sz: float = 1.0 if (i & 4) != 0 else -1.0
		p.append(center + basis * Vector3(sx * h.x, sy * h.y, sz * h.z))
		c.append(col if sy > 0.0 else low)
	_face(p, c, 0, 2, 6, 4, center)
	_face(p, c, 1, 3, 7, 5, center)
	_face(p, c, 0, 1, 5, 4, center)
	_face(p, c, 2, 3, 7, 6, center)
	_face(p, c, 0, 1, 3, 2, center)
	_face(p, c, 4, 5, 7, 6, center)


func _face(p: Array, c: Array, i0: int, i1: int, i2: int, i3: int, center: Vector3) -> void:
	quad_out3(p[i0], p[i1], p[i2], p[i3], c[i0], c[i1], c[i2], c[i3], center)


## Cone / cylinder / pyramid along `axis`, starting at `base`. r1 = 0 gives a point.
## ao darkens the base ring; sway0 / sway1 are wind weights (0..1) at the base / top ring.
func frustum(base: Vector3, axis: Vector3, r0: float, r1: float, length: float, segs: int, col: Color, phase: float = 0.0, ao: float = 0.0, sway0: float = 0.0, sway1: float = 0.0) -> void:
	var ax: Vector3 = axis.normalized()
	var ref: Vector3 = Vector3.UP
	if absf(ax.dot(Vector3.UP)) > 0.95:
		ref = Vector3.RIGHT
	var u: Vector3 = ax.cross(ref).normalized()
	var v: Vector3 = ax.cross(u).normalized()
	var top: Vector3 = base + ax * length
	var center: Vector3 = base + ax * (length * 0.5)
	var cb: Color = shade(col, 1.0 - ao)
	cb.a = 1.0 - sway0
	var ct: Color = col
	ct.a = 1.0 - sway1
	for i in range(segs):
		var a0: float = phase + TAU * float(i) / float(segs)
		var a1: float = phase + TAU * float(i + 1) / float(segs)
		var d0: Vector3 = u * cos(a0) + v * sin(a0)
		var d1: Vector3 = u * cos(a1) + v * sin(a1)
		var b0: Vector3 = base + d0 * r0
		var b1: Vector3 = base + d1 * r0
		var t0: Vector3 = top + d0 * r1
		var t1: Vector3 = top + d1 * r1
		quad_out3(b0, b1, t1, t0, cb, cb, ct, ct, center)
		tri_out3(base, b0, b1, cb, cb, cb, center)
		tri_out3(top, t0, t1, ct, ct, ct, center)


func build(mat: Material) -> ArrayMesh:
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mat != null:
		mesh.surface_set_material(0, mat)
	return mesh
