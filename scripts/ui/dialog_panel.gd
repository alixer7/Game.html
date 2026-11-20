extends ModalPanel
## نافذة الحوار مع الشخصيات: حديث، أسئلة عن الناس والأماكن، هدايا، تجارة، تجنيد رفاق، أوامر، تهديد، اتهام.

var npc = null
var info: Label
var rel_bar: ProgressBar
var speech: Label
var opts: GridContainer
var gift_mode := false

func build() -> void:
	make_frame("حوار", 0.06)
	info = UIKit.label("", 18, UIKit.DIM)
	body.add_child(info)
	rel_bar = UIKit.bar(Color(0.5, 0.9, 0.5), 14)
	rel_bar.min_value = -100
	rel_bar.max_value = 100
	body.add_child(rel_bar)
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", UIKit.sb(Color(0.12, 0.11, 0.1, 0.9), 12, 1, Color(1, 1, 1, 0.08), 16))
	sp.custom_minimum_size = Vector2(0, 150)
	body.add_child(sp)
	speech = UIKit.label("", 23, Color(1, 0.97, 0.9))
	sp.add_child(speech)
	var sc := UIKit.scroll()
	body.add_child(sc)
	opts = GridContainer.new()
	opts.columns = 3
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opts.add_theme_constant_override("h_separation", 8)
	opts.add_theme_constant_override("v_separation", 8)
	sc.add_child(opts)

func open_for(n) -> void:
	npc = n
	gift_mode = false
	npc.in_dialog = true
	var ai: Node = world().ai
	speech.text = ai.greeting(npc.data)
	npc._update_label()
	open()

func close() -> void:
	if npc != null and is_instance_valid(npc):
		npc.in_dialog = false
	super.close()

func _say(t: String) -> void:
	speech.text = t
	if is_instance_valid(npc):
		npc._update_label()
	refresh()

func refresh() -> void:
	if npc == null or not is_instance_valid(npc) or npc.dead:
		close()
		return
	var ai: Node = world().ai
	var d: Dictionary = npc.data
	var r: float = ai.get_rel(d["id"], "player")
	title_lbl.text = "%s - %s" % [d["name"], ai.role_name(d)]
	var s: Dictionary = ai.settlement_of(d)
	var traits := []
	for k in d["known_traits"]:
		var v: float = d["traits"][k]
		if v > 0.62 or v < 0.38:
			traits.append(AIManager.TRAIT_NAMES[k][1 if v > 0.5 else 0])
	info.text = "%s   |   علاقته بك: %s (%d)%s%s" % [s.get("name", "رحّال"), AIManager.rel_label(r), int(r),
		("   |   صفاته: " + "، ".join(traits)) if not traits.is_empty() else "", "   |   رفيقك" if d["companion"] else ""]
	rel_bar.value = r
	rel_bar.add_theme_stylebox_override("fill", UIKit.sb(AIManager.rel_color(r), 6, 0, Color(0, 0, 0, 0), 0))
	clear(opts)
	if gift_mode:
		_gift_view()
		return
	_opt("تحدث معه", func(): _say(ai.chat(d)))
	_opt("اسأل عن الناس", func(): _say(ai.ask_people(d)))
	_opt("اسأل عن المنطقة", func(): _say(ai.ask_place(d)))
	_opt("قدّم هدية", func(): gift_mode = true; refresh())
	if ai.can_trade(d):
		_opt("تاجر معه", func(): var nn = npc; close(); hud.open_trade(nn))
	if d["companion"]:
		_opt("اتبعني", func(): _say(ai.order(d, "follow")))
		_opt("انتظر هنا", func(): _say(ai.order(d, "stay")))
		_opt("احرس هذا المكان", func(): _say(ai.order(d, "guard")))
		_opt("انصرف إلى ديارك", func(): _say(ai.order(d, "dismiss")))
	else:
		_opt("اطلب أن ينضم إليك", func(): _say(ai.recruit(d)))
	_opt("اتهمه بالسرقة", func(): _say(ai.accuse(d)); _check_hostile())
	_opt("هدّده", _threaten)
	_opt("وداعاً", close)

func _opt(t: String, cb: Callable) -> void:
	var b := UIKit.button(t, cb, 20, 60)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opts.add_child(b)

func _threaten() -> void:
	var res: Array = world().ai.threaten(npc.data)
	var t: String = res[0]
	if not res[1].is_empty():
		var names := []
		for e in res[1]:
			names.append("%s ×%d" % [ItemDB.name_of(e[0]), e[1]])
		t += "\n(أخذت: %s)" % "، ".join(names)
	_say(t)
	_check_hostile()

func _check_hostile() -> void:
	if is_instance_valid(npc) and npc.target == world().player:
		close()

func _gift_view() -> void:
	var p := player()
	speech.text = "ماذا تريد أن تهديه؟ (اضغط عنصراً لإهداء واحد منه)"
	_opt("رجوع", func(): gift_mode = false; refresh())
	for i in range(p.inventory.size()):
		var s = p.inventory.slots[i]
		if s == null:
			continue
		var b := UIKit.button("%s ×%d" % [ItemDB.name_of(s["id"]), s["n"]], _give.bind(i), 18, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opts.add_child(b)

func _give(i: int) -> void:
	var p := player()
	var s = p.inventory.slots[i]
	if s == null:
		return
	var n := 1
	if s["id"] == "gold_coin":
		n = mini(s["n"], 5)
	var part := p.inventory.take_slot(i, n)
	var t: String = world().ai.gift(npc.data, part["id"], part["n"])
	gift_mode = false
	_say(t)
