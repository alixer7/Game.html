class_name SurvivalStats
extends RefCounted
## مؤشرات البقاء: الصحة، القدرة على التحمل، الجوع، العطش، حرارة الجسم، الطاقة (النعاس)، اللياقة، المهارات والأمراض.

signal died(cause: String)
signal skill_up(skill: String, level: int)
signal fitness_up(level: int)

const SKILL_NAMES := {"woodcutting": "الاحتطاب", "mining": "التعدين", "gathering": "الجمع", "hunting": "القتال والصيد", "crafting": "الصناعة", "building": "البناء", "social": "الإقناع"}

var health := 100.0
var max_health := 100.0
var stamina := 100.0
var hunger := 85.0
var thirst := 85.0
var energy := 90.0
var body_temp := 37.0
var fitness_xp := 0.0
var skills := {}
var sick := 0.0
var poisoned := 0.0
var bleeding := 0.0
var wet := 0.0
var exhausted := false
var regen_delay := 0.0
var last_cause := ""
var dead := false
var carry_bonus := 0.0
var _temp_target := 37.0

func _init() -> void:
	for s in SKILL_NAMES:
		skills[s] = 0.0

func fitness_level() -> int:
	return mini(int(sqrt(fitness_xp / 40.0)), 30)

func fitness_progress() -> float:
	var l := fitness_level()
	var a := 40.0 * l * l
	var b := 40.0 * (l + 1) * (l + 1)
	return clampf((fitness_xp - a) / (b - a), 0.0, 1.0)

func skill_level(s: String) -> int:
	return mini(int(sqrt(skills.get(s, 0.0) / 20.0)), 20)

func skill_progress(s: String) -> float:
	var l := skill_level(s)
	var a := 20.0 * l * l
	var b := 20.0 * (l + 1) * (l + 1)
	return clampf((skills.get(s, 0.0) - a) / (b - a), 0.0, 1.0)

func add_skill_xp(s: String, amt: float) -> void:
	var before := skill_level(s)
	skills[s] = skills.get(s, 0.0) + amt
	var after := skill_level(s)
	if after > before:
		skill_up.emit(s, after)

func add_fitness_xp(amt: float) -> void:
	var before := fitness_level()
	fitness_xp += amt
	if fitness_level() > before:
		fitness_up.emit(fitness_level())

func skill_power_mult(s: String) -> float:
	return 1.0 + skill_level(s) * 0.04

func skill_yield_mult(s: String) -> float:
	return 1.0 + skill_level(s) * 0.03

func max_stamina() -> float:
	var m := 100.0 + fitness_level() * 4.0
	if hunger < 15.0:
		m *= 0.7
	if thirst < 15.0:
		m *= 0.7
	if energy < 15.0:
		m *= 0.65
	if sick > 0.0:
		m *= 0.8
	return m

func carry_capacity() -> float:
	return 32.0 + fitness_level() * 1.3 + carry_bonus

func warmth_value() -> float:
	return clampf((body_temp - 33.0) / 8.0 * 100.0, 0.0, 100.0)

func temp_trend() -> float:
	return _temp_target - body_temp

func use_stamina(a: float) -> bool:
	if stamina < a * 0.5:
		exhausted = true
		return false
	stamina = maxf(0.0, stamina - a)
	regen_delay = 1.0
	if stamina <= 0.5:
		exhausted = true
	return true

func damage(a: float, cause: String, can_bleed := false) -> void:
	if dead or a <= 0.0:
		return
	health -= a
	last_cause = cause
	if can_bleed and a >= 8.0 and randf() < 0.35:
		bleeding = clampf(bleeding + a * 0.08, 0.0, 3.0)
	if health <= 0.0:
		health = 0.0
		dead = true
		died.emit(cause)

func heal(a: float) -> void:
	health = minf(max_health, health + a)

func consume_food(f: Dictionary) -> String:
	hunger = clampf(hunger + f.get("h", 0.0), 0.0, 100.0)
	thirst = clampf(thirst + f.get("t", 0.0), 0.0, 100.0)
	if f.get("hp", 0.0) > 0.0:
		heal(f["hp"])
	if f.get("warm", 0.0) > 0.0:
		body_temp = minf(37.8, body_temp + f["warm"] * 0.12)
	var msg := ""
	for c in f.get("cure", []):
		msg = cure(c)
	if f.get("sick", 0.0) > 0.0 and randf() < f["sick"]:
		if f.get("poison", false):
			poisoned = maxf(poisoned, 6.0)
			msg = "تسممت! تحتاج دواءً عشبياً"
		else:
			sick = maxf(sick, randf_range(5.0, 10.0))
			msg = "أصبت بتسمم غذائي... تشعر بالغثيان"
	return msg

func cure(c: String) -> String:
	match c:
		"bleed":
			if bleeding > 0.0:
				bleeding = 0.0
				return "توقف النزيف"
		"sick":
			if sick > 0.0:
				sick = 0.0
				return "شُفيت من المرض"
		"poison":
			if poisoned > 0.0:
				poisoned = 0.0
				return "زال أثر السم"
	return ""

## تحديث كل إطار. dt بالثواني الحقيقية، dh بساعات اللعب
func update(dt: float, dh: float, ctx: Dictionary) -> void:
	if dead:
		return
	var sprint: bool = ctx.get("sprint", false)
	var moving: bool = ctx.get("moving", false)
	var swimming: bool = ctx.get("swim", false)
	var sleeping: bool = ctx.get("sleep", false)
	var eff_temp: float = ctx.get("eff_temp", 20.0)
	var carry: float = ctx.get("carry", 0.0)
	var working: bool = ctx.get("work", false)
	# --- الجوع والعطش والطاقة ---
	var hmul := 1.0
	if sprint: hmul += 1.2
	if working: hmul += 0.5
	if swimming: hmul += 0.8
	if body_temp < 35.8: hmul += 0.4
	if sleeping: hmul *= 0.45
	var tmul := 1.0
	if sprint: tmul += 1.0
	if body_temp > 38.0: tmul += 0.9
	if sick > 0.0: tmul += 0.6
	if sleeping: tmul *= 0.45
	hunger = maxf(0.0, hunger - 3.8 * hmul * dh)
	thirst = maxf(0.0, thirst - 5.6 * tmul * dh)
	if sleeping:
		energy = minf(100.0, energy + 13.0 * float(ctx.get("bed_quality", 0.5)) * dh)
	else:
		energy = maxf(0.0, energy - (4.0 + (1.5 if sprint or working else 0.0)) * dh)
	# --- حرارة الجسم ---
	var target := 37.0
	if eff_temp < 14.0:
		target = 37.0 - (14.0 - eff_temp) * 0.2
	elif eff_temp > 30.0:
		target = 37.0 + (eff_temp - 30.0) * 0.17
	_temp_target = target
	var rate := 1.0 + absf(target - body_temp) * 0.6
	body_temp = move_toward(body_temp, target, rate * dh)
	wet = move_toward(wet, 1.0 if ctx.get("getting_wet", false) else 0.0, dt / (8.0 if ctx.get("getting_wet", false) else 90.0 / (1.0 + float(ctx.get("near_fire", 0.0)) * 4.0)))
	# --- الصحة ---
	var hp_rate := 0.0
	if hunger <= 0.0: hp_rate -= 9.0
	if thirst <= 0.0: hp_rate -= 16.0
	if body_temp < 34.2: hp_rate -= 14.0 * (34.2 - body_temp + 0.5)
	if body_temp > 39.4: hp_rate -= 12.0 * (body_temp - 39.4 + 0.5)
	if sick > 0.0:
		hp_rate -= 3.0
		hunger = maxf(0.0, hunger - 2.0 * dh)
		sick = maxf(0.0, sick - dh)
	if poisoned > 0.0:
		hp_rate -= 10.0
		poisoned = maxf(0.0, poisoned - dh)
	if bleeding > 0.0:
		hp_rate -= 24.0 * bleeding
		bleeding = maxf(0.0, bleeding - dh * 0.15)
	if hp_rate == 0.0 and hunger > 35.0 and thirst > 35.0 and body_temp > 35.5 and body_temp < 38.5:
		hp_rate = 4.0 * (2.0 if sleeping else 1.0)
	if hp_rate < 0.0:
		var cause := "الجوع" if hunger <= 0.0 else ("العطش" if thirst <= 0.0 else ("البرد القارس" if body_temp < 34.2 else ("ضربة الشمس" if body_temp > 39.4 else ("النزيف" if bleeding > 0.0 else ("السم" if poisoned > 0.0 else "المرض")))))
		damage(-hp_rate * dh, cause)
	else:
		heal(hp_rate * dh)
	# --- القدرة على التحمل ---
	var ms := max_stamina()
	if sprint and moving:
		stamina -= (11.0 + carry * 6.0) * dt
		regen_delay = 0.8
	elif swimming:
		stamina -= 4.5 * dt
		regen_delay = 0.5
	if stamina < 0.0:
		stamina = 0.0
		exhausted = true
		if swimming:
			damage(6.0 * dt, "الغرق")
	regen_delay -= dt
	if regen_delay <= 0.0 and not swimming:
		var regen := 16.0 * (1.0 + fitness_level() * 0.03)
		if body_temp < 35.5: regen *= 0.7
		if energy < 20.0: regen *= 0.6
		if carry > 1.0: regen *= 0.6
		stamina = minf(ms, stamina + regen * dt)
	if stamina > ms:
		stamina = ms
	if exhausted and stamina > ms * 0.3:
		exhausted = false

func status_list() -> Array:
	var s := []
	if hunger < 20.0: s.append(["جائع", Color(1, 0.7, 0.3)])
	if thirst < 20.0: s.append(["عطشان", Color(0.4, 0.7, 1)])
	if body_temp < 35.5: s.append(["تشعر بالبرد" if body_temp > 34.2 else "تتجمد!", Color(0.6, 0.85, 1)])
	if body_temp > 38.3: s.append(["حرارة شديدة" if body_temp < 39.4 else "ضربة شمس!", Color(1, 0.5, 0.2)])
	if energy < 20.0: s.append(["منهك - تحتاج للنوم", Color(0.8, 0.7, 1)])
	if sick > 0.0: s.append(["مريض", Color(0.6, 0.9, 0.3)])
	if poisoned > 0.0: s.append(["مسموم", Color(0.5, 1, 0.3)])
	if bleeding > 0.0: s.append(["نزيف", Color(1, 0.2, 0.2)])
	if wet > 0.3: s.append(["مبلل", Color(0.5, 0.7, 1)])
	return s

func to_data() -> Dictionary:
	return {"hp": health, "st": stamina, "hu": hunger, "th": thirst, "en": energy, "bt": body_temp, "fx": fitness_xp, "sk": skills.duplicate(), "sick": sick, "poi": poisoned, "bl": bleeding, "wet": wet}

func from_data(d: Dictionary) -> void:
	health = float(d.get("hp", 100.0))
	stamina = float(d.get("st", 100.0))
	hunger = float(d.get("hu", 80.0))
	thirst = float(d.get("th", 80.0))
	energy = float(d.get("en", 80.0))
	body_temp = float(d.get("bt", 37.0))
	fitness_xp = float(d.get("fx", 0.0))
	var sk: Dictionary = d.get("sk", {})
	for k in sk:
		skills[k] = float(sk[k])
	sick = float(d.get("sick", 0.0))
	poisoned = float(d.get("poi", 0.0))
	bleeding = float(d.get("bl", 0.0))
	wet = float(d.get("wet", 0.0))
	dead = false
