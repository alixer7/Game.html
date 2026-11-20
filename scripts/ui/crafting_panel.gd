extends ModalPanel
## نافذة التصنيع: تصنيفات، قائمة الوصفات، المكونات المطلوبة، المحطة المطلوبة، وطابور الصناعة.

var cat := "all"
var only_avail := false
var station_hint := ""
var list: VBoxContainer
var det: VBoxContainer
var tabs: HBoxContainer
var sel_r := -1
var avail_btn: Button

func build() -> void:
	make_frame("التصنيع")
	tabs = UIKit.hbox(6)
	tabs.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(tabs)
	var row := UIKit.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	det = UIKit.vbox(8)
	det.custom_minimum_size = Vector2(420, 0)
	det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(det)
	var sc := UIKit.scroll()
	sc.custom_minimum_size = Vector2(520, 0)
	row.add_child(sc)
	list = UIKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)

func open_for(station: String) -> void:
	station_hint = station
	cat = "all"
	sel_r = -1
	open()

func refresh() -> void:
	clear(tabs)
	avail_btn = UIKit.button("المتاح فقط (مفعّل)" if only_avail else "المتاح فقط", func(): only_avail = not only_avail; refresh(), 18, 46)
	tabs.add_child(avail_btn)
	for c in RecipeDB.CATS:
		var b := UIKit.button(RecipeDB.CAT_NAMES[c], func(): cat = c; refresh(), 18, 46)
		if cat == c:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color(0.45, 0.34, 0.15, 1.0), 10, 2, UIKit.GOLD, 10))
		tabs.add_child(b)
	var ab := UIKit.button("الكل", func(): cat = "all"; refresh(), 18, 46)
	if cat == "all":
		ab.add_theme_stylebox_override("normal", UIKit.sb(Color(0.45, 0.34, 0.15, 1.0), 10, 2, UIKit.GOLD, 10))
	tabs.add_child(ab)
	clear(list)
	var p := player()
	var idxs := []
	for i in range(RecipeDB.recipes.size()):
		var r: Dictionary = RecipeDB.recipes[i]
		if cat != "all" and r["cat"] != cat:
			continue
		var why := p.can_craft(r)
		if only_avail and why != "":
			continue
		idxs.append(i)
	if station_hint != "":
		idxs.sort_custom(func(a, b): return int(RecipeDB.recipes[a]["station"] == station_hint) > int(RecipeDB.recipes[b]["station"] == station_hint))
	for i in idxs:
		var r: Dictionary = RecipeDB.recipes[i]
		var why: String = p.can_craft(r)
		var has_mats: bool = p.inventory.has_all(r["needs"])
		var h := UIKit.hbox(8)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): sel_r = i; _details())
		if i == sel_r:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color(0.45, 0.34, 0.15, 1.0), 10, 2, UIKit.GOLD, 10))
		var inner := UIKit.hbox(8)
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.alignment = BoxContainer.ALIGNMENT_END
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(inner)
		var st_name: String = RecipeDB.STATION_NAMES.get(r["station"], "")
		var col := UIKit.GOOD if why == "" else (Color(1, 0.8, 0.45) if has_mats else Color(0.75, 0.72, 0.68))
		var l := UIKit.label("%s ×%d  —  %s" % [ItemDB.name_of(r["out"]), r["n"], st_name], 19, col)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(l)
		var ic := ItemIcon.new()
		ic.custom_minimum_size = Vector2(56, 56)
		ic.set_item(r["out"], r["n"])
		inner.add_child(ic)
		h.add_child(b)
		list.add_child(h)
	if sel_r == -1 and not idxs.is_empty():
		sel_r = idxs[0]
	_details()

func _do_craft(r: Dictionary, m: int) -> void:
	if player().craft(r, m):
		refresh()

func _details() -> void:
	clear(det)
	var p := player()
	if p.craft_queue.size() > 0:
		var q: Dictionary = p.craft_queue[0]
		det.add_child(UIKit.label("قيد الصنع: %s (%d ث)%s" % [ItemDB.name_of(q["r"]["out"]), int(q["t"]), "  +%d بالانتظار" % (p.craft_queue.size() - 1) if p.craft_queue.size() > 1 else ""], 17, UIKit.GOLD))
	if sel_r < 0:
		det.add_child(UIKit.label("اختر وصفة من القائمة", 20, UIKit.DIM))
		return
	var r: Dictionary = RecipeDB.recipes[sel_r]
	var hh := UIKit.hbox(10)
	hh.alignment = BoxContainer.ALIGNMENT_END
	var nm := UIKit.label("%s ×%d" % [ItemDB.name_of(r["out"]), r["n"]], 26, UIKit.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(nm)
	var ic := ItemIcon.new()
	ic.custom_minimum_size = Vector2(84, 84)
	ic.set_item(r["out"], r["n"])
	hh.add_child(ic)
	det.add_child(hh)
	det.add_child(UIKit.label(ItemDB.describe(r["out"]), 17, UIKit.DIM))
	det.add_child(UIKit.sep())
	det.add_child(UIKit.label("المكونات:", 20, UIKit.GOLD))
	for k in r["needs"]:
		var have := p.inventory.count_key(k)
		var need: int = r["needs"][k]
		det.add_child(UIKit.label("%s: %d / %d" % [RecipeDB.need_name(k), have, need], 19, UIKit.GOOD if have >= need else UIKit.BAD))
	for k in r.get("extra_out", {}):
		det.add_child(UIKit.label("يعيد أيضاً: %s ×%d" % [ItemDB.name_of(k), r["extra_out"][k]], 17, UIKit.DIM))
	var st: String = r["station"]
	var st_ok: bool = world().build.station_near(p.global_position, st)
	det.add_child(UIKit.label("المكان: %s %s" % [RecipeDB.STATION_NAMES.get(st, st), "(متوفرة)" if st_ok else "(يجب أن تكون قربها)"], 19, UIKit.GOOD if st_ok else UIKit.BAD))
	if st == "campfire" and not st_ok:
		det.add_child(UIKit.label("ابنِ نار مخيم من قائمة البناء وأشعلها بالحطب", 16, UIKit.DIM))
	elif st != "hand" and not st_ok:
		det.add_child(UIKit.label("ابنِ هذه المحطة من قائمة البناء (محطات صناعة)", 16, UIKit.DIM))
	det.add_child(UIKit.label("الوقت: %.1f ث" % (r["time"] / (1.0 + p.stats.skill_level("crafting") * 0.06)), 17, UIKit.DIM))
	var bh := UIKit.hbox(10)
	bh.alignment = BoxContainer.ALIGNMENT_END
	det.add_child(bh)
	var why := p.can_craft(r)
	var b1 := UIKit.button("اصنع", _do_craft.bind(r, 1), 24, 68)
	b1.custom_minimum_size = Vector2(180, 68)
	b1.disabled = why != ""
	bh.add_child(b1)
	var b5 := UIKit.button("اصنع ×5", _do_craft.bind(r, 5), 20, 68)
	b5.disabled = p.can_craft(r, 5) != ""
	bh.add_child(b5)
	if why != "":
		det.add_child(UIKit.label(why, 18, UIKit.BAD))
