extends RefCounted
## Shared look for the HUD, touch controls and menus: palette, system fonts and drawing helpers.
## Palette follows the black / white / gold brand with cyan and red as tactical accents.

const GOLD := Color(0.96, 0.77, 0.22)
const GOLD_DIM := Color(0.62, 0.50, 0.16)
const INK := Color(0.04, 0.05, 0.06)
const STEEL := Color(0.12, 0.14, 0.16)
const WHITE := Color(1.0, 1.0, 1.0)
const CYAN := Color(0.35, 0.88, 1.0)
const RED := Color(1.0, 0.30, 0.22)
const GREEN := Color(0.45, 0.95, 0.52)
const AMBER := Color(1.0, 0.68, 0.18)

static var _f_ui: Font = null
static var _f_num: Font = null
static var _f_head: Font = null


static func _sys(names: Array, weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	return f


## Condensed UI font (falls back to the default font when none is installed).
static func font_ui() -> Font:
	if _f_ui == null:
		_f_ui = _sys(["Roboto Condensed", "sans-serif-condensed", "Bahnschrift", "Arial Narrow", "Roboto", "sans-serif"], 600)
	return _f_ui


## Heavier condensed font for titles.
static func font_head() -> Font:
	if _f_head == null:
		_f_head = _sys(["Roboto Condensed", "sans-serif-condensed", "Bahnschrift", "Arial Narrow", "Roboto", "sans-serif"], 800)
	return _f_head


## Monospaced font so changing numbers do not jitter.
static func font_num() -> Font:
	if _f_num == null:
		_f_num = _sys(["Roboto Mono", "monospace", "Consolas", "Courier New", "Roboto", "sans-serif"], 700)
	return _f_num


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func text_width(s: String, size: int, font: Font = null) -> float:
	var f: Font = font if font != null else font_ui()
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Text with a soft drop shadow for readability over the 3D scene.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, font: Font = null, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f: Font = font if font != null else font_ui()
	ci.draw_string(f, pos + Vector2(1.5, 2.0), s, align, width, size, Color(0, 0, 0, 0.6 * col.a))
	ci.draw_string(f, pos, s, align, width, size, col)


## Rectangle with the top-left and bottom-right corners cut diagonally.
static func chamfer_pts(r: Rect2, c: float) -> PackedVector2Array:
	var x: float = r.position.x
	var y: float = r.position.y
	var w: float = r.size.x
	var h: float = r.size.y
	return PackedVector2Array([
		Vector2(x + c, y), Vector2(x + w, y), Vector2(x + w, y + h - c),
		Vector2(x + w - c, y + h), Vector2(x, y + h), Vector2(x, y + c)])


## Glass-like tactical panel: vertical gradient, thin border, bright accent corners.
static func panel(ci: CanvasItem, r: Rect2, accent: Color = GOLD, alpha: float = 0.62, c: float = 12.0, glow: float = 0.0) -> void:
	var pts: PackedVector2Array = chamfer_pts(r, c)
	var top := Color(0.10, 0.11, 0.13, alpha)
	var bot := Color(0.03, 0.035, 0.045, alpha * 0.92)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top if p.y < r.position.y + r.size.y * 0.5 else bot)
	ci.draw_polygon(pts, cols)
	if glow > 0.01:
		var gc := Color(accent.r, accent.g, accent.b, glow * 0.35)
		var gcols := PackedColorArray()
		for p in pts:
			gcols.append(gc)
		ci.draw_polygon(pts, gcols)
	var loop := PackedVector2Array(pts)
	loop.append(pts[0])
	ci.draw_polyline(loop, Color(accent.r, accent.g, accent.b, 0.5), 1.5, true)
	var x: float = r.position.x
	var y: float = r.position.y
	ci.draw_line(Vector2(x + c, y), Vector2(x + c + 54.0, y), accent, 3.0)
	ci.draw_line(Vector2(x + r.size.x - c, y + r.size.y), Vector2(x + r.size.x - c - 30.0, y + r.size.y), Color(accent.r, accent.g, accent.b, 0.8), 3.0)
	ci.draw_line(Vector2(x, y + c + 4.0), Vector2(x, y + r.size.y - 6.0), Color(accent.r, accent.g, accent.b, 0.35), 2.0)


## Row of skewed segments. `ghost` (optional, >= frac) draws a lighter trailing segment run.
static func seg_bar(ci: CanvasItem, r: Rect2, frac: float, col: Color, segs: int, ghost: float = -1.0, skew: float = 5.0, gap: float = 3.0) -> void:
	var sw: float = (r.size.x - gap * float(segs - 1)) / float(segs)
	var filled: float = clampf(frac, 0.0, 1.0) * float(segs)
	var ghost_n: float = clampf(ghost, 0.0, 1.0) * float(segs)
	for k in range(segs):
		var x: float = r.position.x + float(k) * (sw + gap)
		var pts := PackedVector2Array([
			Vector2(x + skew, r.position.y), Vector2(x + sw + skew, r.position.y),
			Vector2(x + sw, r.position.y + r.size.y), Vector2(x, r.position.y + r.size.y)])
		var c: Color = Color(1, 1, 1, 0.09)
		if float(k) < filled:
			c = col
			if float(k) + 1.0 > filled:
				c = Color(col.r, col.g, col.b, 0.35 + 0.65 * (filled - float(k)))
		elif float(k) < ghost_n:
			c = Color(1.0, 1.0, 1.0, 0.55)
		ci.draw_colored_polygon(pts, c)


## Soft glow made of stacked translucent circles.
static func glow_circle(ci: CanvasItem, center: Vector2, radius: float, col: Color, layers: int = 4) -> void:
	for i in range(layers):
		var k: float = float(i) / float(layers)
		ci.draw_circle(center, radius * (1.0 + (1.0 - k) * 0.5), Color(col.r, col.g, col.b, col.a * 0.12 * (k + 0.3)))


static func ease_out(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x)
