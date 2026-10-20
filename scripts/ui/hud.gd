extends Control
## Tactical HUD: hull integrity, score, weapon tier and power timer, supply-drop countdowns,
## time-of-day strip, pickup toasts, floating kill scores, damage vignette and low-armour warning.
## Drawn directly (no node tree) for speed and a crisp look. Visual only: reads game state, never changes it.

const Cfg = preload("res://scripts/core/config.gd")
const SafeArea = preload("res://scripts/util/safe_area.gd")
const UiStyle = preload("res://scripts/util/ui_style.gd")

var player = null
var pickups = null
var day_night = null
var score: int = 0
var distance: float = 0.0
var hit_flash: float = 0.0

var _toasts: Array = []
var _popups: Array = []
var _t: float = 0.0
var _hp_ghost: float = 1.0
var _score_vis: float = 0.0
var _last_tier: int = 0
var _tier_flash: float = 0.0
var _hp_pulse: float = 0.0
var _last_hp: float = 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func toast(text: String, color: Color = UiStyle.GOLD) -> void:
	_toasts.append({"text": text, "color": color, "t": 2.6})
	while _toasts.size() > 4:
		_toasts.pop_front()


## Floating "+points" label at a screen position (used for kills).
func add_popup(points: int, pos: Vector2) -> void:
	_popups.append({"text": "+%d" % points, "pos": pos, "t": 1.0})
	while _popups.size() > 8:
		_popups.pop_front()


func clear_toasts() -> void:
	_toasts.clear()
	_popups.clear()
	hit_flash = 0.0
	_hp_ghost = 1.0
	_score_vis = 0.0
	_tier_flash = 0.0
	_last_tier = 0
	_last_hp = 1.0


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	hit_flash = maxf(0.0, hit_flash - delta * 2.2)
	_tier_flash = maxf(0.0, _tier_flash - delta * 1.6)
	_hp_pulse = maxf(0.0, _hp_pulse - delta * 2.0)
	if player != null:
		var frac: float = clampf(player.hp / player.max_hp, 0.0, 1.0)
		if frac < _last_hp - 0.001:
			_hp_pulse = 1.0
		_last_hp = frac
		_hp_ghost = maxf(frac, _hp_ghost - delta * 0.30)
		if player.tier > _last_tier:
			_tier_flash = 1.0
		_last_tier = player.tier
	_score_vis = lerpf(_score_vis, float(score), 1.0 - exp(-9.0 * delta))
	if absf(_score_vis - float(score)) < 1.0:
		_score_vis = float(score)
	var i: int = _toasts.size() - 1
	while i >= 0:
		_toasts[i]["t"] = float(_toasts[i]["t"]) - delta
		if float(_toasts[i]["t"]) <= 0.0:
			_toasts.remove_at(i)
		i -= 1
	var j: int = _popups.size() - 1
	while j >= 0:
		_popups[j]["t"] = float(_popups[j]["t"]) - delta * 1.1
		if float(_popups[j]["t"]) <= 0.0:
			_popups.remove_at(j)
		j -= 1
	queue_redraw()


func _fmt_time(s: float) -> String:
	var total: int = int(ceilf(maxf(s, 0.0)))
	return "%d:%02d" % [int(floorf(float(total) / 60.0)), total % 60]


func _draw() -> void:
	if player == null:
		return
	var ins: Vector4 = SafeArea.insets(size)
	var x0: float = ins.x + 22.0
	var y0: float = ins.y + 14.0
	_draw_edges()
	_draw_armor(x0, y0)
	_draw_score(x0, y0 + 82.0)
	_draw_weapon(size.x * 0.5, y0)
	_draw_timeline(size.x * 0.5, y0 + 78.0)
	_draw_supply(size.x - ins.z - 104.0, y0)
	_draw_toasts()
	_draw_popups()
	_draw_warning()


# ------------------------------------------------------------------ modules

func _draw_armor(x: float, y: float) -> void:
	var frac: float = clampf(player.hp / player.max_hp, 0.0, 1.0)
	var accent: Color = UiStyle.GOLD
	if _hp_pulse > 0.05:
		accent = UiStyle.RED
	UiStyle.panel(self, Rect2(x, y, 286.0, 70.0), accent, 0.64, 10.0, _hp_pulse * 0.8)
	UiStyle.text(self, Vector2(x + 15.0, y + 21.0), "HULL INTEGRITY", 13, UiStyle.GOLD, UiStyle.font_head())
	UiStyle.text(self, Vector2(x + 15.0, y + 24.0), "%d%%" % int(ceilf(frac * 100.0)), 22, UiStyle.WHITE, UiStyle.font_num(), HORIZONTAL_ALIGNMENT_RIGHT, 256.0)
	var col: Color = UiStyle.GREEN
	if frac <= 0.25:
		col = UiStyle.RED
		if int(_t * 5.0) % 2 == 0:
			col = UiStyle.with_alpha(UiStyle.RED, 0.55)
	elif frac <= 0.5:
		col = UiStyle.AMBER
	UiStyle.seg_bar(self, Rect2(x + 15.0, y + 31.0, 256.0, 19.0), frac, col, 20, _hp_ghost, 4.0, 3.0)
	var state: String = "SYSTEMS NOMINAL"
	if frac <= 0.25:
		state = "CRITICAL DAMAGE"
	elif frac <= 0.5:
		state = "HULL DAMAGED"
	UiStyle.text(self, Vector2(x + 15.0, y + 64.0), state, 12, UiStyle.with_alpha(col, 0.85), UiStyle.font_ui())


func _draw_score(x: float, y: float) -> void:
	UiStyle.text(self, Vector2(x + 4.0, y), "SCORE", 12, UiStyle.GOLD, UiStyle.font_head())
	var s: String = "%06d" % int(round(_score_vis))
	var nz: int = 0
	while nz < s.length() - 1 and s[nz] == "0":
		nz += 1
	var f: Font = UiStyle.font_num()
	var zeros: String = s.substr(0, nz)
	var rest: String = s.substr(nz)
	UiStyle.text(self, Vector2(x + 4.0, y + 34.0), zeros, 36, Color(1, 1, 1, 0.22), f)
	var zw: float = UiStyle.text_width(zeros, 36, f)
	UiStyle.text(self, Vector2(x + 4.0 + zw, y + 34.0), rest, 36, UiStyle.WHITE, f)
	draw_line(Vector2(x + 4.0, y + 43.0), Vector2(x + 124.0, y + 43.0), UiStyle.with_alpha(UiStyle.GOLD, 0.55), 2.0)
	UiStyle.text(self, Vector2(x + 4.0, y + 62.0), "DIST  %.2f KM" % (distance / 1000.0), 14, Color(1, 1, 1, 0.8), UiStyle.font_ui())


func _tier_color(tier: int) -> Color:
	if tier <= 1:
		return UiStyle.GOLD
	if tier <= 3:
		return UiStyle.CYAN
	return UiStyle.GREEN


func _draw_weapon(cx: float, y: float) -> void:
	var w: float = 360.0
	var rect := Rect2(cx - w * 0.5, y, w, 70.0)
	var t: Dictionary = Cfg.TIERS[player.tier]
	var col: Color = _tier_color(player.tier)
	UiStyle.panel(self, rect, col, 0.64, 10.0, _tier_flash)
	UiStyle.text(self, Vector2(rect.position.x + 15.0, y + 20.0), "PRIMARY WEAPON", 12, UiStyle.GOLD, UiStyle.font_head())
	# weapon glyph
	var gc := Vector2(rect.position.x + 38.0, y + 40.0)
	var kind: int = int(t["kind"])
	UiStyle.glow_circle(self, gc, 16.0, UiStyle.with_alpha(col, 0.45), 3)
	if kind == Cfg.K_BULLET:
		for k in range(3):
			draw_rect(Rect2(gc + Vector2(-10.0 + float(k) * 7.5, -11.0), Vector2(4.0, 22.0)), col)
	elif kind == Cfg.K_LASER:
		draw_line(gc + Vector2(0.0, -13.0), gc + Vector2(0.0, 13.0), col, 3.5, true)
		draw_line(gc + Vector2(-8.0, -8.0), gc + Vector2(-8.0, 8.0), UiStyle.with_alpha(col, 0.6), 2.0, true)
		draw_line(gc + Vector2(8.0, -8.0), gc + Vector2(8.0, 8.0), UiStyle.with_alpha(col, 0.6), 2.0, true)
	else:
		draw_circle(gc, 7.5, col)
		draw_arc(gc, 12.5, 0.0, TAU, 24, UiStyle.with_alpha(col, 0.8), 2.0, true)
		draw_arc(gc, 12.5, _t * 3.0, _t * 3.0 + 1.5, 10, Color(1, 1, 1, 0.9), 2.5, true)
	var name_col: Color = col.lerp(Color(1, 1, 1, 1), _tier_flash * 0.8)
	UiStyle.text(self, Vector2(rect.position.x + 70.0, y + 46.0), "%s  x%d" % [String(t["name"]), int(t["barrels"])], 23, name_col, UiStyle.font_head())
	for k in range(Cfg.TIERS.size()):
		var px: float = rect.position.x + w - 16.0 - float(Cfg.TIERS.size() - k) * 12.0
		var pr := PackedVector2Array([Vector2(px + 2.5, y + 10.0), Vector2(px + 9.0, y + 10.0), Vector2(px + 6.5, y + 18.0), Vector2(px, y + 18.0)])
		if k <= player.tier:
			draw_colored_polygon(pr, _tier_color(k))
		else:
			draw_colored_polygon(pr, Color(1, 1, 1, 0.14))
	var bar := Rect2(rect.position.x + 15.0, y + 58.0, w - 30.0, 4.0)
	draw_rect(bar, Color(1, 1, 1, 0.10))
	if player.tier > 0:
		var f: float = clampf(player.power_t / Cfg.WEAPON_POWER_TIME, 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), col)
		var sx: float = bar.position.x + fmod(_t * 0.9, 1.0) * bar.size.x * f
		draw_rect(Rect2(sx, bar.position.y, minf(22.0, bar.position.x + bar.size.x * f - sx), bar.size.y), Color(1, 1, 1, 0.45))


func _draw_timeline(cx: float, y: float) -> void:
	if day_night == null:
		return
	var w: float = 250.0
	var x: float = cx - w * 0.5
	var pal: Array = [
		Color(1.0, 0.78, 0.45), Color(0.45, 0.72, 1.0), Color(1.0, 0.55, 0.28), Color(0.55, 0.30, 0.55),
		Color(0.10, 0.16, 0.38), Color(0.10, 0.16, 0.38), Color(0.90, 0.55, 0.55), Color(1.0, 0.78, 0.45)]
	var stops: Array = [0.0, 0.18, 0.40, 0.52, 0.62, 0.84, 0.93, 1.0]
	var n: int = 50
	var cw: float = w / float(n)
	for k in range(n):
		var tt: float = (float(k) + 0.5) / float(n)
		var i: int = 0
		while i < stops.size() - 2 and tt >= float(stops[i + 1]):
			i += 1
		var f: float = clampf((tt - float(stops[i])) / (float(stops[i + 1]) - float(stops[i])), 0.0, 1.0)
		var c: Color = (pal[i] as Color).lerp(pal[i + 1], f)
		draw_rect(Rect2(x + float(k) * cw, y, cw + 0.5, 5.0), UiStyle.with_alpha(c, 0.85))
	var mx: float = x + day_night.t * w
	draw_colored_polygon(PackedVector2Array([Vector2(mx, y + 7.0), Vector2(mx - 5.0, y + 14.0), Vector2(mx + 5.0, y + 14.0)]), UiStyle.WHITE)
	draw_line(Vector2(mx, y - 2.0), Vector2(mx, y + 6.0), UiStyle.WHITE, 2.0)
	var hours: float = fposmod(day_night.t * 24.0 + 6.0, 24.0)
	var clock: String = "%02d:%02d" % [int(floorf(hours)), int(floorf((hours - floorf(hours)) * 60.0))]
	UiStyle.text(self, Vector2(x, y + 28.0), "%s  %s" % [day_night.phase_name(), clock], 12, Color(1, 1, 1, 0.85), UiStyle.font_ui(), HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_supply(right: float, y: float) -> void:
	var w: float = 252.0
	var rect := Rect2(right - w, y, w, 70.0)
	UiStyle.panel(self, rect, UiStyle.GOLD, 0.64, 10.0)
	_supply_row(rect, y + 9.0, Cfg.P_MISSILE, "MISSILE DROP", UiStyle.CYAN, Cfg.MISSILE_SPAWN_INTERVAL)
	_supply_row(rect, y + 39.0, Cfg.P_NUKE, "NUKE DROP", UiStyle.RED, Cfg.NUKE_SPAWN_INTERVAL)


func _supply_row(rect: Rect2, ry: float, kind: int, label: String, col: Color, interval: float) -> void:
	var active: bool = pickups.has_active(kind)
	var tl: float = pickups.time_left(kind)
	var blink: float = 0.5 + 0.5 * sin(_t * 7.0)
	var c: Color = col
	var txt: String = _fmt_time(tl)
	if active:
		txt = "INBOUND"
		c = col.lerp(UiStyle.WHITE, blink * 0.6)
	var ix: float = rect.position.x + 22.0
	var iy: float = ry + 10.0
	if kind == Cfg.P_MISSILE:
		draw_colored_polygon(PackedVector2Array([Vector2(ix - 2.5, iy - 7.0), Vector2(ix + 2.5, iy - 7.0), Vector2(ix + 2.5, iy + 5.0), Vector2(ix - 2.5, iy + 5.0)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(ix - 2.5, iy - 7.0), Vector2(ix, iy - 12.0), Vector2(ix + 2.5, iy - 7.0)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(ix - 2.5, iy + 1.0), Vector2(ix - 6.5, iy + 6.5), Vector2(ix - 2.5, iy + 5.0)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(ix + 2.5, iy + 1.0), Vector2(ix + 2.5, iy + 5.0), Vector2(ix + 6.5, iy + 6.5)]), c)
	else:
		draw_circle(Vector2(ix, iy), 3.2, c)
		for k in range(3):
			var a0: float = deg_to_rad(-90.0 + 120.0 * float(k) - 30.0)
			draw_arc(Vector2(ix, iy), 7.5, a0, a0 + deg_to_rad(60.0), 8, c, 4.0, true)
	UiStyle.text(self, Vector2(rect.position.x + 38.0, ry + 14.0), label, 12, UiStyle.GOLD, UiStyle.font_head())
	UiStyle.text(self, Vector2(rect.position.x, ry + 16.0), txt, 18, c, UiStyle.font_num(), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 15.0)
	var bar := Rect2(rect.position.x + 15.0, ry + 21.0, rect.size.x - 30.0, 3.0)
	draw_rect(bar, Color(1, 1, 1, 0.10))
	var f: float = 1.0 if active else clampf(1.0 - tl / interval, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), c)


func _draw_toasts() -> void:
	var cx: float = size.x * 0.5
	var y: float = size.y * 0.27
	for k in range(_toasts.size()):
		var item: Dictionary = _toasts[k]
		var age: float = 2.6 - float(item["t"])
		var appear: float = UiStyle.ease_out(age / 0.25)
		var vanish: float = clampf(float(item["t"]) / 0.5, 0.0, 1.0)
		var a: float = appear * vanish
		var c: Color = item["color"]
		var txt: String = String(item["text"])
		var tw: float = UiStyle.text_width(txt, 21, UiStyle.font_head())
		var rect := Rect2(cx - (tw + 56.0) * 0.5, y + float(k) * 42.0 + (1.0 - appear) * -14.0, tw + 56.0, 35.0)
		UiStyle.panel(self, rect, UiStyle.with_alpha(c, a), 0.78 * a, 8.0)
		var dm := Vector2(rect.position.x + 19.0, rect.position.y + 17.5)
		draw_colored_polygon(PackedVector2Array([dm + Vector2(0, -6), dm + Vector2(6, 0), dm + Vector2(0, 6), dm + Vector2(-6, 0)]), UiStyle.with_alpha(c, a))
		UiStyle.text(self, Vector2(rect.position.x + 34.0, rect.position.y + 25.0), txt, 21, Color(1, 1, 1, a), UiStyle.font_head())


func _draw_popups() -> void:
	for p in _popups:
		var t: float = float(p["t"])
		var pos: Vector2 = p["pos"]
		var rise: float = (1.0 - t) * 46.0
		var a: float = clampf(t * 1.6, 0.0, 1.0)
		UiStyle.text(self, Vector2(pos.x - 30.0, pos.y - rise), String(p["text"]), 20, UiStyle.with_alpha(UiStyle.GOLD, a), UiStyle.font_head(), HORIZONTAL_ALIGNMENT_CENTER, 60.0)


func _edge_glow(col: Color, a: float, th: float) -> void:
	var c1 := Color(col.r, col.g, col.b, a)
	var c0 := Color(col.r, col.g, col.b, 0.0)
	var w: float = size.x
	var h: float = size.y
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(th, 0), Vector2(th, h), Vector2(0, h)]), PackedColorArray([c1, c0, c0, c1]))
	draw_polygon(PackedVector2Array([Vector2(w - th, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - th, h)]), PackedColorArray([c0, c1, c1, c0]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, th), Vector2(0, th)]), PackedColorArray([c1, c1, c0, c0]))
	draw_polygon(PackedVector2Array([Vector2(0, h - th), Vector2(w, h - th), Vector2(w, h), Vector2(0, h)]), PackedColorArray([c0, c0, c1, c1]))


func _draw_edges() -> void:
	if hit_flash > 0.02:
		_edge_glow(UiStyle.RED, hit_flash * 0.55, 150.0)
	if player.alive and player.hp / player.max_hp <= 0.3:
		var pulse: float = 0.5 + 0.5 * sin(_t * 8.0)
		_edge_glow(UiStyle.RED, 0.12 + 0.22 * pulse, 110.0)


func _draw_warning() -> void:
	if not player.alive or player.hp / player.max_hp > 0.3:
		return
	var pulse: float = 0.5 + 0.5 * sin(_t * 8.0)
	var cx: float = size.x * 0.5
	var y: float = size.y * 0.22
	var col: Color = UiStyle.with_alpha(UiStyle.RED, 0.45 + pulse * 0.55)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 128.0, y - 6.0), Vector2(cx - 113.0, y - 31.0), Vector2(cx - 98.0, y - 6.0)]), col)
	UiStyle.text(self, Vector2(cx - 117.0, y - 10.0), "!", 18, Color(0, 0, 0, 0.9), UiStyle.font_head())
	UiStyle.text(self, Vector2(cx - 86.0, y - 6.0), "ARMOR CRITICAL", 26, col, UiStyle.font_head())
