extends RefCounted


static func prepare_viewport(context: Node) -> void:
	# A standalone headless scene starts at 64x64, unlike the real main scene.
	var layout = preload("res://scripts/GameWindowLayout.gd")
	layout.configure_window(context.get_window())
	context.get_window().size = layout.MINIMUM_SIZE


## Exercise the real shop gate instead of showing a locked batch panel directly.
static func unlock_batch_upgrade() -> bool:
	if PrestigeManager.is_feature_unlocked(&"batch_upgrade_panel"):
		return true
	PrestigeManager.unlock_jjam()
	if not PrestigeManager.jjam_prestige():
		return false
	return PrestigeManager.purchase_shop_item("batch_upgrade_panel")
