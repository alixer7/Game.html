extends ModalPanel
## نافذة التخزين: نقل الأغراض بين الحقيبة والصندوق، مع عرض الأمان والملكية (الأخذ من صناديق الآخرين سرقة).

var container = null
var g_player: GridContainer
var g_box: GridContainer
var info: Label
var mode := "all"
var mode_btn: Button

func build() -> void:
	make_frame("التخزين")
	info = UIKit.label("", 18, UIKit.DIM)
	body.add_child(info)
	var tools := UIKit.hbox(8)
	tools.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(tools)
	mode_btn = UIKit.button("نقل: الكومة كاملة", _toggle_mode, 18, 48)
	tools.add_child(mode_btn)
	tools.add_child(UIKit.button("خذ الكل", _take_all, 18, 48))
	tools.add_child(UIKit.button("خزّن كل شيء عدا الشريط", _store_all, 18, 48))
	var row := UIKit.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var lv := UIKit.vbox(6)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lv)
	lv.add_child(UIKit.label("الصندوق (اضغط لتأخذ)", 20, UIKit.GOLD))
	var sc1 := UIKit.scroll()
	lv.add_child(sc1)
	g_box = GridContainer.new()
	g_box.columns = 6
	sc1.add_child(g_box)
	var rv := UIKit.vbox(6)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rv)
	rv.add_child(UIKit.label("حقيبتك (اضغط لتخزّن)", 20, UIKit.GOLD))
	var sc2 := UIKit.scroll()
	rv.add_child(sc2)
	g_player = GridContainer.new()
	g_player.columns = 6
	sc2.add_child(g_player)

func open_for(c) -> void:
	container = c
	if c is BuildPiece and c.tampered and c.owner_id == "player":
		c.tampered = false
		Game.notify("يبدو أن أحداً عبث بهذا الصندوق! تفقد السجل في نافذة شخصيتي", Color(1, 0.6, 0.4))
	open()

func _toggle_mode() -> void:
	mode = {"all": "half", "half": "one", "one": "all"}[mode]
	mode_btn.text = {"all": "نقل: الكومة كاملة", "half": "نقل: النصف", "one": "نقل: واحد"}[mode]

func _amount(s: Dictionary) -> int:
	match mode:
		"half": return maxi(1, int(s["n"] / 2))
		"one": return 1
	return s["n"]

func refresh() -> void:
	if container == null or not is_instance_valid(container):
		close()
		return
	var inv: Inventory = container.inventory
	title_lbl.text = container.display_name()
	var t := "الوزن: %.1f%s كغ   |   الخانات الفارغة: %d" % [inv.total_weight(), (" / %.0f" % inv.max_weight) if inv.max_weight < INF else "", inv.free_slots()]
	if container is BuildPiece:
		if container.owner_id == "player":
			t += "\n" + container.enclosure_report()
		else:
			t += "\nهذا ملك %s! أخذ أي شيء منه سرقة، وإن رآك أحد ستسوء سمعتك." % world().build.owner_name(container.owner_id)
	info.text = t
	clear(g_box)
	for i in range(inv.size()):
		g_box.add_child(slot_button(inv.slots[i], _take.bind(i), 78.0))
	clear(g_player)
	var pinv := player().inventory
	for i in range(pinv.size()):
		g_player.add_child(slot_button(pinv.slots[i], _store.bind(i), 78.0))

func _take(i: int) -> void:
	var inv: Inventory = container.inventory
	var s = inv.slots[i]
	if s == null:
		return
	var n := _amount(s)
	var part := inv.take_slot(i, n)
	var left := player().inventory.add_stack(part)
	if left > 0:
		inv.add(part["id"], left, part.get("d", -1.0), part.get("a", 0.0))
		Game.notify("حقيبتك ممتلئة", Color(1, 0.7, 0.4))
	var got: int = part["n"] - left
	if got > 0 and container is BuildPiece and container.owner_id != "player":
		_theft(part["id"], got)
	if is_instance_valid(container):
		refresh()

func _theft(id: String, n: int) -> void:
	var w: Node = world()
	var val := ItemDB.value_of(id) * n
	var sev := clampf(val * 0.8 + 5.0, 5.0, 40.0)
	var seen: Array = w.ai.witness(container.global_position, "player", "", sev, "steal", 24.0)
	if seen.is_empty():
		return
	var names := []
	for npc in seen:
		names.append(npc.data["name"])
		if npc.data["role"] == "guard" or (npc.data["faction"] == container.owner_id and npc.traits()["brave"] > 0.6 and sev > 15.0) or npc.data["role"] == "bandit":
			npc.become_hostile_to(w.player, false)
	Game.notify("رآك %s تسرق!" % "، ".join(names), Color(1, 0.4, 0.35))
	w.ai.log_event("ضُبطت تسرق من %s" % container.display_name())

func _store(i: int) -> void:
	var pinv := player().inventory
	var s = pinv.slots[i]
	if s == null:
		return
	var n := _amount(s)
	var part := pinv.take_slot(i, n)
	var left: int = container.inventory.add_stack(part)
	if left > 0:
		pinv.add(part["id"], left, part.get("d", -1.0), part.get("a", 0.0))
		Game.notify("الصندوق ممتلئ أو تجاوز حد الوزن", Color(1, 0.7, 0.4))
	refresh()

func _take_all() -> void:
	var inv: Inventory = container.inventory
	var stolen := 0
	for i in range(inv.size()):
		var s = inv.slots[i]
		if s == null:
			continue
		var part := inv.take_slot(i)
		var left := player().inventory.add_stack(part)
		if left > 0:
			inv.add(part["id"], left, part.get("d", -1.0), part.get("a", 0.0))
		stolen += part["n"] - left
		if not is_instance_valid(container):
			break
	if stolen > 0 and is_instance_valid(container) and container is BuildPiece and container.owner_id != "player":
		_theft("gold_coin", stolen)
	if is_instance_valid(container):
		refresh()
	else:
		close()

func _store_all() -> void:
	var pinv := player().inventory
	for i in range(6, pinv.size()):
		var s = pinv.slots[i]
		if s == null:
			continue
		var part := pinv.take_slot(i)
		var left: int = container.inventory.add_stack(part)
		if left > 0:
			pinv.add(part["id"], left, part.get("d", -1.0), part.get("a", 0.0))
	refresh()
