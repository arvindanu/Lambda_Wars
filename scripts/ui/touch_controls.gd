extends Control
## On-screen controls: virtual joystick (bottom-left) and FIRE / MISSILE / NUKE buttons (bottom-right).
## Handles several simultaneous touches. Mouse input is emulated as touch, so it also works on desktop.
## Layout and hit testing are unchanged; only the presentation is polished (glow, cooldown sweep,
## ready pulse, press feedback).

signal missile_pressed
signal nuke_pressed
signal pause_pressed

const SafeArea = preload("res://scripts/util/safe_area.gd")
const UiStyle = preload("res://scripts/util/ui_style.gd")

## Button centres keep the layout of the original design (computed from these reference radii);
## the drawn buttons are about 16% smaller. Touch targets stay generous via HIT_SCALE.
const REF_JOY_R: float = 105.0
const REF_FIRE_R: float = 90.0
const REF_MISS_R: float = 62.0
const REF_NUKE_R: float = 62.0
const REF_PAUSE_R: float = 34.0
const HIT_SCALE: float = 1.4
## Thumb travel for full stick deflection (kept close to the original so strafing feels the same).
const JOY_INPUT_R: float = 100.0

var move: Vector2 = Vector2.ZERO
var fire_held: bool = false
var missile_ready: float = 1.0
var nuke_ready: float = 1.0
var missile_count: int = 0
var nuke_count: int = 0

var _joy_idx: int = -1
var _fire_idx: int = -1
var _knob: Vector2 = Vector2.ZERO
var _joy_c: Vector2 = Vector2.ZERO
var _joy_r: float = 88.0
var _fire_c: Vector2 = Vector2.ZERO
var _fire_r: float = 76.0
var _miss_c: Vector2 = Vector2.ZERO
var _miss_r: float = 52.0
var _nuke_c: Vector2 = Vector2.ZERO
var _nuke_r: float = 52.0
var _pause_c: Vector2 = Vector2.ZERO
var _pause_r: float = 29.0
var _miss_flash: float = 0.0
var _nuke_flash: float = 0.0
var _t: float = 0.0
var _prev_m: float = 1.0
var _prev_n: float = 1.0
var _pulse_m: float = 0.0
var _pulse_n: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_layout)
	_layout()


func _on_visibility_changed() -> void:
	if not visible:
		reset_inputs()


func reset_inputs() -> void:
	_joy_idx = -1
	_fire_idx = -1
	_knob = Vector2.ZERO
	move = Vector2.ZERO
	fire_held = false


func _layout() -> void:
	var ins: Vector4 = SafeArea.insets(size)
	var w: float = size.x
	var h: float = size.y
	_joy_c = Vector2(ins.x + 60.0 + REF_JOY_R, h - ins.w - 40.0 - REF_JOY_R)
	_fire_c = Vector2(w - ins.z - 48.0 - REF_FIRE_R, h - ins.w - 44.0 - REF_FIRE_R)
	_miss_c = Vector2(_fire_c.x - REF_FIRE_R - REF_MISS_R - 34.0, h - ins.w - 38.0 - REF_MISS_R)
	_nuke_c = Vector2(w - ins.z - 44.0 - REF_NUKE_R, _fire_c.y - REF_FIRE_R - REF_NUKE_R - 32.0)
	_pause_c = Vector2(w - ins.z - 30.0 - REF_PAUSE_R, ins.y + 24.0 + REF_PAUSE_R)


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
		accept_event()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _joy_idx:
			_update_joy(d.position)
		accept_event()


func _hit(pos: Vector2, c: Vector2, r: float) -> bool:
	return pos.distance_to(c) <= r * HIT_SCALE


func _press(idx: int, pos: Vector2) -> void:
	if _hit(pos, _fire_c, _fire_r):
		if _fire_idx < 0:
			_fire_idx = idx
			fire_held = true
	elif _hit(pos, _miss_c, _miss_r):
		_miss_flash = 0.2
		missile_pressed.emit()
	elif _hit(pos, _nuke_c, _nuke_r):
		_nuke_flash = 0.2
		nuke_pressed.emit()
	elif pos.distance_to(_pause_c) <= _pause_r * 1.7:
		pause_pressed.emit()
	elif pos.x < size.x * 0.42 and pos.y > size.y * 0.2 and _joy_idx < 0:
		_joy_idx = idx
		_update_joy(pos)


func _release(idx: int) -> void:
	if idx == _joy_idx:
		_joy_idx = -1
		_knob = Vector2.ZERO
		move = Vector2.ZERO
	if idx == _fire_idx:
		_fire_idx = -1
		fire_held = false


func _update_joy(pos: Vector2) -> void:
	var v: Vector2 = (pos - _joy_c) / JOY_INPUT_R
	if v.length() > 1.0:
		v = v.normalized()
	_knob = v * _joy_r
	var vl: float = v.length()
	if vl < 0.12:
		move = Vector2.ZERO
	else:
		move = v.normalized() * clampf((vl - 0.12) / 0.73, 0.0, 1.0)


# ------------------------------------------------------------------ drawing

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_miss_flash = maxf(0.0, _miss_flash - delta)
	_nuke_flash = maxf(0.0, _nuke_flash - delta)
	if missile_ready >= 0.999 and _prev_m < 0.999 and missile_count > 0:
		_pulse_m = 1.0
	if nuke_ready >= 0.999 and _prev_n < 0.999 and nuke_count > 0:
		_pulse_n = 1.0
	_prev_m = missile_ready
	_prev_n = nuke_ready
	_pulse_m = maxf(0.0, _pulse_m - delta * 2.2)
	_pulse_n = maxf(0.0, _pulse_n - delta * 2.2)
	queue_redraw()


func _draw() -> void:
	_draw_joystick()
	_draw_button(_fire_c, _fire_r, 0, 1.0, -1, fire_held, UiStyle.GOLD, 0.0)
	_draw_button(_miss_c, _miss_r, 1, missile_ready, missile_count, _miss_flash > 0.0, UiStyle.CYAN, _pulse_m)
	_draw_button(_nuke_c, _nuke_r, 2, nuke_ready, nuke_count, _nuke_flash > 0.0, UiStyle.RED, _pulse_n)
	UiStyle.text(self, _fire_c + Vector2(-_fire_r, _fire_r + 21.0), "FIRE", 16, Color(1, 1, 1, 0.8), UiStyle.font_head(), HORIZONTAL_ALIGNMENT_CENTER, _fire_r * 2.0)
	_draw_pause()


func _draw_joystick() -> void:
	var gold: Color = UiStyle.GOLD
	var act: bool = _joy_idx >= 0
	var k: float = _joy_r / REF_JOY_R
	UiStyle.glow_circle(self, _joy_c, _joy_r, UiStyle.with_alpha(gold, 0.55 if act else 0.25), 3)
	draw_circle(_joy_c, _joy_r, Color(0.03, 0.04, 0.05, 0.42))
	draw_circle(_joy_c, _joy_r * 0.62, Color(0.03, 0.04, 0.05, 0.28))
	draw_arc(_joy_c, _joy_r, 0.0, TAU, 64, UiStyle.with_alpha(gold, 0.85), 2.5, true)
	draw_arc(_joy_c, _joy_r * 0.62, 0.0, TAU, 48, UiStyle.with_alpha(gold, 0.22), 1.5, true)
	for i in range(16):
		var a: float = TAU * float(i) / 16.0
		var dir := Vector2(cos(a), sin(a))
		var major: bool = (i % 4) == 0
		var r_out: float = _joy_r * (0.96 if major else 0.92)
		draw_line(_joy_c + dir * (_joy_r * 0.85), _joy_c + dir * r_out, UiStyle.with_alpha(gold, 0.75 if major else 0.32), 2.5 if major else 1.5, true)
	# left / right chevrons light up with stick direction (the helicopter strafes horizontally)
	for side in [-1.0, 1.0]:
		var sx: float = float(side)
		var lit: float = clampf(move.x * sx, 0.0, 1.0)
		var cx: float = _joy_c.x + sx * _joy_r * 0.62
		var col: Color = Color(1.0, 0.9, 0.5, 0.35 + 0.65 * lit)
		var chev := PackedVector2Array([
			Vector2(cx + sx * 12.0 * k, _joy_c.y), Vector2(cx - sx * 6.0 * k, _joy_c.y - 14.0 * k), Vector2(cx - sx * 6.0 * k, _joy_c.y + 14.0 * k)])
		draw_colored_polygon(chev, col)
	var knob_pos: Vector2 = _joy_c + _knob * 0.7
	if act:
		draw_line(_joy_c, knob_pos, UiStyle.with_alpha(gold, 0.5), 3.0, true)
	UiStyle.glow_circle(self, knob_pos, _joy_r * 0.36, UiStyle.with_alpha(gold, 0.8 if act else 0.4), 3)
	draw_circle(knob_pos, _joy_r * 0.38, Color(gold.r, gold.g, gold.b, 0.62 if act else 0.38))
	draw_circle(knob_pos, _joy_r * 0.26, Color(1.0, 0.95, 0.7, 0.28 if act else 0.14))
	draw_arc(knob_pos, _joy_r * 0.38, 0.0, TAU, 36, Color(1, 1, 1, 0.7), 2.0, true)
	draw_circle(knob_pos, 3.5, Color(1, 1, 1, 0.8))


func _draw_button(c: Vector2, r: float, kind: int, ready_frac: float, count: int, pressed: bool, tint: Color, pulse: float) -> void:
	var rr: float = r * (0.93 if pressed else 1.0)
	var empty: bool = count == 0
	var is_ready: bool = ready_frac >= 0.999 and not empty
	var glow_a: float = 0.55 if pressed else (0.28 if is_ready or kind == 0 else 0.1)
	UiStyle.glow_circle(self, c, rr, UiStyle.with_alpha(tint, glow_a + 0.2 * pulse), 3)
	draw_circle(c, rr, Color(0.03, 0.04, 0.05, 0.6 if pressed else 0.44))
	draw_circle(c, rr * 0.72, Color(tint.r, tint.g, tint.b, 0.16 if pressed else 0.08))
	draw_arc(c, rr - 2.0, 0.0, TAU, 56, UiStyle.with_alpha(tint, 0.95 if not empty else 0.4), 3.5, true)
	draw_arc(c, rr * 0.72, 0.0, TAU, 48, UiStyle.with_alpha(tint, 0.3), 1.5, true)
	if kind == 0 and fire_held:
		for k in range(6):
			var a0: float = _t * 2.4 + TAU * float(k) / 6.0
			draw_arc(c, rr * 1.08, a0, a0 + 0.5, 8, UiStyle.with_alpha(tint, 0.85), 3.0, true)
	if ready_frac < 0.999:
		draw_arc(c, rr * 0.5, -PI * 0.5 + TAU * ready_frac, -PI * 1.5 + TAU, 40, Color(0, 0, 0, 0.52), rr, false)
		draw_arc(c, rr * 0.86, -PI * 0.5, -PI * 0.5 + TAU * ready_frac, 48, UiStyle.with_alpha(tint, 0.95), 5.0, true)
	if pulse > 0.01:
		draw_arc(c, rr * (1.0 + (1.0 - pulse) * 0.55), 0.0, TAU, 56, Color(1, 1, 1, pulse * 0.75), 3.0, true)
	var ic: Color = Color(1, 1, 1, 0.97)
	if empty:
		ic = Color(1, 1, 1, 0.3)
	elif ready_frac < 0.999:
		ic = Color(1, 1, 1, 0.55)
	var iy: float = -rr * 0.08 if kind != 0 else 0.0
	var ic_c: Vector2 = c + Vector2(0.0, iy)
	if kind == 0:
		draw_arc(ic_c, rr * 0.34, 0.0, TAU, 28, ic, 3.0, true)
		draw_circle(ic_c, rr * 0.07, ic)
		for k in range(4):
			var a: float = float(k) * PI * 0.5
			var dir := Vector2(cos(a), sin(a))
			draw_line(ic_c + dir * (rr * 0.24), ic_c + dir * (rr * 0.56), ic, 3.0, true)
	elif kind == 1:
		_poly(ic_c, rr, [Vector2(-0.10, -0.22), Vector2(0.10, -0.22), Vector2(0.10, 0.24), Vector2(-0.10, 0.24)], ic)
		_poly(ic_c, rr, [Vector2(-0.10, -0.22), Vector2(0.0, -0.46), Vector2(0.10, -0.22)], Color(tint.r, tint.g, tint.b, ic.a))
		_poly(ic_c, rr, [Vector2(-0.10, 0.06), Vector2(-0.28, 0.32), Vector2(-0.10, 0.24)], ic)
		_poly(ic_c, rr, [Vector2(0.10, 0.06), Vector2(0.10, 0.24), Vector2(0.28, 0.32)], ic)
	else:
		for k in range(3):
			var a0: float = deg_to_rad(-90.0 + 120.0 * float(k) - 30.0)
			var a1: float = a0 + deg_to_rad(60.0)
			var pts := PackedVector2Array([ic_c])
			for s in range(9):
				var a: float = lerpf(a0, a1, float(s) / 8.0)
				pts.append(ic_c + Vector2(cos(a), sin(a)) * rr * 0.42)
			draw_colored_polygon(pts, ic)
		draw_circle(ic_c, rr * 0.11, Color(0.03, 0.04, 0.05, 1.0))
		draw_circle(ic_c, rr * 0.07, ic)
	if kind == 1:
		UiStyle.text(self, c + Vector2(-rr, rr * 0.7), "MSL", 13, UiStyle.with_alpha(tint, 0.9), UiStyle.font_head(), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0)
	elif kind == 2:
		UiStyle.text(self, c + Vector2(-rr, rr * 0.7), "NUKE", 13, UiStyle.with_alpha(tint, 0.9), UiStyle.font_head(), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0)
	if count >= 0:
		var badge := Rect2(c + Vector2(rr * 0.36, rr * 0.64), Vector2(42.0, 24.0))
		draw_rect(badge, Color(0.03, 0.04, 0.05, 0.9))
		draw_rect(badge, UiStyle.with_alpha(UiStyle.RED if empty else UiStyle.GOLD, 0.9), false, 2.0)
		UiStyle.text(self, badge.position + Vector2(0.0, 19.0), "x%d" % count, 18, UiStyle.RED if empty else UiStyle.GOLD, UiStyle.font_num(), HORIZONTAL_ALIGNMENT_CENTER, badge.size.x)


func _poly(c: Vector2, r: float, pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		var v: Vector2 = p
		out.append(c + v * r * 1.5)
	draw_colored_polygon(out, col)


func _draw_pause() -> void:
	UiStyle.glow_circle(self, _pause_c, _pause_r, UiStyle.with_alpha(UiStyle.WHITE, 0.25), 2)
	draw_circle(_pause_c, _pause_r, Color(0.03, 0.04, 0.05, 0.55))
	draw_arc(_pause_c, _pause_r, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 2.0, true)
	draw_rect(Rect2(_pause_c + Vector2(-7.5, -9.0), Vector2(5.0, 18.0)), Color(1, 1, 1, 0.9))
	draw_rect(Rect2(_pause_c + Vector2(2.5, -9.0), Vector2(5.0, 18.0)), Color(1, 1, 1, 0.9))
