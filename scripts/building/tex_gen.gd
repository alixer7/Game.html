class_name TexGen
extends RefCounted
## توليد خامات إجرائية للمباني (ألواح خشب، كتل حجرية، طوب، قش) مع خرائط نتوءات.

static var _mats := {}

static func building_mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var img: Image
	var rough := 0.85
	match kind:
		"wood": img = _planks()
		"stone": img = _stone()
		"brick": img = _brick()
		"thatch": img = _thatch()
		"log": img = _planks(true)
		_: img = _stone()
	var tex := ImageTexture.create_from_image(img)
	var nimg := img.duplicate()
	nimg.convert(Image.FORMAT_RGBA8)
	nimg.bump_map_to_normal_map(3.0 if kind != "thatch" else 2.0)
	nimg.generate_mipmaps()
	var ntex := ImageTexture.create_from_image(nimg)
	img.generate_mipmaps()
	tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.normal_enabled = true
	m.normal_texture = ntex
	m.normal_scale = 0.8
	m.roughness = rough if kind != "stone" else 0.92
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[kind] = m
	return m

static func _nz(s: int, f: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.frequency = f
	n.fractal_octaves = 3
	return n

static func _planks(logs := false) -> Image:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var n := _nz(3, 0.08)
	var g := _nz(5, 0.02)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var pw := 32
	var tints := []
	for i in range(S / pw):
		tints.append(r.randf_range(0.82, 1.12))
	for y in range(S):
		for x in range(S):
			var pi := x / pw
			var lx := x % pw
			var grain := sin((y * 0.35 + n.get_noise_2d(x * 3.0, y * 0.5) * 6.0 + pi * 13.0)) * 0.5 + 0.5
			var base = Color(0.5, 0.33, 0.19) * tints[pi]
			var c = base.lerp(Color(0.36, 0.22, 0.12), grain * 0.35 + g.get_noise_2d(x, y) * 0.2)
			if lx < 2 or lx > pw - 2:
				c = c.darkened(0.55)
			if not logs and (y % 64 < 2) and ((pi % 2 == 0)):
				c = c.darkened(0.45)
			if not logs and ((lx == 6 or lx == pw - 7) and (y % 64 == 8 or y % 64 == 56)):
				c = Color(0.25, 0.25, 0.27)
			img.set_pixel(x, y, c)
	return img

static func _stone() -> Image:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var n := _nz(11, 0.09)
	var n2 := _nz(13, 0.3)
	var r := RandomNumberGenerator.new()
	r.seed = 17
	var rh := 32
	for row in range(S / rh):
		var off := r.randi_range(0, 40)
		var x0 := -off
		while x0 < S:
			var w := r.randi_range(36, 60)
			var tint := r.randf_range(0.8, 1.15)
			var base := Color(0.55, 0.53, 0.5) * tint
			for y in range(row * rh, row * rh + rh):
				for xx in range(x0, x0 + w):
					var x := posmod(xx, S)
					var ly := y - row * rh
					var lx := xx - x0
					var c := base * (0.85 + n.get_noise_2d(x, y) * 0.25 + n2.get_noise_2d(x, y) * 0.1)
					var edge := mini(mini(ly, rh - 1 - ly), mini(lx, w - 1 - lx))
					if edge < 2:
						c = Color(0.62, 0.6, 0.56) * (0.7 + n2.get_noise_2d(x, y) * 0.2)
					elif edge < 4:
						c = c.darkened(0.2)
					img.set_pixel(x, y, c)
			x0 += w
	return img

static func _brick() -> Image:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var n := _nz(21, 0.15)
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var bh := 16
	var bw := 32
	for row in range(S / bh):
		var off := (bw / 2) if row % 2 == 1 else 0
		for b in range(-1, S / bw + 1):
			var tint := r.randf_range(0.82, 1.12)
			var base := Color(0.62, 0.28, 0.18) * tint
			for y in range(row * bh, row * bh + bh):
				for xx in range(b * bw + off, b * bw + off + bw):
					if xx < 0 or xx >= S:
						continue
					var ly := y - row * bh
					var lx := xx - (b * bw + off)
					var c := base * (0.88 + n.get_noise_2d(xx, y) * 0.22)
					if ly < 2 or lx < 2:
						c = Color(0.72, 0.68, 0.6) * (0.85 + n.get_noise_2d(xx * 2, y * 2) * 0.15)
					img.set_pixel(xx, y, c)
	return img

static func _thatch() -> Image:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var n := _nz(31, 0.5)
	var n2 := _nz(37, 0.05)
	for y in range(S):
		for x in range(S):
			var row := y % 24
			var straw := n.get_noise_2d(x * 1.0, y * 0.08) * 0.5 + 0.5
			var c := Color(0.72, 0.6, 0.32).lerp(Color(0.52, 0.42, 0.2), straw)
			c *= 0.85 + n2.get_noise_2d(x, y) * 0.3
			if row > 19:
				c = c.darkened(0.35 + (row - 19) * 0.06)
			img.set_pixel(x, y, c)
	return img
