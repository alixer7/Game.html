class_name ResourceBody
extends StaticBody3D
## جسم تصادم لمورد طبيعي (شجرة، صخرة، نبتة) يربط التفاعل بمدير التضاريس.

var terrain: Node = null
var chunk_key := Vector2i.ZERO
var sidx := 0
var rtype := ""

func get_interact_text(player) -> String:
	var td := ResDB.get_type(rtype)
	if td.is_empty():
		return ""
	if td["tool"] == "":
		return "%s: %s" % [td["verb"], td["name"]]
	var prog: float = terrain.get_progress(chunk_key, sidx)
	var t := "%s %s" % [td["verb"], td["name"]]
	if prog > 0.0:
		t += " (%d٪)" % int(prog * 100)
	var held: String = player.held_tool_kind()
	if held != td["tool"]:
		t += "  - تحتاج %s" % ItemDB.tool_kind_name(td["tool"])
	elif player.held_tool_tier() < td["tier"]:
		t += "  - تحتاج أداة أقوى"
	return t

func is_hand_gather() -> bool:
	var td := ResDB.get_type(rtype)
	return not td.is_empty() and td["tool"] == ""

func interact(player) -> void:
	terrain.player_interact(self, player)

func on_hit(dmg: float, kind: String, tier: int, attacker, hit_pos: Vector3) -> void:
	terrain.player_hit(self, dmg, kind, tier, attacker, hit_pos)
