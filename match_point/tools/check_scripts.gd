extends SceneTree
## فحص تحليل كل السكربتات: godot --headless --path . --script tools/check_scripts.gd
func _init() -> void:
	var files := ["res://scripts/core/ball_physics.gd", "res://scripts/core/shot_solver.gd", "res://scripts/core/player_profile.gd",
		"res://scripts/game/player_rig.gd", "res://scripts/game/player.gd", "res://scripts/game/ball.gd", "res://scripts/game/match.gd",
		"res://scripts/game/ai_controller.gd", "res://scripts/game/human_controller.gd", "res://scripts/ui/hud.gd", "res://scripts/ui/qte_bar.gd",
		"res://scripts/ui/menus.gd", "res://scripts/world/arena.gd", "res://scripts/world/human_look.gd", "res://scripts/main.gd"]
	for f in files:
		var s = load(f)
		print(f, " -> ", "OK" if s != null else "FAIL")
	quit()
