extends RefCounted
## Central tuning values for Lambda Wars.
## Usage: const Cfg = preload("res://scripts/core/config.gd")

# ---- Game modes ----
const MODE_ATTRACT: int = 0
const MODE_PLAY: int = 1
const MODE_OVER: int = 2

# ---- Player / lane ----
const LANE_HALF: float = 34.0
const FWD_SPEED_MIN: float = 18.0
const FWD_SPEED_MAX: float = 27.0
const STRAFE_SPEED: float = 30.0
const STRAFE_ACCEL: float = 110.0
const HELI_MAX_HP: float = 100.0
const HELI_HOVER: float = 18.0

# ---- Camera (high-angle, top-down) ----
const CAM_FOLLOW: float = 0.35
const CAM_HEIGHT: float = 46.0
const CAM_BACK: float = 11.0
const CAM_PITCH: float = -52.0
const CAM_FOV: float = 54.0

# ---- World streaming ----
const CHUNK_SIZE: float = 48.0
const CHUNK_CELLS: int = 16
const COL_MIN: int = -3
const COL_MAX: int = 2
const ROWS_AHEAD: int = 3
const ROWS_BEHIND: int = 1
const WATER_LEVEL: float = 0.0
const DAY_LENGTH: float = 360.0

# ---- Spawning ----
const PICKUP_SPAWN_AHEAD: float = 100.0
const ENEMY_SPAWN_AHEAD: float = 112.0
const ENEMY_DESPAWN_BEHIND: float = 30.0

# ---- Pickup timing (seconds of active play) ----
const MISSILE_SPAWN_INTERVAL: float = 180.0
const NUKE_SPAWN_INTERVAL: float = 480.0
const WEAPON_SPAWN_INTERVAL: float = 55.0
const REPAIR_SPAWN_INTERVAL: float = 80.0

# ---- Special weapons ----
const START_MISSILES: int = 3
const START_NUKES: int = 1
const MISSILE_PICKUP_AMOUNT: int = 5
const NUKE_PICKUP_AMOUNT: int = 1
const MAX_MISSILES: int = 20
const MAX_NUKES: int = 3
const MISSILE_COOLDOWN: float = 1.0
const NUKE_COOLDOWN: float = 5.0
const MISSILE_DAMAGE: float = 160.0
const MISSILE_SPLASH: float = 8.0
const MISSILE_ACCEL: float = 70.0
const NUKE_RADIUS: float = 65.0
const NUKE_SHOCK_SPEED: float = 85.0
const NUKE_AIR_DAMAGE: float = 70.0
const WEAPON_POWER_TIME: float = 40.0
const REPAIR_AMOUNT: float = 35.0

# ---- Projectile kinds ----
const K_BULLET: int = 0
const K_LASER: int = 1
const K_PLASMA: int = 2
const K_MISSILE: int = 3
const K_NUKE: int = 4
const K_SHELL: int = 5
const K_EBULLET: int = 6
const K_EPLASMA: int = 7

# ---- Pickup kinds ----
const P_WEAPON: int = 0
const P_MISSILE: int = 1
const P_NUKE: int = 2
const P_REPAIR: int = 3

# ---- Primary weapon tiers (standard bullets -> laser -> alien energy) ----
const TIERS: Array = [
	{"name": "BULLETS", "kind": 0, "barrels": 1, "damage": 9.0, "rate": 0.16, "speed": 90.0, "pierce": 0, "splash": 0.0},
	{"name": "BULLETS", "kind": 0, "barrels": 2, "damage": 9.0, "rate": 0.15, "speed": 90.0, "pierce": 0, "splash": 0.0},
	{"name": "LASER", "kind": 1, "barrels": 2, "damage": 14.0, "rate": 0.17, "speed": 135.0, "pierce": 1, "splash": 0.0},
	{"name": "LASER", "kind": 1, "barrels": 3, "damage": 14.0, "rate": 0.16, "speed": 135.0, "pierce": 1, "splash": 0.0},
	{"name": "ALIEN ENERGY", "kind": 2, "barrels": 2, "damage": 26.0, "rate": 0.30, "speed": 62.0, "pierce": 0, "splash": 3.5},
	{"name": "ALIEN ENERGY", "kind": 2, "barrels": 3, "damage": 26.0, "rate": 0.27, "speed": 62.0, "pierce": 0, "splash": 3.5},
]

# ---- Enemies ----
const ENEMIES: Dictionary = {
	"jeep": {"hp": 40.0, "radius": 2.3, "score": 60, "speed": 9.0, "air": false},
	"truck": {"hp": 140.0, "radius": 3.1, "score": 110, "speed": 6.0, "air": false},
	"artillery": {"hp": 90.0, "radius": 3.0, "score": 140, "speed": 0.0, "air": false},
	"heli": {"hp": 170.0, "radius": 3.6, "score": 260, "speed": 0.0, "air": true},
}

# ---- Scoring ----
const UNITS_PER_POINT: float = 5.0

# ---- Player ----
const PLAYER_RADIUS: float = 2.0
const MAX_TIER: int = 5
