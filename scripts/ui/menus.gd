extends Control
## All menu screens, built in code with a shared black / white / gold tactical theme.
## Screens: loading, title, hangar (helicopter skins), pause, game over, settings.
## Pages fade in and their items slide in one after another. Visual layer only.

signal start_requested
signal hangar_opened
signal hangar_closed
signal resume_requested
signal restart_requested
signal menu_requested
signal skin_preview(index: int)
signal settings_changed
signal quit_requested

const UiStyle = preload("res://scripts/util/ui_style.gd")

const GOLD := UiStyle.GOLD
const GOLD_DIM := UiStyle.GOLD_DIM
const INK := UiStyle.INK
const WHITE := UiStyle.WHITE
const RED := UiStyle.RED
const GREEN := UiStyle.GREEN

const QUALITY_NAMES: Array = ["LOW", "MEDIUM", "HIGH"]

var current: String = ""

var _pages: Dictionary = {}
var _intro: Dictionary = {}
var _settings_from: String = "title"
var _hangar_sel: int = 0
var _skin_buttons: Array = []
var _best_tween: Tween = null
var _load_frac: float = 0.0
var _loading_ctl: Control = null
var _prog_ctl: Control = null
var _prog_frac: float = 0.0
var _prog_text: String = ""

var _lbl_title_stats: Label = null
var _lbl_hangar_pts: Label = null
var _lbl_skin_state: Label = null
var _lbl_skin_name: Label = null
var _lbl_skin_sub: Label = null
var _btn_equip: Button = null
var _lbl_over_title: Label = null
var _lbl_over_score: Label = null
var _lbl_over_best: Label = null
var _lbl_over_dist: Label = null
var _lbl_over_kills: Label = null
var _lbl_over_total: Label = null
var _lbl_over_unlock: Label = null
var _btn_haptics: Button = null
var _btn_shadows: Button = null
var _btn_quality: Button = null
var _lbl_volume: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_build_loading()
	_build_title()
	_build_hangar()
	_build_pause()
	_build_over()
	_build_settings()
	hide_all()


# ------------------------------------------------------------------ theme and helpers

func _box(bg: Color, border: Color, left_w: int = 2, other_w: int = 1, margin: float = 12.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = left_w
	sb.border_width_top = other_w
	sb.border_width_right = other_w
	sb.border_width_bottom = other_w
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(margin)
	sb.content_margin_left = margin + 6.0
	return sb


func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.05, 0.06, 0.93)
	sb.border_color = GOLD_DIM
	sb.set_border_width_all(2)
	sb.border_width_top = 4
	sb.border_color = GOLD
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(24.0)
	sb.shadow_size = 18
	sb.shadow_color = Color(0, 0, 0, 0.6)
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = UiStyle.font_ui()
	th.default_font_size = 24
	th.set_stylebox("normal", "Button", _box(Color(INK.r, INK.g, INK.b, 0.86), GOLD, 5, 1))
	th.set_stylebox("hover", "Button", _box(Color(0.20, 0.15, 0.05, 0.96), Color(1.0, 0.86, 0.4), 6, 2))
	th.set_stylebox("pressed", "Button", _box(GOLD, GOLD, 6, 2))
	th.set_stylebox("disabled", "Button", _box(Color(0.08, 0.08, 0.09, 0.8), Color(0.3, 0.3, 0.3), 3, 1))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", WHITE)
	th.set_color("font_hover_color", "Button", Color(1.0, 0.88, 0.45))
	th.set_color("font_pressed_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	th.set_font("font", "Button", UiStyle.font_head())
	th.set_font_size("font_size", "Button", 26)
	th.set_stylebox("panel", "PanelContainer", _panel_box())
	return th


func _label(text: String, font_size: int, color: Color = WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, head: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	if head:
		l.add_theme_font_override("font", UiStyle.font_head())
	l.horizontal_alignment = align
	return l


func _button(text: String, callback: Callable, min_w: float = 320.0, min_h: float = 62.0, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.add_theme_stylebox_override("normal", _box(GOLD, Color(1.0, 0.9, 0.5), 8, 1))
		b.add_theme_stylebox_override("hover", _box(Color(1.0, 0.86, 0.38), Color(1, 1, 1), 8, 2))
		b.add_theme_stylebox_override("pressed", _box(Color(0.75, 0.6, 0.15), GOLD, 8, 2))
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
	b.pressed.connect(_click.bind(callback))
	return b


func _click(callback: Callable) -> void:
	Feedback.play("click", -4.0)
	callback.call()


func _page(key: String, dim: bool) -> Control:
	var p := Control.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim:
		var d := ColorRect.new()
		d.color = Color(0.0, 0.0, 0.0, 0.66)
		d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		d.mouse_filter = Control.MOUSE_FILTER_STOP
		p.add_child(d)
	add_child(p)
	_pages[key] = p
	_intro[key] = []
	return p


## Wraps an item in a fixed-size holder so it can slide in even inside a container.
func _slot(page_key: String, item: Control, w: float, h: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, h)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.position = Vector2.ZERO
	item.size = Vector2(w, h)
	holder.add_child(item)
	(_intro[page_key] as Array).append(item)
	return holder


func _fade_item(page_key: String, item: Control) -> void:
	(_intro[page_key] as Array).append(item)


func _centered_panel(page: Control) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0.0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _rule(w: float, col: Color = GOLD) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(col.r, col.g, col.b, 0.8)
	r.custom_minimum_size = Vector2(w, 2.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _fmt(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var cnt: int = 0
	for k in range(s.length() - 1, -1, -1):
		out = s[k] + out
		cnt += 1
		if cnt % 3 == 0 and k > 0:
			out = "," + out
	return out


## Dark side gradient with hazard stripes and corner brackets drawn behind menu content.
func _backdrop(page: Control, side_w: float) -> void:
	var bg := Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(_draw_backdrop.bind(bg, side_w))
	page.add_child(bg)
	page.move_child(bg, 0)


func _draw_backdrop(bg: Control, side_w: float) -> void:
	var w: float = bg.size.x
	var h: float = bg.size.y
	var sw: float = w * side_w
	bg.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(sw, 0), Vector2(sw, h), Vector2(0, h)]),
		PackedColorArray([Color(0, 0, 0, 0.86), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.86)]))
	bg.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 90), Vector2(0, 90)]),
		PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	bg.draw_polygon(PackedVector2Array([Vector2(0, h - 90), Vector2(w, h - 90), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.65), Color(0, 0, 0, 0.65)]))
	var x: float = 0.0
	while x < w:
		bg.draw_colored_polygon(PackedVector2Array([Vector2(x, h), Vector2(x + 12.0, h), Vector2(x + 24.0, h - 12.0), Vector2(x + 12.0, h - 12.0)]), Color(GOLD.r, GOLD.g, GOLD.b, 0.5))
		x += 48.0
	bg.draw_line(Vector2(48.0, 30.0), Vector2(48.0, h - 40.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.35), 2.0)
	bg.draw_line(Vector2(30.0, 30.0), Vector2(78.0, 30.0), GOLD, 3.0)
	bg.draw_line(Vector2(w - 30.0, 30.0), Vector2(w - 78.0, 30.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.7), 3.0)
	bg.draw_line(Vector2(w - 30.0, 30.0), Vector2(w - 30.0, 78.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.7), 3.0)


# ------------------------------------------------------------------ button callbacks

func _do_start() -> void:
	start_requested.emit()


func _do_quit() -> void:
	quit_requested.emit()


func _do_resume() -> void:
	resume_requested.emit()


func _do_restart() -> void:
	restart_requested.emit()


func _do_menu() -> void:
	menu_requested.emit()


func _open_settings_title() -> void:
	show_settings("title")


func _open_settings_pause() -> void:
	show_settings("pause")


func _vol_down() -> void:
	_change_volume(-0.1)


func _vol_up() -> void:
	_change_volume(0.1)


# ------------------------------------------------------------------ loading

func _build_loading() -> void:
	var page: Control = _page("loading", false)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.04, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	page.add_child(bg)
	_loading_ctl = Control.new()
	_loading_ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_ctl.draw.connect(_draw_loading)
	page.add_child(_loading_ctl)


func _draw_loading() -> void:
	var c: Control = _loading_ctl
	var cx: float = c.size.x * 0.5
	var cy: float = c.size.y * 0.5
	_draw_lambda(c, Vector2(cx - 150.0, cy - 80.0), 0.9)
	var f: Font = UiStyle.font_head()
	c.draw_string(f, Vector2(cx - 60.0, cy - 40.0), "LAMBDA", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 64, WHITE)
	c.draw_string(f, Vector2(cx - 60.0, cy + 18.0), "WARS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 64, GOLD)
	var bw: float = 420.0
	var bx: float = cx - bw * 0.5
	var by: float = cy + 70.0
	c.draw_rect(Rect2(bx, by, bw, 6.0), Color(1, 1, 1, 0.12))
	c.draw_rect(Rect2(bx, by, bw * clampf(_load_frac, 0.0, 1.0), 6.0), GOLD)
	c.draw_string(UiStyle.font_ui(), Vector2(bx, by + 34.0), "PREPARING THEATER OF OPERATIONS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(1, 1, 1, 0.65))
	c.draw_string(UiStyle.font_num(), Vector2(bx, by + 34.0), "%d%%" % int(_load_frac * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, bw, 16, GOLD)


func _draw_lambda(c: Control, origin: Vector2, s: float) -> void:
	var a := PackedVector2Array([origin + Vector2(4.0, 6.0) * s, origin + Vector2(30.0, 6.0) * s, origin + Vector2(84.0, 112.0) * s])
	var b := PackedVector2Array([origin + Vector2(56.0, 56.0) * s, origin + Vector2(2.0, 112.0) * s])
	c.draw_polyline(a, GOLD, 15.0 * s, true)
	c.draw_polyline(b, GOLD, 15.0 * s, true)


func show_loading() -> void:
	_load_frac = 0.0
	_show("loading")


func set_loading_progress(f: float) -> void:
	_load_frac = f
	if _loading_ctl != null:
		_loading_ctl.queue_redraw()


# ------------------------------------------------------------------ title

func _build_title() -> void:
	var page: Control = _page("title", false)
	_backdrop(page, 0.62)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 56)
	page.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var logo := Control.new()
	logo.custom_minimum_size = Vector2(560.0, 132.0)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.draw.connect(_draw_logo.bind(logo))
	box.add_child(logo)
	_fade_item("title", logo)
	var sub: Label = _label("HELICOPTER AIR WARFARE", 22, GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	box.add_child(sub)
	_fade_item("title", sub)
	box.add_child(_spacer(8.0))
	box.add_child(_slot("title", _button("DEPLOY", _do_start, 360.0, 72.0, true), 360.0, 72.0))
	box.add_child(_slot("title", _button("HANGAR", _open_hangar, 360.0, 62.0), 360.0, 62.0))
	box.add_child(_slot("title", _button("SETTINGS", _open_settings_title, 360.0, 62.0), 360.0, 62.0))
	if OS.get_name() != "Android" and OS.get_name() != "iOS" and OS.get_name() != "Web":
		box.add_child(_slot("title", _button("QUIT", _do_quit, 360.0, 62.0), 360.0, 62.0))
	box.add_child(_spacer(6.0))
	_lbl_title_stats = _label("", 20, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, true)
	box.add_child(_lbl_title_stats)
	_fade_item("title", _lbl_title_stats)
	var brand: Label = _label("TermorganWorks", 18, GOLD_DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	box.add_child(brand)
	_fade_item("title", brand)


func _draw_logo(logo: Control) -> void:
	_draw_lambda(logo, Vector2.ZERO, 1.0)
	var f: Font = UiStyle.font_head()
	logo.draw_string(f, Vector2(124.0, 64.0), "LAMBDA", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 72, WHITE)
	logo.draw_string(f, Vector2(124.0, 126.0), "WARS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 72, GOLD)
	logo.draw_line(Vector2(124.0, 76.0), Vector2(430.0, 76.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.0), 2.0)


func show_title() -> void:
	_lbl_title_stats.text = "BEST  %s     TOTAL POINTS  %s" % [_fmt(GameState.best_score), _fmt(GameState.total_points)]
	_show("title")


# ------------------------------------------------------------------ hangar

func _build_hangar() -> void:
	var page: Control = _page("hangar", false)
	_backdrop(page, 0.5)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	margin.add_theme_constant_override("margin_right", 60)
	page.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(470.0, 0.0)
	row.add_child(panel)
	_fade_item("hangar", panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	box.add_child(_label("HANGAR", 38, GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(_rule(420.0))
	_lbl_hangar_pts = _label("", 19, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, true)
	box.add_child(_lbl_hangar_pts)
	_prog_ctl = Control.new()
	_prog_ctl.custom_minimum_size = Vector2(420.0, 40.0)
	_prog_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prog_ctl.draw.connect(_draw_progress)
	box.add_child(_prog_ctl)
	_skin_buttons.clear()
	for i in range(GameState.SKINS.size()):
		var b := _button("", _noop, 420.0, 42.0)
		b.add_theme_font_size_override("font_size", 21)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_skin_pressed.bind(i))
		var sw := Control.new()
		sw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.draw.connect(_draw_swatch.bind(sw, i))
		b.add_child(sw)
		box.add_child(b)
		_skin_buttons.append(b)
	box.add_child(_spacer(2.0))
	_btn_equip = _button("EQUIP", _equip_selected, 420.0, 52.0, true)
	box.add_child(_btn_equip)
	box.add_child(_button("BACK", _close_hangar, 420.0, 50.0))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var rbox := VBoxContainer.new()
	rbox.size_flags_vertical = Control.SIZE_SHRINK_END
	rbox.add_theme_constant_override("separation", 4)
	row.add_child(rbox)
	_lbl_skin_sub = _label("AIRFRAME LIVERY", 18, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, true)
	rbox.add_child(_lbl_skin_sub)
	_lbl_skin_name = _label("", 56, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, true)
	rbox.add_child(_lbl_skin_name)
	_lbl_skin_state = _label("", 22, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, true)
	rbox.add_child(_lbl_skin_state)
	rbox.add_child(_spacer(12.0))
	_fade_item("hangar", rbox)


func _noop() -> void:
	pass


func _draw_swatch(sw: Control, index: int) -> void:
	var skin: Dictionary = GameState.SKINS[index]
	var x: float = sw.size.x - 70.0
	var cy: float = sw.size.y * 0.5
	var unlocked: bool = GameState.is_unlocked(index)
	var a: float = 1.0 if unlocked else 0.45
	var body: Color = skin["body"]
	var accent: Color = skin["accent"]
	sw.draw_rect(Rect2(x, cy - 9.0, 24.0, 18.0), Color(body.r, body.g, body.b, a))
	sw.draw_rect(Rect2(x + 28.0, cy - 9.0, 14.0, 18.0), Color(accent.r, accent.g, accent.b, a))
	sw.draw_rect(Rect2(x, cy - 9.0, 42.0, 18.0), Color(1, 1, 1, 0.5 * a), false, 1.0)
	if not unlocked:
		var lx: float = x + 50.0
		sw.draw_rect(Rect2(lx, cy - 2.0, 12.0, 10.0), Color(1, 1, 1, 0.6))
		sw.draw_arc(Vector2(lx + 6.0, cy - 2.0), 4.5, PI, TAU, 8, Color(1, 1, 1, 0.6), 2.0)


func _draw_progress() -> void:
	var c: Control = _prog_ctl
	c.draw_string(UiStyle.font_ui(), Vector2(0.0, 14.0), _prog_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(1, 1, 1, 0.8))
	c.draw_rect(Rect2(0.0, 24.0, 420.0, 8.0), Color(1, 1, 1, 0.12))
	c.draw_rect(Rect2(0.0, 24.0, 420.0 * clampf(_prog_frac, 0.0, 1.0), 8.0), GOLD)


func _open_hangar() -> void:
	_hangar_sel = GameState.selected_skin
	_refresh_hangar()
	_show("hangar")
	hangar_opened.emit()
	skin_preview.emit(_hangar_sel)


func _close_hangar() -> void:
	hangar_closed.emit()
	show_title()


func show_hangar_from_over() -> void:
	_open_hangar()


func _on_skin_pressed(index: int) -> void:
	_hangar_sel = index
	_refresh_hangar()
	skin_preview.emit(index)


func _equip_selected() -> void:
	if GameState.is_unlocked(_hangar_sel):
		GameState.selected_skin = _hangar_sel
		GameState.save_data()
		_refresh_hangar()


func _refresh_hangar() -> void:
	_lbl_hangar_pts.text = "TOTAL POINTS  %s" % _fmt(GameState.total_points)
	# progress toward the next locked skin
	var next_i: int = -1
	for i in range(GameState.SKINS.size()):
		if not GameState.is_unlocked(i):
			next_i = i
			break
	if next_i < 0:
		_prog_text = "ALL AIRFRAMES UNLOCKED"
		_prog_frac = 1.0
	else:
		var cost: int = int(GameState.SKINS[next_i]["cost"])
		_prog_text = "NEXT: %s    %s / %s" % [String(GameState.SKINS[next_i]["name"]), _fmt(GameState.total_points), _fmt(cost)]
		_prog_frac = float(GameState.total_points) / float(maxi(cost, 1))
	_prog_ctl.queue_redraw()
	for i in range(_skin_buttons.size()):
		var skin: Dictionary = GameState.SKINS[i]
		var b: Button = _skin_buttons[i]
		var tag: String = ""
		if i == GameState.selected_skin:
			tag = "EQUIPPED"
		elif GameState.is_unlocked(i):
			tag = "READY"
		else:
			tag = "%s PTS" % _fmt(int(skin["cost"]))
		b.text = "%s   /   %s" % [String(skin["name"]), tag]
		var sel: bool = i == _hangar_sel
		var col: Color = WHITE
		if sel:
			col = GOLD
		elif not GameState.is_unlocked(i):
			col = Color(0.6, 0.6, 0.62)
		b.add_theme_color_override("font_color", col)
		b.add_theme_stylebox_override("normal", _box(Color(0.20, 0.15, 0.05, 0.96) if sel else Color(INK.r, INK.g, INK.b, 0.86), GOLD if sel else GOLD_DIM, 7 if sel else 4, 2 if sel else 1))
		for ch in b.get_children():
			(ch as Control).queue_redraw()
	var unlocked: bool = GameState.is_unlocked(_hangar_sel)
	var equipped: bool = _hangar_sel == GameState.selected_skin
	_lbl_skin_name.text = String(GameState.SKINS[_hangar_sel]["name"])
	if equipped:
		_lbl_skin_state.text = "CURRENTLY EQUIPPED"
		_lbl_skin_state.add_theme_color_override("font_color", GREEN)
	elif unlocked:
		_lbl_skin_state.text = "UNLOCKED - READY TO EQUIP"
		_lbl_skin_state.add_theme_color_override("font_color", GOLD)
	else:
		var need: int = int(GameState.SKINS[_hangar_sel]["cost"]) - GameState.total_points
		_lbl_skin_state.text = "LOCKED - %s MORE POINTS" % _fmt(need)
		_lbl_skin_state.add_theme_color_override("font_color", RED)
	_btn_equip.disabled = (not unlocked) or equipped


# ------------------------------------------------------------------ pause

func _build_pause() -> void:
	var page: Control = _page("pause", true)
	var box: VBoxContainer = _centered_panel(page)
	box.add_child(_label("PAUSED", 48, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true))
	box.add_child(_rule(360.0))
	box.add_child(_spacer(4.0))
	box.add_child(_slot("pause", _button("RESUME", _do_resume, 380.0, 68.0, true), 380.0, 68.0))
	box.add_child(_slot("pause", _button("RESTART", _do_restart, 380.0, 60.0), 380.0, 60.0))
	box.add_child(_slot("pause", _button("SETTINGS", _open_settings_pause, 380.0, 60.0), 380.0, 60.0))
	box.add_child(_slot("pause", _button("MAIN MENU", _do_menu, 380.0, 60.0), 380.0, 60.0))


func show_pause() -> void:
	_show("pause")


# ------------------------------------------------------------------ game over

func _stat(parent: Container, title: String) -> Label:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.custom_minimum_size = Vector2(150.0, 0.0)
	v.add_child(_label(title, 14, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true))
	var val: Label = _label("-", 26, WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(val)
	parent.add_child(v)
	return val


func _build_over() -> void:
	var page: Control = _page("over", true)
	var box: VBoxContainer = _centered_panel(page)
	box.add_child(_label("MISSION REPORT", 18, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true))
	_lbl_over_title = _label("HELICOPTER DOWN", 44, RED, HORIZONTAL_ALIGNMENT_CENTER, true)
	box.add_child(_lbl_over_title)
	box.add_child(_rule(480.0, RED))
	_lbl_over_score = _label("000000", 72, WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	box.add_child(_lbl_over_score)
	_lbl_over_best = _label("", 24, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true)
	box.add_child(_lbl_over_best)
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 24)
	box.add_child(stats)
	_lbl_over_dist = _stat(stats, "DISTANCE")
	_lbl_over_kills = _stat(stats, "KILLS")
	_lbl_over_total = _stat(stats, "TOTAL POINTS")
	_lbl_over_unlock = _label("", 22, GREEN, HORIZONTAL_ALIGNMENT_CENTER, true)
	box.add_child(_lbl_over_unlock)
	box.add_child(_slot("over", _button("REDEPLOY", _do_restart, 420.0, 68.0, true), 420.0, 68.0))
	box.add_child(_slot("over", _button("HANGAR", _open_hangar, 420.0, 58.0), 420.0, 58.0))
	box.add_child(_slot("over", _button("MAIN MENU", _do_menu, 420.0, 58.0), 420.0, 58.0))


func show_over(score: int, new_best: bool, unlocked: Array, dist_m: float, kills: int) -> void:
	_lbl_over_score.text = "000000"
	if new_best:
		_lbl_over_best.text = "NEW PERSONAL BEST"
	else:
		_lbl_over_best.text = "BEST  %s" % _fmt(GameState.best_score)
	_lbl_over_dist.text = "%.2f KM" % (dist_m / 1000.0)
	_lbl_over_kills.text = str(kills)
	_lbl_over_total.text = _fmt(GameState.total_points)
	if unlocked.is_empty():
		_lbl_over_unlock.text = ""
		_lbl_over_unlock.visible = false
	else:
		_lbl_over_unlock.text = "AIRFRAME UNLOCKED:  %s" % ", ".join(PackedStringArray(unlocked))
		_lbl_over_unlock.visible = true
	_show("over")
	var tw: Tween = create_tween()
	tw.tween_method(_set_over_score, 0.0, float(score), 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if new_best:
		_best_tween = create_tween()
		_best_tween.set_loops()
		_best_tween.tween_property(_lbl_over_best, "modulate:a", 0.35, 0.5)
		_best_tween.tween_property(_lbl_over_best, "modulate:a", 1.0, 0.5)


func _set_over_score(v: float) -> void:
	_lbl_over_score.text = "%06d" % int(round(v))


# ------------------------------------------------------------------ settings

func _build_settings() -> void:
	var page: Control = _page("settings", true)
	var box: VBoxContainer = _centered_panel(page)
	box.add_child(_label("SETTINGS", 46, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true))
	box.add_child(_rule(400.0))
	box.add_child(_spacer(4.0))
	_btn_haptics = _button("", _toggle_haptics, 420.0, 58.0)
	box.add_child(_slot("settings", _btn_haptics, 420.0, 58.0))
	_btn_shadows = _button("", _toggle_shadows, 420.0, 58.0)
	box.add_child(_slot("settings", _btn_shadows, 420.0, 58.0))
	_btn_quality = _button("", _toggle_quality, 420.0, 58.0)
	box.add_child(_slot("settings", _btn_quality, 420.0, 58.0))
	var vrow := HBoxContainer.new()
	vrow.alignment = BoxContainer.ALIGNMENT_CENTER
	vrow.add_theme_constant_override("separation", 10)
	vrow.add_child(_button("-", _vol_down, 90.0, 58.0))
	_lbl_volume = _label("", 24, WHITE, HORIZONTAL_ALIGNMENT_CENTER, true)
	_lbl_volume.custom_minimum_size = Vector2(230.0, 0.0)
	_lbl_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vrow.add_child(_lbl_volume)
	vrow.add_child(_button("+", _vol_up, 90.0, 58.0))
	box.add_child(vrow)
	box.add_child(_slot("settings", _button("BACK", _close_settings, 420.0, 64.0, true), 420.0, 64.0))


func show_settings(from_page: String) -> void:
	_settings_from = from_page
	_refresh_settings()
	_show("settings")


func _close_settings() -> void:
	if _settings_from == "pause":
		show_pause()
	else:
		show_title()


func _refresh_settings() -> void:
	_btn_haptics.text = "HAPTICS:  %s" % ("ON" if GameState.haptics else "OFF")
	_btn_shadows.text = "SHADOWS:  %s" % ("ON" if GameState.shadows else "OFF")
	_btn_quality.text = "GRAPHICS:  %s" % String(QUALITY_NAMES[clampi(GameState.quality, 0, 2)])
	_lbl_volume.text = "VOLUME  %d%%" % int(round(GameState.volume * 100.0))


func _toggle_haptics() -> void:
	GameState.haptics = not GameState.haptics
	GameState.save_data()
	if GameState.haptics:
		Input.vibrate_handheld(60)
	_refresh_settings()
	settings_changed.emit()


func _toggle_shadows() -> void:
	GameState.shadows = not GameState.shadows
	GameState.save_data()
	_refresh_settings()
	settings_changed.emit()


func _toggle_quality() -> void:
	GameState.quality = (GameState.quality + 1) % 3
	GameState.save_data()
	_refresh_settings()
	settings_changed.emit()


func _change_volume(delta: float) -> void:
	GameState.volume = clampf(GameState.volume + delta, 0.0, 1.0)
	GameState.apply_volume()
	GameState.save_data()
	_refresh_settings()
	settings_changed.emit()


## Called by the game when it lowers graphics automatically; refreshes the label if settings are open.
func notify_quality_changed() -> void:
	if current == "settings":
		_refresh_settings()


# ------------------------------------------------------------------ navigation

func _show(key: String) -> void:
	visible = true
	current = key
	if _best_tween != null:
		_best_tween.kill()
		_best_tween = null
	for k in _pages.keys():
		var p: Control = _pages[k]
		p.visible = (k == key)
	var page: Control = _pages[key]
	page.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(page, "modulate:a", 1.0, 0.22)
	var items: Array = _intro[key]
	for i in range(items.size()):
		var item: Control = items[i]
		item.modulate.a = 0.0
		var itw: Tween = create_tween()
		itw.set_parallel(true)
		itw.tween_property(item, "modulate:a", 1.0, 0.3).set_delay(0.05 * float(i)).set_ease(Tween.EASE_OUT)
		if item is Button:
			item.position.x = -48.0
			itw.tween_property(item, "position:x", 0.0, 0.34).set_delay(0.05 * float(i)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if key != "loading":
		Feedback.play("ui_in", -9.0)


func hide_all() -> void:
	current = ""
	if _best_tween != null:
		_best_tween.kill()
		_best_tween = null
	for k in _pages.keys():
		var p: Control = _pages[k]
		p.visible = false


func is_open() -> bool:
	return current != ""


## Handles the Android back button. Returns true when a menu consumed it.
func handle_back() -> bool:
	match current:
		"settings":
			Feedback.play("ui_back", -8.0)
			_close_settings()
			return true
		"hangar":
			Feedback.play("ui_back", -8.0)
			_close_hangar()
			return true
		"pause":
			resume_requested.emit()
			return true
		"over":
			menu_requested.emit()
			return true
	return false
