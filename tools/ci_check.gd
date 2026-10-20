extends SceneTree
## CI helper (run with: godot --headless --path . --script res://tools/ci_check.gd).
## Loads every script and scene of the project and exits with code 1 if any of them fails to
## load or compile, so parser errors and missing resources fail the build early.

const ROOTS: Array = ["res://scripts", "res://scenes", "res://tools"]


func _init() -> void:
	var files: Array = []
	for root in ROOTS:
		_collect(String(root), files)
	files.sort()
	var failures: int = 0
	for path in files:
		var res: Resource = load(String(path))
		if res == null:
			printerr("CI CHECK FAILED: cannot load ", path)
			failures += 1
			continue
		if res is GDScript:
			var script: GDScript = res
			if not script.can_instantiate():
				printerr("CI CHECK FAILED: script does not compile: ", path)
				failures += 1
	print("CI CHECK: %d files checked, %d failures" % [files.size(), failures])
	quit(1 if failures > 0 else 0)


func _collect(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)
