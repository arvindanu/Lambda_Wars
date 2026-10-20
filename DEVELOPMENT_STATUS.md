# Lambda Wars - Development Status

Android helicopter combat game, Godot 4.x (GDScript), Compatibility renderer, landscape.
All geometry, sounds and UI are generated in code: the project has **no external art or audio assets**.

## How to run

1. Open `project.godot` in Godot 4.7 (4.7.2 is what CI uses).
2. Let the first import finish, then press Play. Main scene: `scenes/main.tscn`.
3. Desktop test controls: A/D or arrow keys to strafe, Space or J to fire, M missile, N nuke, Esc pause/back.
   Mouse clicks are emulated as touches, so the on-screen joystick and buttons also work with a mouse.

## Android export

1. Editor > Manage Export Templates, install templates for your Godot version.
2. Project > Install Android Build Template (needed for custom permissions).
3. Project > Export > Add > Android. Enable **Use Gradle Build** if you installed the template.
4. Under Permissions tick **Vibrate** (haptics).
5. Screen orientation is already set to sensor-landscape in `project.godot`. Textures use ETC2/ASTC import.
6. Set a package name, keystore (debug keystore is fine for testing) and export the APK / AAB.

## Structure

```
project.godot            settings, autoloads (GameState, Feedback), landscape, Compatibility renderer
scenes/main.tscn         single node running scripts/main.gd (everything else is built in code)
scripts/main.gd          scene construction, state machine (title / play / game over / pause / hangar), frame order
scripts/core/
  config.gd              ALL tuning constants (speeds, timers, weapon tiers, enemy stats)
  game_state.gd          autoload: saved points, best score, skins + unlock costs, settings
  feedback.gd            autoload: synthesized sound effects, rotor loop, haptics
scripts/world/
  world.gd               infinite chunked terrain: hills, mountains, rivers, roads, biomes, props
  day_night.gd           morning -> day -> evening -> dusk -> night -> dawn light/sky/fog cycle
scripts/battle/
  player.gd              helicopter: strafing, banking, weapon tiers, missiles, nukes, armour
  heli_model.gd          low-poly helicopter builder (player skins and enemy helicopters)
  enemy_models.gd        jeep, truck, artillery models
  enemy.gd / enemies.gd  enemy unit + manager (spawning, AI, firing, kills, nuke shockwave)
  projectiles.gd         pooled bullets / lasers / alien energy / missiles / nukes / shells
  pickups.gd             floating drops + spawn timers
  effects.gd             pooled explosions, smoke, debris, flashes, shock rings, scorch marks
scripts/ui/
  touch_controls.gd      multitouch joystick + FIRE / MISSILE / NUKE buttons + pause
  hud.gd                 armour, score, weapon tier, supply timers, toasts, damage vignette
  menus.gd               title, hangar (skins), pause, game over, settings
scripts/util/            mesh_builder.gd (flat-shaded meshes with baked AO), mesh_kit.gd, safe_area.gd,
                         shaders.gd (terrain / water / sky shaders), ui_style.gd (fonts, palette, drawing helpers)
scripts/world/ambient_fx.gd  drifting dust / embers / fireflies
```

## Completed features

- **Camera / view:** high-angle top-down follow camera, helicopter held near bottom-centre, landscape.
- **World:** infinite streamed terrain (hills, mountains, snow caps, rivers with reflective water, winding roads
  with markings, grass / desert / forest biomes, trees, rocks, houses, ruins, wrecks, craters).
  Fog hides chunk edges. Real directional shadows (toggle in Settings) with a blob-shadow fallback.
- **Day / night:** 6-minute smooth cycle (morning, day, evening, dusk, night, dawn) driving sun, sky, ambient light, fog.
- **Controls:** bottom-left joystick (horizontal strafing with inertia and banking), bottom-right FIRE, MISSILE, NUKE,
  separate large touch targets, full multitouch, safe-area aware, keyboard fallback on desktop.
- **Primary weapon tiers:** standard bullets (1-2 barrels) -> lasers (2-3 barrels, pierce) -> alien energy
  (2-3 barrels, splash). Weapon pickups raise the tier for 40 s per level.
- **Missiles:** homing, splash damage, smoke trails, 1 s cooldown. Supply crate about every 3 minutes (+5), 3 at start.
- **Nukes:** bomb flies ahead, detonates with flash, expanding shockwave, mushroom cloud, debris and screen shake.
  Kills every ground enemy inside the 65 unit radius as the wave reaches it, damages air units, clears enemy fire.
  Supply crate about every 8 minutes, 1 at start. Cooldowns and ammo shown on the buttons; supply countdowns on the HUD.
- **Enemies:** armed jeeps (fast bursts), trucks (rocket shells, convoy on roads), artillery (telegraphed lobbed shells),
  hostile helicopters (alien plasma bursts, ram damage). Difficulty ramps with play time.
- **Pickups:** weapon, missile, nuke, armour repair. Floating with rings and a ground beam as a depth cue, mild magnet pull,
  a missed missile/nuke crate is re-dropped after 14 s.
- **Progression:** points = distance + kills. Lifetime points unlock 7 helicopter skins, previewed live in the Hangar.
- **Persistence:** best score, lifetime points, selected skin and settings saved to `user://lambda_wars.cfg`.
- **Audio / haptics:** every sound synthesized at start-up; vibration on hits, explosions, missiles, nukes.
- **Lifecycle:** auto-pause when the app loses focus; Android back button handled (pause / menu back / quit on title).


## Visual pass v2 (presentation only - no gameplay changes)

Gameplay constants (`config.gd`), AI, damage, hit radii, timers, controls and progression are unchanged.
The only edits to gameplay scripts are cosmetic hooks (smoke, glow, blinking lights).

**Rendering note:** the project uses the Compatibility renderer for Android. It has no screen-space ambient
occlusion or screen-space reflections, so those looks are produced another way:
- Ambient occlusion: baked into vertex colours (valleys darker, tree/rock/house bases darker) plus contact shadows.
- Reflections: the water reflects a real-time procedural sky (sun, moon, clouds, stars) through the engine's sky radiance.

**Lighting and atmosphere**
- Custom sky shader with gradient, clouds, stars at night and sun / moon disc; reflected by the water.
- Six distinct moods (morning, day, evening, dusk, night, dawn): sun colour and angle, ambient, fog colour and
  density, sun-scatter, tonemap exposure, saturation / contrast, screen colour grade, vignette strength and
  ambient particles (dust by day, embers at dusk, fireflies at night).
- Soft directional shadows (2 cascades on High), filmic tonemapping, optional glow on High, MSAA by quality.

**Environment**
- Terrain: per-vertex baked AO, slope-based rock, grass / lush / dirt / desert / forest patches, detail-noise shader,
  snow caps, sandy wet riverbanks.
- Roads: crisp asphalt ribbon with edge lines and dashes, roadside posts, bridges with parapets where they cross rivers.
- Rivers: translucent shoreline water with foam, depth tint and animated wave normals (sun glints and sky reflection).
- Props: wind-swayed trees, bushes, reeds and grass, houses with windows and chimneys, ruins, tank wrecks, tents,
  sandbags, tank traps, barrels, watchtowers, craters. Chunks build in two stages so phones do not hitch.

**Combat effects**
- Additive fire / sparks / muzzle flashes, layered explosions (flash, fireball, smoke, sparks, debris with smoke trails,
  ground shock ring and dust), scorch marks, burning wrecks that smoke where they fell.
- Projectiles have bright cores with glowing halos; missiles and nukes have flickering engine flames.
- Bigger nuke: triple flash, three shock rings, stalk and cap in fire and smoke, spark shower.
- Helicopter: livery stripes, shaded belly, sensor turret, weapon-pod rocket tubes, blinking navigation lights,
  exhaust shimmer, and smoke / fire when badly damaged. Damaged enemies trail smoke.
- Pickups: glow halo, sparkles and a ground landing marker.

**HUD and controls**
- Glass tactical panels with chamfered corners, system condensed fonts, monospaced numbers.
- Hull bar with trailing damage ghost, animated score counter, weapon module with tier flash and power timer shimmer,
  supply countdowns with progress bars, time-of-day strip, slide-in toast banners, floating kill scores, soft edge
  vignettes for damage and low armour.
- Touch controls: same layout and hit areas, now with glow, direction chevrons, cooldown sweep, ready pulse,
  ammo badges and press feedback.

**Menus**
- Loading screen with progress, cinematic low-angle title camera that blends into the gameplay camera on Deploy,
  staggered slide-in buttons, page fades, hazard-stripe backdrops, UI sounds.
- Hangar: hover pad with light cone and rim light, slow camera orbit, colour swatches, lock icons, progress bar to the
  next unlock. Mission report: animated score count-up, stat blocks, pulsing NEW BEST.
- Settings: haptics, shadows, **graphics quality** (Low / Medium / High) and volume.

**Performance**
- Quality levels: Low = plain materials, no halos / particles / grading, fewer effects. Medium = shaders, 2x MSAA, ambient
  particles, grading. High = adds glow, 2-cascade shadows (4x MSAA on desktop).
- Default is Medium on phones, High on desktop. If the frame rate stays under 40 FPS for several seconds the game
  lowers one level automatically and says so.
- Sky reflection and atmosphere update about 5 times per second; all effects use fixed pools.
- `lambda_wars_v1_gameplay_only.zip` is the previous visual version, kept as a fallback.


## Compact controls and HUD (final pass)

- Joystick, FIRE, MSL, NUKE and pause buttons are about 16% smaller (joystick 88, fire 76, missile / nuke 52, pause 29
  units on the 720-unit-high canvas). Button **centres are unchanged**, so thumbs land where they did before; the gaps
  between buttons grew from about 36 to about 60 units.
- Touch targets stay generous: hit radius is 1.4x the drawn radius, the joystick keeps nearly the same thumb travel
  (100 units for full deflection), and the pause button has a 1.7x hit radius.
- HUD panels are about 14% smaller (hull 286x70, weapon 360x70, supply 252x70), with smaller icons, bars and toasts.
  Text stays at 12 units or larger so it remains readable on phones.
- Gameplay, button behaviour and all visual effects are unchanged.

## Repository and CI

- `export_presets.cfg` with three Android presets, `assets/icons/` launcher icons, `VERSION`, `.gitignore`,
  `.gitattributes`, `.editorconfig`.
- `.github/workflows/build-android.yml`: validate (import + load every script), headless smoke test (non-blocking),
  build (debug APK, release APK, release AAB, signature check, checksums), release (GitHub Release on `v*` tags).
- `.github/actions/setup-godot`: cached install of Godot 4.7.2 and its export templates.
- Signing from repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`;
  falls back to the debug key on branches and refuses to build tags without them. See `README.md`.
- `tools/ci_check.gd` (parser / resource check) and `tools/make_keystore.sh` (keystore + secret helper).
- `main.gd` contains one inert test hook: `--ci-autostart` (only passed by the CI smoke test).

## Known issues / risks

- **Not yet run in the Godot editor** (this applies to both passes). The engine was not available while writing this code, so it was checked by
  careful review and static scripts only (constant/path cross-checks, bracket and indentation checks). Expect that a
  first run may surface a small parser or runtime error. Send the exact error text and it can be fixed quickly.
- Balance numbers (damage, spawn rates, supply timers) are first-pass defaults, all in `scripts/core/config.gd`.
- Start-up builds about 30 terrain chunks at once, so expect a brief pause on low-end phones before the title appears.
- The new shaders (terrain, water, sky) are the most likely place for a first-run error; they are plain Godot 4
  spatial / sky shaders. If one fails, set Graphics to Low (plain materials) to keep playing and send the shader error.
- Sounds are simple synthesized effects; swap in recorded audio later through `feedback.gd` if desired.

## Remaining tasks

1. First on-device pass: tune joystick feel, camera height, enemy density, fog distance.
2. Profile on a mid-range Android phone (chunk count in `config.gd`: `COL_MIN`, `COL_MAX`, `ROWS_AHEAD`).
3. Add enemy fighter jets / more vehicle variety if wanted.
4. Final app icon and splash screen, store listing assets.
5. Optional: music, tutorial overlay, more skins.

## Tuning cheat sheet (`scripts/core/config.gd`)

| Want to change | Constant |
| --- | --- |
| Missile / nuke supply timing | `MISSILE_SPAWN_INTERVAL`, `NUKE_SPAWN_INTERVAL` (seconds of play) |
| Starting ammo | `START_MISSILES`, `START_NUKES` |
| Nuke size / speed of shockwave | `NUKE_RADIUS`, `NUKE_SHOCK_SPEED` |
| Weapon stats per tier | `TIERS` |
| Enemy health / score | `ENEMIES` |
| Skin unlock costs | `SKINS` in `game_state.gd` |
| Day length | `DAY_LENGTH` |
| Draw distance / performance | `COL_MIN`, `COL_MAX`, `ROWS_AHEAD`, `CHUNK_CELLS` |
