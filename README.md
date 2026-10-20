# Lambda Wars

[![Android Build](../../actions/workflows/build-android.yml/badge.svg)](../../actions/workflows/build-android.yml)

A top-down low-poly helicopter war game for Android, made with **Godot 4.7** (GDScript, Compatibility renderer).
Fly over an endless procedural battlefield, fight jeeps, trucks, artillery and hostile helicopters, collect weapon
upgrades, missiles and tactical nukes, and unlock new helicopter liveries.

Everything is generated in code: geometry, shaders, sounds and UI. The only asset files are the app icons.

| | |
| --- | --- |
| Engine | Godot **4.7.2** stable (Compatibility / OpenGL renderer) |
| Platform | Android 7.0+ (API 24+), landscape, arm64-v8a and armeabi-v7a |
| Package ID | `com.termorganworks.lambdawars` (change it in `export_presets.cfg` before your first Play upload) |
| Build outputs | debug APK, release APK, release AAB (signed-ready) |

## Controls

| Action | Touch | Keyboard (desktop testing) |
| --- | --- | --- |
| Strafe | joystick, bottom-left | `A` / `D` or arrow keys |
| Fire | **FIRE**, bottom-right | `Space` or `J` |
| Missile | **MSL** button | `M` |
| Nuke | **NUKE** button | `N` |
| Pause / back | pause button, Android back | `Esc` |

## Open and run locally

1. Install [Godot 4.7.2](https://godotengine.org/download) (the standard build, not .NET).
2. Open Godot, choose **Import**, and select `project.godot`.
3. Let the first import finish, then press **F5**. The main scene is `scenes/main.tscn`.

Mouse clicks act as touches, so the on-screen controls also work with a mouse.

## Repository layout

```
project.godot            project settings, autoloads, landscape, Compatibility renderer
export_presets.cfg       three Android export presets (debug APK, release APK, release AAB)
VERSION                  base app version, used by CI (1.0.0)
icon.svg                 project icon
assets/icons/            Android launcher icons (main, adaptive foreground / background / monochrome, Play 512)
scenes/main.tscn         single node; everything else is built in code
scripts/                 game code (core, world, battle, ui, util)
tools/ci_check.gd        loads every script and scene; used by CI to catch parser errors
tools/make_keystore.sh   helper that creates the release keystore and prints the GitHub secrets
.github/workflows/       build-android.yml  (validate, smoke test, build, release)
.github/actions/         setup-godot  (installs Godot and export templates, cached)
DEVELOPMENT_STATUS.md    feature list, tuning cheat sheet, known risks
```

## Put it on GitHub

```bash
git init
git add .
git commit -m "Lambda Wars"
git branch -M main
git remote add origin https://github.com/<your-user>/<your-repo>.git
git push -u origin main
```

Make sure `export_presets.cfg` is committed (it contains no secrets) and `.github/` is included. Then open the
**Actions** tab: the first run starts automatically on push.

## What the automated build does

The workflow `.github/workflows/build-android.yml` runs on every push to `main`/`master`, on pull requests, on version
tags (`v*`), and manually (**Actions > Android Build > Run workflow**).

| Job | When | What it does |
| --- | --- | --- |
| `validate` | always | Installs Godot 4.7.2 and its export templates, imports the project, loads every script and scene (fails on any parser error or missing resource). |
| `smoke-test` | after validate | Plays the game headless for 50 seconds of game time (`--ci-autostart`) and fails if a script error is logged. It is **non-blocking**: a failure shows a warning but does not stop the build. |
| `build` | after validate | Installs JDK 17 and the Android SDK packages the Godot build template asks for, then exports the **debug APK**; on pushes, tags and manual runs also the **release APK** and **release AAB**. Verifies signatures and writes `SHA256SUMS.txt`. |
| `release` | on `v*` tags | Publishes a GitHub Release with the release APK, AAB and checksums. |

Pull requests only build the debug APK (secrets are not available to forks).

Download the files from the run page under **Artifacts** (`lambda-wars-android-<version>`).

### Versioning

* `VERSION` holds the base version (for example `1.0.0`).
* Branch builds are named `1.0.0-dev.<run number>`; tag builds use the tag (`v1.2.0` becomes `1.2.0`).
* Android `versionCode` = GitHub run number + `VERSION_CODE_OFFSET` (set at the top of the workflow, default `0`).
  Google Play requires every upload to have a higher code, so raise the offset if you already published builds.

## Signing release builds

Without secrets, release builds are still produced but are signed with a throw-away **debug key**: they install fine
for testing, but Google Play will not accept them. Tag builds refuse to run without real signing secrets.

### 1. Create a release keystore (once)

Easiest: run the helper (needs a JDK 17+ for `keytool`):

```bash
./tools/make_keystore.sh lambda-wars-release.keystore lambdawars
```

It asks for a password and prints the three secret values. Or do it by hand:

```bash
keytool -genkeypair -v -keystore lambda-wars-release.keystore -storetype PKCS12 \
  -alias lambdawars -keyalg RSA -keysize 2048 -validity 10000
```

Use **one password for both the store and the key** (Godot takes a single password; PKCS12 keystores do this by default).

> Back up the keystore file and password somewhere safe (not in git). `.gitignore` already blocks `*.keystore` and `*.jks`.

### 2. Convert it to base64

| System | Command |
| --- | --- |
| Linux | `base64 -w0 lambda-wars-release.keystore` |
| macOS | `base64 -i lambda-wars-release.keystore \| pbcopy` |
| Windows PowerShell | `[Convert]::ToBase64String([IO.File]::ReadAllBytes("lambda-wars-release.keystore")) \| Set-Clipboard` |

### 3. Add the repository secrets

**Settings > Secrets and variables > Actions > New repository secret**

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | the base64 text of the keystore file |
| `ANDROID_KEYSTORE_ALIAS` | the key alias, for example `lambdawars` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore / key password |

With the GitHub CLI:

```bash
base64 -w0 lambda-wars-release.keystore | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_ALIAS --body "lambdawars"
gh secret set ANDROID_KEYSTORE_PASSWORD
```

The workflow checks the secrets against the keystore before building, so a typo fails early with a clear message.
After a release build, the job log prints the signing certificate (`apksigner verify --print-certs`).

### Google Play notes

* Upload the **AAB** (`*-release.aab`), not the APK.
* Enrol in **Play App Signing** (recommended). Your keystore then acts as the *upload key*, and Google holds the real
  app signing key, so a lost upload key can be reset.
* The package ID cannot change after the first upload. Edit `package/unique_name` in `export_presets.cfg` first if you
  want a different one.

## Publishing a release

```bash
# 1. edit VERSION if you want a new base version, commit it
# 2. tag and push
git tag v1.0.0
git push origin v1.0.0
```

The tag build signs with your release key and creates a GitHub Release with the APK, AAB and checksums.

## Installing a build on a phone

```bash
adb install -r lambda-wars-1.0.0-debug.apk
```

or copy the APK to the device and open it (allow installs from your file manager when asked).

## Customising the pipeline

| Change | Where |
| --- | --- |
| Godot version | `GODOT_VERSION` at the top of `.github/workflows/build-android.yml`, plus the version in `config/features` of `project.godot` (open the project once in that editor version to update it) |
| JDK | `JAVA_VERSION` in the workflow (Godot 4.7 needs 17 or newer) |
| Android SDK / NDK | read automatically from Godot's build template; fallbacks are the `ANDROID_FALLBACK_*` variables |
| App name, package ID, architectures, permissions | `export_presets.cfg` (or **Project > Export** in the editor) |
| Icons | files in `assets/icons/`, referenced from the presets |
| Graphics detail | in game: **Settings > Graphics** (Low / Medium / High) |

## Export from the command line (optional)

After installing the export templates and the Android build template in your editor, and configuring the Android SDK
and JDK paths in **Editor Settings > Export > Android**:

```bash
godot --headless --path . --import
godot --headless --path . --export-debug   "Android Debug APK"   build/lambda-wars-debug.apk
godot --headless --path . --export-release "Android Release APK" build/lambda-wars-release.apk
godot --headless --path . --export-release "Android Release AAB" build/lambda-wars-release.aab
```

Release exports read the keystore from the environment: `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
`GODOT_ANDROID_KEYSTORE_RELEASE_USER` (the alias) and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`.

To run the same checks as CI locally:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/ci_check.gd
godot --headless --path . --fixed-fps 60 --quit-after 3000 -- --ci-autostart
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `validate` fails with a parser error | The log names the script and line. Open the project in Godot 4.7.2 and fix it, or send the log. |
| Release build says it used the debug key | The three signing secrets are missing or empty. Add them (see above). |
| `keytool` error "password was incorrect" in *Prepare release signing* | `ANDROID_KEYSTORE_PASSWORD` or `ANDROID_KEYSTORE_ALIAS` does not match the keystore. |
| Tag build fails immediately in *Prepare release signing* | Tag builds require the secrets on purpose, so an unsigned build is never published. |
| `Could not download` the Godot editor | Check that `GODOT_VERSION` exists as a release on github.com/godotengine/godot/releases. |
| "No export template found" (local) | **Editor > Manage Export Templates > Download and Install**. |
| "Android build template version mismatch" (local) | **Project > Install Android Build Template**. CI installs it automatically. |
| "Target platform requires ETC2/ASTC texture compression" | Already enabled in `project.godot`; do not turn it off. |
| Gradle / SDK errors in the AAB export | Open the *Export release AAB* log. The SDK packages are installed from Godot's own `config.gradle`, so a version bump of Godot normally needs no changes. |
| GitHub Release step: "Resource not accessible by integration" | **Settings > Actions > General > Workflow permissions**: allow read and write, or allow the workflow's `contents: write`. |
| `smoke-test` shows a warning | It is informational. Open its log to see the script error that was reported. |

## Licence

Add a `LICENSE` file with the terms you want before making the repository public. Until then all rights are reserved.
