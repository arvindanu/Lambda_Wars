extends Node
## Lambda Wars - main controller. Builds the scene in code, owns the game state machine
## (loading -> title -> play -> game over, plus pause and hangar) and steps every system in a fixed order.
## This pass added only presentation: sky / fog / grading, cinematic title camera, loading screen,
## hangar showcase, popups and graphics quality levels. Gameplay flow is unchanged.

const Cfg = preload("res://scripts/core/config.gd")
const Shaders = preload("res://scripts/util/shaders.gd")
const UiStyle = preload("res://scripts/util/ui_style.gd")
const World = preload("res://scripts/world/world.gd")
const DayNight = preload("res://scripts/world/day_night.gd")
const AmbientFx = preload("res://scripts/world/ambient_fx.gd")
const Player = preload("res://scripts/battle/player.gd")
const Projectiles = preload("res://scripts/battle/projectiles.gd")
const Enemies = preload("res://scripts/battle/enemies.gd")
const Pickups = preload("res://scripts/battle/pickups.gd")
const Effects = preload("res://scripts/battle/effects.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Menus = preload("res://scripts/ui/menus.gd")

const VIGNETTE_CODE := """
shader_type canvas_item;
uniform float strength = 0.3;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = dot(uv, uv) * 2.2;
	float v = smoothstep(0.25, 1.0, d);
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
"""

var mode: int = Cfg.MODE_ATTRACT
var paused: bool = false
var dying: bool = false
var in_hangar: bool = false

var world = null
var day_night = null
var player = null
var projectiles = null
var enemies = null
var pickups = null
var fx = null
var ambient = null
var touch = null
var hud = null
var menus = null

var camera: Camera3D = null
var light: DirectionalLight3D = null
var env: Environment = null
var sky_mat: ShaderMaterial = null
var ui: CanvasLayer = null
var grade_layer: CanvasLayer = null
var grade_rect: ColorRect = null
var vignette_rect: ColorRect = null
var vignette_mat: ShaderMaterial = null
var flash_rect: ColorRect = null
var hangar_fx: Node3D = null
var hangar_ring: Node3D = null

var run_time: float = 0.0
var distance: float = 0.0
var kill_score: int = 0
var start_z: float = 0.0

var _shake: float = 0.0
var _cam_x: float = 0.0
var _cam_t: float = 0.0
var _cin: float = 1.0
var _dying_t: float = 0.0
var _flash: float = 0.0
var _loading: bool = true
var _atmo_t: float = 0.0
var _fps_t: float = 0.0
var _low_fps: int = 0
var _ci_autostart: bool = false


func _ready() -> void:
	randomize()
	# Test hook for the CI smoke run (godot ... -- --ci-autostart). Never set in normal play.
	_ci_autostart = OS.get_cmdline_user_args().has("--ci-autostart")
	_build_environment()

	world = World.new()
	add_child(world)
	world.setup(randi() % 100000 + 1)

	fx = Effects.new()
	add_child(fx)
	projectiles = Projectiles.new()
	add_child(projectiles)
	enemies = Enemies.new()
	add_child(enemies)
	player = Player.new()
	add_child(player)
	pickups = Pickups.new()
	add_child(pickups)
	ambient = AmbientFx.new()
	add_child(ambient)

	player.setup(projectiles, fx, world, enemies)
	projectiles.setup(enemies, player, fx, world)
	enemies.setup(projectiles, player, fx, world)
	pickups.setup(player, world)
	pickups.fx = fx

	_build_hangar_set()
	_build_ui()
	_connect_signals()

	player.reset(Vector3(0.0, Cfg.HELI_HOVER, 0.0))
	_apply_settings()
	_sync_atmosphere()
	menus.show_loading()
	_loading = true


# ------------------------------------------------------------------ scene construction

func _build_environment() -> void:
	sky_mat = Shaders.sky_material()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0035
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	light = DirectionalLight3D.new()
	light.shadow_enabled = GameState.shadows
	light.directional_shadow_max_distance = 150.0
	light.shadow_blur = 1.6
	light.light_angular_distance = 0.5
	add_child(light)

	day_night = DayNight.new()
	day_night.setup(light, env, sky_mat)

	camera = Camera3D.new()
	camera.fov = Cfg.CAM_FOV
	camera.near = 1.0
	camera.far = 420.0
	add_child(camera)
	camera.current = true


## Hover pad, light cone and rim light used while previewing helicopters in the hangar.
func _build_hangar_set() -> void:
	hangar_fx = Node3D.new()
	hangar_fx.visible = false
	add_child(hangar_fx)
	var pad := CylinderMesh.new()
	pad.top_radius = 6.6
	pad.bottom_radius = 6.9
	pad.height = 0.35
	pad.radial_segments = 28
	pad.rings = 1
	var pad_mi := MeshInstance3D.new()
	pad_mi.mesh = pad
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.08, 0.09, 0.10)
	pm.metallic = 0.7
	pm.roughness = 0.35
	pad_mi.material_override = pm
	pad_mi.position = Vector3(0.0, -4.6, 0.0)
	hangar_fx.add_child(pad_mi)

	var gold: Color = UiStyle.GOLD
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 6.0
	ring_mesh.outer_radius = 6.35
	ring_mesh.rings = 40
	ring_mesh.ring_segments = 4
	hangar_ring = Node3D.new()
	hangar_ring.position = Vector3(0.0, -4.4, 0.0)
	hangar_fx.add_child(hangar_ring)
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring_mesh
	ring_mi.material_override = _glow_mat(gold, 0.9)
	ring_mi.scale = Vector3(1.0, 0.3, 1.0)
	hangar_ring.add_child(ring_mi)
	var ring2 := TorusMesh.new()
	ring2.inner_radius = 4.3
	ring2.outer_radius = 4.45
	ring2.rings = 32
	ring2.ring_segments = 4
	var ring2_mi := MeshInstance3D.new()
	ring2_mi.mesh = ring2
	ring2_mi.material_override = _glow_mat(gold, 0.45)
	ring2_mi.scale = Vector3(1.0, 0.3, 1.0)
	ring2_mi.position = Vector3(0.0, -4.35, 0.0)
	hangar_fx.add_child(ring2_mi)

	var cone := CylinderMesh.new()
	cone.top_radius = 1.2
	cone.bottom_radius = 6.2
	cone.height = 7.5
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var cone_mi := MeshInstance3D.new()
	cone_mi.mesh = cone
	cone_mi.material_override = _glow_mat(Color(1.0, 0.9, 0.6), 0.07)
	cone_mi.position = Vector3(0.0, -0.9, 0.0)
	hangar_fx.add_child(cone_mi)

	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.85, 0.6)
	rim.light_energy = 1.8
	rim.omni_range = 30.0
	rim.position = Vector3(7.0, 5.0, 9.0)
	hangar_fx.add_child(rim)


func _glow_mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	return m


func _build_ui() -> void:
	# screen-space colour grade and vignette sit under the HUD so only the 3D scene is tinted
	grade_layer = CanvasLayer.new()
	grade_layer.layer = 5
	add_child(grade_layer)
	grade_rect = ColorRect.new()
	grade_rect.color = Color(1, 1, 1, 1)
	grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	grade_rect.material = cm
	grade_layer.add_child(grade_rect)
	var vsh := Shader.new()
	vsh.code = VIGNETTE_CODE
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = vsh
	vignette_rect = ColorRect.new()
	vignette_rect.color = Color(1, 1, 1, 1)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette_rect.material = vignette_mat
	grade_layer.add_child(vignette_rect)

	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	touch = TouchControls.new()
	ui.add_child(touch)
	hud = Hud.new()
	ui.add_child(hud)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(flash_rect)

	menus = Menus.new()
	ui.add_child(menus)

	hud.player = player
	hud.pickups = pickups
	hud.day_night = day_night
	hud.visible = false
	touch.visible = false


func _connect_signals() -> void:
	touch.missile_pressed.connect(_on_missile_button)
	touch.nuke_pressed.connect(_on_nuke_button)
	touch.pause_pressed.connect(_pause_game)

	menus.start_requested.connect(_start_game)
	menus.restart_requested.connect(_start_game)
	menus.resume_requested.connect(_resume_game)
	menus.menu_requested.connect(_go_title)
	menus.hangar_opened.connect(_on_hangar_opened)
	menus.hangar_closed.connect(_on_hangar_closed)
	menus.skin_preview.connect(_on_skin_preview)
	menus.settings_changed.connect(_apply_settings)
	menus.quit_requested.connect(_quit)

	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	projectiles.nuke_detonated.connect(_on_nuke_detonated)
	projectiles.shake.connect(add_shake)
	enemies.shake.connect(add_shake)
	enemies.enemy_killed.connect(_on_enemy_killed)
	pickups.collected.connect(_on_pickup)


func _quit() -> void:
	get_tree().quit()


# ------------------------------------------------------------------ graphics quality

## 0 = low (no extras), 1 = medium (shaders, ambient particles, grading), 2 = high (adds glow, 2-split shadows).
func _apply_quality() -> void:
	var q: int = GameState.quality
	world.apply_quality(q)
	projectiles.halos_enabled = q > 0
	fx.density = [0.45, 0.75, 1.0][q]
	ambient.set_enabled(q >= 1)
	grade_layer.visible = q >= 1
	env.glow_enabled = q >= 2
	# edge smoothing matters a lot on flat-shaded low-poly geometry
	var vp: Viewport = get_viewport()
	if q <= 0:
		vp.msaa_3d = Viewport.MSAA_DISABLED
	elif q == 1 or OS.has_feature("mobile"):
		vp.msaa_3d = Viewport.MSAA_2X
	else:
		vp.msaa_3d = Viewport.MSAA_4X
	if q >= 2:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	else:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL


func _apply_settings() -> void:
	light.shadow_enabled = GameState.shadows
	GameState.apply_volume()
	_apply_quality()


## Pushes the current time-of-day mood to the screen-space layers and ambient particles.
func _sync_atmosphere() -> void:
	var g: Color = day_night.grade
	grade_rect.color = Color(clampf(g.r, 0.0, 1.0), clampf(g.g, 0.0, 1.0), clampf(g.b, 0.0, 1.0), 1.0)
	vignette_mat.set_shader_parameter("strength", day_night.vignette)
	ambient.set_style(day_night.mote)


# ------------------------------------------------------------------ state transitions

func _clear_battlefield() -> void:
	enemies.reset()
	projectiles.clear()
	fx.clear()
	pickups.reset()


func _go_title() -> void:
	mode = Cfg.MODE_ATTRACT
	paused = false
	dying = false
	in_hangar = false
	_clear_battlefield()
	player.reset(Vector3(0.0, Cfg.HELI_HOVER, player.position.z))
	player.apply_skin(GameState.selected_skin)
	hud.visible = false
	touch.visible = false
	Feedback.rotor_stop()
	menus.show_title()


func _start_game() -> void:
	_clear_battlefield()
	player.reset(Vector3(0.0, Cfg.HELI_HOVER, player.position.z))
	player.apply_skin(GameState.selected_skin)
	run_time = 0.0
	distance = 0.0
	kill_score = 0
	start_z = player.position.z
	_cam_x = 0.0
	_flash = 0.0
	_fps_t = 0.0
	_low_fps = 0
	mode = Cfg.MODE_PLAY
	paused = false
	dying = false
	in_hangar = false
	menus.hide_all()
	hud.clear_toasts()
	hud.visible = true
	touch.visible = true
	Feedback.rotor_start()


func _pause_game() -> void:
	if mode != Cfg.MODE_PLAY or dying or paused:
		return
	paused = true
	touch.visible = false
	Feedback.rotor_stop()
	menus.show_pause()


func _resume_game() -> void:
	if mode != Cfg.MODE_PLAY or not paused:
		return
	paused = false
	menus.hide_all()
	touch.visible = true
	Feedback.rotor_start()


func _on_hangar_opened() -> void:
	in_hangar = true
	mode = Cfg.MODE_ATTRACT
	paused = false
	dying = false
	_clear_battlefield()
	player.reset(Vector3(0.0, Cfg.HELI_HOVER, player.position.z))
	player.showcase = true
	hud.visible = false
	touch.visible = false
	Feedback.rotor_stop()


func _on_hangar_closed() -> void:
	_go_title()


func _on_skin_preview(index: int) -> void:
	player.apply_skin(index)


func _on_player_damaged(_amount: float) -> void:
	hud.hit_flash = 1.0
	add_shake(0.8)
	Feedback.play("hit", -2.0, randf_range(0.9, 1.0))
	Feedback.vibrate(45)


func _on_player_died() -> void:
	dying = true
	_dying_t = 1.8
	var p: Vector3 = player.position
	fx.explosion(p, 2.6, -999.0)
	fx.explosion(p + Vector3(0.0, -4.0, 0.0), 2.0, -999.0)
	fx.flash(p, 14.0, 0.6, Color(1.0, 0.7, 0.3))
	player.set_model_visible(false)
	touch.visible = false
	add_shake(2.2)
	Feedback.play("boom", 0.0, 0.7)
	Feedback.vibrate(220)
	Feedback.rotor_stop()


func _game_over() -> void:
	dying = false
	mode = Cfg.MODE_OVER
	hud.visible = false
	var final_score: int = _score()
	var res: Dictionary = GameState.commit_run(final_score)
	menus.show_over(final_score, bool(res["new_best"]), res["unlocked"], distance, enemies.kills)


func _score() -> int:
	return int(distance / Cfg.UNITS_PER_POINT) + kill_score


# ------------------------------------------------------------------ gameplay events

func _can_act() -> bool:
	return mode == Cfg.MODE_PLAY and not paused and not dying and player.alive


func _on_missile_button() -> void:
	if not _can_act():
		return
	if player.try_missile():
		return
	if player.missiles <= 0:
		hud.toast("NO MISSILES - AWAIT SUPPLY DROP", UiStyle.RED)


func _on_nuke_button() -> void:
	if not _can_act():
		return
	if player.try_nuke():
		hud.toast("NUKE AWAY", UiStyle.RED)
		return
	if player.nukes <= 0:
		hud.toast("NO NUKES - AWAIT SUPPLY DROP", UiStyle.RED)


func _on_nuke_detonated(pos: Vector3) -> void:
	fx.nuke(pos)
	enemies.nuke(pos)
	projectiles.clear_hostile(pos, Cfg.NUKE_RADIUS)
	_flash = 0.95
	add_shake(3.0)
	Feedback.play("nuke", 0.0)
	Feedback.vibrate(400)


func _on_enemy_killed(points: int, pos: Vector3, _type: String) -> void:
	kill_score += points
	var wp: Vector3 = pos + Vector3(0.0, 4.0, 0.0)
	if not camera.is_position_behind(wp):
		hud.add_popup(points, camera.unproject_position(wp))


func _on_pickup(kind: int) -> void:
	var msg: String = player.apply_pickup(kind)
	hud.toast(msg, Pickups.COLORS[kind])
	Feedback.play("pickup", -2.0)
	Feedback.vibrate(25)


func add_shake(amount: float) -> void:
	_shake = minf(maxf(_shake, amount), 3.0)


# ------------------------------------------------------------------ per-frame

func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	_cam_t += dt
	_atmo_t += dt
	if _atmo_t >= 0.2:
		_atmo_t = 0.0
		_sync_atmosphere()
	if _loading:
		_step_loading(dt)
		return
	if mode == Cfg.MODE_PLAY:
		_step_play(dt)
	elif mode == Cfg.MODE_OVER:
		_step_over(dt)
	else:
		_step_attract(dt)
	ambient.follow(player.position)
	_update_camera(dt)
	_flash = move_toward(_flash, 0.0, dt * 0.9)
	flash_rect.color.a = _flash


## Builds the first ring of terrain a few stages per frame while the loading screen shows progress.
func _step_loading(dt: float) -> void:
	day_night.step(dt)
	world.update(player.position, 3)
	var prog: float = world.progress(player.position)
	menus.set_loading_progress(prog)
	_update_camera(dt)
	if prog >= 0.999:
		_loading = false
		_go_title()
		if _ci_autostart:
			_start_game()


func _step_attract(dt: float) -> void:
	day_night.step(dt)
	fx.step(dt)
	if in_hangar:
		player.step_showcase(dt)
		return
	player.step_attract(dt)
	world.update(player.position)


func _step_over(dt: float) -> void:
	fx.step(dt)
	projectiles.step(dt)


func _step_play(dt: float) -> void:
	if paused:
		return
	if dying:
		_dying_t -= dt
		enemies.step(dt, run_time)
		projectiles.step(dt)
		fx.step(dt)
		world.update(player.position)
		if _dying_t <= 0.0:
			_game_over()
		return

	run_time += dt
	var kx: float = touch.move.x
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		kx -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		kx += 1.0
	var firing: bool = touch.fire_held or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_J)
	if _ci_autostart:
		_ci_drive(kx)
		kx = sin(run_time * 0.8)
		firing = true

	player.step(dt, kx, firing, distance)
	distance = maxf(0.0, start_z - player.position.z)
	day_night.step(dt)
	world.update(player.position)
	enemies.step(dt, run_time)
	projectiles.step(dt)
	pickups.step(dt)
	fx.step(dt)

	touch.missile_ready = 1.0 - clampf(player.missile_cd / Cfg.MISSILE_COOLDOWN, 0.0, 1.0)
	touch.nuke_ready = 1.0 - clampf(player.nuke_cd / Cfg.NUKE_COOLDOWN, 0.0, 1.0)
	touch.missile_count = player.missiles
	touch.nuke_count = player.nukes
	hud.score = _score()
	hud.distance = distance
	Feedback.rotor_level(0.85)
	_watch_performance(dt)


## CI smoke test only: periodically uses the special weapons so those code paths run too.
func _ci_drive(_kx: float) -> void:
	var sec: int = int(run_time)
	if sec % 7 == 3:
		player.try_missile()
	if sec == 15:
		player.try_nuke()


## If the frame rate stays low for several seconds, drop one graphics level (visual detail only).
func _watch_performance(dt: float) -> void:
	_fps_t += dt
	if _fps_t < 2.0:
		return
	_fps_t = 0.0
	if run_time < 10.0 or GameState.quality <= 0:
		return
	if Engine.get_frames_per_second() < 40.0:
		_low_fps += 1
	else:
		_low_fps = 0
	if _low_fps >= 3:
		_low_fps = 0
		GameState.quality -= 1
		GameState.save_data()
		_apply_quality()
		menus.notify_quality_changed()
		hud.toast("GRAPHICS REDUCED FOR SMOOTHNESS", UiStyle.AMBER)


func _update_camera(dt: float) -> void:
	var p: Vector3 = player.position
	if in_hangar:
		var a: float = sin(_cam_t * 0.25) * 0.5
		var cpos: Vector3 = p + Vector3(sin(a) * 14.0, 4.0 + 0.8 * sin(_cam_t * 0.4), cos(a) * 14.0)
		camera.fov = 50.0
		camera.look_at_from_position(cpos, p + Vector3(-3.2, 0.3, 0.0), Vector3.UP)
		hangar_fx.visible = true
		hangar_fx.position = p
		hangar_ring.rotation.y += dt * 0.8
		return
	hangar_fx.visible = false

	_cam_x = lerpf(_cam_x, p.x * Cfg.CAM_FOLLOW, 1.0 - exp(-8.0 * dt))
	var off := Vector3.ZERO
	if _shake > 0.01:
		off = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * (_shake * 1.2)
		_shake = move_toward(_shake, 0.0, dt * 3.0)
	var g_pos := Vector3(_cam_x, Cfg.CAM_HEIGHT, p.z + Cfg.CAM_BACK) + off
	var g_basis := Basis.from_euler(Vector3(deg_to_rad(Cfg.CAM_PITCH), 0.0, 0.0))

	var target_cin: float = 1.0 if (mode == Cfg.MODE_ATTRACT or _loading) else 0.0
	_cin = move_toward(_cin, target_cin, dt * 1.1)
	if _cin <= 0.001:
		camera.position = g_pos
		camera.basis = g_basis
		camera.fov = Cfg.CAM_FOV
		return

	# cinematic low-angle title view blending to / from the gameplay camera
	var ang: float = _cam_t * 0.12
	var c_pos: Vector3 = p + Vector3(15.0 + 4.0 * sin(ang), 8.5 + 1.5 * sin(ang * 1.3), 26.0 + 3.0 * cos(ang))
	var c_xf: Transform3D = Transform3D(Basis.IDENTITY, c_pos).looking_at(p + Vector3(-6.5, 1.0, -8.0), Vector3.UP)
	var e: float = _cin * _cin * (3.0 - 2.0 * _cin)
	var q: Quaternion = Quaternion(g_basis).slerp(Quaternion(c_xf.basis), e)
	camera.position = g_pos.lerp(c_pos, e)
	camera.basis = Basis(q)
	camera.fov = lerpf(Cfg.CAM_FOV, 48.0, e)


# ------------------------------------------------------------------ input and lifecycle

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE:
			_handle_back()
		elif k.keycode == KEY_M:
			_on_missile_button()
		elif k.keycode == KEY_N:
			_on_nuke_button()


func _handle_back() -> void:
	if _loading:
		return
	if menus.handle_back():
		return
	if mode == Cfg.MODE_PLAY and not dying:
		if paused:
			_resume_game()
		else:
			_pause_game()
	elif mode == Cfg.MODE_ATTRACT and menus.current == "title":
		get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_pause_game()
