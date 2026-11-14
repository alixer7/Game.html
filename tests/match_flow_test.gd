extends Node
## Runs the real main scene through a full match (player car driven by a bot).
## godot --headless --path . --fixed-fps 60 res://tests/match_flow_test.tscn
var main: Node
var started := false
var t := 0.0
var last_state := -1
var states_seen := {}
var limit := 400.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.data["tutorial_seen"] = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _process(delta: float) -> void:
	t += delta
	if not started and t > 1.0:
		started = true
		main._start_match({"size": 2, "difficulty": 2, "minutes": 1, "team": 0})
		var m: MatchController = main.match_ctrl
		var pc := m.player_car
		m.world.controllers[pc.id] = BotController.new(pc, m.world, m.pred, m.coord, 2)
		m.ended.connect(func(res): print("ENDED score=", res["score"], " stats=", res["stats"]))
	if started and main.match_ctrl:
		var m: MatchController = main.match_ctrl
		if m.state != last_state:
			last_state = m.state
			states_seen[m.state] = true
			print("%.1f state=%s score=%s time_left=%.1f ot=%s" % [t, MatchController.State.keys()[m.state], m.score, m.time_left, m.overtime])
		if m.state == MatchController.State.ENDED and t > 5.0 and main.menus.current == "end":
			print("END SCREEN shown. states seen: ", states_seen.keys())
			get_tree().quit()
	if t > limit:
		print("TIMEOUT states seen: ", states_seen.keys())
		get_tree().quit()
