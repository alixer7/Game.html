extends RefCounted
## CPU opponent: reaction-delayed blocking, punishing, juggles, anti-air, zoning, executions.
## Produces raw button dictionaries frame by frame from a queue of scripted inputs.

const U = preload("res://scripts/util.gd")

var F
var lvl := 1
var mode := "cpu"
var q := []
var cd := 30
var react := 15
var block_p := 0.55
var pun_p := 0.4
var aggr := 0.5
var seen = null
var seen_t := 0
var decided := false
var was_bstun := false
var tried := false

func _init(f, l: int, m := "cpu") -> void:
	F = f
	lvl = l
	mode = m
	react = [22, 15, 10, 7][l]
	block_p = [0.25, 0.55, 0.78, 0.93][l]
	pun_p = [0.1, 0.4, 0.72, 0.95][l]
	aggr = [0.3, 0.5, 0.65, 0.78][l]

static func parse(s: String) -> Array:
	var out := []
	for tk in s.strip_edges().split(" ", false):
		if tk.begins_with("w") and tk.substr(1).is_valid_int():
			out.append({n = int(tk.substr(1))})
			continue
		var d := ""
		var b := ""
		if "+" in tk:
			var parts := tk.split("+")
			d = parts[0]; b = parts[1]
		elif tk in ["1", "2", "3", "4", "TH", "BL", "SP"]:
			b = tk
		else:
			d = tk
		if d != "" and b == "":
			out.append({d = d, n = 2})
		elif d != "":
			out.append({d = d, n = 1})
			out.append({d = d, b = [b], n = 1})
		else:
			out.append({b = [b], n = 1})
		if b != "": out.append({d = d, n = 1})
	return out

func push(s: String, ex := false) -> void:
	var p := parse(s)
	if ex:
		for it in p:
			if it.has("b"):
				for b in it.b:
					if b in ["1", "2", "3", "4"]: it.ex = true
	q.append_array(p)

func hold(d: String, b, n: int) -> void:
	var it := {d = d, n = n}
	if b != null: it.b = b
	q.append(it)

func raw() -> Dictionary:
	var o := {}
	if q.is_empty(): think()
	if q.is_empty(): return o
	var it: Dictionary = q[0]
	var d: String = it.get("d", "")
	if "F" in d: o["R" if F.facing > 0 else "L"] = true
	if "B" in d: o["L" if F.facing > 0 else "R"] = true
	if "D" in d: o.D = true
	if "U" in d: o.U = true
	if it.has("b"):
		for b in it.b: o[b] = true
	if it.get("ex", false): o.BL = true
	it.n -= 1
	if it.n <= 0: q.pop_front()
	return o

func threat():
	var O = F.opp()
	if O.state == "attack" and O.move != null and O.mf <= O.move.lastActive:
		var reach := 0.9
		for h in O.move.hits: reach = maxf(reach, h.box[1])
		reach = reach * O.s + 0.5
		if absf(O.x - F.x) < reach or O.move.has("motion"):
			return O.move.hits[0].lvl if O.move.hits.size() > 0 else "mid"
	for p in G.projs:
		if p.F == O and not p.dead and signf(F.x - p.x) == signf(p.vx if p.vx != 0.0 else 1.0) and absf(F.x - p.x) < 3.2:
			return null if p.h.lvl == "unblockable" else "proj:" + p.h.lvl
	return null

func think() -> void:
	var O = F.opp()
	var D: Dictionary = F.def
	var A: Dictionary = D.ai
	var L := lvl
	var dist: float = absf(O.x - F.x)
	var r := randf()
	if mode == "stand": return
	if mode == "block" or mode == "crouch":
		var th = threat()
		if mode == "crouch":
			hold("D", ["BL"] if th != null else null, 2)
			return
		if th != null:
			var lv: String = th.replace("proj:", "")
			hold("D" if lv == "low" else "", ["BL"], 3)
		return
	if mode == "jump":
		if F.state == "stand": q.append_array([{d = "U", n = 2}, {n = 20}])
		return
	if G.phase == "endthem":
		if F.hp <= 0 or O.state != "dizzy": return
		var E: Dictionary = D.exec
		var want: float = {close = 1.2, mid = 2.4, far = 3.2}[E.range]
		if randf() < [0.3, 0.6, 0.85, 1.0][L] or tried:
			if absf(dist - want) > 0.5:
				q.append({d = "F" if dist > want else "B", n = 6})
				return
			tried = true
			var sq := []
			for i in E.seq.size():
				if i > 0 and E.seq[i - 1] == E.seq[i]: sq.append("N")
				sq.append(E.seq[i])
			push(" ".join(sq) + " " + E.seq[E.seq.size() - 1] + "+" + E.btn)
			q.append({n = 40})
		else:
			q.append({n = 30})
			if randf() < 0.4: tried = true
		return
	if G.phase != "fight" and not G.training: return
	var st: String = F.state
	if (st == "hit" or st == "juggle") and F.meter >= 200 and F.combo_hits >= 3 and randf() < [0.0, 0.04, 0.1, 0.18][L]:
		q.append_array([{d = "F", b = ["BL"], n = 1}, {n = 4}])
		return
	var neutral: bool = st in ["stand", "walkf", "walkb", "crouch", "block", "cblock"]
	var th = threat()
	if th != null:
		var key = O.move if O.move != null else th
		if not is_same(seen, key):
			seen = key; seen_t = G.frame; decided = false
		if not decided and G.frame - seen_t >= react:
			decided = true
			if th.begins_with("proj"):
				var lv: String = th.substr(5)
				if L >= 2 and r < 0.25:
					q.append({d = "U", b = ["BL"], n = 2})
					return
				if lv == "high" and L >= 1 and r < 0.6:
					hold("D", null, 26)
					return
				if r < block_p:
					hold("D" if lv == "low" else "", ["BL"], 26)
					return
			elif r < block_p:
				var low: bool = th == "low"
				var over: bool = th == "overhead"
				var right: bool = randf() < [0.5, 0.7, 0.88, 0.97][L]
				var crouch: bool = low if right else (true if over else (not low and randf() < 0.5))
				var n: int = maxi(6, O.move.lastActive - O.mf + 8) if O.move != null else 14
				if th == "high" and L >= 2 and randf() < 0.4: hold("D", null, n)
				else: hold("D" if crouch else "", ["BL"], n)
				return
	if not neutral and st != "bstun":
		was_bstun = false
		return
	if st == "bstun":
		was_bstun = true
		hold("D" if F.block_low else "", ["BL"], 1)
		return
	if was_bstun:
		was_bstun = false
		if O.state == "attack" and O.move != null and O.mf > O.move.lastActive - 1:
			var left: int = O.move.total - O.mf
			if left > 8 and dist < 2.2 and randf() < pun_p:
				push(U.pick(A.punish) if left > 14 else "D+1", F.meter >= 100 and L >= 2 and randf() < 0.3)
				return
	if O.state == "juggle" and not O.no_juggle and O.y > 0.45 and O.vy > -0.02 and dist < 2.2 and randf() < [0.2, 0.5, 0.8, 0.95][L]:
		push(U.pick(A.juggles))
		return
	if (O.state == "air" or (O.state == "attack" and O.move != null and O.move.get("air", false))) and dist < 2.4 and signf(O.vx) == signf(F.x - O.x) and randf() < [0.15, 0.4, 0.7, 0.9][L]:
		push(A.antiair)
		return
	cd -= 1
	if cd > 0:
		if dist > 4.5 and randf() < 0.5: q.append({d = "F", n = 3})
		else: q.append({n = 2})
		return
	cd = randi_range([22, 14, 9, 6][L], [40, 28, 20, 14][L])
	if F.meter >= 300 and dist < 1.9 and randf() < [0.03, 0.15, 0.3, 0.45][L]:
		q.append_array([{b = ["SP"], n = 1}, {n = 4}])
		return
	var ex: bool = F.meter >= 100 and randf() < [0.03, 0.1, 0.2, 0.3][L]
	var proj = null
	for s in D.spec:
		if F.mv[s.id].get("proj", false) and F.mv[s.id].has("ev"):
			proj = s
			break
	var spx := func(s): return " ".join(s.seq) + "+" + s.btn
	if dist > 3.6:
		if proj and r < A.zone:
			push(spx.call(proj), ex)
			return
		if r < 0.1:
			q.append_array([{d = "F", n = 1}, {n = 2}, {d = "F", n = 2}])
			return
		if r < 0.16 and L >= 1:
			q.append_array([{d = "UF", n = 2}, {n = 18}, {b = [U.pick(["2", "4"])], n = 1}, {n = 20}])
			return
		q.append({d = "F", n = randi_range(14, 34)})
		return
	if dist > 1.7:
		if proj and r < A.zone * 0.6:
			push(spx.call(proj), ex)
			return
		if r < 0.3:
			push("B+3")
			return
		if r < 0.3 + A.rush * 0.25:
			for s in D.spec:
				if s.id in ["rush", "charge", "lunge", "glide", "waltz"]:
					push(spx.call(s), ex)
					return
		if r < 0.62:
			q.append({d = "F", n = randi_range(10, 24)})
			return
		if r < 0.7:
			q.append_array([{d = "F", n = 1}, {n = 2}, {d = "F", n = 2}])
			return
		if r < 0.76:
			q.append_array([{d = "UF", n = 2}, {n = 16}, {b = ["4"], n = 1}, {n = 20}])
			return
		hold("", ["BL"], randi_range(10, 24))
		return
	if r < aggr:
		push(U.pick(A.combos), ex)
		return
	if r < aggr + 0.1:
		q.append_array([{b = ["TH"], n = 1}, {n = 6}])
		return
	if r < aggr + 0.17:
		push(U.pick(["D+3", "D+1", "D+4"]))
		return
	if r < aggr + 0.22:
		q.append_array([{d = "B", n = 1}, {n = 2}, {d = "B", n = 2}])
		return
	hold("D" if randf() < 0.3 else "", ["BL"], randi_range(10, 22))
