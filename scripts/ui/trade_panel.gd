extends ModalPanel
## المقايضة: اختر ما تريد أخذه وما تعرضه. الأسعار تتأثر بالعلاقة وجشع التاجر ومهارة الإقناع.

var npc = null
var their: VBoxContainer
var yours: VBoxContainer
var summary: Label
var want := {}
var give := {}

func build() -> void:
	make_frame("المقايضة")
	summary = UIKit.label("", 20, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(summary)
	var bh := UIKit.hbox(10)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(bh)
	bh.add_child(UIKit.button("امسح الاختيار", func(): want.clear(); give.clear(); refresh(), 20, 56))
	var deal := UIKit.button("اعرض الصفقة", _deal, 22, 56)
	deal.custom_minimum_size = Vector2(220, 56)
	bh.add_child(deal)
	var row := UIKit.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var lv := UIKit.vbox(6)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lv)
	lv.add_child(UIKit.label("بضاعته (اضغط لإضافة واحد)", 19, UIKit.GOLD))
	var s1 := UIKit.scroll()
	lv.add_child(s1)
	their = UIKit.vbox(4)
	their.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s1.add_child(their)
	var rv := UIKit.vbox(6)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rv)
	rv.add_child(UIKit.label("أغراضك (اضغط لعرض واحد)", 19, UIKit.GOLD))
	var s2 := UIKit.scroll()
	rv.add_child(s2)
	yours = UIKit.vbox(4)
	yours.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s2.add_child(yours)

func open_for(n) -> void:
	npc = n
	want.clear()
	give.clear()
	npc.in_dialog = true
	open()

func close() -> void:
	if npc != null and is_instance_valid(npc):
		npc.in_dialog = false
	super.close()

func _price(id: String, buying: bool) -> float:
	return maxf(0.5, ItemDB.value_of(id) * world().ai.price_mult(npc.data, buying))

func refresh() -> void:
	if npc == null or not is_instance_valid(npc) or npc.dead:
		close()
		return
	title_lbl.text = "مقايضة مع %s" % npc.data["name"]
	var ninv: Inventory = npc.data["inv"]
	var pinv := player().inventory
	clear(their)
	for i in range(ninv.size()):
		var s = ninv.slots[i]
		if s == null:
			continue
		var w: int = want.get(i, 0)
		their.add_child(_row(s, w, _price(s["id"], true), func(): want[i] = mini(want.get(i, 0) + 1, s["n"]); refresh()))
	clear(yours)
	for i in range(pinv.size()):
		var s = pinv.slots[i]
		if s == null:
			continue
		var g: int = give.get(i, 0)
		yours.add_child(_row(s, g, _price(s["id"], false), func(): give[i] = mini(give.get(i, 0) + 1, s["n"]); refresh()))
	var tv := _total_want()
	var gv := _total_give()
	summary.text = "قيمة ما تأخذه: %.1f   |   قيمة ما تعطيه: %.1f   %s" % [tv, gv, "(صفقة مقبولة)" if gv >= tv and tv > 0.0 else ("(أضف المزيد)" if tv > 0.0 else "")]
	summary.add_theme_color_override("font_color", UIKit.GOOD if gv >= tv and tv > 0.0 else UIKit.TEXT)

func _row(s: Dictionary, sel: int, price: float, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 58)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	if sel > 0:
		b.add_theme_stylebox_override("normal", UIKit.sb(Color(0.4, 0.32, 0.15, 1.0), 10, 2, UIKit.GOLD, 8))
	var h := UIKit.hbox(8)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_END
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var l := UIKit.label("%s ×%d   (%.1f للوحدة)%s" % [ItemDB.name_of(s["id"]), s["n"], price, ("   مختار: %d" % sel) if sel > 0 else ""], 18, UIKit.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var ic := ItemIcon.new()
	ic.custom_minimum_size = Vector2(50, 50)
	ic.set_item(s["id"], s["n"])
	h.add_child(ic)
	return b

func _total_want() -> float:
	var t := 0.0
	var ninv: Inventory = npc.data["inv"]
	for i in want:
		var s = ninv.slots[i]
		if s != null:
			t += _price(s["id"], true) * want[i]
	return t

func _total_give() -> float:
	var t := 0.0
	var pinv := player().inventory
	for i in give:
		var s = pinv.slots[i]
		if s != null:
			t += _price(s["id"], false) * give[i]
	return t

func _deal() -> void:
	var tv := _total_want()
	var gv := _total_give()
	if tv <= 0.0 and gv <= 0.0:
		return
	if gv < tv:
		Game.notify("%s: هذا لا يكفي، أضف المزيد" % npc.data["name"], Color(1, 0.8, 0.5))
		Sfx.play("click")
		return
	var ninv: Inventory = npc.data["inv"]
	var pinv := player().inventory
	var got := []
	for i in want:
		var s = ninv.slots[i]
		if s != null:
			got.append(ninv.take_slot(i, want[i]))
	var gave := []
	for i in give:
		var s = pinv.slots[i]
		if s != null:
			gave.append(pinv.take_slot(i, give[i]))
	for st in gave:
		ninv.add_stack(st)
	var list := []
	for st in got:
		list.append([st["id"], st["n"]])
	player().receive_items(list, player().global_position)
	var ai: Node = world().ai
	var bonus := clampf((gv - tv) * 0.5, 0.0, 6.0) + 1.0
	ai.add_rel(npc.data["id"], "player", bonus)
	player().stats.add_skill_xp("social", 2.0 + tv * 0.05)
	Sfx.play("coin")
	Game.notify("تمت الصفقة مع %s" % npc.data["name"], Color(0.7, 1, 0.7))
	want.clear()
	give.clear()
	refresh()
