extends SceneTree
## Images de la fiche Google Play : icône 512 × 512 et bannière 1024 × 500,
## composées à partir des captures du jeu (export/store/*.png).
## Usage (avec rendu, pas --headless) : godot --path . -s res://tools/store_art.gd

const DIR := "res://export/store/"
const GREEN := Color("00853f")
const YELLOW := Color("fdef42")
const RED := Color("e31b23")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _render(Vector2i(1024, 500), _banner, "banniere_1024x500.png")
	await _render(Vector2i(512, 512), _icon, "icone_512.png")
	print("images de la fiche : ok")
	quit()


func _render(size: Vector2i, build: Callable, out: String) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var c := Control.new()
	c.size = size
	vp.add_child(c)
	build.call(c, Vector2(size))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8) # Play : pas de transparence
	img.save_png(ProjectSettings.globalize_path(DIR + out))
	vp.queue_free()


func _photo(parent: Control, file: String, rect: Rect2) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + file))
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.position = rect.position
	tr.size = rect.size
	parent.add_child(tr)


func _shade(parent: Control, rect: Rect2, from: Color, to: Color, horizontal: bool) -> void:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.position = rect.position
	tr.size = rect.size
	parent.add_child(tr)


func _text(parent: Control, txt: String, pos: Vector2, w: float, fsize: int, col: Color, outline := 0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.size = Vector2(w, fsize * 1.3)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	parent.add_child(l)


func _flag_band(parent: Control, rect: Rect2) -> void:
	var w := rect.size.x / 3.0
	for k in 3:
		var r := ColorRect.new()
		r.color = [GREEN, YELLOW, RED][k]
		r.position = rect.position + Vector2(w * k, 0)
		r.size = Vector2(w + 1, rect.size.y)
		parent.add_child(r)


## Bannière : la rue de Dakar, titre à gauche sur un dégradé sombre
func _banner(c: Control, s: Vector2) -> void:
	_photo(c, "propre_rue.png", Rect2(Vector2.ZERO, s))
	_shade(c, Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.0), true)
	_flag_band(c, Rect2(0, s.y - 12, s.x, 12))
	_text(c, "GALSEN-LIFE", Vector2(48, 120), 700, 92, Color.WHITE, 10)
	_text(c, "Vis ta vie à Dakar", Vector2(52, 238), 700, 40, YELLOW, 6)
	_text(c, "Métiers • Lutte • Marchés • Jeu en ligne", Vector2(52, 300), 700, 28, Color(1, 1, 1, 0.92), 5)


## Icône : scène de nuit, drapeau en bas, nom du jeu
func _icon(c: Control, s: Vector2) -> void:
	_photo(c, "propre_nuit.png", Rect2(Vector2(-180, 0), Vector2(s.x * 1.7, s.y)))
	_shade(c, Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.15), Color(0, 0, 0, 0.75), false)
	_flag_band(c, Rect2(0, s.y - 150, s.x, 150))
	var star := Label.new()
	star.text = "★"
	star.position = Vector2(0, s.y - 160)
	star.size = Vector2(s.x, 150)
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	star.add_theme_font_size_override("font_size", 120)
	star.add_theme_color_override("font_color", GREEN)
	c.add_child(star)
	_text(c, "GALSEN", Vector2(0, 70), s.x, 118, Color.WHITE, 14, HORIZONTAL_ALIGNMENT_CENTER)
	_text(c, "LIFE", Vector2(0, 205), s.x, 104, YELLOW, 14, HORIZONTAL_ALIGNMENT_CENTER)
