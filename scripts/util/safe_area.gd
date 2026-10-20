extends RefCounted
## Converts the OS safe area (notches, rounded corners, gesture bars) into UI-space insets.


## Returns Vector4(left, top, right, bottom) in canvas units for a UI of size `ui_size`.
static func insets(ui_size: Vector2) -> Vector4:
	var win: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var sx: float = ui_size.x / float(win.x)
	var sy: float = ui_size.y / float(win.y)
	var left: float = maxf(0.0, float(safe.position.x)) * sx
	var top: float = maxf(0.0, float(safe.position.y)) * sy
	var right: float = maxf(0.0, float(win.x - (safe.position.x + safe.size.x))) * sx
	var bottom: float = maxf(0.0, float(win.y - (safe.position.y + safe.size.y))) * sy
	return Vector4(minf(left, 140.0), minf(top, 80.0), minf(right, 140.0), minf(bottom, 80.0))
