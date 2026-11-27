extends RefCounted
## Per-player input buffer: button edges, direction history (numpad notation
## relative to facing), motion detection and double-tap dashes.

const BTNS := ["U", "D", "L", "R", "1", "2", "3", "4", "BL", "TH", "SP", "ST"]

var h := {}
var press := {}
var used := {}
var dh := [[5, -999]]
var dir := 5
var e6 := -99
var l6 := -99
var e4 := -99
var l4 := -99
var dash := -99
var bdash := -99
var f := 0

func sample(raw: Dictionary, facing: int, frame: int) -> void:
	f = frame
	for b in BTNS:
		var v: bool = raw.get(b, false)
		if v and not h.get(b, false): press[b] = frame
		h[b] = v
	var x := (1 if raw.get("R", false) else 0) - (1 if raw.get("L", false) else 0)
	var y := (1 if raw.get("U", false) else 0) - (1 if raw.get("D", false) else 0)
	var d := 5 + x * facing + y * 3
	if d != dir:
		if dir == 6: l6 = frame
		if dir == 4: l4 = frame
		if d == 6:
			if frame - e6 < 14 and l6 > e6: dash = frame
			e6 = frame
		if d == 4:
			if frame - e4 < 14 and l4 > e4: bdash = frame
			e4 = frame
		dir = d
		dh.append([d, frame])
		if dh.size() > 40: dh.pop_front()

func held(b: String) -> bool:
	return h.get(b, false)

func recent(b: String, n := 5) -> int:
	if not press.has(b): return -1
	var p: int = press[b]
	if used.get(b, -1000) == p: return -1
	return p if f - p <= n else -1

func consume(b: String) -> void:
	if press.has(b): used[b] = press[b]

static func dmatch(c: String, d: int) -> bool:
	match c:
		"F": return d == 6 or d == 3 or d == 9
		"B": return d == 4 or d == 1 or d == 7
		"D": return d <= 3
		"U": return d >= 7
		"N": return d >= 4
	return false

func motion(seq: Array, at: int, win := 20) -> bool:
	var i := dh.size() - 1
	var j := seq.size() - 1
	var first := true
	while i >= 0 and dh[i][1] > at: i -= 1
	while i >= 0 and j >= 0:
		var end: int = mini(dh[i + 1][1], at) if i + 1 < dh.size() else at
		if at - end > win: break
		if dmatch(seq[j], dh[i][0]):
			if first and at - end > 9: return false
			j -= 1
			first = false
		i -= 1
	return j < 0

func clear() -> void:
	h = {}; press = {}; used = {}; dh = [[5, -999]]; dir = 5
