class_name MatchRules
extends RefCounted
## قوانين التسجيل الرسمية: نقاط (15/30/40/تعادل/أفضلية)، أشواط، مجموعات،
## شوط فاصل (تاي بريك) عند التعادل، وتناوب الإرسال.

var sets_to_win := 1
var games_per_set := 6

var points := [0, 0]
var games := [0, 0]
var sets := [0, 0]
var set_history: Array = []      # [[g0, g1, tb_loser_points أو -1], ...]
var server := 0
var tiebreak := false
var tb_first_server := 0
var finished := false
var winner := -1
var final_tb10 := false          # شوط فاصل حتى 10 في المجموعة الحاسمة (نظام البطولات الكبرى)


func reset(first_server: int = 0) -> void:
	points = [0, 0]
	games = [0, 0]
	sets = [0, 0]
	set_history = []
	server = first_server
	tiebreak = false
	finished = false
	winner = -1


## هل الإرسال من الجهة اليمنى (deuce)؟
func deuce_court() -> bool:
	return (points[0] + points[1]) % 2 == 0


func current_server() -> int:
	if tiebreak:
		var total: int = points[0] + points[1]
		if ((total + 1) / 2) % 2 == 0:
			return tb_first_server
		return 1 - tb_first_server
	return server


## يسجل نقطة للاعب p ويعيد الأحداث الناتجة
func point_won(p: int) -> Dictionary:
	var ev := {"game": false, "set": false, "match": false, "tiebreak_start": false, "winner": p, "change_ends": false}
	if finished:
		return ev
	points[p] += 1
	var o := 1 - p
	var game_done := false
	if tiebreak:
		if points[p] >= tb_target() and points[p] - points[o] >= 2:
			game_done = true
		elif (points[0] + points[1]) % 6 == 0:
			ev["change_ends"] = true
	else:
		if points[p] >= 4 and points[p] - points[o] >= 2:
			game_done = true
	if not game_done:
		return ev
	# --- نهاية شوط ---
	ev["game"] = true
	var was_tb := tiebreak
	var tb_loser: int = points[o]
	games[p] += 1
	points = [0, 0]
	var set_done := false
	if was_tb:
		set_done = true
	elif games[p] >= games_per_set and games[p] - games[o] >= 2:
		set_done = true
	if was_tb:
		tiebreak = false
		server = 1 - tb_first_server
	else:
		server = 1 - server
	var tot: int = games[0] + games[1]
	ev["change_ends"] = tot % 2 == 1
	if set_done:
		ev["set"] = true
		set_history.append([games[0], games[1], tb_loser if was_tb else -1])
		sets[p] += 1
		games = [0, 0]
		if sets[p] >= sets_to_win:
			finished = true
			winner = p
			ev["match"] = true
	elif games[0] == games_per_set and games[1] == games_per_set:
		tiebreak = true
		tb_first_server = server
		ev["tiebreak_start"] = true
	return ev


func tb_target() -> int:
	if final_tb10 and sets[0] == sets_to_win - 1 and sets[1] == sets_to_win - 1:
		return 10
	return 7


func is_deuce() -> bool:
	return not tiebreak and points[0] >= 3 and points[0] == points[1]


func advantage() -> int:
	if tiebreak or points[0] < 3 or points[1] < 3 or points[0] == points[1]:
		return -1
	return 0 if points[0] > points[1] else 1


## نص نقاط لاعب للوحة النتيجة
func point_label(p: int) -> String:
	if tiebreak:
		return str(points[p])
	var o := 1 - p
	if points[0] >= 3 and points[1] >= 3:
		if points[p] == points[o]:
			return "40"
		return "AD" if points[p] > points[o] else "40"
	return ["0", "15", "30", "40"][mini(points[p], 3)]


## هل النقطة القادمة حاسمة؟ يعيد "match" / "set" / "break" / ""
func pressure() -> String:
	for p in 2:
		var o := 1 - p
		var wins_game := false
		if tiebreak:
			wins_game = points[p] >= tb_target() - 1 and points[p] - points[o] >= 1
		else:
			wins_game = points[p] >= 3 and points[p] - points[o] >= 1
		if not wins_game:
			continue
		var wins_set: bool = tiebreak or (games[p] + 1 >= games_per_set and games[p] + 1 - games[o] >= 2)
		if wins_set and sets[p] + 1 >= sets_to_win:
			return "match"
		if wins_set:
			return "set"
		if not tiebreak and current_server() != p:
			return "break"
	return ""
