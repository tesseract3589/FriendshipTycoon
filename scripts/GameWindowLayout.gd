extends RefCounted

const MINIMUM_SIZE := Vector2i(1152, 648)
const MAXIMUM_SIZE := Vector2i(1920, 1080)


static func configure_window(window: Window) -> void:
	if not OS.has_feature("pc"):
		return
	window.min_size = MINIMUM_SIZE
	window.max_size = MAXIMUM_SIZE
	if window.mode == Window.MODE_WINDOWED:
		window.size = window.size.clamp(MINIMUM_SIZE, MAXIMUM_SIZE)


## Keep UI at the minimum window's size; only its placement follows larger windows.
## Smaller mobile screens can still shrink the content to fit.
static func get_ui_layout_size(viewport_size: Vector2) -> Vector2:
	return viewport_size.min(Vector2(MINIMUM_SIZE))
