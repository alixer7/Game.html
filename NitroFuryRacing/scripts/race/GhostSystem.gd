class_name GhostSystem
extends Node3D

## Time Trial Ghost Recorder & Glowing Cyan Hologram Replayer.

var _recording: bool = false
var _record_frames: Array = []
var _record_accum: float = 0.0
var _record_time: float = 0.0

var _playback_frames: Array = []
var _ghost_node: Node3D = null
var _ghost_visuals: Node3D = null
var _playback_time: float = 0.0
var _playing: bool = false

const SAMPLE_DT := 0.065 # ~15 Hz compact smooth recording

func start_session(track_id: String, racer_data: Dictionary) -> void:
	_recording = true
	_record_frames.clear()
	_record_accum = 0.0
	_record_time = 0.0
	_playback_time = 0.0
	_playing = false

	if _ghost_node and is_instance_valid(_ghost_node):
		_ghost_node.queue_free()
		_ghost_node = null

	var saved := GameState.load_ghost(track_id)
	if saved.has("frames") and saved["frames"] is Array and saved["frames"].size() > 5:
		_playback_frames = saved["frames"]
		_playing = true
		_ghost_node = Node3D.new()
		add_child(_ghost_node)
		var vis_script := load("res://scripts/physics/KartVisuals.gd")
		_ghost_visuals = vis_script.new()
		_ghost_node.add_child(_ghost_visuals)
		_ghost_visuals.build_kart(saved.get("racer", racer_data), true)

func step(delta: float, player_kart: KartPhysics) -> void:
	if not player_kart or not player_kart.race_started:
		return

	if _recording and not player_kart.race_finished_flag:
		_record_time += delta
		_record_accum += delta
		if _record_accum >= SAMPLE_DT:
			_record_accum -= SAMPLE_DT
			var p := player_kart.global_position
			_record_frames.append([
				snappedf(_record_time, 0.01),
				snappedf(p.x, 0.05),
				snappedf(p.y, 0.05),
				snappedf(p.z, 0.05),
				snappedf(player_kart.heading_yaw, 0.02),
				player_kart.fire_tier
			])

	if _playing and _ghost_node and is_instance_valid(_ghost_node) and _playback_frames.size() >= 2:
		_playback_time += delta
		var idx := int(floorf(_playback_time / SAMPLE_DT))
		if idx >= _playback_frames.size() - 1:
			var last: Array = _playback_frames[_playback_frames.size() - 1]
			_ghost_node.global_position = Vector3(float(last[1]), float(last[2]), float(last[3]))
			_ghost_node.rotation = Vector3(0.0, float(last[4]), 0.0)
			return
		var f0: Array = _playback_frames[idx]
		var f1: Array = _playback_frames[idx + 1]
		var frac := clampf((_playback_time - float(idx) * SAMPLE_DT) / SAMPLE_DT, 0.0, 1.0)
		var p0 := Vector3(float(f0[1]), float(f0[2]), float(f0[3]))
		var p1 := Vector3(float(f1[1]), float(f1[2]), float(f1[3]))
		_ghost_node.global_position = p0.lerp(p1, frac)
		_ghost_node.rotation = Vector3(0.0, lerp_angle(float(f0[4]), float(f1[4]), frac), 0.0)
		if _ghost_visuals:
			_ghost_visuals.update_anim(delta, {"speed": 42.0, "fire_tier": int(f0[5])})

func finish_and_save_if_best(track_id: String, total_time: float, racer_data: Dictionary) -> void:
	_recording = false
	var existing := GameState.load_ghost(track_id)
	var prev_best := float(existing.get("total_time", 9999.0))
	if total_time > 5.0 and total_time < prev_best and _record_frames.size() > 10:
		GameState.save_ghost(track_id, {
			"total_time": total_time,
			"racer": {"ear_style": racer_data.get("ear_style", "fox")},
			"frames": _record_frames
		})
