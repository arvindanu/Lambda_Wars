extends Node
## Audio + haptics (autoload "Feedback"). All sounds are synthesized at startup,
## so the project needs no external audio files.

const RATE: int = 22050

var _sounds: Dictionary = {}
var _players: Array = []
var _next: int = 0
var _rotor: AudioStreamPlayer = null
var _vibe_until_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sounds["shot"] = _synth(0, 0.11)
	_sounds["laser"] = _synth(1, 0.22)
	_sounds["plasma"] = _synth(2, 0.28)
	_sounds["eshot"] = _synth(3, 0.12)
	_sounds["missile"] = _synth(4, 0.7)
	_sounds["boom"] = _synth(5, 0.9)
	_sounds["nuke"] = _synth(6, 2.4)
	_sounds["pickup"] = _synth(7, 0.35)
	_sounds["hit"] = _synth(8, 0.1)
	_sounds["click"] = _synth(9, 0.06)
	_sounds["warn"] = _synth(10, 0.4)
	_sounds["rotor"] = _synth(11, 0.4)
	_sounds["ui_in"] = _synth(12, 0.28)
	_sounds["ui_back"] = _synth(13, 0.2)
	for i in range(10):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_rotor = AudioStreamPlayer.new()
	_rotor.stream = _sounds["rotor"]
	_rotor.volume_db = -80.0
	add_child(_rotor)


func play(sound_name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if GameState.volume <= 0.01 or not _sounds.has(sound_name):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[sound_name]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func vibrate(ms: int) -> void:
	if not GameState.haptics:
		return
	var now: int = Time.get_ticks_msec()
	if now < _vibe_until_ms:
		return
	_vibe_until_ms = now + ms + 25
	Input.vibrate_handheld(ms)


func rotor_start() -> void:
	if _rotor != null and not _rotor.playing:
		_rotor.play()


func rotor_stop() -> void:
	if _rotor != null:
		_rotor.stop()


func rotor_level(level: float) -> void:
	if _rotor == null:
		return
	var v: float = clampf(level, 0.0, 1.0)
	_rotor.volume_db = linear_to_db(maxf(0.0001, v * 0.3))
	_rotor.pitch_scale = 0.75 + v * 0.45


## Builds one 16-bit mono sound. id selects the recipe.
func _synth(id: int, dur: float) -> AudioStreamWAV:
	var n: int = int(dur * float(RATE))
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9000 + id
	var lp: float = 0.0
	var phase: float = 0.0
	for i in range(n):
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		var inv: float = 1.0 - u
		var nz: float = rng.randf() * 2.0 - 1.0
		var s: float = 0.0
		if id == 0:
			lp += (nz - lp) * 0.55
			s = lp * pow(inv, 3.0) * 0.8 + sin(t * TAU * 180.0 * inv) * inv * inv * 0.5
		elif id == 1:
			phase += TAU * (1600.0 - 1100.0 * u) / float(RATE)
			s = sin(phase) * pow(inv, 1.2) * 0.5
		elif id == 2:
			phase += TAU * (420.0 + 120.0 * sin(t * 60.0) - 200.0 * u) / float(RATE)
			s = (sin(phase) + 0.5 * sin(phase * 2.01)) * pow(inv, 1.5) * 0.4
		elif id == 3:
			lp += (nz - lp) * 0.3
			s = lp * pow(inv, 2.5) * 0.6 + sin(t * TAU * 140.0) * inv * 0.3
		elif id == 4:
			lp += (nz - lp) * 0.12
			s = lp * minf(u * 12.0, 1.0) * pow(inv, 1.1) * 1.2
		elif id == 5:
			lp += (nz - lp) * 0.12
			s = lp * pow(inv, 2.2) * 1.6 + sin(t * TAU * 55.0 * (1.0 - u * 0.7)) * pow(inv, 1.6) * 0.7
		elif id == 6:
			lp += (nz - lp) * 0.04
			s = lp * pow(inv, 1.4) * 2.4 + sin(t * TAU * 38.0 * (1.0 - u * 0.6)) * pow(inv, 1.2) * 0.9
		elif id == 7:
			var f: float = 660.0 if u < 0.4 else 990.0
			phase += TAU * f / float(RATE)
			s = sin(phase) * inv * 0.5
		elif id == 8:
			lp += (nz - lp) * 0.7
			s = lp * inv * inv * 0.7
		elif id == 9:
			s = sin(t * TAU * 900.0) * pow(inv, 3.0) * 0.5
		elif id == 10:
			var on: bool = (u < 0.35) or (u > 0.5 and u < 0.85)
			s = sin(t * TAU * 880.0) * 0.4 if on else 0.0
		elif id == 12:
			phase += TAU * (300.0 + 700.0 * u) / float(RATE)
			s = sin(phase) * sin(u * PI) * 0.28
		elif id == 13:
			phase += TAU * (620.0 - 380.0 * u) / float(RATE)
			s = sin(phase) * pow(inv, 1.5) * 0.3
		else:
			lp += (nz - lp) * 0.2
			var pulse: float = 0.55 + 0.45 * sin(t * TAU * 25.0)
			s = (sin(t * TAU * 50.0) * 0.6 + lp * 0.25) * pulse
		s = clampf(s, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if id == 11:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w
