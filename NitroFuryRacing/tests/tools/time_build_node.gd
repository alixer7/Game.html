extends Node
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var tid := args[0] if args.size() > 0 else "tiki_cove"
	var tb := TrackBuilder.new()
	add_child(tb)
	var t1 := Time.get_ticks_msec()
	tb.build_track(tid, false)
	print("TOTAL build ms: ", Time.get_ticks_msec() - t1)
	get_tree().quit()
