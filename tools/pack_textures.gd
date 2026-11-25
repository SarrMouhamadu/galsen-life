extends SceneTree
## Assemble les textures photo de la ville (ambientCG, CC0) en deux tableaux de textures :
##   world/textures/city_albedo.png : détail de couleur (normalisé, multiplie la couleur des sommets) + rugosité en alpha
##   world/textures/city_normal.png : cartes de normales (convention OpenGL)
## Une couche par matériau, empilées verticalement (importées comme Texture2DArray).
## Usage : godot --headless --path . -s res://tools/pack_textures.gd -- <dossier des JPG ambientCG>

## Ordre des couches (le même que dans les shaders city_ground / city_facade)
const LAYERS := ["Asphalt031", "PavingStones128", "Concrete034", "Ground054", "CorrugatedSteel007A", "Plaster007", "Wood051", "Fabric086"]
const SIZE := 1024
const OUT := "res://world/textures/"


func _init() -> void:
	var src: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var alb := Image.create_empty(SIZE, SIZE * LAYERS.size(), false, Image.FORMAT_RGBA8)
	var nrm := Image.create_empty(SIZE, SIZE * LAYERS.size(), false, Image.FORMAT_RGB8)
	for i in LAYERS.size():
		var id: String = LAYERS[i]
		var col := _load(src, id, "Color")
		var rough := _load(src, id, "Roughness")
		var nm := _load(src, id, "NormalGL")
		# Couleur moyenne : le détail est relatif (×2 autour de 0,5) pour garder la teinte des sommets
		var small := col.duplicate()
		small.resize(16, 16, Image.INTERPOLATE_CUBIC)
		var mean := Color(0, 0, 0)
		for y in 16:
			for x in 16:
				mean += small.get_pixel(x, y)
		mean = mean / 256.0
		var cd := col.get_data()
		var rd := rough.get_data()
		var out := PackedByteArray()
		out.resize(SIZE * SIZE * 4)
		var k := [0.5 / maxf(mean.r, 0.02), 0.5 / maxf(mean.g, 0.02), 0.5 / maxf(mean.b, 0.02)]
		var kr: float = k[0]
		var kg: float = k[1]
		var kb: float = k[2]
		for px in SIZE * SIZE:
			var s := px * 3
			var o := px * 4
			out[o] = mini(255, int(cd[s] * kr))
			out[o + 1] = mini(255, int(cd[s + 1] * kg))
			out[o + 2] = mini(255, int(cd[s + 2] * kb))
			out[o + 3] = rd[s]
		var layer := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, out)
		alb.blit_rect(layer, Rect2i(0, 0, SIZE, SIZE), Vector2i(0, i * SIZE))
		nrm.blit_rect(nm, Rect2i(0, 0, SIZE, SIZE), Vector2i(0, i * SIZE))
		print("%s : moyenne %s" % [id, mean])
	alb.save_png(OUT + "city_albedo.png")
	nrm.save_png(OUT + "city_normal.png")
	# Bois et tissu seuls (étals des marchés)
	for pair in [["Wood051", "wood"], ["Fabric086", "fabric"]]:
		var c := _load(src, pair[0], "Color")
		c.resize(512, 512, Image.INTERPOLATE_CUBIC)
		if pair[1] == "fabric":
			c.adjust_bcs(1.35, 1.0, 0.0) # gris clair : teinté par la couleur de la bâche
		else:
			c.adjust_bcs(2.2, 1.0, 0.9) # bois clair (teinté ensuite)
		c.save_jpg(OUT + pair[1] + ".jpg", 0.9)
	print("textures de la ville : ok")
	quit()


func _load(src: String, id: String, map: String) -> Image:
	var img := Image.load_from_file("%s/%s_1K-JPG_%s.jpg" % [src, id, map])
	img.convert(Image.FORMAT_RGB8)
	if img.get_size() != Vector2i(SIZE, SIZE):
		img.resize(SIZE, SIZE, Image.INTERPOLATE_CUBIC)
	return img
