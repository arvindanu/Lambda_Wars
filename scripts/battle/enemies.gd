extends Node3D
## Spawns and drives all enemies: jeeps, trucks, artillery and hostile helicopters.
## Dead units are only flagged during a frame and swept at the start of the next one,
## so other systems can safely iterate `list` while damage is dealt.

signal enemy_killed(points: int, pos: Vector3, type: String)
signal shake(amount: float)

const Cfg = preload("res://scripts/core/config.gd")
const Enemy = preload("res://scripts/battle/enemy.gd")

var list: Array = []
var kills: int = 0
var enabled: bool = true

var projectiles = null
var player = null
var fx = null
var world = null

var _rng := RandomNumberGenerator.new()
var _spawn_t: float = 2.0
var _snd_t: float = 0.0
var _play_time: float = 0.0
var _nukes: Array = []


func setup(projectiles_ref, player_ref, fx_ref, world_ref) -> void:
	projectiles = projectiles_ref
	player = player_ref
	fx = fx_ref
	world = world_ref
	_rng.randomize()


func reset() -> void:
	for e in list:
		e.queue_free()
	list.clear()
	_nukes.clear()
	kills = 0
	_spawn_t = 2.0
	_play_time = 0.0


func _intensity() -> float:
	return clampf(_play_time / 60.0, 0.0, 8.0)


func active_count() -> int:
	var n: int = 0
	for e in list:
		if not e.dead:
			n += 1
	return n


func _air_count() -> int:
	var n: int = 0
	for e in list:
		if not e.dead and e.air:
			n += 1
	return n


# ------------------------------------------------------------------ main step

func step(dt: float, play_time: float) -> void:
	_play_time = play_time
	_snd_t -= dt
	_sweep()
	if enabled:
		_spawn_logic(dt)
	var pp: Vector3 = player.position
	for e in list:
		if e.dead:
			continue
		e.age += dt
		if e.air:
			_tick_heli(e, dt, pp)
		else:
			_tick_ground(e, dt, pp)
		if e.dead:
			continue
		e.update_visual(dt)
		_try_fire(e, dt, pp)
		_damage_smoke(e, dt)
		if e.position.z > pp.z + Cfg.ENEMY_DESPAWN_BEHIND:
			e.dead = true
			e.visible = false
	_step_nukes(dt)


## Cosmetic: badly damaged units trail smoke.
func _damage_smoke(e, dt: float) -> void:
	if e.hp >= e.max_hp * 0.4 or e.dead:
		return
	if _rng.randf() < dt * 9.0:
		fx.puff(e.position + Vector3(0.0, e.mid_height * 1.6, 0.0), Vector3(0.0, 3.0, 1.0), 0.9, 0.7, 2.0, Color(0.12, 0.12, 0.12, 0.65), Color(0.06, 0.06, 0.06, 0.0), 0.0, 0.5)


func _sweep() -> void:
	var i: int = list.size() - 1
	while i >= 0:
		var e = list[i]
		if e.dead:
			list.remove_at(i)
			e.queue_free()
		i -= 1


# ------------------------------------------------------------------ spawning

func _spawn_logic(dt: float) -> void:
	_spawn_t -= dt
	if _spawn_t > 0.0:
		return
	var inten: float = _intensity()
	_spawn_t = maxf(0.9, 3.0 - inten * 0.28) * _rng.randf_range(0.8, 1.2)
	var cap: int = mini(10 + int(inten * 2.0), 22)
	if active_count() >= cap:
		return
	var pool: Array = ["jeep", "jeep", "truck"]
	if _play_time > 22.0:
		pool.append("artillery")
	if _play_time > 70.0:
		pool.append("artillery")
		pool.append("truck")
	if _play_time > 45.0 and _air_count() < mini(1 + int(inten * 0.5), 3):
		pool.append("heli")
		pool.append("heli")
	var t: String = pool[_rng.randi() % pool.size()]
	var n: int = 1
	if t == "jeep":
		n = _rng.randi_range(1, 3)
	elif t == "truck":
		n = _rng.randi_range(1, 2)
	_spawn_group(t, n)


func _spawn_group(t: String, n: int) -> void:
	var pp: Vector3 = player.position
	var cz: float = pp.z - Cfg.ENEMY_SPAWN_AHEAD
	var on_road: bool = (t == "jeep" or t == "truck") and _rng.randf() < 0.5
	var cx: float = pp.x + _rng.randf_range(-45.0, 45.0)
	if on_road:
		cx = world.road_x(cz)
	cx = clampf(cx, -70.0, 70.0)
	for i in range(n):
		var x: float = cx + (float(i) - float(n - 1) * 0.5) * 7.0
		var z: float = cz - float(i) * 7.0
		if on_road and t == "truck":
			x = world.road_x(z) + (3.0 if (i % 2) == 0 else -3.0) * 0.5
		if t != "heli" and world.is_water(x, z):
			continue
		_spawn_one(t, x, z, on_road)


func _spawn_one(t: String, x: float, z: float, on_road: bool) -> void:
	var e = Enemy.new()
	add_child(e)
	e.setup(t, 1.0 + _intensity() * 0.06, _rng)
	e.on_road = on_road and t == "truck"
	if e.on_road:
		e.lane_off = x - world.road_x(z)
	if e.air:
		e.position = Vector3(x, 9.0 + _rng.randf_range(-1.0, 2.0), z)
	else:
		e.position = Vector3(x, world.height_at(x, z), z)
	list.append(e)


# ------------------------------------------------------------------ movement

func _tick_ground(e, dt: float, pp: Vector3) -> void:
	var vxl: float = 0.0
	var inv_dt: float = 1.0 / maxf(dt, 0.0001)
	if e.type == "jeep":
		var goal: float = pp.x + sin(e.age * 0.8 + e.phase) * e.amp
		var nx: float = move_toward(e.position.x, goal, 7.0 * dt)
		vxl = (nx - e.position.x) * inv_dt
		e.position.x = nx
		e.position.z += e.speed * dt
	elif e.type == "truck":
		e.position.z += e.speed * dt
		if e.on_road:
			var nx2: float = world.road_x(e.position.z) + e.lane_off
			vxl = (nx2 - e.position.x) * inv_dt
			e.position.x = nx2
	var h: float = world.height_at(e.position.x, e.position.z)
	if h < Cfg.WATER_LEVEL - 0.3:
		# vehicle drove into a river
		fx.splash(Vector3(e.position.x, Cfg.WATER_LEVEL, e.position.z))
		e.dead = true
		e.visible = false
		return
	e.position.y = h

	if e.speed > 0.0:
		var yaw: float = atan2(-clampf(vxl, -12.0, 12.0), -e.speed)
		e.model_root.rotation.y = lerp_angle(e.model_root.rotation.y, yaw, 1.0 - exp(-8.0 * dt))
	if e.turret != null:
		var dx: float = pp.x - e.position.x
		var dz: float = pp.z - e.position.z
		var want: float = atan2(-dx, -dz) - e.model_root.rotation.y
		e.turret.rotation.y = lerp_angle(e.turret.rotation.y, want, 1.0 - exp(-6.0 * dt))


func _tick_heli(e, dt: float, pp: Vector3) -> void:
	var target_z: float = pp.z - e.hover_ahead
	e.position.z += (-player.fwd_speed + clampf((target_z - e.position.z) * 1.4, -24.0, 24.0)) * dt
	var cx: float = pp.x * 0.5
	var nx: float = cx + sin(e.age * 0.7 + e.phase) * e.amp
	var vxl: float = (nx - e.position.x) / maxf(dt, 0.0001)
	e.position.x = nx
	e.position.y = 9.0 + sin(e.age * 1.7 + e.phase) * 0.7
	e.model_root.rotation.z = lerpf(e.model_root.rotation.z, clampf(-vxl * 0.03, -0.5, 0.5), 1.0 - exp(-6.0 * dt))
	e.model_root.rotation.x = lerpf(e.model_root.rotation.x, -0.12, 1.0 - exp(-4.0 * dt))
	# ramming the player
	if player.alive:
		var dx: float = pp.x - e.position.x
		var dz: float = pp.z - e.position.z
		var rr: float = e.radius + Cfg.PLAYER_RADIUS
		if dx * dx + dz * dz < rr * rr:
			player.take_damage(25.0)
			damage_enemy(e, 99999.0)


# ------------------------------------------------------------------ firing

func _try_fire(e, dt: float, pp: Vector3) -> void:
	if e.dead or not player.alive:
		return
	if e.warn_t > 0.0:
		e.warn_t -= dt
		if e.warn_t <= 0.0:
			e.burst_left = 2 if e.type == "truck" else 1
			e.burst_t = 0.0
		else:
			_warn_puff(e, dt)
			return
	if e.burst_left > 0:
		e.burst_t -= dt
		if e.burst_t <= 0.0:
			_shoot(e)
			e.burst_left -= 1
			e.burst_t = _burst_gap(e.type)
		return
	var ahead: float = pp.z - e.position.z
	var in_view: bool = ahead > 6.0 and ahead < 88.0 and absf(pp.x - e.position.x) < 75.0
	e.fire_t -= dt
	if e.fire_t > 0.0 or not in_view:
		return
	var scale_cd: float = 1.0 - minf(_intensity() * 0.05, 0.35)
	match e.type:
		"jeep":
			e.burst_left = 3
			e.burst_t = 0.0
			e.fire_t = _rng.randf_range(1.9, 2.8) * scale_cd
		"truck":
			e.warn_t = 0.45
			e.fire_t = _rng.randf_range(3.2, 4.4) * scale_cd
		"artillery":
			e.warn_t = 0.6
			e.fire_t = _rng.randf_range(3.4, 4.6) * scale_cd
		_:
			e.burst_left = 3
			e.burst_t = 0.0
			e.fire_t = _rng.randf_range(2.2, 3.2) * scale_cd


func _burst_gap(t: String) -> float:
	if t == "jeep":
		return 0.12
	if t == "truck":
		return 0.4
	return 0.18


func _warn_puff(e, dt: float) -> void:
	if _rng.randf() < dt * 14.0:
		fx.puff(e.position + Vector3(0.0, e.mid_height * 2.0, 0.0), Vector3(0.0, 2.0, 0.0), 0.3, 0.8, 0.2, Color(1.0, 0.25, 0.1, 0.9), Color(1.0, 0.25, 0.1, 0.0))


func _shoot(e) -> void:
	match e.type:
		"jeep":
			_aim_fire(e, Cfg.K_EBULLET, 48.0, 5.0, false, 0.07, Color(1.0, 0.55, 0.2))
		"truck":
			_aim_fire(e, Cfg.K_SHELL, 30.0, 10.0, true, 0.08, Color(1.0, 0.6, 0.2))
		"artillery":
			_aim_fire(e, Cfg.K_SHELL, 38.0, 16.0, true, 0.03, Color(1.0, 0.7, 0.3))
		_:
			_aim_fire(e, Cfg.K_EPLASMA, 40.0, 8.0, true, 0.05, Color(0.95, 0.4, 1.0))


func _aim_fire(e, kind: int, speed: float, dmg: float, lead: bool, err: float, flash_col: Color) -> void:
	var pp: Vector3 = player.position
	var flat := Vector3(pp.x - e.position.x, 0.0, pp.z - e.position.z)
	var src: Vector3 = e.position + Vector3(0.0, e.mid_height * 1.5, 0.0)
	if flat.length_squared() > 0.01:
		src += flat.normalized() * 2.2
	var tgt: Vector3 = pp
	if lead:
		var t_est: float = src.distance_to(pp) / speed
		tgt += Vector3(player.vx, 0.0, -player.fwd_speed) * t_est
	var d: Vector3 = tgt - src
	var dist: float = maxf(d.length(), 1.0)
	var flight: float = dist / speed
	d = d.rotated(Vector3.UP, _rng.randf_range(-err, err))
	projectiles.fire(kind, src, d.normalized() * speed, dmg, flight + 0.7, false)
	fx.muzzle(src, flash_col)
	if _snd_t <= 0.0:
		_snd_t = 0.09
		Feedback.play("eshot", -12.0, _rng.randf_range(0.8, 1.05))


# ------------------------------------------------------------------ damage

func damage_enemy(e, dmg: float) -> void:
	if e.dead:
		return
	e.hp -= dmg
	e.hit_flash()
	if e.hp <= 0.0:
		_kill(e)


## Area damage on the ground plane; `skip` is an enemy that already took the direct hit.
func splash(pos: Vector3, radius: float, dmg: float, skip) -> void:
	for e in list:
		if e.dead or e == skip:
			continue
		var dx: float = e.position.x - pos.x
		var dz: float = e.position.z - pos.z
		var reach: float = radius + e.radius * 0.5
		var d2: float = dx * dx + dz * dz
		if d2 < reach * reach:
			var fall: float = 1.0 - sqrt(d2) / reach * 0.6
			damage_enemy(e, dmg * fall)


func _kill(e) -> void:
	e.dead = true
	e.visible = false
	kills += 1
	enemy_killed.emit(e.points, e.position, e.type)
	var size: float = 1.0
	var gy: float = e.position.y
	if e.type == "truck":
		size = 1.5
	elif e.type == "artillery":
		size = 1.4
	elif e.type == "heli":
		size = 1.9
		gy = world.height_at(e.position.x, e.position.z)
	var center: Vector3 = e.position + Vector3(0.0, e.mid_height, 0.0)
	if e.air:
		fx.explosion(center, size, -999.0)
		fx.explosion(Vector3(e.position.x, gy + 1.0, e.position.z), 1.2, gy)
	else:
		fx.explosion(center, size, gy)
		fx.burning(Vector3(e.position.x, gy + 1.0, e.position.z), 4.0 + size * 1.5, size)
	Feedback.play("boom", -5.0, _rng.randf_range(0.9, 1.15))
	Feedback.vibrate(25)
	shake.emit(0.3 * size)


## Finds the best homing target in front of `pos` for missiles.
func find_target(pos: Vector3, max_dx: float):
	var best = null
	var best_score: float = INF
	for e in list:
		if e.dead:
			continue
		var dz: float = pos.z - e.position.z
		if dz < 4.0 or dz > 110.0:
			continue
		var dx: float = absf(e.position.x - pos.x)
		if dx > max_dx + dz * 0.25:
			continue
		var score: float = dx * 1.4 + dz * 0.5
		if score < best_score:
			best_score = score
			best = e
	return best


# ------------------------------------------------------------------ nukes

func nuke(pos: Vector3) -> void:
	_nukes.append({"pos": pos, "t": 0.0, "hit": {}})


func _step_nukes(dt: float) -> void:
	var i: int = _nukes.size() - 1
	while i >= 0:
		var n: Dictionary = _nukes[i]
		n["t"] = float(n["t"]) + dt
		var reach: float = minf(float(n["t"]) * Cfg.NUKE_SHOCK_SPEED, Cfg.NUKE_RADIUS)
		var np: Vector3 = n["pos"]
		var hit: Dictionary = n["hit"]
		for e in list:
			if e.dead:
				continue
			var id: int = e.get_instance_id()
			if hit.has(id):
				continue
			var d: float = Vector2(e.position.x - np.x, e.position.z - np.z).length()
			if d <= reach:
				hit[id] = true
				if e.air:
					damage_enemy(e, Cfg.NUKE_AIR_DAMAGE)
				else:
					damage_enemy(e, 99999.0)
		if float(n["t"]) * Cfg.NUKE_SHOCK_SPEED >= Cfg.NUKE_RADIUS:
			_nukes.remove_at(i)
		i -= 1
