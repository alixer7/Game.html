extends ModalPanel
## نافذة الحقيبة: الخانات، المعدات (الملابس والدروع والحقيبة)، التفاصيل، الاستخدام والإسقاط والنقل.

var grid: GridContainer
var equip_row: HBoxContainer
var det_icon: ItemIcon
var det_name: Label
var det_desc: Label
var det_btns: HBoxContainer
var info: Label
var sel_i := -1
var sel_eq := ""

func build() -> void:
	make_frame("الحقيبة")
	var row := UIKit.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UIKit.vbox(8)
	left.custom_minimum_size = Vector2(380, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	info = UIKit.label("", 18, UIKit.DIM)
	left.add_child(info)
	left.add_child(UIKit.label("المعدات (اضغط لخلعها):", 18, UIKit.GOLD))
	equip_row = UIKit.hbox(6)
	equip_row.alignment = BoxContainer.ALIGNMENT_END
	left.add_child(equip_row)
	left.add_child(UIKit.sep())
	var dh := UIKit.hbox(10)
	dh.alignment = BoxContainer.ALIGNMENT_END
	left.add_child(dh)
	det_name = UIKit.label("", 24, UIKit.TEXT)
	det_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(det_name)
	det_icon = ItemIcon.new()
	det_icon.custom_minimum_size = Vector2(80, 80)
	dh.add_child(det_icon)
	det_desc = UIKit.label("", 18, UIKit.DIM)
	left.add_child(det_desc)
	det_btns = UIKit.hbox(8)
	det_btns.alignment = BoxContainer.ALIGNMENT_END
	left.add_child(det_btns)
	var sc := UIKit.scroll()
	sc.custom_minimum_size = Vector2(6 * 90, 0)
	sc.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(sc)
	var gv := UIKit.vbox(6)
	sc.add_child(gv)
	gv.add_child(UIKit.label("الصف الأول = شريط الأدوات السريع. اضغط عنصراً ثم خانة أخرى لنقله.", 16, UIKit.DIM))
	grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	gv.add_child(grid)

func open() -> void:
	sel_i = -1
	sel_eq = ""
	super.open()

func refresh() -> void:
	var p := player()
	var w := p.carry_weight()
	var cap := p.stats.carry_capacity()
	var ins := p.insulation()
	info.text = "الحمولة: %.1f / %.0f كغ   |   عزل البرد: %d   حماية الحر: %d   الدروع: %d" % [w, cap, int(ins.x), int(ins.y), int(p.armor())]
	if w > cap:
		info.text += "\nتحمل وزناً زائداً! ستتحرك ببطء. خزّن الفائض في صندوق."
	clear(grid)
	for i in range(p.inventory.size()):
		var s = p.inventory.slots[i]
		var b := slot_button(s, _on_slot.bind(i), 84.0, i == sel_i)
		if i < 6 and i != sel_i:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color(0.2, 0.2, 0.14, 0.95), 10, 1, Color(0.9, 0.8, 0.4, 0.35), 4))
		grid.add_child(b)
	clear(equip_row)
	for slot in ["back", "feet", "legs", "body", "head"]:
		var v := UIKit.vbox(2)
		var e = p.equipment[slot]
		var b2 := slot_button(e, _on_equip.bind(slot), 70.0, sel_eq == slot)
		v.add_child(b2)
		v.add_child(UIKit.label(ItemDB.SLOT_NAMES[slot], 14, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
		equip_row.add_child(v)
	_details()

func _details() -> void:
	clear(det_btns)
	var p := player()
	var s = null
	if sel_i >= 0:
		s = p.inventory.slots[sel_i]
	elif sel_eq != "":
		s = p.equipment[sel_eq]
	if s == null:
		det_name.text = "اختر عنصراً"
		det_desc.text = ""
		det_icon.set_item("")
		return
	var it := ItemDB.get_item(s["id"])
	det_icon.set_item(s["id"], s["n"], s.get("d", -1.0))
	det_name.text = "%s ×%d" % [it["name"], s["n"]]
	var extra := ""
	if it.has("spoil"):
		extra = "\nالعمر: %d / %d ساعة" % [int(s.get("a", 0.0)), int(it["spoil"])]
	if s.get("d", -1.0) >= 0.0 and ItemDB.max_dur(s["id"]) > 0.0:
		extra += "\nالمتانة: %d / %d" % [int(s["d"]), int(ItemDB.max_dur(s["id"]))]
	det_desc.text = "%s\n%s%s" % [ItemDB.CAT_NAMES.get(it["cat"], ""), ItemDB.describe(s["id"]), extra]
	if sel_eq != "":
		det_btns.add_child(UIKit.button("اخلع", func(): p.unequip(sel_eq); sel_eq = ""; refresh(), 20))
		return
	if it.has("food"):
		det_btns.add_child(UIKit.button("اشرب" if it["food"].get("t", 0) > it["food"].get("h", 0) else "كُل", func(): p.use_slot(sel_i); refresh(), 20))
	if it.has("med"):
		det_btns.add_child(UIKit.button("استخدم", func(): p.use_slot(sel_i); refresh(), 20))
	if it.has("wear"):
		det_btns.add_child(UIKit.button("ارتدِ", func(): p.equip_from_slot(sel_i); sel_i = -1; refresh(), 20))
	if s["n"] > 1:
		det_btns.add_child(UIKit.button("اقسم", _split, 20))
	det_btns.add_child(UIKit.button("أسقط 1", func(): p.drop_slot(sel_i, 1); _fix_sel(); refresh(), 20))
	det_btns.add_child(UIKit.button("أسقط الكل", func(): p.drop_slot(sel_i); sel_i = -1; refresh(), 20))

func _fix_sel() -> void:
	if sel_i >= 0 and player().inventory.slots[sel_i] == null:
		sel_i = -1

func _split() -> void:
	var inv := player().inventory
	var s = inv.slots[sel_i]
	if s == null or s["n"] < 2:
		return
	for j in range(inv.size()):
		if inv.slots[j] == null:
			var half := int(s["n"] / 2)
			inv.slots[j] = {"id": s["id"], "n": half, "d": s.get("d", -1.0), "a": s.get("a", 0.0)}
			s["n"] -= half
			inv.changed.emit()
			break
	refresh()

func _on_slot(i: int) -> void:
	var p := player()
	if sel_eq != "":
		sel_eq = ""
	if sel_i == -1:
		if p.inventory.slots[i] != null:
			sel_i = i
	elif sel_i == i:
		sel_i = -1
	else:
		p.inventory.swap(sel_i, i)
		sel_i = -1
	refresh()

func _on_equip(slot: String) -> void:
	sel_i = -1
	sel_eq = slot if player().equipment[slot] != null else ""
	refresh()
