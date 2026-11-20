class_name Inventory
extends RefCounted
## مخزون عام بخانات (للاعب والصناديق والشخصيات). كل خانة: {"id","n","d" (المتانة),"a" (العمر بالساعات)}

signal changed

var slots: Array = []
var max_weight: float = INF

func _init(n_slots := 24, max_w := INF) -> void:
	slots.resize(n_slots)
	max_weight = max_w

func size() -> int:
	return slots.size()

func get_slot(i: int):
	return slots[i] if i >= 0 and i < slots.size() else null

func total_weight() -> float:
	var w := 0.0
	for s in slots:
		if s != null:
			w += ItemDB.weight(s["id"]) * s["n"]
	return w

func count(id: String) -> int:
	var c := 0
	for s in slots:
		if s != null and s["id"] == id:
			c += s["n"]
	return c

func count_key(key: String) -> int:
	if key.begins_with("#"):
		var tag := key.substr(1)
		var c := 0
		for s in slots:
			if s != null and ItemDB.has_tag(s["id"], tag):
				c += s["n"]
		return c
	return count(key)

func has_all(needs: Dictionary, mult := 1) -> bool:
	for k in needs:
		if count_key(k) < needs[k] * mult:
			return false
	return true

func free_slots() -> int:
	var c := 0
	for s in slots:
		if s == null:
			c += 1
	return c

func is_empty() -> bool:
	for s in slots:
		if s != null:
			return false
	return true

func room_for(id: String) -> int:
	## كم يمكن إضافته من هذا العنصر (حسب الخانات والوزن)
	var st := ItemDB.stack_of(id)
	var r := 0
	for s in slots:
		if s == null:
			r += st
		elif s["id"] == id:
			r += maxi(0, st - s["n"])
	if max_weight < INF:
		var w := ItemDB.weight(id)
		if w > 0.0:
			r = mini(r, int(floor((max_weight - total_weight()) / w + 0.0001)))
	return maxi(r, 0)

func add(id: String, n: int, dur := -1.0, age := 0.0) -> int:
	## يضيف ويعيد الكمية التي لم تتسع
	if n <= 0 or not ItemDB.exists(id):
		return 0
	if max_weight < INF:
		var w := ItemDB.weight(id)
		if w > 0.0:
			var fit := maxi(int(floor((max_weight - total_weight()) / w + 0.0001)), 0)
			if fit < n:
				if fit == 0:
					return n
				return (n - fit) + _add_raw(id, fit, dur, age)
	return _add_raw(id, n, dur, age)

func _add_raw(id: String, n: int, dur: float, age: float) -> int:
	var st := ItemDB.stack_of(id)
	if dur < 0.0:
		dur = ItemDB.max_dur(id)
	var left := n
	if st > 1:
		for s in slots:
			if s != null and s["id"] == id and s["n"] < st:
				var put := mini(st - s["n"], left)
				# متوسط العمر للأكوام المدمجة
				s["a"] = (s.get("a", 0.0) * s["n"] + age * put) / float(s["n"] + put)
				s["n"] += put
				left -= put
				if left <= 0:
					break
	if left > 0:
		for i in range(slots.size()):
			if slots[i] == null:
				var put2 := mini(st, left)
				slots[i] = {"id": id, "n": put2, "d": dur, "a": age}
				left -= put2
				if left <= 0:
					break
	if left != n:
		changed.emit()
	return left

func remove(id: String, n: int) -> int:
	## يزيل ويعيد الكمية التي أزيلت فعلاً
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):
		var s = slots[i]
		if s != null and s["id"] == id:
			var take := mini(s["n"], n - removed)
			s["n"] -= take
			removed += take
			if s["n"] <= 0:
				slots[i] = null
			if removed >= n:
				break
	if removed > 0:
		changed.emit()
	return removed

func remove_key(key: String, n: int) -> Array:
	## يزيل حسب المعرف أو العلامة، ويعيد قائمة [[id, n], ...] لما أزيل
	var out := []
	if not key.begins_with("#"):
		var r := remove(key, n)
		if r > 0:
			out.append([key, r])
		return out
	var tag := key.substr(1)
	var left := n
	for i in range(slots.size()):
		var s = slots[i]
		if s != null and ItemDB.has_tag(s["id"], tag):
			var take := mini(s["n"], left)
			out.append([s["id"], take])
			s["n"] -= take
			left -= take
			if s["n"] <= 0:
				slots[i] = null
			if left <= 0:
				break
	if not out.is_empty():
		changed.emit()
	return out

func remove_needs(needs: Dictionary, mult := 1) -> bool:
	if not has_all(needs, mult):
		return false
	for k in needs:
		remove_key(k, needs[k] * mult)
	return true

func take_slot(i: int, n := -1) -> Dictionary:
	var s = slots[i]
	if s == null:
		return {}
	if n < 0 or n >= s["n"]:
		slots[i] = null
		changed.emit()
		return s
	var part: Dictionary = s.duplicate()
	part["n"] = n
	s["n"] -= n
	changed.emit()
	return part

func add_stack(st: Dictionary) -> int:
	if st.is_empty():
		return 0
	return add(st["id"], st["n"], st.get("d", -1.0), st.get("a", 0.0))

func swap(i: int, j: int) -> void:
	if i == j:
		return
	var a = slots[i]
	var b = slots[j]
	if a != null and b != null and a["id"] == b["id"] and ItemDB.stack_of(a["id"]) > 1:
		var st := ItemDB.stack_of(a["id"])
		var put := mini(st - b["n"], a["n"])
		b["n"] += put
		a["n"] -= put
		if a["n"] <= 0:
			slots[i] = null
	else:
		slots[i] = b
		slots[j] = a
	changed.emit()

func damage_slot(i: int, amount: float) -> bool:
	## يقلل المتانة ويعيد true إذا انكسرت الأداة
	var s = slots[i]
	if s == null or s.get("d", -1.0) < 0.0:
		return false
	s["d"] -= amount
	if s["d"] <= 0.0:
		slots[i] = null
		changed.emit()
		return true
	return false

func age_items(hours: float, mult := 1.0) -> Array:
	## تقادم الطعام. يعيد أسماء العناصر التي فسدت
	var spoiled := []
	var to_add := []
	for i in range(slots.size()):
		var s = slots[i]
		if s == null:
			continue
		var it := ItemDB.get_item(s["id"])
		if not it.has("spoil"):
			continue
		s["a"] = s.get("a", 0.0) + hours * mult
		if s["a"] >= it["spoil"]:
			spoiled.append(it["name"])
			to_add.append([it.get("spoil_to", ""), s["n"]])
			slots[i] = null
	for e in to_add:
		if e[0] != "":
			add(e[0], e[1])
	if not spoiled.is_empty():
		changed.emit()
	return spoiled

func most_valuable(n_max := 3) -> Array:
	## يعيد فهارس الخانات الأعلى قيمة (يستخدمها اللصوص)
	var idx := []
	for i in range(slots.size()):
		if slots[i] != null:
			idx.append(i)
	idx.sort_custom(func(a, b): return ItemDB.value_of(slots[a]["id"]) * slots[a]["n"] > ItemDB.value_of(slots[b]["id"]) * slots[b]["n"])
	return idx.slice(0, n_max)

func to_data() -> Array:
	var out := []
	for s in slots:
		out.append(s.duplicate() if s != null else null)
	return out

func from_data(arr: Array) -> void:
	for i in range(slots.size()):
		slots[i] = null
	for i in range(mini(arr.size(), slots.size())):
		var s = arr[i]
		if s is Dictionary and ItemDB.exists(str(s.get("id", ""))):
			slots[i] = {"id": str(s["id"]), "n": int(s.get("n", 1)), "d": float(s.get("d", -1.0)), "a": float(s.get("a", 0.0))}
	changed.emit()

func clear() -> void:
	for i in range(slots.size()):
		slots[i] = null
	changed.emit()
