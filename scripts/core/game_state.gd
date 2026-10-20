extends Node
## Persistent progression + settings (autoload "GameState").

const SAVE_PATH: String = "user://lambda_wars.cfg"

# Skins unlock once lifetime points reach "cost" (points are never spent).
const SKINS: Array = [
	{"name": "OLIVE DRAB", "cost": 0, "body": Color(0.31, 0.38, 0.20), "accent": Color(0.15, 0.18, 0.10), "glass": Color(0.45, 0.70, 0.80), "glow": 0.0},
	{"name": "DESERT STORM", "cost": 1500, "body": Color(0.72, 0.60, 0.38), "accent": Color(0.40, 0.30, 0.18), "glass": Color(0.55, 0.75, 0.85), "glow": 0.0},
	{"name": "ARCTIC OPS", "cost": 4000, "body": Color(0.88, 0.90, 0.94), "accent": Color(0.35, 0.45, 0.60), "glass": Color(0.40, 0.65, 0.85), "glow": 0.0},
	{"name": "NIGHT RAVEN", "cost": 8500, "body": Color(0.10, 0.10, 0.13), "accent": Color(0.28, 0.28, 0.33), "glass": Color(0.20, 0.45, 0.60), "glow": 0.0},
	{"name": "CRIMSON VIPER", "cost": 15000, "body": Color(0.65, 0.10, 0.10), "accent": Color(0.15, 0.15, 0.15), "glass": Color(0.80, 0.85, 0.90), "glow": 0.0},
	{"name": "GOLD STANDARD", "cost": 25000, "body": Color(0.85, 0.65, 0.15), "accent": Color(0.25, 0.20, 0.10), "glass": Color(0.70, 0.85, 0.90), "glow": 0.12},
	{"name": "NEON SPECTER", "cost": 40000, "body": Color(0.08, 0.10, 0.20), "accent": Color(0.10, 0.90, 0.90), "glass": Color(0.30, 0.90, 1.00), "glow": 0.6},
]

var total_points: int = 0
var best_score: int = 0
var selected_skin: int = 0
var haptics: bool = true
var shadows: bool = true
## 0 = low, 1 = medium, 2 = high (visual detail only)
var quality: int = 1 if OS.has_feature("mobile") else 2
var volume: float = 0.8


func _ready() -> void:
	load_data()
	apply_volume()


func is_unlocked(index: int) -> bool:
	if index < 0 or index >= SKINS.size():
		return false
	return total_points >= int(SKINS[index]["cost"])


func load_data() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	total_points = int(cf.get_value("progress", "total_points", 0))
	best_score = int(cf.get_value("progress", "best_score", 0))
	selected_skin = int(cf.get_value("progress", "skin", 0))
	haptics = bool(cf.get_value("settings", "haptics", true))
	shadows = bool(cf.get_value("settings", "shadows", true))
	quality = clampi(int(cf.get_value("settings", "quality", quality)), 0, 2)
	volume = float(cf.get_value("settings", "volume", 0.8))
	selected_skin = clampi(selected_skin, 0, SKINS.size() - 1)
	if not is_unlocked(selected_skin):
		selected_skin = 0


func save_data() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "total_points", total_points)
	cf.set_value("progress", "best_score", best_score)
	cf.set_value("progress", "skin", selected_skin)
	cf.set_value("settings", "haptics", haptics)
	cf.set_value("settings", "shadows", shadows)
	cf.set_value("settings", "quality", quality)
	cf.set_value("settings", "volume", volume)
	cf.save(SAVE_PATH)


func apply_volume() -> void:
	AudioServer.set_bus_mute(0, volume <= 0.01)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.01)))


## Adds the run's score to lifetime points. Returns {"unlocked": [names], "new_best": bool}.
func commit_run(score: int) -> Dictionary:
	var before: int = total_points
	total_points += score
	var new_best: bool = score > best_score
	if new_best:
		best_score = score
	var unlocked: Array = []
	for i in range(SKINS.size()):
		var c: int = int(SKINS[i]["cost"])
		if before < c and total_points >= c:
			unlocked.append(String(SKINS[i]["name"]))
	save_data()
	return {"unlocked": unlocked, "new_best": new_best}
