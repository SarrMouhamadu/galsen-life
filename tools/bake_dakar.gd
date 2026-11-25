extends SceneTree
## Outil hors-jeu : convertit les données OpenStreetMap du Plateau et de la Médina en ville jouable.
##
##   godot --headless --path . -s res://tools/bake_dakar.gd
##
## Entrée  : tools/osm/dakar_raw.json (requête Overpass, voir tools/osm/query.overpassql)
## Sorties : world/dakar/city.scn   maillages fusionnés par blocs de 400 m + collisions
##           world/dakar/data.json  réseau routier, lieux, quartiers
##           world/dakar/minimap.png
##
## Données © les contributeurs d'OpenStreetMap, licence ODbL.

const Mk = preload("res://scripts/util/mk.gd")
const SidewalkPlan = preload("res://scripts/world/sidewalk_plan.gd")

const SRC := "res://tools/osm/dakar_raw.json"
const DETAILS := "res://tools/osm/dakar_details.json" ## feux, passages piétons, terrains, plages, lieux de culte
const OUT_DIR := "res://world/dakar"
const LAT0 := 14.675
const LON0 := -17.44
const BBOX := [14.653, -17.455, 14.690, -17.425] # sud, ouest, nord, est (jusqu'à l'Anse Bernard)
const CHUNK := 150.0 ## petits blocs : le téléphone ne dessine que ce qui est à portée de vue
const MAP_RES := 2.0 # mètres par pixel de la mini-carte
const FILL_STEP := 12.0
const ROAD_Y := 0.07
const WALK_Y := 0.03
const SIDEWALK_Y := 0.16 ## trottoirs surélevés
const SIDEWALK_W := 1.8
const DOOR_COLORS := [Color("1f4e9c"), Color("1e7a4a"), Color("a4161a"), Color("6c757d"), Color("2a9d8f"), Color("b08968")]
const AD_COLORS := [Color("ff6b00"), Color("1dc3f3"), Color("e63946"), Color("ffd60a"), Color("2a9d8f"), Color("7b2cbf")]
const AWNING_COLORS := [Color("2f6e4a"), Color("b23a2e"), Color("1f4e8c"), Color("d9a520"), Color("7a3e8c")] ## toiles des auvents

const ROAD_WIDTH := {
	"motorway": 16.0, "trunk": 14.0, "trunk_link": 7.0, "primary": 12.0, "primary_link": 7.0,
	"secondary": 10.0, "secondary_link": 7.0, "tertiary": 8.5, "tertiary_link": 6.5,
	"unclassified": 6.5, "residential": 6.5, "living_street": 5.5, "road": 6.5,
	"service": 4.5, "pedestrian": 5.0,
}
const TRAFFIC := ["motorway", "trunk", "trunk_link", "primary", "primary_link", "secondary",
	"secondary_link", "tertiary", "tertiary_link", "unclassified", "residential", "living_street", "road"]
const NO_WALK := ["motorway", "trunk", "trunk_link"]
const DASHED := ["trunk", "primary", "secondary"]
const FACADES := [
	Color("d9a066"), Color("e8d5b0"), Color("f2efe6"), Color("e9c46a"), Color("c8643b"),
	Color("9cc5d9"), Color("e8a0a8"), Color("b9d8a5"), Color("ddd5c4"), Color("f4e1c1"),
]
## Style des bâtiments célèbres (nom OSM normalisé → couleur, étages)
const STYLES := {
	"Grande Mosquée de Dakar": [Color("f4f1ea"), 4.0],
	"Marché Sandaga": [Color("c9773c"), 3.0],
	"Cathédrale du Souvenir africain": [Color("efe3c8"), 6.0],
	"Hopital Principal de Dakar": [Color("f8f9fa"), 4.0],
	"Assemblée Nationale du Sénégal": [Color("f1f1ee"), 4.0],
	"Gare de Dakar": [Color("f0d9a8"), 2.0],
	"Marché Kermel": [Color("e9c46a"), 2.0],
	"Marché Tilène": [Color("d9a066"), 2.0],
}
## Lieux du jeu : nom OSM normalisé → [nom dans le jeu, texte du panneau, décor]
const LANDMARKS := {
	"Place de l'Indépendance": ["Place de l'Indépendance", "Place de l'Indépendance", "place"],
	"Marché Sandaga": ["Marché Sandaga", "Marché Sandaga", ""],
	"Grande Mosquée de Dakar": ["Grande Mosquée", "Grande Mosquée", "minaret"],
	"Hopital Principal de Dakar": ["Hôpital Principal", "Hôpital Principal", "cross"],
	"Cathédrale du Souvenir africain": ["Cathédrale", "Cathédrale du Souvenir africain", ""],
	"Assemblée Nationale du Sénégal": ["Assemblée nationale", "Assemblée nationale", ""],
	"Gare de Dakar": ["Gare de Dakar", "Gare de Dakar", ""],
	"Marché Kermel": ["Marché Kermel", "Marché Kermel", ""],
	"Marché Tilène": ["Marché Tilène", "Marché Tilène", ""],
	"Gare Routière Petersen": ["Gare routière Petersen", "Gare routière Petersen", ""],
	"Porte du Troisième Millénaire": ["Porte du Millénaire", "Porte du Troisième Millénaire", "porte"],
	"Commissariat de Police de Reubeuss": ["Commissariat", "Commissariat de Rebeuss", ""],
	"Dibiterie Le Mboté": ["Dibiterie", "Dibiterie Le Mboté", ""],
	"État major Gendarmerie Senegal": ["Caserne", "État-major de la Gendarmerie", "caserne"],
}


class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()


class Chunk:
	var walls := Surf.new()
	var roofs := Surf.new()
	var roads := Surf.new()
	var col := PackedVector3Array()
	var roof_col := PackedVector3Array() ## toits : collision invisible (couche 8) pour savoir si on est dans un bâtiment


var kx := 0.0
var kz := 0.0
var min_x := 0.0
var max_x := 0.0
var min_z := 0.0
var max_z := 0.0
var rng := RandomNumberGenerator.new()

var buildings: Array = [] # {poly, levels, kind, name}
var roads: Array = [] # {ids, pts, hw, width, oneway, name}
var coast: Array = [] # {ids, pts}
var districts: Array = [] # [nom, Vector2]
var pois: Array = [] # {name, c, poly}
var nofill: Array = [] # polygones sans remplissage (places, parcs)
var port_yards: Array = [] ## {poly, name, dense} : terminal à conteneurs et môles du port (landuse OSM nommés)

var node_index := {} # id OSM → index
var node_pos := PackedVector2Array()
var edges: Array = [] # [a, b, largeur, drapeaux, nom]
var street_names: Array = []
var lands: Array = [] # polygones de terre (x, z)

var gw := 0
var gh := 0
var grid := PackedByteArray() # 0 libre, 1 route, 2 bâtiment, 3 non constructible, 4 mer
var seg_hash := {} # cellule → [[a, b, largeur, traffic]]
var places := {}
var parking: Array = []
var chunks := {}

# Détails (tools/osm/dakar_details.json)
var signals: Array = []
var stop_signs: Array = []
var crossings: Array = []
var pitches: Array = [] ## {sport, poly, name}
var beaches: Array = []
var beach_names: Array = [] ## [nom, position] des points « plage » nommés
var parks: Array = []
var worship: Array = [] ## {religion, name, c, poly}
var signal_nodes: Array = []


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	rng.seed = 221
	kx = 111320.0 * cos(deg_to_rad(LAT0))
	kz = 110574.0
	var sw := proj(BBOX[0], BBOX[1])
	var ne := proj(BBOX[2], BBOX[3])
	min_x = sw.x
	max_x = ne.x
	min_z = ne.y
	max_z = sw.y
	var raw = JSON.parse_string(FileAccess.get_file_as_string(SRC))
	_collect(raw["elements"])
	_collect_details()
	_collect_extra(raw["elements"])
	print("collecte : %d bâtiments, %d routes, %d côtes, %d lieux" % [buildings.size(), roads.size(), coast.size(), pois.size()])
	_build_graph()
	_compute_elevation()
	_compute_land()
	print("terre : %d polygone(s)" % lands.size())
	_raster()
	var before := buildings.size()
	_fill_buildings()
	print("remplissage : %d bâtiments générés" % (buildings.size() - before))
	_compute_places()
	_compute_service_places()
	_collect_trees()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_map_signals()
	_auto_signals()
	_compute_rules()
	_build_scene()
	_write_data()
	_write_minimap()
	print("terminé en %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


func proj(lat: float, lon: float) -> Vector2:
	return Vector2((lon - LON0) * kx, -(lat - LAT0) * kz)


func _norm(s: String) -> String:
	return s.replace("’", "'").strip_edges()


func _inside(p: Vector2, margin := 0.0) -> bool:
	return p.x > min_x - margin and p.x < max_x + margin and p.y > min_z - margin and p.y < max_z + margin


# --- Lecture des données OSM ---------------------------------------------------

func _geom(g: Array, closed_dedupe := true) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in g:
		if p == null:
			continue
		out.append(proj(p["lat"], p["lon"]))
	if closed_dedupe and out.size() > 2 and out[0].distance_to(out[out.size() - 1]) < 0.01:
		out.remove_at(out.size() - 1)
	return out


func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(1.0, poly.size())


func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func _collect(els: Array) -> void:
	for e in els:
		var tags: Dictionary = e.get("tags", {})
		var etype: String = e["type"]
		var name := _norm(str(tags.get("name", "")))
		if tags.has("building") and etype == "way" and e.has("geometry"):
			_add_building(_geom(e["geometry"]), tags, name)
		elif tags.has("building") and etype == "relation":
			for m in e.get("members", []):
				if m.get("role", "") == "outer" and m.has("geometry"):
					_add_building(_geom(m["geometry"]), tags, name)
		if tags.has("highway") and etype == "way" and e.has("geometry") and ROAD_WIDTH.has(tags["highway"]):
			var hw: String = tags["highway"]
			var width: float = ROAD_WIDTH[hw]
			if tags.has("lanes"):
				width = clampf(str(tags["lanes"]).to_int() * 3.3, 4.0, 18.0)
			var oneway := 0
			var ow := str(tags.get("oneway", "no"))
			if ow in ["yes", "1", "true"] or tags.get("junction", "") == "roundabout" or hw == "motorway":
				oneway = 1
			elif ow == "-1":
				oneway = -1
			roads.append({"ids": e["nodes"], "pts": _geom(e["geometry"], false), "hw": hw, "width": width, "oneway": oneway, "name": name,
				"bridge": str(tags.get("bridge", "no")) in ["yes", "viaduct"], "tunnel": str(tags.get("tunnel", "no")) == "yes"})
		if tags.get("natural", "") == "coastline" and etype == "way" and e.has("geometry"):
			coast.append({"ids": e["nodes"], "pts": _geom(e["geometry"], false)})
		if tags.has("place") and etype == "node" and tags["place"] != "square" and name != "":
			districts.append([name.replace("Medina", "Médina"), proj(e["lat"], e["lon"])])
		if name != "" and not tags.has("highway") or (tags.has("highway") and tags.get("area", "") == "yes" and name != ""):
			var poly := PackedVector2Array()
			var c := Vector2.ZERO
			if etype == "node":
				c = proj(e["lat"], e["lon"])
			elif e.has("geometry"):
				poly = _geom(e["geometry"])
				c = _centroid(poly)
			elif e.has("bounds"):
				var b: Dictionary = e["bounds"]
				c = proj((b["minlat"] + b["maxlat"]) / 2.0, (b["minlon"] + b["maxlon"]) / 2.0)
			pois.append({"name": name, "c": c, "poly": poly})
			if poly.size() >= 3 and not tags.has("building") and (tags.get("place", "") == "square" or tags.has("leisure") or tags.get("highway", "") == "pedestrian"):
				nofill.append(poly)


func _add_building(poly: PackedVector2Array, tags: Dictionary, name: String) -> void:
	if poly.size() < 3 or _area(poly) < 10.0:
		return
	var kind := str(tags["building"])
	if kind in ["roof", "ruins", "no"]:
		return
	if not _inside(_centroid(poly)):
		return
	var levels := -1.0
	if tags.has("building:levels"):
		levels = str(tags["building:levels"]).to_float()
	elif tags.has("height"):
		levels = str(tags["height"]).to_float() / 3.2
	buildings.append({"poly": poly, "levels": levels, "kind": kind, "name": name})


# --- Réseau routier --------------------------------------------------------------

func _node(id: int, p: Vector2) -> int:
	if node_index.has(id):
		return node_index[id]
	node_index[id] = node_pos.size()
	node_pos.append(p)
	return node_pos.size() - 1


func _build_graph() -> void:
	var seen := {}
	for r in roads:
		var ids: Array = r["ids"]
		var pts: PackedVector2Array = r["pts"]
		if ids.size() != pts.size():
			continue
		var hw: String = r["hw"]
		var name_idx := -1
		if r["name"] != "":
			name_idx = street_names.find(r["name"])
			if name_idx == -1:
				street_names.append(r["name"])
				name_idx = street_names.size() - 1
		for i in ids.size() - 1:
			var pa := pts[i]
			var pb := pts[i + 1]
			if not _inside(pa, 40.0) or not _inside(pb, 40.0) or pa.distance_to(pb) < 0.05:
				continue
			var a := _node(int(ids[i]), pa)
			var b := _node(int(ids[i + 1]), pb)
			var flags := 0
			if r["oneway"] != 0:
				flags |= 1
				if r["oneway"] == -1:
					var tmp := a
					a = b
					b = tmp
			if hw in TRAFFIC:
				flags |= 2
			if not hw in NO_WALK:
				flags |= 4
			var key := Vector2i(mini(a, b), maxi(a, b))
			if seen.has(key):
				continue
			seen[key] = true
			edges.append([a, b, r["width"], flags, name_idx, hw])
	print("graphe : %d nœuds, %d tronçons, %d noms de rues" % [node_pos.size(), edges.size(), street_names.size()])


# --- Côte : reconstruction des polygones de terre -----------------------------------

func _perim_t(p: Vector2, w: float, h: float, ox: float, oy: float) -> float:
	# Périmètre parcouru dans le sens trigonométrique (repère nord en haut) depuis le coin sud-ouest.
	var dx0 := absf(p.y - oy)
	var dx1 := absf(p.x - (ox + w))
	var dx2 := absf(p.y - (oy + h))
	var dx3 := absf(p.x - ox)
	var m := minf(minf(dx0, dx1), minf(dx2, dx3))
	if m == dx0:
		return p.x - ox
	if m == dx1:
		return w + (p.y - oy)
	if m == dx2:
		return w + h + (ox + w - p.x)
	return 2.0 * w + h + (oy + h - p.y)


func _compute_land() -> void:
	# Repère « géo » : x vers l'est, y vers le nord. Dans OSM, la terre est à gauche de la côte.
	var ox := min_x
	var oy := -max_z
	var w := max_x - min_x
	var h := max_z - min_z
	var box := PackedVector2Array([Vector2(ox, oy), Vector2(ox + w, oy), Vector2(ox + w, oy + h), Vector2(ox, oy + h)])
	var ways: Array = []
	for c in coast:
		var ids: Array = (c["ids"] as Array).duplicate()
		var pts: PackedVector2Array = c["pts"]
		var geo := PackedVector2Array()
		for p in pts:
			geo.append(Vector2(p.x, -p.y))
		ways.append({"ids": ids, "pts": geo})
	var merged := true
	while merged:
		merged = false
		for i in ways.size():
			for j in ways.size():
				if i != j and ways[i]["ids"].back() == ways[j]["ids"].front():
					var pj: PackedVector2Array = ways[j]["pts"]
					var pi: PackedVector2Array = ways[i]["pts"]
					pi.append_array(pj.slice(1))
					ways[i] = {"ids": ways[i]["ids"] + (ways[j]["ids"] as Array).slice(1), "pts": pi}
					ways.remove_at(j)
					merged = true
					break
			if merged:
				break
	var pieces: Array = []
	for wy in ways:
		var chain: PackedVector2Array = wy["pts"]
		var closed: bool = wy["ids"].front() == wy["ids"].back()
		var all_in := true
		for p in chain:
			if not Geometry2D.is_point_in_polygon(p, box):
				all_in = false
				break
		if closed and all_in:
			lands.append(_geo_to_xz(chain))
			continue
		for piece in Geometry2D.intersect_polyline_with_polygon(chain, box):
			if piece.size() < 2:
				continue
			# Garder le sens de parcours d'origine (terre à gauche)
			var i0 := _nearest_index(chain, piece[0])
			var i1 := _nearest_index(chain, piece[piece.size() - 1])
			if i0 > i1:
				piece.reverse()
			pieces.append(piece)
	if pieces.is_empty():
		if lands.is_empty():
			lands.append(_geo_to_xz(box))
		return
	var per := 2.0 * (w + h)
	var corners := [[w, Vector2(ox + w, oy)], [w + h, Vector2(ox + w, oy + h)], [2.0 * w + h, Vector2(ox, oy + h)], [per, Vector2(ox, oy)]]
	var used := []
	used.resize(pieces.size())
	used.fill(false)
	for s in pieces.size():
		if used[s]:
			continue
		var poly := PackedVector2Array()
		var cur := s
		var guard := 0
		while guard < 1000:
			guard += 1
			used[cur] = true
			poly.append_array(pieces[cur])
			var last: PackedVector2Array = pieces[cur]
			var t_end := _perim_t(last[last.size() - 1], w, h, ox, oy)
			var best := -1
			var best_d := INF
			for k in pieces.size():
				if used[k] and k != s:
					continue
				var pk: PackedVector2Array = pieces[k]
				var d := fposmod(_perim_t(pk[0], w, h, ox, oy) - t_end, per)
				if d < best_d:
					best_d = d
					best = k
			var passed: Array = []
			for cn in corners:
				var dc := fposmod(float(cn[0]) - t_end, per)
				if dc > 0.0 and dc < best_d:
					passed.append([dc, cn[1]])
			passed.sort_custom(func(a, b): return a[0] < b[0])
			for pc in passed:
				poly.append(pc[1])
			if best == s:
				break
			cur = best
		lands.append(_geo_to_xz(poly))


func _nearest_index(chain: PackedVector2Array, p: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in chain.size():
		var d := chain[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _geo_to_xz(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(Vector2(p.x, -p.y))
	return out


# --- Grille d'occupation (remplissage + mini-carte) -----------------------------

func _raster() -> void:
	gw = int(ceil((max_x - min_x) / MAP_RES))
	gh = int(ceil((max_z - min_z) / MAP_RES))
	grid.resize(gw * gh)
	grid.fill(4)
	for land in lands:
		_fill_poly(land, 0)
	for e in edges:
		var a := node_pos[e[0]]
		var b := node_pos[e[1]]
		var w: float = e[2]
		_fill_poly(_quad(a, b, w / 2.0 + 1.5, 1.0), 1)
		_hash_segment(a, b, w, (e[3] & 2) != 0)
	for b in buildings:
		_fill_poly(b["poly"], 2)
	for p in nofill:
		_fill_poly(p, 3)


func _quad(a: Vector2, b: Vector2, half: float, ext: float) -> PackedVector2Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * half
	var a2 := a - d * ext
	var b2 := b + d * ext
	return PackedVector2Array([a2 + n, b2 + n, b2 - n, a2 - n])


func _fill_poly(poly: PackedVector2Array, value: int) -> void:
	if poly.size() < 3:
		return
	var zmin := INF
	var zmax := -INF
	for p in poly:
		zmin = minf(zmin, p.y)
		zmax = maxf(zmax, p.y)
	var r0 := maxi(0, int((zmin - min_z) / MAP_RES))
	var r1 := mini(gh - 1, int((zmax - min_z) / MAP_RES))
	var n := poly.size()
	for row in range(r0, r1 + 1):
		var zc := min_z + (row + 0.5) * MAP_RES
		var xs: Array = []
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			if (a.y <= zc and b.y > zc) or (b.y <= zc and a.y > zc):
				xs.append(a.x + (zc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			var c0 := maxi(0, int((float(xs[k]) - min_x) / MAP_RES + 0.5))
			var c1 := mini(gw - 1, int((float(xs[k + 1]) - min_x) / MAP_RES - 0.5))
			var base := row * gw
			for col in range(c0, c1 + 1):
				if value == 0 or grid[base + col] != 4:
					grid[base + col] = value
			k += 2


func _cell(p: Vector2) -> int:
	var c := int((p.x - min_x) / MAP_RES)
	var r := int((p.y - min_z) / MAP_RES)
	if c < 0 or r < 0 or c >= gw or r >= gh:
		return 4
	return grid[r * gw + c]


func _hash_segment(a: Vector2, b: Vector2, w: float, traffic: bool) -> void:
	var cells := {}
	var steps := int(a.distance_to(b) / 30.0) + 1
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		cells[Vector2i(floori(p.x / 60.0), floori(p.y / 60.0))] = true
	for c in cells:
		if not seg_hash.has(c):
			seg_hash[c] = []
		seg_hash[c].append([a, b, w, traffic])


## Route la plus proche : [distance, direction, largeur, point projeté]
func _nearest_road(p: Vector2, traffic_only := false) -> Array:
	var best := [INF, Vector2.RIGHT, 6.0, p]
	var c := Vector2i(floori(p.x / 60.0), floori(p.y / 60.0))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := c + Vector2i(dx, dy)
			if not seg_hash.has(key):
				continue
			for s in seg_hash[key]:
				if traffic_only and not s[3]:
					continue
				var q := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
				var d := p.distance_to(q)
				if d < best[0]:
					best = [d, (s[1] - s[0]).normalized(), s[2], q]
	return best


func _fill_buildings() -> void:
	var z := min_z + FILL_STEP / 2.0
	while z < max_z:
		var x := min_x + FILL_STEP / 2.0
		while x < max_x:
			var c := Vector2(x + rng.randf_range(-1.5, 1.5), z + rng.randf_range(-1.5, 1.5))
			x += FILL_STEP
			if _cell(c) != 0:
				continue
			var nr := _nearest_road(c)
			var dist: float = nr[0]
			var w: float = nr[2]
			if dist > 42.0 or dist < w / 2.0 + 4.0:
				continue
			var dir: Vector2 = nr[1]
			var nrm := Vector2(-dir.y, dir.x)
			var hw := rng.randf_range(4.0, 5.8)
			var hd := rng.randf_range(4.0, 6.0)
			var poly := PackedVector2Array([c + dir * hw + nrm * hd, c - dir * hw + nrm * hd, c - dir * hw - nrm * hd, c + dir * hw - nrm * hd])
			var ok := true
			for sp in [c, c + dir * hw * 0.9 + nrm * hd * 0.9, c - dir * hw * 0.9 + nrm * hd * 0.9,
					c - dir * hw * 0.9 - nrm * hd * 0.9, c + dir * hw * 0.9 - nrm * hd * 0.9,
					c + dir * hw, c - dir * hw, c + nrm * hd, c - nrm * hd]:
				if _cell(sp) != 0:
					ok = false
					break
			if not ok:
				continue
			_fill_poly(poly, 2)
			buildings.append({"poly": poly, "levels": -1.0, "kind": "fill", "name": ""})
		z += FILL_STEP


# --- Lieux du jeu -------------------------------------------------------------------

func _district(p: Vector2) -> String:
	var best := "Dakar"
	var bd := INF
	for d in districts:
		var dd: float = p.distance_to(d[1])
		if dd < bd:
			bd = dd
			best = d[0]
	return best


## Point sur le trottoir devant un lieu : [x, z, cap de la route, nx, nz] (n = vers le lieu)
func _curb(c: Vector2, along := 0.0) -> Array:
	var nr := _nearest_road(c, true)
	if nr[0] == INF:
		nr = _nearest_road(c)
	if along != 0.0:
		# Décalage le long de la rue, puis on se recolle à la vraie rue la plus proche
		var nr2 := _nearest_road(nr[3] + nr[1] * along, true)
		if nr2[0] < INF:
			nr = nr2
	var dir: Vector2 = nr[1]
	var w: float = nr[2]
	var q: Vector2 = nr[3]
	var n := Vector2(-dir.y, dir.x)
	if n.dot(c - q) < 0.0:
		n = -n
	# Sens de circulation avec le trottoir à droite : la droite de f est (-f.z, f.x)
	var f := dir
	if Vector2(-f.y, f.x).dot(n) < 0.0:
		f = -f
	var curb := q + n * (w / 2.0 + 1.2)
	return [curb.x, curb.y, atan2(-f.x, -f.y), n.x, n.y, q.x + n.x * (w / 2.0 - 1.1), q.y + n.y * (w / 2.0 - 1.1), f.x, f.y]


func _compute_places() -> void:
	var found := {}
	for p in pois:
		var nm: String = p["name"]
		if LANDMARKS.has(nm) and not found.has(nm):
			found[nm] = p
	for nm in LANDMARKS:
		if not found.has(nm):
			print("lieu absent des données : ", nm)
			continue
		var info: Array = LANDMARKS[nm]
		var p: Dictionary = found[nm]
		places[info[0]] = _curb(p["c"])
		places[info[0]].append(p["c"].x)
		places[info[0]].append(p["c"].y)
	# Lieux inventés pour les métiers, à côté de vrais repères
	if places.has("Marché Sandaga"):
		places["Café Touba"] = _curb(_poi_c("Marché Sandaga"), 22.0)
	if places.has("Marché Tilène"):
		places["Chez Adja"] = _curb(_poi_c("Marché Tilène"), 28.0)
	if places.has("Gare routière Petersen"):
		places["Garage Taxi"] = _curb(_poi_c("Gare routière Petersen"), -20.0)
	for k in places:
		if places[k].size() < 11:
			places[k].append(places[k][0])
			places[k].append(places[k][1])
	# Véhicules garés le long du trottoir
	# Plage, terrains de sport, église
	for bch in beaches:
		if bch["name"] != "":
			places["Plage de l'Anse Bernard"] = _with_center(_curb(_centroid(bch["poly"])), _centroid(bch["poly"]))
			break
	var sport_names := {"soccer": "Terrain de foot", "basketball": "Terrain de basket", "tennis": "Courts de tennis"}
	for p in pitches:
		var key: String = p["name"] if p["name"] != "" else sport_names[p["sport"]]
		if not places.has(key):
			var pc := _centroid(p["poly"])
			places[key] = _with_center(_curb(pc), pc)
	for w in worship:
		if w["religion"] == "christian" and w["name"] == "Saint-Laurent de Gibraltar":
			places["Église Saint-Laurent"] = _with_center(_curb(w["c"]), w["c"])
		if w["name"] == "Mosquée Seydou Nourou Tall" and not places.has("Mosquée Seydou Nourou Tall"):
			places["Mosquée Seydou Nourou Tall"] = _with_center(_curb(w["c"]), w["c"])
	# Entreprises où travailler (à côté de vrais repères)
	var biz := [["Orange Money", "Marché Sandaga", -36.0], ["Orange Money (Petersen)", "Gare routière Petersen", 34.0],
		["Wave", "Marché Tilène", -32.0], ["Wave (Kermel)", "Marché Kermel", 26.0],
		["Jumbo", "Gare de Dakar", 60.0], ["Jadida", "Place de l'Indépendance", 70.0]]
	for bz in biz:
		if places.has(bz[1]):
			var anchor := _poi_c(bz[1])
			places[bz[0]] = _with_center(_curb(anchor, bz[2]), anchor)
	_park("Jumbo", "van", [10.0])
	_park("Garage Taxi", "taxi", [0.0, 7.0, 14.0])
	_park("Gare routière Petersen", "car_rapide", [8.0])
	_park("Gare routière Petersen", "bus", [24.0])
	_park("Gare routière Petersen", "coach", [40.0])
	_park("Chez Adja", "jakarta", [-4.0, -6.0])
	_park("Commissariat", "police", [6.0, 13.0])
	_park("Marché Sandaga", "clando", [-12.0])
	_park("Caserne", "army", [8.0, 16.0])


func _with_center(curb: Array, c: Vector2) -> Array:
	curb.append(c.x)
	curb.append(c.y)
	return curb


func _poi_c(game_name: String) -> Vector2:
	var p: Array = places[game_name]
	return Vector2(p[9], p[10])


func _park(place: String, type: String, offsets: Array) -> void:
	if not places.has(place):
		return
	var p: Array = places[place]
	var f := Vector2(p[7], p[8])
	for o in offsets:
		var pos := Vector2(p[5], p[6]) + f * float(o)
		parking.append({"type": type, "pos": [pos.x, pos.y], "yaw": p[2]})


# --- Géométrie 3D ---------------------------------------------------------------------

func _chunk_of(p: Vector2) -> Chunk:
	var key := Vector2i(floori((p.x - min_x) / CHUNK), floori((p.y - min_z) / CHUNK))
	if not chunks.has(key):
		chunks[key] = Chunk.new()
	return chunks[key]


func _tri(s: Surf, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, col: Color) -> void:
	# Godot : faces avant dans le sens horaire.
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		var t := b
		b = c
		c = t
	s.v.append(a)
	s.v.append(b)
	s.v.append(c)
	for i in 3:
		s.n.append(nrm)
		s.c.append(col)


func _style_for(b: Dictionary, i: int) -> Array:
	var nm: String = b["name"]
	if STYLES.has(nm):
		return STYLES[nm]
	var poly: PackedVector2Array = b["poly"]
	var c := _centroid(poly)
	var d := _district(c)
	var local := RandomNumberGenerator.new()
	local.seed = i * 7919 + 13
	var col: Color = FACADES[local.randi() % FACADES.size()]
	var levels: float = b["levels"]
	if levels <= 0.0:
		match d:
			"Dakar-Plateau":
				levels = local.randi_range(3, 9)
			"Gibraltar", "Rebeuss":
				levels = local.randi_range(2, 5)
			_:
				levels = local.randi_range(1, 3)
		if _area(poly) > 900.0:
			levels = minf(levels, 3.0)
	var zone := _zone(c)
	var given: bool = b["levels"] > 0.0
	match zone:
		"populaire":
			col = POPULAR_FACADES[local.randi() % POPULAR_FACADES.size()]
			if not given:
				levels = minf(levels, local.randi_range(1, 3))
		"luxe":
			col = LUXE_FACADES[local.randi() % LUXE_FACADES.size()]
			if not given:
				levels = local.randi_range(2, 3)
		"industriel":
			col = INDUS_FACADES[local.randi() % INDUS_FACADES.size()]
			if not given:
				levels = 2.5
		_:
			if levels >= 8:
				# Tours de bureaux du Plateau : façades vitrées bleutées
				col = Color("8fa9bf").lerp(col, 0.25)
	var kind: String = b["kind"]
	if kind in ["industrial", "warehouse", "hangar"]:
		col = Color("b8b5ad")
	elif kind in ["mosque"]:
		col = Color("f4f1ea")
	return [col, clampf(levels, 1.0, 25.0)]


func _mesh_building(b: Dictionary, i: int) -> float:
	var poly: PackedVector2Array = b["poly"]
	var st := _style_for(b, i)
	var col: Color = st[0]
	var levels: float = st[1]
	var h: float = levels * 3.2
	var cen := _centroid(poly)
	var ch := _chunk_of(cen)
	var n := poly.size()
	var p0 := poly[0]
	var p1 := poly[1]
	var e0 := (p1 - p0).normalized()
	var flip := Geometry2D.is_point_in_polygon((p0 + p1) / 2.0 + Vector2(e0.y, -e0.x) * 0.05, poly)
	var lrng := RandomNumberGenerator.new()
	lrng.seed = i * 31 + 7
	var zone := _zone(cen)
	# Tours du Plateau : socle commercial de 2 étages puis tour vitrée en retrait
	var tower_h := 0.0
	if _tower_site(b, poly, zone, lrng):
		var given: float = b["levels"]
		tower_h = (given if given >= 10.0 else float(lrng.randi_range(12, 26))) * 3.2
		levels = 2.0
		h = 6.4
	# Façade moderne à bandeaux vitrés pour une partie des immeubles de bureaux (alpha 0.85)
	elif zone == "affaires" and levels >= 5 and b["name"] == "" and lrng.randf() < 0.35:
		col = Color(MODERN_FACADES[lrng.randi() % MODERN_FACADES.size()], 0.85)
	var dirt := col.darkened(0.4 if zone == "populaire" else 0.28)
	dirt.a = col.a
	# Façade donnant sur la rue la plus proche
	var nr := _nearest_road(cen)
	var to_road: Vector2 = (nr[3] - cen).normalized() if nr[0] < INF else Vector2.ZERO
	var front := -1
	var front_dot := -2.0
	var outs: Array = []
	for k in n:
		var a := poly[k]
		var bb := poly[(k + 1) % n]
		var ed := bb - a
		var o := Vector2(ed.y, -ed.x).normalized() * (-1.0 if flip else 1.0)
		outs.append(o)
		if ed.length() < 0.05:
			continue
		var nrm := Vector3(o.x, 0.0, o.y)
		var A := Vector3(a.x, 0.0, a.y)
		var B := Vector3(bb.x, 0.0, bb.y)
		var At := A + Vector3(0, h, 0)
		var Bt := B + Vector3(0, h, 0)
		# Mur : bas sali par la poussière (dégradé de couleur)
		_tri_c(ch.walls, A, B, Bt, nrm, dirt, dirt, col)
		_tri_c(ch.walls, A, Bt, At, nrm, dirt, col, col)
		ch.col.append_array(PackedVector3Array([A, B, Bt, A, Bt, At]))
		if ed.length() > 2.5 and o.dot(to_road) > front_dot:
			front_dot = o.dot(to_road)
			front = k
	# Tout ce qui s'ajoute aux murs après les façades principales : sans fenêtres (voir la fin)
	var walls_end := ch.walls.c.size()
	# Corniche en béton sous le toit, seulement sur les façades qui donnent sur la rue (peu de triangles)
	if levels >= 2.0 and tower_h == 0.0 and to_road != Vector2.ZERO:
		var cc := col.lightened(0.14)
		for k in n:
			var a := poly[k]
			var bb := poly[(k + 1) % n]
			var o: Vector2 = outs[k]
			if a.distance_to(bb) < 3.0 or o.dot(to_road) < 0.3:
				continue
			var u := (bb - a).normalized()
			var a2 := a + o * 0.3 - u * 0.15
			var b2 := bb + o * 0.3 + u * 0.15
			var nrm := Vector3(o.x, 0, o.y)
			var y0 := h - 0.38
			_quad_v(ch.walls, Vector3(a2.x, y0, a2.y), Vector3(b2.x, y0, b2.y), 0.38, nrm, cc)
			_tri(ch.walls, Vector3(a.x, y0, a.y), Vector3(bb.x, y0, bb.y), Vector3(b2.x, y0, b2.y), Vector3.DOWN, cc.darkened(0.25))
			_tri(ch.walls, Vector3(a.x, y0, a.y), Vector3(b2.x, y0, b2.y), Vector3(a2.x, y0, a2.y), Vector3.DOWN, cc.darkened(0.25))
			_tri(ch.walls, Vector3(a.x, h, a.y), Vector3(bb.x, h, bb.y), Vector3(b2.x, h, b2.y), Vector3.UP, cc)
			_tri(ch.walls, Vector3(a.x, h, a.y), Vector3(b2.x, h, b2.y), Vector3(a2.x, h, a2.y), Vector3.UP, cc)
			variety["corniches"] = int(variety.get("corniches", 0)) + 1
	var idx := Geometry2D.triangulate_polygon(poly)
	var roof := col.darkened(0.18)
	roof.a = 0.5 # toit-terrasse en béton
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var bb := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		_tri(ch.roofs, Vector3(a.x, h, a.y), Vector3(bb.x, h, bb.y), Vector3(c.x, h, c.y), Vector3.UP, roof)
		ch.roof_col.append_array(PackedVector3Array([Vector3(a.x, h, a.y), Vector3(bb.x, h, bb.y), Vector3(c.x, h, c.y)]))
	var small := _area(poly) < 2500.0
	# Petites maisons des quartiers aisés et du Plateau colonial : toit à quatre pans en tuiles
	var ob0 := _obb(poly)
	var hip: bool = tower_h == 0.0 and zone in ["luxe", "affaires"] and levels <= 3 and b["name"] == "" 			and _area(poly) < 450.0 and _area(poly) > 0.85 * 4.0 * ob0[2] * ob0[3] and lrng.randf() < 0.35
	if hip:
		variety["toits en tuiles"] = int(variety.get("toits en tuiles", 0)) + 1
		_hip_roof(ch, ob0, h, lrng)
	# Quartiers populaires : toits en tôle ondulée sur une partie des maisons
	elif zone == "populaire" and small and lrng.randf() < 0.45:
		var ob := _obb(poly)
		var oc: Vector2 = ob[0]
		var ou: Vector2 = ob[1]
		var ov := Vector2(-ou.y, ou.x)
		var stripes := maxi(3, int(ob[2] * 2.0 / 0.8))
		for sk in stripes:
			var sc: Vector2 = oc + ou * (-ob[2] + (sk + 0.5) * ob[2] * 2.0 / stripes) * 0.85
			var tin: Color = Color("8a8f9373") if sk % 2 == 0 else Color("6f747873")
			if lrng.randf() < 0.3:
				tin = Color("8b5a3c73") # tôle rouillée
			_rect(ch.roofs, sc, ou, ob[2] / stripes * 0.85, ob[3] * 0.8, h + 0.35 + (sk % 2) * 0.04, tin)
	# Villas : pergola sur le toit-terrasse
	if zone == "luxe" and small and not hip and lrng.randf() < 0.5:
		var pc := cen
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				_obox(ch.roofs, Vector3(pc.x + sx * 1.6, h + 1.2, pc.y + sz * 1.6), Vector3(0.08, 1.2, 0.08), Vector3.RIGHT, Color("f1f1f1b3"))
		for k in 6:
			_obox(ch.roofs, Vector3(pc.x - 1.6 + k * 0.64, h + 2.45, pc.y), Vector3(0.05, 0.05, 1.8), Vector3.RIGHT, Color("8d6748"))
	# Toit-terrasse : muret (acrotère) tout autour
	if levels <= 6 and small and not hip:
		for k in n:
			var a := poly[k]
			var bb := poly[(k + 1) % n]
			if a.distance_to(bb) < 0.05:
				continue
			var o: Vector2 = outs[k]
			var inner_a := a - o * 0.15
			var inner_b := bb - o * 0.15
			var nrm := Vector3(o.x, 0, o.y)
			_quad_v(ch.walls, Vector3(a.x, h, a.y), Vector3(bb.x, h, bb.y), 0.9, nrm, col)
			_quad_v(ch.walls, Vector3(inner_a.x, h, inner_a.y), Vector3(inner_b.x, h, inner_b.y), 0.9, -nrm, col.darkened(0.08))
			_tri(ch.roofs, Vector3(a.x, h + 0.9, a.y), Vector3(bb.x, h + 0.9, bb.y), Vector3(inner_b.x, h + 0.9, inner_b.y), Vector3.UP, Color(col.lightened(0.05), 0.7))
			_tri(ch.roofs, Vector3(a.x, h + 0.9, a.y), Vector3(inner_b.x, h + 0.9, inner_b.y), Vector3(inner_a.x, h + 0.9, inner_a.y), Vector3.UP, Color(col.lightened(0.05), 0.7))
	# Porte métallique ou boutique côté rue
	if front != -1 and nr[0] < 30.0:
		var a := poly[front]
		var bb := poly[(front + 1) % n]
		var o: Vector2 = outs[front]
		var u := (bb - a).normalized()
		var mid := (a + bb) / 2.0 + o * 0.04
		var edge_len := a.distance_to(bb)
		var nrm := Vector3(o.x, 0, o.y)
		var main_road: bool = nr[2] >= 8.0 and nr[0] < 16.0
		# Rues secondaires : une partie des rez-de-chaussée sont aussi des boutiques (quartiers populaires
		# et Plateau surtout), pas dans les quartiers résidentiels aisés ni les zones industrielles
		var side_shop: bool = not main_road and nr[2] >= 4.0 and nr[0] < 14.0 and edge_len > 3.5 			and lrng.randf() < (0.5 if zone == "populaire" else (0.4 if zone == "affaires" else 0.0))
		if (main_road or side_shop) and edge_len > 3.5:
			# Boutique : rideau de fer et enseigne peinte
			var sw := minf(edge_len * 0.8, 4.5)
			_quad_v(ch.walls, Vector3(mid.x - u.x * sw / 2.0, 0.0, mid.y - u.y * sw / 2.0), Vector3(mid.x + u.x * sw / 2.0, 0.0, mid.y + u.y * sw / 2.0), 2.6, nrm, Color("8d919666")) # rideau de fer
			var ad: Color = AD_COLORS[lrng.randi() % AD_COLORS.size()]
			var m2 := mid + o * 0.02
			_quad_v(ch.walls, Vector3(m2.x - u.x * sw / 2.0, 2.65, m2.y - u.y * sw / 2.0), Vector3(m2.x + u.x * sw / 2.0, 2.65, m2.y + u.y * sw / 2.0), 0.7, nrm, Color(ad, 0.3))
			# Auvent incliné au-dessus de la vitrine : tôle ondulée ou toile de couleur (deux faces)
			if lrng.randf() < 0.7:
				var aw: Color = Color("9aa0a666") if lrng.randf() < 0.5 else Color(AWNING_COLORS[lrng.randi() % AWNING_COLORS.size()], 0.3)
				var hw2 := sw / 2.0 + 0.15
				var dep := 1.3
				var w0 := mid - u * hw2 + o * 0.02
				var w1 := mid + u * hw2 + o * 0.02
				var f0 := w0 + o * dep
				var f1 := w1 + o * dep
				var P0 := Vector3(w0.x, 2.62, w0.y)
				var P1 := Vector3(w1.x, 2.62, w1.y)
				var Q0 := Vector3(f0.x, 2.25, f0.y)
				var Q1 := Vector3(f1.x, 2.25, f1.y)
				var up_n := Vector3(o.x * 0.28, 1.0, o.y * 0.28).normalized()
				_tri(ch.walls, P0, P1, Q1, up_n, aw)
				_tri(ch.walls, P0, Q1, Q0, up_n, aw)
				_tri(ch.walls, P0, Q1, P1, -up_n, aw.darkened(0.3))
				_tri(ch.walls, P0, Q0, Q1, -up_n, aw.darkened(0.3))
				# Lambrequin (bord avant pendant)
				_quad_v(ch.walls, Q0 - Vector3(0, 0.22, 0), Q1 - Vector3(0, 0.22, 0), 0.22, nrm, aw.darkened(0.1))
				_quad_v(ch.walls, Q1 - Vector3(0, 0.22, 0), Q0 - Vector3(0, 0.22, 0), 0.22, -nrm, aw.darkened(0.35))
				variety["auvents"] = int(variety.get("auvents", 0)) + 1
				if int(variety["auvents"]) == 40:
					print("  exemple auvent : %.1f, %.1f (façade vers %.2f, %.2f)" % [f0.x, f0.y, o.x, o.y])
		else:
			var dc: Color = DOOR_COLORS[lrng.randi() % DOOR_COLORS.size()]
			_quad_v(ch.walls, Vector3(mid.x - u.x * 0.6, 0.0, mid.y - u.y * 0.6), Vector3(mid.x + u.x * 0.6, 0.0, mid.y + u.y * 0.6), 2.15, nrm, Color(dc, 0.3))
		# Balcons dans les étages
		# Villas : bandeaux vitrés à chaque étage ; entrepôts : grande porte roulante
		if zone == "luxe" and edge_len > 4.0:
			for fl in int(levels):
				var gw2 := minf(edge_len * 0.7, 7.0)
				var g0 := (a + bb) / 2.0 + o * 0.05
				_quad_v(ch.walls, Vector3(g0.x - u.x * gw2 / 2.0, fl * 3.2 + 0.9, g0.y - u.y * gw2 / 2.0), Vector3(g0.x + u.x * gw2 / 2.0, fl * 3.2 + 0.9, g0.y + u.y * gw2 / 2.0), 1.6, nrm, Color("35566f33")) # vitrage
		if zone == "industriel" and edge_len > 6.0:
			var dw := minf(edge_len * 0.5, 6.0)
			var d0 := (a + bb) / 2.0 + o * 0.06
			_quad_v(ch.roofs, Vector3(d0.x - u.x * dw / 2.0, 0.0, d0.y - u.y * dw / 2.0), Vector3(d0.x + u.x * dw / 2.0, 0.0, d0.y + u.y * dw / 2.0), 4.4, nrm, Color("5c6670"))
			for sline in 6:
				_quad_v(ch.roofs, Vector3(d0.x - u.x * dw / 2.0, 0.6 + sline * 0.65, d0.y - u.y * dw / 2.0) + nrm * 0.01, Vector3(d0.x + u.x * dw / 2.0, 0.6 + sline * 0.65, d0.y + u.y * dw / 2.0) + nrm * 0.01, 0.06, nrm, Color("48515a"))
		if levels >= 3 and edge_len > 3.0 and (zone != "populaire" or lrng.randf() < 0.3):
			var bw := minf(edge_len * 0.55, 4.0)
			for f in range(1, int(levels)):
				var bc := (a + bb) / 2.0 + o * 0.45
				_obox(ch.walls, Vector3(bc.x, f * 3.2 + 0.05, bc.y), Vector3(bw / 2.0, 0.08, 0.45), Vector3(u.x, 0, u.y), col.lightened(0.1))
				_obox(ch.walls, Vector3(bc.x + o.x * 0.42, f * 3.2 + 0.55, bc.y + o.y * 0.42), Vector3(bw / 2.0, 0.45, 0.03), Vector3(u.x, 0, u.y), Color("e8e4dc"))
	# Réservoir d'eau sur le toit, fers à béton en attente (maisons en construction)
	if levels <= 4 and small and not hip:
		if lrng.randf() < 0.35:
			var tank_col: Color = [Color("1f3b73"), Color("222222"), Color("2d6a4f")][lrng.randi() % 3]
			var tp := cen.lerp(poly[0], 0.4)
			_obox(ch.walls, Vector3(tp.x, h + 0.35, tp.y), Vector3(0.6, 0.35, 0.6), Vector3.RIGHT, Color("6c757d4d"))
			_obox(ch.walls, Vector3(tp.x, h + 1.25, tp.y), Vector3(0.55, 0.55, 0.55), Vector3.RIGHT, Color(tank_col, 0.3))
		if lrng.randf() < 0.25:
			for k in mini(4, n):
				var cp := poly[k].lerp(cen, 0.08)
				_obox(ch.walls, Vector3(cp.x, h + 0.9 + 0.6, cp.y), Vector3(0.03, 0.6, 0.03), Vector3.RIGHT, Color("5b46364d"))
	# Acrotères, balcons, réservoirs… : enduit sans fenêtres (alpha 0.5) sauf matériau déjà choisi
	for k in range(walls_end, ch.walls.c.size()):
		var wc: Color = ch.walls.c[k]
		if wc.a > 0.8:
			wc.a = 0.5
			ch.walls.c[k] = wc
	if tower_h > 0.0:
		variety["tours"] = int(variety.get("tours", 0)) + 1
		_tower(ch, poly, cen, h, tower_h, lrng)
		return tower_h
	if levels <= 4 and small:
		_house_extras(ch, poly, ob0, h, col, zone, hip, outs, to_road, lrng)
	return h


## Emplacement d'une tour : Plateau (quartier d'affaires), bâtiment assez grand et presque convexe
## (la tour en retrait reste dans l'emprise), pas un monument ni un entrepôt.
func _tower_site(b: Dictionary, poly: PackedVector2Array, zone: String, lrng: RandomNumberGenerator) -> bool:
	if zone != "affaires" or b["name"] != "" or str(b["kind"]) in ["industrial", "warehouse", "hangar", "mosque", "church", "fill"]:
		return false
	var area := _area(poly)
	if area < 220.0 or area > 3500.0:
		return false
	var hull := Geometry2D.convex_hull(poly)
	if area < 0.9 * _area(hull):
		return false
	var ob := _obb(poly)
	if ob[3] < 6.0:
		return false
	return float(b["levels"]) >= 10.0 or lrng.randf() < 0.25


## Tour : fût vitré (mur-rideau, alpha 0.75) ou à bandeaux (0.85) en retrait sur le socle, parfois un
## second retrait, toit technique, antenne à feu rouge, héliport sur les plus hautes.
func _tower(ch: Chunk, poly: PackedVector2Array, cen: Vector2, base_h: float, top_h: float, lrng: RandomNumberGenerator) -> void:
	var glass_tower := lrng.randf() < 0.7
	var col: Color = TOWER_GLASS[lrng.randi() % TOWER_GLASS.size()] if glass_tower else MODERN_FACADES[lrng.randi() % MODERN_FACADES.size()]
	col.a = 0.75 if glass_tower else 0.85
	var steps := [[base_h, top_h, 0.78]]
	if top_h > 45.0 and lrng.randf() < 0.45:
		var cut := snappedf(top_h * lrng.randf_range(0.6, 0.75), 3.2)
		steps = [[base_h, cut, 0.8], [cut, top_h, 0.58]]
	var last := PackedVector2Array()
	for st in steps:
		var y0: float = st[0]
		var y1: float = st[1]
		var sp := PackedVector2Array()
		for p in poly:
			sp.append(cen + (p - cen) * float(st[2]))
		var n := sp.size()
		var e0 := (sp[1] - sp[0]).normalized()
		var flip := Geometry2D.is_point_in_polygon((sp[0] + sp[1]) / 2.0 + Vector2(e0.y, -e0.x) * 0.05, sp)
		for k in n:
			var a := sp[k]
			var bb := sp[(k + 1) % n]
			var ed := bb - a
			if ed.length() < 0.05:
				continue
			var o := Vector2(ed.y, -ed.x).normalized() * (-1.0 if flip else 1.0)
			var nrm := Vector3(o.x, 0.0, o.y)
			var A := Vector3(a.x, y0, a.y)
			var B := Vector3(bb.x, y0, bb.y)
			var At := Vector3(a.x, y1, a.y)
			var Bt := Vector3(bb.x, y1, bb.y)
			_tri(ch.walls, A, B, Bt, nrm, col)
			_tri(ch.walls, A, Bt, At, nrm, col)
			ch.col.append_array(PackedVector3Array([A, B, Bt, A, Bt, At]))
			# Couronnement : bandeau plein en haut de chaque fût
			_quad_v(ch.walls, At, Bt, 1.2, nrm, Color(col.lightened(0.35), 0.5))
		_fill_flat(ch.roofs, sp, y1 + 1.2, Color(Color("8f8c86"), 0.5))
		var idx := Geometry2D.triangulate_polygon(sp)
		for k in range(0, idx.size(), 3):
			for j in 3:
				var q := sp[idx[k + j]]
				ch.roof_col.append(Vector3(q.x, y1 + 1.2, q.y))
		last = sp
	# Toit : local technique, climatiseurs, puis antenne ou héliport
	var ob := _obb(last)
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var v := Vector2(-u.y, u.x)
	var hl: float = ob[2]
	var hw: float = ob[3]
	var y := top_h + 1.2
	var ax := Vector3(u.x, 0, u.y)
	var tech := c - u * hl * 0.45
	_obox(ch.walls, Vector3(tech.x, y + 1.8, tech.y), Vector3(hl * 0.3, 1.8, hw * 0.5), ax, Color("b9b7b080"))
	for k in 3:
		var ac := c + u * hl * 0.1 + v * hw * (-0.6 + k * 0.6)
		_obox(ch.walls, Vector3(ac.x, y + 0.5, ac.y), Vector3(0.6, 0.5, 0.6), ax, Color("d4d4d080"))
	if top_h > 55.0 and hl > 7.0 and lrng.randf() < 0.6:
		var hp := c + u * hl * 0.5
		var r := minf(hw * 0.8, 6.0)
		var yellow := Color(Color("f2c94c"), 0.7)
		_disc_n(ch.roofs, hp, r, y + 0.05, Color(Color("3d3f42"), 0.7), 16)
		_ring(ch.roofs, hp, r * 0.85, y + 0.08, 0.25)
		_rect(ch.roofs, hp + v * r * 0.3, u, r * 0.38, r * 0.08, y + 0.1, yellow)
		_rect(ch.roofs, hp - v * r * 0.3, u, r * 0.38, r * 0.08, y + 0.1, yellow)
		_rect(ch.roofs, hp, v, r * 0.3, r * 0.08, y + 0.1, yellow)
	else:
		var ah := lrng.randf_range(8.0, 16.0)
		_obox(ch.walls, Vector3(tech.x, y + 3.6 + ah / 2.0, tech.y), Vector3(0.12, ah / 2.0, 0.12), Vector3.RIGHT, Color("a8a8a880"))
		_obox(ch.walls, Vector3(tech.x, y + 3.6 + ah + 0.2, tech.y), Vector3(0.3, 0.2, 0.3), Vector3.RIGHT, Color(Color("e0201b"), 0.3))


## Toit à quatre pans en tuiles (rendu « tôle » teinté terre cuite), avec débord et sous-face.
func _hip_roof(ch: Chunk, ob: Array, h: float, lrng: RandomNumberGenerator) -> void:
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var v := Vector2(-u.y, u.x)
	var hl: float = ob[2] + 0.5
	var hw: float = ob[3] + 0.5
	var rise := hw * lrng.randf_range(0.45, 0.65)
	var tile: Color = [Color("b5523b73"), Color("a2442f73"), Color("c0653f73"), Color("6e4a3a73")][lrng.randi() % 4]
	var ridge := maxf(hl - hw, 0.2)
	var q: Array = []
	for p in [c + u * hl + v * hw, c - u * hl + v * hw, c - u * hl - v * hw, c + u * hl - v * hw]:
		q.append(Vector3(p.x, h, p.y))
	var r1 := Vector3(c.x + u.x * ridge, h + rise, c.y + u.y * ridge)
	var r2 := Vector3(c.x - u.x * ridge, h + rise, c.y - u.y * ridge)
	var faces := [[q[0], q[1], r2, r1], [q[2], q[3], r1, r2], [q[1], q[2], r2], [q[3], q[0], r1]]
	for f in faces:
		var nrm: Vector3 = (f[1] - f[0]).cross(f[2] - f[0]).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		_tri(ch.roofs, f[0], f[1], f[2], nrm, tile)
		if f.size() == 4:
			_tri(ch.roofs, f[0], f[2], f[3], nrm, tile)
	# Sous-face du débord (visible depuis la rue)
	var under := Color("d9d2c480")
	_tri(ch.roofs, q[0], q[1], q[2], Vector3.DOWN, under)
	_tri(ch.roofs, q[0], q[2], q[3], Vector3.DOWN, under)
	# Faîtage
	_obox(ch.roofs, (r1 + r2) / 2.0 + Vector3(0, 0.08, 0), Vector3(maxf(ridge, 0.3), 0.1, 0.16), Vector3(u.x, 0, u.y), tile.darkened(0.2))


## Variété des maisons : soubassement peint, cage d'escalier ou chambre sur le toit, villa avec mur d'enceinte.
func _house_extras(ch: Chunk, poly: PackedVector2Array, ob: Array, h: float, col: Color, zone: String,
		hip: bool, outs: Array, to_road: Vector2, lrng: RandomNumberGenerator) -> void:
	var n := poly.size()
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var v := Vector2(-u.y, u.x)
	var hl: float = ob[2]
	var hw: float = ob[3]
	var ax := Vector3(u.x, 0, u.y)
	# Soubassement peint (bas des murs d'une autre couleur)
	if lrng.randf() < 0.45:
		var pc: Color = [col.darkened(0.35), Color("7a5c3e"), Color("4a5a6a"), Color("8b2e2e"), Color("2f5d50")][lrng.randi() % 5]
		pc.a = 0.3
		for k in n:
			var a := poly[k]
			var bb := poly[(k + 1) % n]
			if a.distance_to(bb) < 0.5:
				continue
			var o: Vector2 = outs[k]
			_quad_v(ch.walls, Vector3(a.x + o.x * 0.03, 0.0, a.y + o.y * 0.03), Vector3(bb.x + o.x * 0.03, 0.0, bb.y + o.y * 0.03), 0.9, Vector3(o.x, 0, o.y), pc)
	if not hip and hl > 3.0 and hw > 2.5:
		var r := lrng.randf()
		if zone != "luxe" and r < 0.25:
			# Chambre construite sur une moitié du toit (avec fenêtres)
			var rc := c + u * hl * 0.5
			var he := Vector3(hl * 0.48, 1.6, hw * 0.92)
			_obox(ch.walls, Vector3(rc.x, h + 1.6, rc.y), he, ax, Color(col, 1.0))
			_obox(ch.walls, Vector3(rc.x, h + 3.25, rc.y), Vector3(he.x + 0.15, 0.08, he.z + 0.15), ax, Color(col.lightened(0.1), 0.5))
			_box_col(ch, Vector3(rc.x, h + 1.6, rc.y), he, ax)
		elif r < 0.65:
			# Cage d'escalier sur le toit-terrasse, porte en tôle peinte
			var sc := c - u * (hl - 1.6) + v * (hw - 1.5) * (1.0 if lrng.randf() < 0.5 else -1.0)
			_obox(ch.walls, Vector3(sc.x, h + 1.3, sc.y), Vector3(1.3, 1.3, 1.2), ax, Color(col, 0.5))
			_obox(ch.walls, Vector3(sc.x, h + 2.65, sc.y), Vector3(1.45, 0.06, 1.35), ax, Color(col.darkened(0.1), 0.5))
			var dp := sc + u * 1.32
			var dc: Color = DOOR_COLORS[lrng.randi() % DOOR_COLORS.size()]
			_obox(ch.walls, Vector3(dp.x, h + 1.0, dp.y), Vector3(0.02, 1.0, 0.45), ax, Color(dc, 0.3))
	if zone == "luxe" and _area(poly) < 600.0:
		_villa_wall(ch, ob, to_road, lrng)


## Mur d'enceinte de villa (2,2 m, chaperon, bougainvillées, portail face à la rue) : tout autour si le
## terrain est libre, sinon une cour fermée devant la maison. Jamais sur un trottoir ni une place de parking.
func _villa_wall(ch: Chunk, ob: Array, to_road: Vector2, lrng: RandomNumberGenerator) -> void:
	if lrng.randf() > 0.7:
		return
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var v := Vector2(-u.y, u.x)
	var m := lrng.randf_range(2.5, 4.0)
	var hl: float = ob[2] + m
	var hw: float = ob[3] + m
	var P := [c + u * hl + v * hw, c - u * hl + v * hw, c - u * hl - v * hw, c + u * hl - v * hw]
	var H := [c + u * ob[2] + v * ob[3], c - u * ob[2] + v * ob[3], c - u * ob[2] - v * ob[3], c + u * ob[2] - v * ob[3]]
	# Côté du portail : celui qui regarde le plus vers la rue
	var gate_side := 0
	var best := -2.0
	for k in 4:
		var mid: Vector2 = (P[k] + P[(k + 1) % 4]) / 2.0
		var d := (mid - c).normalized().dot(to_road)
		if d > best:
			best = d
			gate_side = k
	var g1 := (gate_side + 1) % 4
	var ring := [[P[0], P[1]], [P[1], P[2]], [P[2], P[3]], [P[3], P[0]]]
	# Cour avant : mur côté rue et deux retours jusqu'aux coins de la maison
	var court := [[P[gate_side], P[g1]], [H[gate_side], P[gate_side]], [P[g1], H[g1]]]
	var segs: Array = ring if _wall_free(ring, ob, hl, hw) else (court if _wall_free(court, ob, hl, hw) else [])
	if segs.is_empty():
		return
	var kind := "villas closes" if segs == ring else "cours de villa"
	variety[kind] = int(variety.get(kind, 0)) + 1
	var wall: Color = [Color("f2ece0"), Color("efe1c6"), Color("e8d9d0"), Color("f5f1e8")][lrng.randi() % 4]
	var gate: Color = [Color("1f3b2d"), Color("222222"), Color("1f4e9c"), Color("5a3e2b")][lrng.randi() % 4]
	for si in segs.size():
		var a: Vector2 = segs[si][0]
		var b: Vector2 = segs[si][1]
		var L := a.distance_to(b)
		if L < 0.3:
			continue
		var dir := (b - a) / L
		var ax := Vector3(dir.x, 0, dir.y)
		var mid := (a + b) / 2.0
		var parts := [[a, b]]
		var front: bool = (segs == ring and si == gate_side) or (segs == court and si == 0)
		if front and L > 6.0:
			parts = [[a, mid - dir * 1.8], [mid + dir * 1.8, b]]
			# Portail métallique entre deux piliers
			_obox(ch.walls, Vector3(mid.x, 1.0, mid.y), Vector3(1.8, 1.0, 0.05), ax, Color(gate, 0.3))
			_box_col(ch, Vector3(mid.x, 1.0, mid.y), Vector3(1.8, 1.0, 0.1), ax)
			for sg: float in [-1.0, 1.0]:
				var pp: Vector2 = mid + dir * 1.95 * sg
				_obox(ch.walls, Vector3(pp.x, 1.35, pp.y), Vector3(0.25, 1.35, 0.25), ax, Color(wall.darkened(0.08), 0.5))
		for pt in parts:
			var s0: Vector2 = pt[0]
			var s1: Vector2 = pt[1]
			var sl := s0.distance_to(s1)
			if sl < 0.3:
				continue
			var sm := (s0 + s1) / 2.0
			var he := Vector3(sl / 2.0, 1.1, 0.12)
			_obox(ch.walls, Vector3(sm.x, 1.1, sm.y), he, ax, Color(wall, 0.5))
			_obox(ch.walls, Vector3(sm.x, 2.25, sm.y), Vector3(sl / 2.0 + 0.05, 0.05, 0.2), ax, Color(wall.darkened(0.15), 0.5))
			_box_col(ch, Vector3(sm.x, 1.1, sm.y), he, ax)
			# Bougainvillées qui débordent du mur
			if sl > 3.0 and lrng.randf() < 0.55:
				var bp := s0.lerp(s1, lrng.randf_range(0.2, 0.8))
				var bc: Color = [Color("d6336c"), Color("c2255c"), Color("e8590c"), Color("be4bdb")][lrng.randi() % 4]
				_obox(ch.walls, Vector3(bp.x, 2.45, bp.y), Vector3(minf(lrng.randf_range(0.8, 1.6), sl / 2.0), 0.4, 0.45), ax, Color(bc, 0.5))
				_obox(ch.walls, Vector3(bp.x, 2.1, bp.y), Vector3(0.5, 0.35, 0.3), ax, Color(bc.darkened(0.3), 0.5))


## Vrai si tous les murs passent sur du terrain libre, loin des trottoirs et des places de parking
func _wall_free(segs: Array, ob: Array, hl: float, hw: float) -> bool:
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var v := Vector2(-u.y, u.x)
	for sg in segs:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var steps := int(a.distance_to(b) / 1.0) + 1
		for t in range(1, steps):
			var p := a.lerp(b, float(t) / steps)
			var cv := _cell(p)
			# La maison elle-même (cellules de 2 m qui débordent un peu) ne compte pas
			var own: bool = absf((p - c).dot(u)) < float(ob[2]) + 2.1 and absf((p - c).dot(v)) < float(ob[3]) + 2.1
			if cv != 0 and not (cv == 2 and own):
				return false
			var nr := _nearest_road(p)
			if nr[0] < float(nr[2]) / 2.0 + SIDEWALK_W + 1.0:
				return false
	for sp in parking:
		var pp := _park_xz(sp)
		if absf((pp - c).dot(u)) < hl + 2.0 and absf((pp - c).dot(v)) < hw + 2.0:
			return false
	return true


func _park_xz(sp: Dictionary) -> Vector2:
	var p = sp["pos"]
	return Vector2(p[0], p[1]) if p is Array else Vector2(p.x, p.y)


## Collision d'un pavé orienté (faces latérales seulement)
func _box_col(ch: Chunk, c: Vector3, he: Vector3, ax: Vector3) -> void:
	var x := ax.normalized() * he.x
	var z := ax.normalized().cross(Vector3.UP).normalized() * he.z
	var y := Vector3(0, he.y, 0)
	var P := [c - x - z, c + x - z, c + x + z, c - x + z]
	for k in 4:
		var a: Vector3 = P[k] - y
		var b: Vector3 = P[(k + 1) % 4] - y
		ch.col.append_array(PackedVector3Array([a, b, b + y * 2.0, a, b + y * 2.0, a + y * 2.0]))


## Triangle avec une couleur par sommet
func _tri_c(s: Surf, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
	s.v.append_array(PackedVector3Array([a, b, c]))
	s.n.append_array(PackedVector3Array([nrm, nrm, nrm]))
	s.c.append_array(PackedColorArray([ca, cb, cc]))


## Quadrilatère vertical de a à b, de hauteur hgt
func _quad_v(s: Surf, a: Vector3, b: Vector3, hgt: float, nrm: Vector3, col: Color) -> void:
	var up := Vector3(0, hgt, 0)
	_tri(s, a, b, b + up, nrm, col)
	_tri(s, a, b + up, a + up, nrm, col)


## Pavé orienté (centre, demi-tailles, axe x local horizontal)
func _obox(s: Surf, c: Vector3, he: Vector3, ax: Vector3, col: Color) -> void:
	var x := ax.normalized() * he.x
	var y := Vector3(0, he.y, 0)
	var z := ax.normalized().cross(Vector3.UP).normalized() * he.z
	var faces := [[x, y, z], [-x, y, z], [y, x, z], [-y, x, z], [z, x, y], [-z, x, y]]
	for f in faces:
		var nrm: Vector3 = f[0].normalized()
		var fc: Vector3 = c + f[0]
		var p1: Vector3 = f[1]
		var p2: Vector3 = f[2]
		_tri(s, fc - p1 - p2, fc + p1 - p2, fc + p1 + p2, nrm, col)
		_tri(s, fc - p1 - p2, fc + p1 + p2, fc - p1 + p2, nrm, col)

func _ribbon(s: Surf, a: Vector2, b: Vector2, half: float, y: float, col: Color, ext: float) -> void:
	var q := _quad(a, b, half, ext)
	var v := []
	for p in q:
		v.append(Vector3(p.x, y, p.y))
	_tri(s, v[0], v[1], v[2], Vector3.UP, col)
	_tri(s, v[0], v[2], v[3], Vector3.UP, col)


## Trottoirs surélevés avec bordure (tracé partagé avec la collision du jeu : scripts/world/sidewalk_plan.gd)
func _build_sidewalks(curb: Color) -> void:
	var segs: Array = []
	for e in edges:
		var hw: String = e[5]
		segs.append([e[0], e[1], float(e[2]), (int(e[3]) & 2) != 0 and not hw in NO_WALK, (int(e[3]) & 2) != 0,
			_h(e[0]) <= 0.01 and _h(e[1]) <= 0.01])
	var pl: Dictionary = SidewalkPlan.plan(PackedVector2Array(node_pos), segs)
	SidewalkPlan.save(pl, OUT_DIR + "/sidewalks.res") # collision du jeu (dakar_city.gd)
	for r in pl["runs"]:
		var e: Array = edges[r["seg"]]
		var hw: String = e[5]
		var sa: Vector2 = r["a"]
		var sb: Vector2 = r["b"]
		var d: Vector2 = r["d"]
		var n: Vector2 = r["n"]
		var w: float = r["w"]
		var side: int = r["side"]
		var ch := _chunk_of((sa + sb) / 2.0)
		var painted: bool = hw in DASHED or hw == "trunk_link" or hw == "primary_link"
		# Dalles alignées sur la rue (voir _paved)
		var paved := _paved(d)
		var off: Vector2 = n * side * (w / 2.0 + 0.2 + (SIDEWALK_W - 0.2) / 2.0)
		_ribbon(ch.roads, sa + off, sb + off, (SIDEWALK_W - 0.2) / 2.0, SIDEWALK_Y, paved, 0.0)
		var e0: Vector2 = sa + n * side * (w / 2.0)
		var face := Vector3(-n.x * side, 0, -n.y * side)
		var tn: Vector2 = n * side * 0.2
		# Bordure en pierre (20 cm), peinte noir et blanc sur les grands axes
		var csl := (sb - sa).length()
		var cseg := 1.0 if painted else csl
		var ct0 := 0.0
		var ck := 0
		while ct0 < csl - 0.01:
			var ct1 := minf(ct0 + cseg, csl)
			var cc: Color = curb
			if painted:
				cc = Color("f0efe9b3") if ck % 2 == 0 else Color("232323b3")
			_curb_piece(ch, e0 + d * ct0, e0 + d * ct1, face, tn, cc)
			ct0 = ct1
			ck += 1
		# Face extérieure (côté maisons) jusqu'au sol
		var o0: Vector2 = sa + n * side * (w / 2.0 + SIDEWALK_W)
		var o1: Vector2 = sb + n * side * (w / 2.0 + SIDEWALK_W)
		_tri(ch.roads, Vector3(o0.x, 0.0, o0.y), Vector3(o1.x, 0.0, o1.y), Vector3(o1.x, SIDEWALK_Y, o1.y), -face, curb)
		_tri(ch.roads, Vector3(o0.x, 0.0, o0.y), Vector3(o1.x, SIDEWALK_Y, o1.y), Vector3(o0.x, SIDEWALK_Y, o0.y), -face, curb)
		# Bateaux : le trottoir descend en pente douce au bout (carrefour sans coin, ou chaussée d'une autre rue)
		for endp in [[sa, -d, r["ramp_a"]], [sb, d, r["ramp_b"]]]:
			if not endp[2]:
				continue
			var ep: Vector2 = endp[0]
			var ed: Vector2 = endp[1]
			var i0: Vector2 = ep + n * side * (w / 2.0)
			var i1: Vector2 = ep + n * side * (w / 2.0 + SIDEWALK_W)
			_tri(ch.roads, Vector3(i0.x, SIDEWALK_Y, i0.y), Vector3(i1.x, SIDEWALK_Y, i1.y), Vector3(i1.x + ed.x * 0.3, ROAD_Y, i1.y + ed.y * 0.3), Vector3(ed.x, 1.5, ed.y).normalized(), paved)
			_tri(ch.roads, Vector3(i0.x, SIDEWALK_Y, i0.y), Vector3(i1.x + ed.x * 0.3, ROAD_Y, i1.y + ed.y * 0.3), Vector3(i0.x + ed.x * 0.3, ROAD_Y, i0.y + ed.y * 0.3), Vector3(ed.x, 1.5, ed.y).normalized(), paved)
		# Caniveau le long de la bordure
		var g0: Vector2 = sa + n * side * (w / 2.0 - 0.18)
		var g1: Vector2 = sb + n * side * (w / 2.0 - 0.18)
		_ribbon(ch.roads, g0, g1, 0.17, ROAD_Y + 0.004, Color("8c877bb3"), 0.0)
	# Coins des carrefours : dallage, bordure et caniveau qui suivent l'angle des deux rues
	for c in pl["corners"]:
		var poly: PackedVector2Array = c["poly"]
		var inner: PackedVector2Array = c["inner"]
		var ch := _chunk_of(inner[1])
		_fill_flat(ch.roads, poly, SIDEWALK_Y, _paved(c["dir"]))
		var cen := (poly[0] + poly[1] + poly[2] + poly[3] + poly[4] + poly[5]) / 6.0
		for k in 2:
			var p0: Vector2 = inner[k]
			var p1: Vector2 = inner[k + 1]
			var dd := (p1 - p0).normalized()
			var nn := Vector2(-dd.y, dd.x)
			if nn.dot(cen - p0) < 0.0:
				nn = -nn
			_curb_piece(ch, p0, p1, Vector3(-nn.x, 0, -nn.y), nn * 0.2, curb)
			_ribbon(ch.roads, p0 - nn * 0.18, p1 - nn * 0.18, 0.17, ROAD_Y + 0.004, Color("8c877bb3"), 0.0)
		for k in [3, 4]:
			var q0: Vector2 = poly[k]
			var q1: Vector2 = poly[(k + 1) % 6]
			var dd := (q1 - q0).normalized()
			var nn := Vector2(-dd.y, dd.x)
			if nn.dot(cen - q0) > 0.0:
				nn = -nn
			_tri(ch.roads, Vector3(q0.x, 0.0, q0.y), Vector3(q1.x, 0.0, q1.y), Vector3(q1.x, SIDEWALK_Y, q1.y), Vector3(nn.x, 0, nn.y), curb)
			_tri(ch.roads, Vector3(q0.x, 0.0, q0.y), Vector3(q1.x, SIDEWALK_Y, q1.y), Vector3(q0.x, SIDEWALK_Y, q0.y), Vector3(nn.x, 0, nn.y), curb)
	print("trottoirs : %d tronçons, %d coins de carrefour" % [pl["runs"].size(), pl["corners"].size()])


## Bordure de c0 à c1 : face verticale tournée vers la chaussée (face) et dessus large de tn
func _curb_piece(ch: Chunk, c0: Vector2, c1: Vector2, face: Vector3, tn: Vector2, cc: Color) -> void:
	_tri(ch.roads, Vector3(c0.x, ROAD_Y - 0.02, c0.y), Vector3(c1.x, ROAD_Y - 0.02, c1.y), Vector3(c1.x, SIDEWALK_Y + 0.01, c1.y), face, cc)
	_tri(ch.roads, Vector3(c0.x, ROAD_Y - 0.02, c0.y), Vector3(c1.x, SIDEWALK_Y + 0.01, c1.y), Vector3(c0.x, SIDEWALK_Y + 0.01, c0.y), face, cc)
	_tri(ch.roads, Vector3(c0.x, SIDEWALK_Y + 0.01, c0.y), Vector3(c1.x, SIDEWALK_Y + 0.01, c1.y), Vector3(c1.x + tn.x, SIDEWALK_Y + 0.01, c1.y + tn.y), Vector3.UP, cc.lightened(0.08))
	_tri(ch.roads, Vector3(c0.x, SIDEWALK_Y + 0.01, c0.y), Vector3(c1.x + tn.x, SIDEWALK_Y + 0.01, c1.y + tn.y), Vector3(c0.x + tn.x, SIDEWALK_Y + 0.01, c0.y + tn.y), Vector3.UP, cc.lightened(0.08))


## Chaussée : la couleur des sommets porte la distance au bord (r = m / 8), la demi-largeur (g = m / 8)
## et b = 1 (marqueur) ; city_ground.gdshader en tire poussière des bords, traces de roues et taches.
## Marquages au sol, selon la largeur et le sens de la rue :
##   double sens : axe pointillé (continu et doublé sur les boulevards), voies séparées par des pointillés
##   sens unique : pointillés entre les voies
##   lignes de rive sur les axes, ligne d'arrêt et « STOP » peint avant les carrefours des petites rues,
##   flèches de direction et plaques d'égout.
func _markings(ch: Chunk, e: Array, a: Vector2, b: Vector2, d: Vector2, n: Vector2, L: float, w: float, hw: String, degree: Dictionary) -> void:
	var white := Color("eeeeeef7")
	var oneway := (int(e[3]) & 1) != 0
	var y := ROAD_Y + 0.02
	# Hors des carrefours : on arrête les lignes au bord du disque du carrefour
	var ta: float = (_stop_line_d(e[1], e[0]) + 0.5) if degree[e[0]] > 2 else (1.0 if degree[e[0]] == 1 else 0.0)
	var tb: float = (_stop_line_d(e[0], e[1]) + 0.5) if degree[e[1]] > 2 else (1.0 if degree[e[1]] == 1 else 0.0)
	if ta + tb > L - 1.0:
		return
	var lanes := maxi(1, int(round(w / 3.3))) if oneway else maxi(2, int(round(w / 3.3)) / 2 * 2)
	var major: bool = hw in DASHED
	if w >= 6.0:
		if oneway:
			for k in range(1, lanes):
				_dashes(ch, a, d, n * (-w / 2.0 + w * k / lanes), ta, L - tb, 3.0, 4.5, 0.08, white, y)
		else:
			if w >= 11.0:
				# Boulevard : double ligne continue au centre
				for sg in [-1.0, 1.0]:
					_ribbon(ch.roads, a + d * ta + n * sg * 0.18, a + d * (L - tb) + n * sg * 0.18, 0.07, y, white, 0.0)
			elif major or w >= 7.0:
				_dashes(ch, a, d, Vector2.ZERO, ta, L - tb, 3.0, 4.0, 0.08, white, y)
			else:
				_dashes(ch, a, d, Vector2.ZERO, ta, L - tb, 1.5, 3.5, 0.06, white, y)
			var per_side := lanes / 2
			for k in range(1, per_side):
				for sg in [-1.0, 1.0]:
					_dashes(ch, a, d, n * sg * (w / 2.0) * k / per_side, ta, L - tb, 3.0, 4.5, 0.07, white, y)
	# Lignes de rive (axes principaux)
	if major or hw in ["tertiary", "trunk_link", "primary_link"]:
		for sg in [-1.0, 1.0]:
			_ribbon(ch.roads, a + d * ta + n * sg * (w / 2.0 - 0.45), a + d * (L - tb) + n * sg * (w / 2.0 - 0.45), 0.06, y, white, 0.0)
	# Devant chaque carrefour : passage piéton, puis ligne d'arrêt (pleine : STOP ou feux ; pointillée : cédez)
	for endk in [[e[0], e[1]], [e[1], e[0]]]:
		var from: int = endk[0]
		var nd: int = endk[1]
		if degree[nd] < 3:
			continue
		var pn: Vector2 = node_pos[nd]
		var dout: Vector2 = (node_pos[from] - pn).normalized()
		var din := -dout
		var right := Vector2(-din.y, din.x)
		var key := Vector2i(from, nd)
		var jr := _jr(nd)
		if zebra_arms.has(key):
			var zc: Vector2 = pn + dout * (jr + 2.0)
			var tz := -w / 2.0 + 0.45
			while tz < w / 2.0 - 0.3:
				_ribbon(ch.roads, zc + right * tz - dout * 1.4, zc + right * tz + dout * 1.4, 0.25, y + 0.001, white, 0.0)
				tz += 1.0
		var rule: int = rules.get(key, 0)
		var arrive: bool = not oneway or from == e[0]
		if not arrive or (rule == 0 and not signal_nodes.has(nd)):
			continue
		var lp: Vector2 = pn + dout * (_stop_line_d(from, nd) + 0.2)
		var c0: Vector2 = lp if not oneway else lp - right * w / 2.0
		var c1: Vector2 = lp + right * (w / 2.0)
		if rule == RULE_YIELD:
			_dashes(ch, c0, (c1 - c0).normalized(), Vector2.ZERO, 0.1, c0.distance_to(c1) - 0.2, 0.5, 0.4, 0.15, white, y + 0.002)
		else:
			_ribbon(ch.roads, c0 + right * 0.05, c1 - right * 0.3, 0.2, y + 0.002, white, 0.0)
		if rule == 0 and w >= 7.0 and L > 30.0 and not oneway:
			_arrow(ch, (c0 + c1) / 2.0 + dout * 4.5, din, y + 0.002, white)
	# Plaques d'égout dans les voies
	var t := ta + 9.0 + fmod(absf(a.x * 3.1 + a.y * 1.7), 20.0)
	while t < L - tb - 3.0:
		var side := 1.0 if int(t) % 2 == 0 else -1.0
		_disc_n(ch.roads, a + d * t + n * side * w * 0.22, 0.32, ROAD_Y + 0.012, Color("2d2d2df7"), 10)
		t += 37.0


## Rayon d'un carrefour (demi-largeur de la plus grande rue qui y arrive)
func _jr(nd: int) -> float:
	if _road_grid.is_empty():
		_build_road_grid()
	return float(_junction_r.get(nd, 3.0))


## Pointillés le long de la rue (décalage `off` depuis l'axe), de t0 à t1
func _dashes(ch: Chunk, a: Vector2, d: Vector2, off: Vector2, t0: float, t1: float, dash: float, gap: float, half: float, col: Color, y: float) -> void:
	var t := t0 + gap * 0.5
	while t + dash < t1:
		_ribbon(ch.roads, a + d * t + off, a + d * (t + dash) + off, half, y, col, 0.0)
		t += dash + gap


## Flèche « tout droit » peinte dans la voie (pointe vers dir)
func _arrow(ch: Chunk, c: Vector2, dir: Vector2, y: float, col: Color) -> void:
	var nn := Vector2(-dir.y, dir.x)
	_ribbon(ch.roads, c - dir * 2.0, c + dir * 0.6, 0.15, y, col, 0.0)
	var tip := c + dir * 2.0
	var l := c + dir * 0.6 + nn * 0.55
	var r := c + dir * 0.6 - nn * 0.55
	_tri(ch.roads, Vector3(tip.x, y, tip.y), Vector3(l.x, y, l.y), Vector3(r.x, y, r.y), Vector3.UP, col)


## Couleur des sommets d'un sol dallé aligné sur la direction dir : r = cos θ / 2 + 1/2, g = sin θ (θ dans [0, π[),
## b = 0 (marqueur), alpha 0.8 (pavés) ; city_ground.gdshader y dessine les dalles.
func _paved(dir: Vector2) -> Color:
	var th := fposmod(dir.angle(), PI)
	return Color(cos(th) * 0.5 + 0.5, sin(th), 0.0, 0.8)


func _road_ribbon(s: Surf, a: Vector2, b: Vector2, half: float, y: float, ext: float) -> void:
	var q := _quad(a, b, half, ext)
	var d := (b - a).normalized()
	var a2 := a - d * ext
	var b2 := b + d * ext
	var ca := Vector3(a2.x, y, a2.y)
	var cb := Vector3(b2.x, y, b2.y)
	var edge := Color(0.0, half / 8.0, 1.0, 0.9)
	var mid := Color(minf(half / 8.0, 1.0), half / 8.0, 1.0, 0.9)
	for side in [[q[0], q[1]], [q[3], q[2]]]:
		var e0 := Vector3(side[0].x, y, side[0].y)
		var e1 := Vector3(side[1].x, y, side[1].y)
		_tri_c(s, e0, e1, cb, Vector3.UP, edge, edge, mid)
		_tri_c(s, e0, cb, ca, Vector3.UP, edge, mid, mid)


func _disc_n(s: Surf, c: Vector2, r: float, y: float, col: Color, seg: int) -> void:
	for k in seg:
		var a0 := k * TAU / seg
		var a1 := (k + 1) * TAU / seg
		_tri(s, Vector3(c.x, y, c.y), Vector3(c.x + cos(a0) * r, y, c.y + sin(a0) * r), Vector3(c.x + cos(a1) * r, y, c.y + sin(a1) * r), Vector3.UP, col)


func _disc(s: Surf, c: Vector2, r: float, y: float, col: Color) -> void:
	var seg := 10
	for k in seg:
		var a0 := k * TAU / seg
		var a1 := (k + 1) * TAU / seg
		_tri(s, Vector3(c.x, y, c.y), Vector3(c.x + cos(a0) * r, y, c.y + sin(a0) * r), Vector3(c.x + cos(a1) * r, y, c.y + sin(a1) * r), Vector3.UP, col)


func _build_scene() -> void:
	var root := Node3D.new()
	root.name = "Dakar"
	# Sol (terre) et quais
	var ground := Surf.new()
	var quay := Surf.new()
	var coast_col := PackedVector3Array()
	for land in lands:
		var idx := Geometry2D.triangulate_polygon(land)
		if idx.is_empty():
			print("triangulation de la terre impossible (%d points)" % land.size())
		for k in range(0, idx.size(), 3):
			var a: Vector2 = land[idx[k]]
			var b: Vector2 = land[idx[k + 1]]
			var c: Vector2 = land[idx[k + 2]]
			_tri(ground, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(c.x, 0, c.y), Vector3.UP, Color("cdbb8f99"))
		var n: int = land.size()
		var p0: Vector2 = land[0]
		var p1: Vector2 = land[1]
		var e0 := (p1 - p0).normalized()
		var flip := Geometry2D.is_point_in_polygon((p0 + p1) / 2.0 + Vector2(e0.y, -e0.x) * 0.05, land)
		for k in n:
			var a: Vector2 = land[k]
			var b: Vector2 = land[(k + 1) % n]
			var mid := (a + b) / 2.0
			# Les bords du cadre ne sont pas la côte
			if absf(mid.x - min_x) < 1.0 or absf(mid.x - max_x) < 1.0 or absf(mid.y - min_z) < 1.0 or absf(mid.y - max_z) < 1.0:
				continue
			var ed := b - a
			if ed.length() < 0.05:
				continue
			var o := Vector2(ed.y, -ed.x).normalized() * (-1.0 if flip else 1.0)
			var nrm := Vector3(o.x, 0, o.y)
			if _on_beach(mid):
				# Plage : le sable descend en pente douce dans l'eau
				var sand := Color("e6d3a399")
				var a2 := a + o * 9.0
				var b2 := b + o * 9.0
				_tri(quay, Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y), Vector3(b2.x, -1.3, b2.y), Vector3.UP, sand)
				_tri(quay, Vector3(a.x, 0.0, a.y), Vector3(b2.x, -1.3, b2.y), Vector3(a2.x, -1.3, a2.y), Vector3.UP, sand)
				coast_col.append_array(PackedVector3Array([Vector3(a.x, -1.5, a.y), Vector3(b.x, -1.5, b.y), Vector3(b.x, 2.5, b.y), Vector3(a.x, -1.5, a.y), Vector3(b.x, 2.5, b.y), Vector3(a.x, 2.5, a.y)]))
				continue
			var A := Vector3(a.x, -1.5, a.y)
			var B := Vector3(b.x, -1.5, b.y)
			var At := Vector3(a.x, 0.0, a.y)
			var Bt := Vector3(b.x, 0.0, b.y)
			_tri(quay, A, B, Bt, nrm, Color("8d8779b3"))
			_tri(quay, A, Bt, At, nrm, Color("8d8779b3"))
			var Ah := Vector3(a.x, 2.5, a.y)
			var Bh := Vector3(b.x, 2.5, b.y)
			coast_col.append_array(PackedVector3Array([A, B, Bh, A, Bh, Ah]))
	var plain := _vc_mat(false)
	var facade := _vc_mat(true)
	var gmesh := ArrayMesh.new()
	_surface(gmesh, ground, plain)
	_surface(gmesh, quay, plain)
	var gmi := MeshInstance3D.new()
	gmi.name = "Sol"
	gmi.mesh = gmesh
	root.add_child(gmi)
	# Corps de collision : sol plat partout, murets le long de la côte, limites de la carte
	var gbody := StaticBody3D.new()
	gbody.name = "SolCollision"
	root.add_child(gbody)
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(max_x - min_x + 400.0, 2.0, max_z - min_z + 400.0)
	gshape.shape = gbox
	gshape.position = Vector3((min_x + max_x) / 2.0, -1.0, (min_z + max_z) / 2.0)
	gbody.add_child(gshape)
	if not coast_col.is_empty():
		var cs := CollisionShape3D.new()
		var cshape := ConcavePolygonShape3D.new()
		cshape.backface_collision = true
		cshape.set_faces(coast_col)
		cs.shape = cshape
		gbody.add_child(cs)
	var walls := [
		[Vector3(min_x, 5, (min_z + max_z) / 2.0), Vector3(2, 10, max_z - min_z)],
		[Vector3(max_x, 5, (min_z + max_z) / 2.0), Vector3(2, 10, max_z - min_z)],
		[Vector3((min_x + max_x) / 2.0, 5, min_z), Vector3(max_x - min_x, 10, 2)],
		[Vector3((min_x + max_x) / 2.0, 5, max_z), Vector3(max_x - min_x, 10, 2)],
	]
	for wl in walls:
		var s := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = wl[1]
		s.shape = b
		s.position = wl[0]
		gbody.add_child(s)

	# Routes : trottoirs, chaussée, marquages
	var degree := {}
	for e in edges:
		degree[e[0]] = degree.get(e[0], 0) + 1
		degree[e[1]] = degree.get(e[1], 0) + 1
	var asphalt := Color("3a3a3ce6") # alpha 0.9 : asphalte (voir city_ground.gdshader)
	var curb := Color("8f8a7eb3") # béton
	var node_w := {}
	for e in edges:
		for nd in [e[0], e[1]]:
			node_w[nd] = maxf(node_w.get(nd, 0.0), e[2])
	for e in edges:
		var a := node_pos[e[0]]
		var b := node_pos[e[1]]
		var w: float = e[2]
		var hw: String = e[5]
		var ch := _chunk_of((a + b) / 2.0)
		# Ponts et rampes : tablier incliné avec parapets (pas de trottoir)
		if _h(e[0]) > 0.01 or _h(e[1]) > 0.01:
			_bridge_edge(ch, e[0], e[1], w, hw)
			continue
		if hw != "pedestrian":
			_road_ribbon(ch.roads, a, b, w / 2.0, ROAD_Y, w * 0.25)
		else:
			# Rue piétonne : dalles alignées sur la rue (voir _paved)
			_ribbon(ch.roads, a, b, w / 2.0, ROAD_Y, _paved(b - a), w * 0.25)
		var L := a.distance_to(b)
		if L < 0.05:
			continue
		var d := (b - a) / L
		var n := Vector2(-d.y, d.x)
		if (e[3] & 2) != 0 and hw != "pedestrian":
			_markings(ch, e, a, b, d, n, L, w, hw, degree)
	_build_sidewalks(curb)
	for nd in node_w:
		if degree[nd] > 2: # pas de disque au bout d'un cul-de-sac : la rue s'arrête net
			var p := node_pos[nd]
			_disc(_chunk_of(p).roads, p, node_w[nd] / 2.0 + 0.3, ROAD_Y + 0.006 + _h(nd), Color(1, 1, 1, 0.9)) # carrefour : loin des bords
	_build_crossings()
	# Terrains, plages, parcs, lieux de culte, panneaux (avant l'assemblage des blocs)
	_build_pitches(root)
	_build_beaches(root)
	_build_parks(root)
	_build_worship(root)
	_build_signs(root)
	_build_traffic_signs()
	_build_street_stalls()
	_build_rails()
	_build_parking_lots()
	_build_amenities(root)
	_build_tunnels(root)
	_build_trees()
	_build_containers(root)

	# Bâtiments
	var heights := {}
	# Un lieu du jeu (marché, café, arrêt…) placé dans l'emprise d'un bâtiment rendrait ce bâtiment
	# « creux » (murs et toit invisibles de l'intérieur) : on le laisse ouvert, comme une place.
	var open_spots: Array = []
	for k in places:
		var pv: Array = places[k]
		open_spots.append(Vector2(pv[0], pv[1]))
	var skipped: Array = []
	# Arène de lutte de la Médina : un îlot sans rue, dégagé de ses bâtiments
	var arene: Dictionary = _pick_arena_site()
	if not arene.is_empty():
		_build_lutte_arena(root, arene["c"], arene["door"])
	var stadiums: Array = []
	for pt in pitches:
		if pt.get("stadium", false):
			stadiums.append(pt["poly"])
	for i in buildings.size():
		var bpoly: PackedVector2Array = buildings[i]["poly"]
		var blocked := false
		# Anciennes tribunes et annexes dans l'enceinte d'un stade : remplacées par les gradins générés
		for spoly in stadiums:
			if Geometry2D.is_point_in_polygon(_centroid(bpoly), spoly):
				blocked = true
		for sp in open_spots:
			if Geometry2D.is_point_in_polygon(sp, bpoly):
				blocked = true
				break
		if not arene.is_empty() and _hits_arena(bpoly, arene):
			blocked = true
		if buildings[i].get("hidden", false):
			continue # maison de remplissage sur le terminal à conteneurs (voir _build_containers)
		if blocked:
			skipped.append(buildings[i]["name"] if buildings[i]["name"] != "" else "#%d" % i)
			continue
		var h := _mesh_building(buildings[i], i)
		var nm: String = buildings[i]["name"]
		if nm != "":
			heights[nm] = h
	print("variantes : %s" % variety)
	print("décors retirés de la chaussée : %s" % removed)
	print("bâtiments laissés ouverts (un lieu du jeu est dedans) : %s" % [skipped])
	var count := 0
	var tris := [0, 0, 0]
	for key in chunks:
		var ch: Chunk = chunks[key]
		tris[0] += ch.walls.v.size() / 3
		tris[1] += ch.roofs.v.size() / 3
		tris[2] += ch.roads.v.size() / 3
		var mesh := ArrayMesh.new()
		_surface(mesh, ch.walls, facade)
		_surface(mesh, ch.roofs, plain)
		_surface(mesh, ch.roads, plain)
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Bloc_%d_%d" % [key.x, key.y]
		mi.mesh = mesh
		root.add_child(mi)
		if not ch.col.is_empty():
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(ch.col)
			cs.shape = shape
			body.add_child(cs)
			mi.add_child(body)
		if not ch.roof_col.is_empty():
			# Toits : rien ne les heurte (masque 0, couche 8) ; seul main.gd les interroge par un rayon vertical
			var rbody := StaticBody3D.new()
			rbody.name = "Toits"
			rbody.collision_layer = 8
			rbody.collision_mask = 0
			var rcs := CollisionShape3D.new()
			var rshape := ConcavePolygonShape3D.new()
			rshape.backface_collision = true
			rshape.set_faces(ch.roof_col)
			rcs.shape = rshape
			rbody.add_child(rcs)
			mi.add_child(rbody)
		count += 1
	print("blocs : %d ; triangles murs %d, toits %d, sol %d" % [count, tris[0], tris[1], tris[2]])
	_build_bridge_col(root)

	# Panneaux et décors des lieux célèbres
	for nm in LANDMARKS:
		var info: Array = LANDMARKS[nm]
		if not places.has(info[0]):
			continue
		var c := _poi_c(info[0])
		var h: float = heights.get(nm, 6.0)
		Mk.label(root, info[1], Vector3(c.x, h + 6.0, c.y), 170, Color("fdef42"))
		match info[2]:
			"place":
				_decor_place(root, c)
			"minaret":
				_decor_mosque(root, c, h)
			"cross":
				_decor_cross(root, c, h)
			"porte":
				_decor_porte(root, c)
			"caserne":
				_decor_caserne(root, info[0])
	_set_owner(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, OUT_DIR + "/city.scn", ResourceSaver.FLAG_COMPRESS)
	print("city.scn : ", "ok" if err == OK else "ERREUR %d" % err)
	root.free()


func _decor_place(root: Node3D, c: Vector2) -> void:
	var p := Vector3(c.x, 0, c.y)
	Mk.cyl(root, 5.0, 5.0, 0.8, p + Vector3(0, 0.4, 0), Color("e9e4d8"), true, 24)
	Mk.cyl(root, 4.4, 4.4, 0.1, p + Vector3(0, 0.82, 0), Color(0.3, 0.6, 0.9, 0.85), false, 24)
	Mk.cyl(root, 0.1, 0.1, 14.0, p + Vector3(0, 7, -14), Color("cccccc"), true, 8)
	var flag := p + Vector3(2.0, 12.5, -14)
	Mk.box(root, Vector3(1.3, 2.6, 0.05), flag + Vector3(-1.3, 0, 0), Color("00853f"))
	Mk.box(root, Vector3(1.3, 2.6, 0.05), flag, Color("fdef42"))
	Mk.box(root, Vector3(1.3, 2.6, 0.05), flag + Vector3(1.3, 0, 0), Color("e31b23"))
	var star := Mk.cyl(root, 0.45, 0.45, 0.07, flag, Color("00853f"), false, 5)
	star.rotation.x = PI / 2.0


func _decor_mosque(root: Node3D, c: Vector2, h: float) -> void:
	var p := Vector3(c.x, 0, c.y)
	var green := Color("2d6a4f")
	Mk.sphere(root, 7.0, p + Vector3(0, h, 0), green, Vector3(1, 0.85, 1))
	Mk.cyl(root, 0.15, 0.15, 3.0, p + Vector3(0, h + 7.0, 0), Color("d4af37"), false, 6)
	# Le minaret de la Grande Mosquée culmine à environ 67 m.
	var m := p + Vector3(18, 0, 10)
	Mk.cyl(root, 2.0, 2.6, 60.0, m + Vector3(0, 30, 0), Color("f4f1ea"), true, 12)
	Mk.cyl(root, 3.2, 3.2, 0.8, m + Vector3(0, 50, 0), green, false, 12)
	Mk.cyl(root, 0.0, 2.2, 6.0, m + Vector3(0, 63, 0), green, false, 12)


func _decor_cross(root: Node3D, c: Vector2, h: float) -> void:
	var p := Vector3(c.x, h + 2.5, c.y)
	Mk.box(root, Vector3(4, 1.2, 0.3), p, Color("d62828"))
	Mk.box(root, Vector3(1.2, 4, 0.3), p, Color("d62828"))


func _decor_porte(root: Node3D, c: Vector2) -> void:
	var nr := _nearest_road(c)
	var dir: Vector2 = nr[1]
	var p := Vector3(c.x, 0, c.y)
	var side := Vector3(dir.x, 0, dir.y) * 6.0
	var bronze := Color("6b5a3e")
	Mk.box(root, Vector3(2, 20, 2), p + side + Vector3(0, 10, 0), bronze, true)
	Mk.box(root, Vector3(2, 20, 2), p - side + Vector3(0, 10, 0), bronze, true)
	var top := Mk.box(root, Vector3(15, 2, 2), p + Vector3(0, 21, 0), bronze)
	top.rotation.y = -atan2(dir.y, dir.x)


## Entrée de la caserne : mât et drapeau, mirador, barrière, panneau « zone militaire ».
func _decor_caserne(root: Node3D, place: String) -> void:
	var p: Array = places[place]
	var curb := Vector3(p[0], 0, p[1])
	var n := Vector3(p[3], 0, p[4])
	var f := Vector3(p[7], 0, p[8])
	var gate := curb + n * 3.0
	var olive := Color("4b5320")
	for side in [-1, 1]:
		Mk.box(root, Vector3(1.0, 3.0, 1.0), gate + f * (side * 4.5) + Vector3(0, 1.5, 0), Color("d8d2c0"), true)
	var bar := Mk.box(root, Vector3(8.0, 0.15, 0.15), gate + Vector3(0, 1.1, 0), Color("e63946"))
	bar.rotation.y = atan2(f.x, f.z) + PI / 2.0
	Mk.cyl(root, 0.08, 0.08, 10.0, gate + f * 8.0 + n * 2.0 + Vector3(0, 5, 0), Color("cccccc"), true, 8)
	var flag := gate + f * 8.0 + n * 2.0 + Vector3(0, 8.8, 0)
	var cols := [Color("00853f"), Color("fdef42"), Color("e31b23")]
	for k in 3:
		var s := Mk.box(root, Vector3(1.0, 2.0, 0.05), flag + f * (1.6 + k * 1.0) * 0.0 + Vector3(0.6 + k * 1.0, 0, 0), cols[k])
	# Mirador
	var tower := gate - f * 8.0 + n * 3.0
	for dx in [-1, 1]:
		for dz in [-1, 1]:
			Mk.box(root, Vector3(0.2, 6.0, 0.2), tower + Vector3(dx * 1.2, 3.0, dz * 1.2), olive, true)
	Mk.box(root, Vector3(3.0, 1.6, 3.0), tower + Vector3(0, 6.8, 0), olive)
	Mk.box(root, Vector3(3.4, 0.2, 3.4), tower + Vector3(0, 7.7, 0), Color("3a3f1c"))
	Mk.label(root, "ZONE MILITAIRE\nAccès interdit", gate + Vector3(0, 4.2, 0), 90, Color("ffd166"))


# --- Détails : feux, passages piétons, terrains de sport, plages, parcs, lieux de culte ---------

func _on_beach(p: Vector2) -> bool:
	for bch in beaches:
		var poly: PackedVector2Array = bch["poly"]
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		for q in poly:
			if q.distance_to(p) < 20.0:
				return true
	return false


func _collect_details() -> void:
	if not FileAccess.file_exists(DETAILS):
		print("pas de fichier de détails")
		return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(DETAILS))
	for e in raw["elements"]:
		var tags: Dictionary = e.get("tags", {})
		var etype: String = e["type"]
		var c := Vector2.ZERO
		var poly := PackedVector2Array()
		if etype == "node":
			c = proj(e["lat"], e["lon"])
		elif e.has("geometry"):
			poly = _geom(e["geometry"])
			c = _centroid(poly)
		elif etype == "relation":
			for m in e.get("members", []):
				if m.get("role", "") == "outer" and m.has("geometry"):
					poly = _geom(m["geometry"])
					c = _centroid(poly)
					break
		if not _inside(c, 60.0):
			continue
		var name := _norm(str(tags.get("name", "")))
		var hw := str(tags.get("highway", ""))
		var leisure := str(tags.get("leisure", ""))
		if hw == "traffic_signals":
			signals.append(c)
		elif hw == "stop":
			stop_signs.append(c)
		elif hw == "crossing":
			crossings.append(c)
		elif (leisure == "pitch" or leisure == "stadium") and poly.size() >= 3:
			var sport := str(tags.get("sport", "soccer"))
			if leisure == "stadium":
				sport = "soccer"
			if sport in ["soccer", "basketball", "tennis"]:
				pitches.append({"sport": sport, "poly": poly, "name": name, "stadium": leisure == "stadium"})
				nofill.append(poly)
		elif str(tags.get("natural", "")) in ["beach", "sand"] and poly.size() < 3 and name != "":
			beach_names.append([name, c])
		elif str(tags.get("natural", "")) in ["beach", "sand"] and poly.size() >= 3:
			beaches.append({"poly": poly, "name": name})
			nofill.append(poly)
		elif (leisure == "park" or str(tags.get("landuse", "")) in ["grass", "recreation_ground"]) and poly.size() >= 3:
			parks.append(poly)
			nofill.append(poly)
		elif str(tags.get("amenity", "")) == "place_of_worship":
			worship.append({"religion": str(tags.get("religion", "")), "name": name, "c": c, "poly": poly})
	# Les plages sans nom prennent le nom du point « plage » le plus proche (ex. Anse Bernard)
	for bn in beach_names:
		var best = null
		var bd := 200.0
		for bch in beaches:
			var d: float = _centroid(bch["poly"]).distance_to(bn[1])
			if d < bd:
				bd = d
				best = bch
		if best != null and best["name"] == "":
			best["name"] = "Plage de l'Anse Bernard" if "Anse Bernard" in bn[0] else bn[0]
	print("détails : %d feux, %d passages piétons, %d terrains, %d plages, %d parcs, %d lieux de culte" % [
		signals.size(), crossings.size(), pitches.size(), beaches.size(), parks.size(), worship.size()])


## Rectangle orienté de surface minimale : [centre, axe long, demi-longueur, demi-largeur]
func _obb(poly: PackedVector2Array) -> Array:
	var hull := Geometry2D.convex_hull(poly)
	var best := [Vector2.ZERO, Vector2.RIGHT, 1.0, 1.0]
	var best_area := INF
	for i in hull.size() - 1:
		var u := (hull[i + 1] - hull[i]).normalized()
		if u.length() < 0.5:
			continue
		var v := Vector2(-u.y, u.x)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in hull:
			var q := Vector2(p.dot(u), p.dot(v))
			mn = mn.min(q)
			mx = mx.max(q)
		var area := (mx.x - mn.x) * (mx.y - mn.y)
		if area < best_area:
			best_area = area
			var mid := (mn + mx) / 2.0
			var hl := (mx.x - mn.x) / 2.0
			var hwid := (mx.y - mn.y) / 2.0
			if hl >= hwid:
				best = [u * mid.x + v * mid.y, u, hl, hwid]
			else:
				best = [u * mid.x + v * mid.y, v, hwid, hl]
	return best


func _fill_flat(s: Surf, poly: PackedVector2Array, y: float, col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var b := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		_tri(s, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP, col)


## Rectangle orienté plein (centre c, axe u, demi-longueur hl, demi-largeur hw)
func _rect(s: Surf, c: Vector2, u: Vector2, hl: float, hw: float, y: float, col: Color) -> void:
	var v := Vector2(-u.y, u.x)
	var p := [c + u * hl + v * hw, c - u * hl + v * hw, c - u * hl - v * hw, c + u * hl - v * hw]
	_tri(s, Vector3(p[0].x, y, p[0].y), Vector3(p[1].x, y, p[1].y), Vector3(p[2].x, y, p[2].y), Vector3.UP, col)
	_tri(s, Vector3(p[0].x, y, p[0].y), Vector3(p[2].x, y, p[2].y), Vector3(p[3].x, y, p[3].y), Vector3.UP, col)


## Contour d'un rectangle (lignes blanches de terrain)
func _rect_lines(s: Surf, c: Vector2, u: Vector2, hl: float, hw: float, y: float, t: float) -> void:
	var v := Vector2(-u.y, u.x)
	var white := Color("f5f5f5")
	_rect(s, c + v * hw, u, hl, t, y, white)
	_rect(s, c - v * hw, u, hl, t, y, white)
	_rect(s, c + u * hl, v, hw, t, y, white)
	_rect(s, c - u * hl, v, hw, t, y, white)


func _ring(s: Surf, c: Vector2, r: float, y: float, t: float) -> void:
	var seg := 24
	for k in seg:
		var a0 := k * TAU / seg
		var a1 := (k + 1) * TAU / seg
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		_ribbon(s, p0, p1, t, y, Color("f5f5f5"), 0.0)


func _build_pitches(root: Node3D) -> void:
	var y := 0.09
	# Terrains situés dans un stade : le stade dessine le sien (aligné sur ce terrain), on ne le double pas
	for st in pitches:
		if not st.get("stadium", false):
			continue
		for q in pitches:
			if q.get("stadium", false) or q["sport"] != "soccer":
				continue
			if Geometry2D.is_point_in_polygon(_centroid(q["poly"]), st["poly"]):
				q["inside_stadium"] = true
				if not st.has("pitch_obb"):
					st["pitch_obb"] = _obb(q["poly"])
	for p in pitches:
		if p.get("inside_stadium", false):
			continue
		var poly: PackedVector2Array = p["poly"]
		var o := _obb(poly)
		var c: Vector2 = o[0]
		var u: Vector2 = o[1]
		var hl: float = o[2]
		var hw: float = o[3]
		var v := Vector2(-u.y, u.x)
		var ch := _chunk_of(c)
		var c3 := Vector3(c.x, 0, c.y)
		var u3 := Vector3(u.x, 0, u.y)
		var v3 := Vector3(v.x, 0, v.y)
		var yaw := atan2(-u.x, -u.y)
		if p.get("stadium", false):
			_build_stadium(root, p, y)
			continue
		match p["sport"]:
			"soccer":
				_fill_flat(ch.roads, poly, y - 0.012, Color("3b8a36"))
				_soccer_pitch(root, ch, c, u, hl * 0.9, hw * 0.86, y)
			"basketball":
				_fill_flat(ch.roads, poly, y - 0.01, Color("2b5aa8"))
				_rect(ch.roads, c, u, hl * 0.9, hw * 0.85, y - 0.005, Color("c8643b"))
				_rect_lines(ch.roads, c, u, hl * 0.9, hw * 0.85, y, 0.05)
				_rect(ch.roads, c, v, hw * 0.85, 0.05, y, Color("f5f5f5"))
				_ring(ch.roads, c, 1.8, y, 0.05)
				for side in [-1, 1]:
					var hc: Vector3 = c3 + u3 * side * (hl * 0.9 - 0.3)
					Mk.box(root, Vector3(0.15, 3.3, 0.15), hc + Vector3(0, 1.65, 0), Color("444444"), true)
					var board := Mk.box(root, Vector3(1.8, 1.05, 0.05), hc - u3 * side * 0.2 + Vector3(0, 3.3, 0), Color.WHITE)
					board.rotation.y = yaw + PI / 2.0
					var ring := Mk.cyl(root, 0.23, 0.23, 0.03, hc - u3 * side * 0.45 + Vector3(0, 3.05, 0), Color("ff5a00"), false, 12)
			"tennis":
				_fill_flat(ch.roads, poly, y - 0.01, Color("2f7a5a"))
				var L2 := minf(hl * 0.85, 11.9)
				var W2 := minf(hw * 0.75, 5.5)
				_rect(ch.roads, c, u, L2, W2, y - 0.005, Color("2b6cb0"))
				_rect_lines(ch.roads, c, u, L2, W2, y, 0.05)
				_rect(ch.roads, c, u, L2 * 0.54, 0.05, y, Color("f5f5f5"))
				for side in [-1, 1]:
					_rect(ch.roads, c + u * side * L2 * 0.54, v, W2, 0.05, y, Color("f5f5f5"))
				var net := Mk.box(root, Vector3(W2 * 2.0 + 0.6, 0.95, 0.03), c3 + Vector3(0, 0.47, 0), Color("222222"))
				net.rotation.y = yaw + PI / 2.0
				var top := Mk.box(root, Vector3(W2 * 2.0 + 0.6, 0.06, 0.05), c3 + Vector3(0, 0.95, 0), Color.WHITE)
				top.rotation.y = yaw + PI / 2.0
		if p["name"] != "":
			Mk.label(root, p["name"], c3 + Vector3(0, 4, 0), 110, Color("caffbf"))


func _build_beaches(root: Node3D) -> void:
	var brng := RandomNumberGenerator.new()
	brng.seed = 99
	var parasol_cols := [Color("e63946"), Color("ffb703"), Color("2a9d8f"), Color("3a86ff"), Color("f8f9fa")]
	var boat_cols := [Color("e63946"), Color("2a9d8f"), Color("ffb703"), Color("3a86ff"), Color("8338ec"), Color("06d6a0")]
	for bch in beaches:
		var poly: PackedVector2Array = bch["poly"]
		var ch := _chunk_of(_centroid(poly))
		_fill_flat(ch.roads, poly, 0.03, Color("efdcae"))
		var o := _obb(poly)
		var c: Vector2 = o[0]
		var u: Vector2 = o[1]
		var hl: float = o[2]
		var hw: float = o[3]
		var v := Vector2(-u.y, u.x)
		var placed := 0
		for k in 120:
			if placed > 28:
				break
			var p := c + u * brng.randf_range(-hl, hl) + v * brng.randf_range(-hw, hw)
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			var near_sea := false
			for d in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
				if _cell(p + d) == 4:
					near_sea = true
			var p3 := Vector3(p.x, 0.03, p.y)
			if near_sea and brng.randf() < 0.6:
				# Pirogue colorée tirée sur le sable
				var col: Color = boat_cols[brng.randi() % boat_cols.size()]
				var hull := Mk.box(root, Vector3(1.3, 0.7, 7.0), p3 + Vector3(0, 0.35, 0), col, true)
				hull.rotation.y = brng.randf() * TAU
				var stripe := Mk.box(hull, Vector3(1.32, 0.14, 7.05), Vector3(0, 0.25, 0), boat_cols[(brng.randi() + 2) % boat_cols.size()])
			elif brng.randf() < 0.5:
				Mk.cyl(root, 0.04, 0.04, 2.3, p3 + Vector3(0, 1.15, 0), Color("dddddd"), false, 4)
				Mk.cyl(root, 0.0, 1.3, 0.5, p3 + Vector3(0, 2.3, 0), parasol_cols[brng.randi() % parasol_cols.size()], false, 10)
			else:
				_palm(root, p3)
			placed += 1
		if bch["name"] != "":
			Mk.label(root, bch["name"], Vector3(c.x, 5, c.y), 150, Color("caf0f8"))


func _palm(root: Node3D, pos: Vector3) -> void:
	Mk.cyl(root, 0.15, 0.22, 6.0, pos + Vector3(0, 3, 0), Color("8a6e4b"), true, 6)
	for k in 6:
		var leaf := Mk.box(root, Vector3(0.5, 0.06, 2.6), pos + Vector3(0, 6.0, 0), Color("3f8f3a"))
		leaf.rotation = Vector3(-0.35, k * TAU / 6.0, 0)
		leaf.translate_object_local(Vector3(0, 0, -1.2))


func _build_parks(root: Node3D) -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = 5
	for poly in parks:
		var ch := _chunk_of(_centroid(poly))
		_fill_flat(ch.roads, poly, 0.025, Color("6a994e"))
		var o := _obb(poly)
		var c: Vector2 = o[0]
		var u: Vector2 = o[1]
		var v := Vector2(-u.y, u.x)
		var n := mini(30, int(_area(poly) / 500.0))
		for k in n * 3:
			if n <= 0:
				break
			var p: Vector2 = c + u * prng.randf_range(-o[2], o[2]) + v * prng.randf_range(-o[3], o[3])
			if not Geometry2D.is_point_in_polygon(p, poly) or _in_road(p, 0.6, true):
				continue
			var p3 := Vector3(p.x, 0, p.y)
			Mk.cyl(root, 0.15, 0.25, 3.0, p3 + Vector3(0, 1.5, 0), Color("6b4f3a"), true, 6)
			Mk.sphere(root, 1.8, p3 + Vector3(0, 3.8, 0), Color("4f7d3a"), Vector3(1, 0.75, 1))
			n -= 1


func _build_worship(root: Node3D) -> void:
	var done: Array = []
	for w in worship:
		var c: Vector2 = w["c"]
		var skip := false
		for d in done:
			if c.distance_to(d) < 40.0:
				skip = true
		if skip:
			continue
		done.append(c)
		var nm: String = w["name"]
		if nm == "Grande Mosquée de Dakar":
			continue
		var poly: PackedVector2Array = w["poly"]
		var base := c
		if poly.size() >= 3:
			base = c.lerp(poly[0], 0.6)
		if _in_road(base, 1.8, true):
			base = c
		if _in_road(base, 1.8, true):
			removed["minarets"] = int(removed.get("minarets", 0)) + 1
			continue
		var p3 := Vector3(base.x, 0, base.y)
		if w["religion"] == "christian":
			# Église : clocher blanc, toit en pointe et croix
			var white := Color("f1ede4")
			Mk.box(root, Vector3(3.2, 16.0, 3.2), p3 + Vector3(0, 8, 0), white, true)
			Mk.cyl(root, 0.0, 2.4, 4.0, p3 + Vector3(0, 18, 0), Color("8a3b2e"), false, 4)
			Mk.box(root, Vector3(0.2, 2.2, 0.2), p3 + Vector3(0, 21.1, 0), Color("d4af37"))
			Mk.box(root, Vector3(1.2, 0.2, 0.2), p3 + Vector3(0, 21.5, 0), Color("d4af37"))
			if nm != "":
				Mk.label(root, nm, p3 + Vector3(0, 24, 0), 130, Color("fff3b0"))
		else:
			# Mosquée de quartier : minaret blanc et vert
			Mk.cyl(root, 0.9, 1.1, 16.0, p3 + Vector3(0, 8, 0), Color("f4f1ea"), true, 10)
			Mk.cyl(root, 1.5, 1.5, 0.5, p3 + Vector3(0, 13, 0), Color("2d6a4f"), false, 10)
			Mk.cyl(root, 0.0, 1.0, 2.5, p3 + Vector3(0, 17.2, 0), Color("2d6a4f"), false, 10)
			Mk.sphere(root, 0.18, p3 + Vector3(0, 18.6, 0), Color("d4af37"))
			if nm != "" and done.size() % 3 == 1:
				Mk.label(root, nm, p3 + Vector3(0, 20.5, 0), 110, Color("d8f3dc"))


## Plus proche tronçon de route d'un point : [indice, distance]
func _nearest_edge(p: Vector2) -> Array:
	var best := -1
	var bd := INF
	for i in edges.size():
		var e: Array = edges[i]
		var q := Geometry2D.get_closest_point_to_segment(p, node_pos[e[0]], node_pos[e[1]])
		var d := p.distance_to(q)
		if d < bd:
			bd = d
			best = i
	return [best, bd]


## Passages piétons (zébras) aux vrais passages et aux feux.
func _build_crossings() -> void:
	var white := Color("f2f2f2f7") # alpha 0.97 : peinture routière usée
	var zebra_nodes := {}
	for k in zebra_arms:
		zebra_nodes[k.y] = true
	for p in crossings:
		var near_junction := false
		for nd in zebra_nodes:
			if p.distance_to(node_pos[nd]) < _jr(nd) + 6.0:
				near_junction = true
				break
		if near_junction:
			continue
		var ne := _nearest_edge(p)
		if ne[0] == -1 or ne[1] > 12.0:
			continue
		var e: Array = edges[ne[0]]
		var a := node_pos[e[0]]
		var b := node_pos[e[1]]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var w: float = e[2]
		var ch := _chunk_of(q)
		var t := -w / 2.0 + 0.4
		while t < w / 2.0 - 0.3:
			var s := q + n * t
			_ribbon(ch.roads, s - d * 1.6, s + d * 1.6, 0.22, ROAD_Y + 0.015, white, 0.0)
			t += 0.9


## Panneaux : STOP, limitation à 50, plaques de rue.
func _build_signs(root: Node3D) -> void:
	for p in ([] if not rules.is_empty() else stop_signs):
		var ne := _nearest_edge(p)
		if ne[0] == -1:
			continue
		var e: Array = edges[ne[0]]
		var d := (node_pos[e[1]] - node_pos[e[0]]).normalized()
		var n := Vector2(-d.y, d.x)
		var pos: Vector2 = _off_road(p + n * (float(e[2]) / 2.0 + 1.0), d)
		if pos == Vector2.INF:
			continue
		_sign_post(root, Vector3(pos.x, SIDEWALK_Y, pos.y), atan2(-d.x, -d.y) + PI, "STOP", Color("c1121f"), 8)
	var placed_names: Array = []
	var speed_acc := 0.0
	for e in edges:
		var hw: String = e[5]
		var a := node_pos[e[0]]
		var b := node_pos[e[1]]
		var L := a.distance_to(b)
		if L < 0.5:
			continue
		var d := (b - a) / L
		var n := Vector2(-d.y, d.x)
		var w: float = e[2]
		if hw in ["primary", "secondary", "trunk"]:
			speed_acc += L
			if speed_acc > 260.0:
				speed_acc = 0.0
				var sp := _off_road(a + d * (L * 0.5) + n * (w / 2.0 + 1.1), d)
				if sp != Vector2.INF:
					_sign_post(root, Vector3(sp.x, SIDEWALK_Y, sp.y), atan2(-d.x, -d.y) + PI, "50", Color("c1121f"), 24)
		var nm_idx: int = e[4]
		if nm_idx >= 0 and placed_names.size() < 160:
			# Plaque de rue : sur le trottoir, après le carrefour (jamais au milieu de la rue qui croise)
			if _road_grid.is_empty():
				_build_road_grid()
			var t0 := minf(L * 0.5, float(_junction_r.get(e[0], w / 2.0)) + SIDEWALK_W + 1.5)
			var np := _off_road(a + d * t0 + n * (w / 2.0 + 1.0), d)
			if np == Vector2.INF:
				continue
			var far := true
			for q in placed_names:
				if np.distance_to(q) < 70.0:
					far = false
					break
			if far:
				placed_names.append(np)
				var p3 := Vector3(np.x, SIDEWALK_Y, np.y)
				Mk.cyl(root, 0.04, 0.04, 2.8, p3 + Vector3(0, 1.4, 0), Color("6c757d"), false, 4)
				var plate := Mk.box(root, Vector3(1.6, 0.32, 0.04), p3 + Vector3(0, 2.75, 0), Color("1f4e9c"))
				plate.rotation.y = atan2(-d.x, -d.y) + PI / 2.0
				var street: String = street_names[nm_idx]
				for face in [-1, 1]:
					# Une face par côté (pas de texte vu à l'envers), taille adaptée pour tenir sur la plaque
					var lbl := Mk.label(plate, street, Vector3(0, 0, face * 0.025), clampi(int(300.0 / maxf(1.0, street.length())), 9, 20), Color.WHITE, false)
					lbl.double_sided = false
					lbl.outline_size = 0
					lbl.rotation.y = 0.0 if face > 0 else PI
					lbl.width = 150.0
					lbl.autowrap_mode = TextServer.AUTOWRAP_OFF


# --- Chaussée : aucun poteau ne doit s'y trouver --------------------------------------

const ROAD_CELL := 25.0
var _road_grid := {}
var _junction_r := {} ## nœud → rayon du carrefour (demi-largeur de la plus grande rue)


func _build_road_grid() -> void:
	for i in edges.size():
		var e: Array = edges[i]
		if (int(e[3]) & 2) == 0:
			continue
		var r: float = float(e[2]) / 2.0
		for nd in [e[0], e[1]]:
			_junction_r[nd] = maxf(_junction_r.get(nd, 0.0), r)
		var pa := node_pos[e[0]]
		var pb := node_pos[e[1]]
		for gx in range(floori((minf(pa.x, pb.x) - r - 1.0) / ROAD_CELL), floori((maxf(pa.x, pb.x) + r + 1.0) / ROAD_CELL) + 1):
			for gz in range(floori((minf(pa.y, pb.y) - r - 1.0) / ROAD_CELL), floori((maxf(pa.y, pb.y) + r + 1.0) / ROAD_CELL) + 1):
				var cell := Vector2i(gx, gz)
				if not _road_grid.has(cell):
					_road_grid[cell] = PackedInt32Array()
				_road_grid[cell].append(i)


## Vrai si p est sur une chaussée (ou à moins de `margin` m de son bord), carrefours compris.
func _in_road(p: Vector2, margin := 0.4, ground_only := false) -> bool:
	if _road_grid.is_empty():
		_build_road_grid()
	for i in _road_grid.get(Vector2i(floori(p.x / ROAD_CELL), floori(p.y / ROAD_CELL)), PackedInt32Array()):
		var e: Array = edges[i]
		if ground_only and (_h(e[0]) > 0.5 or _h(e[1]) > 0.5):
			continue
		var a := node_pos[e[0]]
		var b := node_pos[e[1]]
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < float(e[2]) / 2.0 + margin:
			return true
		for nd in [e[0], e[1]]:
			if p.distance_to(node_pos[nd]) < float(_junction_r.get(nd, 0.0)) + margin:
				return true
	return false


## Premier point hors chaussée en glissant le long de `along` (jusqu'à max_shift m) ; Vector2.INF sinon.
func _off_road(p: Vector2, along: Vector2, max_shift := 12.0) -> Vector2:
	if not _in_road(p):
		return p
	var s := 1.0
	while s <= max_shift:
		for sg: float in [1.0, -1.0]:
			var c2: Vector2 = p + along * s * sg
			if not _in_road(c2):
				return c2
		s += 1.0
	return Vector2.INF


func _sign_post(root: Node3D, pos: Vector3, yaw: float, text: String, col: Color, segments: int) -> void:
	Mk.cyl(root, 0.04, 0.04, 2.4, pos + Vector3(0, 1.2, 0), Color("6c757d"), false, 4)
	var face := Mk.cyl(root, 0.38, 0.38, 0.04, pos + Vector3(0, 2.4, 0), col, false, segments)
	face.rotation = Vector3(PI / 2.0, yaw, 0)
	var inner_col := Color.WHITE if text == "50" else col
	if text == "50":
		var inner := Mk.cyl(root, 0.3, 0.3, 0.05, pos + Vector3(0, 2.4, 0), inner_col, false, segments)
		inner.rotation = Vector3(PI / 2.0, yaw, 0)
	var holder := Node3D.new()
	root.add_child(holder)
	holder.position = pos + Vector3(0, 2.4, 0)
	holder.rotation.y = yaw
	var lbl := Mk.label(holder, text, Vector3(0, 0, 0.04), 30, Color.WHITE if text == "STOP" else Color.BLACK, false)
	lbl.double_sided = false # vu de dos, le panneau est un disque uni (pas de texte à l'envers)
	lbl.outline_size = 0


## Feux tricolores : rattachés au nœud du réseau le plus proche (le jeu les anime).
func _map_signals() -> void:
	var seen := {}
	for p in signals:
		var best := -1
		var bd := 18.0
		for i in node_pos.size():
			var d: float = p.distance_to(node_pos[i])
			if d < bd:
				bd = d
				best = i
		if best != -1 and not seen.has(best):
			seen[best] = true
			signal_nodes.append(best)

## Feux tricolores en plus de ceux d'OpenStreetMap : tout carrefour où se croisent au moins deux rues de 8 m
## et plus (axes, avenues). Un seul feu par groupe de nœuds proches (les doubles voies font plusieurs nœuds).
func _auto_signals() -> void:
	var big := {} ## carrefour → [nombre de branches larges, nombre de branches]
	for e in edges:
		if (int(e[3]) & 2) == 0:
			continue
		for nd in [e[0], e[1]]:
			if not big.has(nd):
				big[nd] = [0, 0, 0]
			big[nd][1] += 1
			if float(e[2]) >= 8.0:
				big[nd][0] += 1
			if float(e[2]) >= 6.5:
				big[nd][2] += 1
	var cands: Array = []
	for nd in big:
		# Une rue large qui continue tout droit n'est pas un croisement : il faut aussi une autre rue d'au moins 6,5 m
		if big[nd][1] >= 3 and big[nd][0] >= 2 and big[nd][2] >= 3 and _h(nd) < 0.01:
			cands.append([big[nd][1] * 10 + big[nd][0], nd])
	cands.sort()
	cands.reverse()
	var added := 0
	for cd in cands:
		var nd: int = cd[1]
		var near := false
		for s in signal_nodes:
			if node_pos[s].distance_to(node_pos[nd]) < 40.0:
				near = true
				break
		if near:
			continue
		signal_nodes.append(nd)
		added += 1
	print("feux tricolores : %d carrefours (%d ajoutés aux %d d'OpenStreetMap)" % [signal_nodes.size(), added, signal_nodes.size() - added])


## Priorités aux carrefours sans feux : l'axe le plus large et le plus droit passe ; les autres branches ont
## un STOP (rue nettement plus étroite que l'axe, ruelle) ou un « cédez le passage » (rues de même taille). Passages piétons
## sur toutes les branches des carrefours à feux et des carrefours d'une rue d'au moins 8 m.
func _compute_rules() -> void:
	var adj := {} ## carrefour → [[autre nœud, largeur, on peut y arriver par là]]
	for e in edges:
		if (int(e[3]) & 2) == 0:
			continue
		var oneway := (int(e[3]) & 1) != 0
		for k in 2:
			var nd: int = e[1] if k == 0 else e[0]
			var other: int = e[0] if k == 0 else e[1]
			if not adj.has(nd):
				adj[nd] = []
			adj[nd].append([other, float(e[2]), k == 0 or not oneway])
	for nd in adj:
		var arms: Array = adj[nd]
		if arms.size() < 3 or _h(nd) > 0.01:
			continue
		var sig: bool = signal_nodes.has(nd)
		var maxw := 0.0
		for a in arms:
			maxw = maxf(maxw, a[1])
		if sig or maxw >= 8.0:
			for a in arms:
				zebra_arms[Vector2i(a[0], nd)] = true
		if sig:
			continue
		var best := -INF
		var bi := 0
		var bj := 1
		for i in arms.size():
			for j in range(i + 1, arms.size()):
				var di := (node_pos[arms[i][0]] - node_pos[nd]).normalized()
				var dj := (node_pos[arms[j][0]] - node_pos[nd]).normalized()
				var score: float = (float(arms[i][1]) + float(arms[j][1])) * 10.0 - di.dot(dj) * 6.0
				if score > best:
					best = score
					bi = i
					bj = j
		var mainw: float = minf(arms[bi][1], arms[bj][1])
		for k in arms.size():
			if k == bi or k == bj or not arms[k][2]:
				continue
			var w: float = arms[k][1]
			# STOP pour une rue nettement plus étroite que l'axe (ou une ruelle) ; cédez entre rues de même taille
			rules[Vector2i(arms[k][0], nd)] = RULE_STOP if (w <= 5.0 or mainw - w >= 1.5) else RULE_YIELD
	var n_stop := 0
	for k in rules:
		if rules[k] == RULE_STOP:
			n_stop += 1
	print("priorités : %d STOP, %d cédez le passage, %d branches avec passage piéton" % [n_stop, rules.size() - n_stop, zebra_arms.size()])


## Distance au centre du carrefour de la ligne d'arrêt (après le passage piéton s'il y en a un)
func _stop_line_d(from: int, nd: int) -> float:
	return _jr(nd) + (3.9 if zebra_arms.has(Vector2i(from, nd)) else 0.5)


# --- Panneaux de signalisation (géométrie fusionnée dans les blocs : aucun nœud en plus) ---

## Panneaux devant chaque branche qui a une règle, et « passage piéton » sur les axes larges
func _build_traffic_signs() -> void:
	var placed := {}
	for key in rules.keys() + zebra_arms.keys():
		if placed.has(key):
			continue
		placed[key] = true
		var from: int = key.x
		var nd: int = key.y
		var kind := ""
		if rules.has(key):
			kind = "stop" if rules[key] == RULE_STOP else "cedez"
		elif not signal_nodes.has(nd):
			var w := _edge_w(from, nd)
			if w < 8.0 or not _can_arrive(from, nd):
				continue
			kind = "pieton"
		else:
			continue
		var w := _edge_w(from, nd)
		var L := node_pos[from].distance_to(node_pos[nd])
		var dout := (node_pos[from] - node_pos[nd]).normalized()
		var din := -dout
		var right := Vector2(-din.y, din.x)
		var t := _stop_line_d(from, nd) + 0.6
		var pos := Vector2.INF
		while t < minf(L - 2.0, _stop_line_d(from, nd) + 6.0):
			var cand: Vector2 = node_pos[nd] + dout * t + right * (w / 2.0 + 0.55)
			if not _in_road(cand, 0.2, true) and _cell(cand) != 2:
				pos = cand
				break
			t += 1.0
		if pos == Vector2.INF:
			sign_count["sans place"] = int(sign_count.get("sans place", 0)) + 1
			continue
		_traffic_sign(_chunk_of(pos), pos, dout, kind)
		sign_count[kind] = int(sign_count.get(kind, 0)) + 1
	print("panneaux de circulation : %s" % sign_count)


## Vie de rue : petits étals de vendeurs, jamais sur la chaussée : derrière le trottoir s'il y a de la place, sinon
## contre le mur sur le dernier demi-mètre du trottoir (les piétons marchent au milieu, à 0,9 m de la bordure).
## Coin thé (ataya), étal de fruits sous parasol, kiosque de cartes de recharge (seulement s'il y a de la place).
## Géométrie fusionnée dans les blocs (aucun nœud en plus) avec une collision simple.
func _build_street_stalls() -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = 7
	var degree := {}
	for e in edges:
		degree[e[0]] = degree.get(e[0], 0) + 1
		degree[e[1]] = degree.get(e[1], 0) + 1
	var avoid: Array = [] ## positions déjà prises (arbres, lieux du jeu, parkings, étals)
	for t in tree_spots:
		avoid.append(t[0])
	for pa in palm_spots:
		avoid.append(pa)
	for k in places:
		var pl: Array = places[k]
		avoid.append(Vector2(pl[0], pl[1]))
		if pl.size() > 6:
			avoid.append(Vector2(pl[5], pl[6]))
	for pk in parking:
		avoid.append(Vector2(pk["pos"][0], pk["pos"][1]))
	var hash := {}
	for q in avoid:
		var hc := Vector2i(floori(q.x / 20.0), floori(q.y / 20.0))
		if not hash.has(hc):
			hash[hc] = []
		hash[hc].append(q)
	var count := {}
	for e in edges:
		var hw: String = e[5]
		var w: float = e[2]
		if (int(e[3]) & 2) == 0 or hw in NO_WALK or w < 5.0 or w > 16.0 or _h(e[0]) > 0.01 or _h(e[1]) > 0.01:
			continue
		var a := node_pos[e[0]]
		var b := node_pos[e[1]]
		var L := a.distance_to(b)
		if L < 24.0:
			continue
		var d := (b - a) / L
		var n := Vector2(-d.y, d.x)
		var t := 10.0 + prng.randf() * 30.0
		while t < L - 10.0:
			var side := 1.0 if prng.randf() < 0.5 else -1.0
			var p := a + d * t + n * side * (w / 2.0 + SIDEWALK_W + 0.75)
			t += 35.0 + prng.randf() * 55.0
			# Place libre derrière le trottoir : pas de bâtiment ni de chaussée sous l'étal ni juste derrière
			var compact := false
			var ok := true
			for off in [Vector2.ZERO, d * 0.9, -d * 0.9, n * side * 1.0, n * side * 0.5 + d * 0.9, n * side * 0.5 - d * 0.9]:
				var c: int = _cell(p + off)
				if c == 2 or c == 4 or _in_road(p + off, 0.4):
					ok = false
			if not ok:
				# Sinon contre le mur, au fond du trottoir
				p = a + d * t + n * side * (w / 2.0 + SIDEWALK_W - 0.27)
				compact = true
				ok = true
				for off in [Vector2.ZERO, d * 0.9, -d * 0.9]:
					if _in_road(p + off, 0.4) or _cell(p + off) == 4:
						ok = false
				if _cell(p + n * side * 0.9) != 2 and _cell(p + n * side * 1.8) != 2 and _cell(p + n * side * 2.8) != 2:
					ok = false # pas de mur derrière : on ne bloque pas un passage
			if not ok:
				continue
			var hc := Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for q in hash.get(hc + Vector2i(dx, dz), []):
						if q.distance_to(p) < 6.0:
							ok = false
			if not ok:
				continue
			if not hash.has(hc):
				hash[hc] = []
			hash[hc].append(p)
			var kind: String = ["the", "fruits", "fruits", "recharge"][prng.randi() % 4]
			if compact and kind == "recharge":
				kind = "the" if prng.randf() < 0.5 else "fruits"
			_stall(_chunk_of(p), Vector3(p.x, SIDEWALK_Y if compact else 0.0, p.y), d, -n * side, kind, prng, compact)
			stalls.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), kind, snappedf(-n.x * side, 0.001), snappedf(-n.y * side, 0.001), SIDEWALK_Y if compact else 0.0])
			count[kind] = int(count.get(kind, 0)) + 1
			if int(count[kind]) == 40:
				print("  exemple %s%s : %.1f, %.1f (rue vers %.2f, %.2f)" % [kind, " sur le trottoir" if compact else "", p.x, p.y, d.x, d.y])
	print("étals de rue : %s" % count)


## Un étal : `along` le long de la rue, `face` vers la rue
## `compact` : sur le trottoir, tout tient dans 0,5 m de profondeur
func _stall(ch: Chunk, base: Vector3, along: Vector2, face: Vector2, kind: String, prng: RandomNumberGenerator, compact := false) -> void:
	var k := 0.55 if compact else 1.0 ## profondeur (vers la rue)
	var ax := Vector3(along.x, 0, along.y)
	var fv := Vector3(face.x, 0, face.y)
	var wood := Color(Color("7a5534"), 0.3)
	var dark := Color(Color("2a2a2a"), 0.3)
	match kind:
		"the":
			# Petite table basse, réchaud à charbon, théière, deux tabourets
			_obox(ch.walls, base + Vector3(0, 0.25, 0), Vector3(0.35, 0.03, 0.25 * k), ax, wood)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_obox(ch.walls, base + ax * sx * 0.3 + fv * sz * 0.2 * k + Vector3(0, 0.11, 0), Vector3(0.025, 0.11, 0.025), ax, wood)
			_obox(ch.walls, base + Vector3(0, 0.33, 0) + ax * 0.12, Vector3(0.07, 0.06, 0.07), ax, Color(Color("1e5aa8"), 0.3))
			_obox(ch.walls, base + Vector3(0, 0.1, 0) - ax * 0.6 + fv * 0.15 * (k - 0.55) * 2.2, Vector3(0.14, 0.1, 0.14), ax, dark)
			_obox(ch.walls, base + Vector3(0, 0.24, 0) - ax * 0.6 + fv * 0.15 * (k - 0.55) * 2.2, Vector3(0.09, 0.05, 0.09), ax, Color(Color("8a8f94"), 0.3))
			for sx in [-1.0, 1.0]:
				_obox(ch.walls, base + ax * sx * 0.75 - fv * 0.25 * (k - 0.55) * 2.2 + Vector3(0, 0.15, 0), Vector3(0.14, 0.15, 0.14), ax, Color(Color(["c1121f", "2a9d8f", "e9c46a"][prng.randi() % 3]), 0.3))
			_box_col(ch, base + Vector3(0, 0.25, 0), Vector3(0.45, 0.25, 0.3 * k), ax)
		"fruits":
			# Table, cageots de fruits colorés, parasol
			_obox(ch.walls, base + Vector3(0, 0.75, 0), Vector3(0.7, 0.04, 0.4 * k), ax, wood)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_obox(ch.walls, base + ax * sx * 0.62 + fv * sz * 0.32 * k + Vector3(0, 0.36, 0), Vector3(0.03, 0.36, 0.03), ax, wood)
			var fruit := ["f4a261", "e76f51", "9ccc65", "ffd166", "8b1e3f", "fb8500"]
			for i in 3:
				var c := Color(Color(fruit[prng.randi() % fruit.size()]), 0.3)
				_obox(ch.walls, base + ax * (i - 1) * 0.42 + Vector3(0, 0.86, 0), Vector3(0.19, 0.07, 0.17 * k), ax, c)
			_obox(ch.walls, base - fv * 0.45 * k + Vector3(0, 1.1, 0), Vector3(0.025, 1.1, 0.025), ax, Color(Color("cfcfcf"), 0.3))
			var cols := ["c1121f", "1e5aa8", "2a9d8f", "f4a261", "6a4c93"]
			var top := Color(Color(cols[prng.randi() % cols.size()]), 0.3)
			var top2 := Color(Color("f4f4f2"), 0.3)
			var hub := base - fv * 0.45 * k + Vector3(0, 2.3, 0)
			for i in 8:
				var a0 := i * TAU / 8.0
				var a1 := (i + 1) * TAU / 8.0
				var r := 1.1
				var p0 := hub + Vector3(cos(a0) * r, -0.3, sin(a0) * r)
				var p1 := hub + Vector3(cos(a1) * r, -0.3, sin(a1) * r)
				var c := top if i % 2 == 0 else top2
				var nrm := (p0 - hub).cross(p1 - hub).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				_tri(ch.walls, hub, p0, p1, nrm, c)
				_tri(ch.walls, hub, p1, p0, -nrm, c) # dessous
			_box_col(ch, base + Vector3(0, 0.45, 0), Vector3(0.72, 0.45, 0.42 * k), ax)
		"recharge":
			# Kiosque peint (cartes de recharge, crédit) avec auvent
			var paint := Color(Color(["f77f00", "2a9d8f", "ffd60a", "e63946"][prng.randi() % 4]), 0.3)
			_obox(ch.walls, base + Vector3(0, 0.55, 0), Vector3(0.6, 0.55, 0.45), ax, paint)
			_obox(ch.walls, base + Vector3(0, 1.75, 0) - fv * 0.25, Vector3(0.6, 0.65, 0.2), ax, Color(paint.darkened(0.25), 0.3))
			_obox(ch.walls, base + Vector3(0, 2.45, 0) + fv * 0.05, Vector3(0.75, 0.04, 0.6), ax, Color(Color("dddddd"), 0.3))
			_obox(ch.walls, base + Vector3(0, 1.15, 0) + fv * 0.42, Vector3(0.5, 0.05, 0.05), ax, Color(Color("f4f4f2"), 0.3))
			_box_col(ch, base + Vector3(0, 1.2, 0), Vector3(0.62, 1.2, 0.47), ax)


func _edge_w(a: int, b: int) -> float:
	for e in edges:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return float(e[2])
	return 6.5


func _can_arrive(from: int, nd: int) -> bool:
	for e in edges:
		if e[0] == from and e[1] == nd:
			return true
		if e[0] == nd and e[1] == from:
			return (int(e[3]) & 1) == 0
	return false


## Panneau sur poteau ; `face` : direction vers laquelle il regarde (vers le conducteur qui arrive)
func _traffic_sign(ch: Chunk, p: Vector2, face: Vector2, kind: String) -> void:
	var nrm := Vector3(face.x, 0, face.y)
	var u := Vector3(face.y, 0, -face.x) # axe x du panneau : vers la droite de qui le regarde
	var ax := Vector3(u.x, 0, u.z)
	var base := Vector3(p.x, SIDEWALK_Y, p.y)
	var grey := Color(Color("8a8f94"), 0.3)
	_obox(ch.walls, base + Vector3(0, 1.15, 0), Vector3(0.035, 1.15, 0.035), ax, grey)
	_box_col(ch, base + Vector3(0, 1.15, 0), Vector3(0.05, 1.15, 0.05), ax)
	var c := base + Vector3(0, 2.25, 0) + nrm * 0.05
	var red := Color(Color("c1121f"), 0.3)
	var white := Color(Color("f4f4f2"), 0.3)
	var blue := Color(Color("1f4e9c"), 0.3)
	var black := Color(Color("1a1a1a"), 0.3)
	match kind:
		"stop":
			_sign_poly(ch, c, u, nrm, _ngon(8, 0.4, PI / 8.0), white, true)
			_sign_poly(ch, c + nrm * 0.004, u, nrm, _ngon(8, 0.36, PI / 8.0), red, false)
			_sign_text(ch, c + nrm * 0.008, u, nrm, white)
		"cedez":
			var outer := [Vector2(0, -0.42), Vector2(0.48, 0.4), Vector2(-0.48, 0.4)]
			var inner := [Vector2(0, -0.27), Vector2(0.33, 0.3), Vector2(-0.33, 0.3)]
			_sign_poly(ch, c, u, nrm, outer, red, true)
			_sign_poly(ch, c + nrm * 0.004, u, nrm, inner, white, false)
		"pieton":
			var sq := [Vector2(-0.32, -0.32), Vector2(0.32, -0.32), Vector2(0.32, 0.32), Vector2(-0.32, 0.32)]
			_sign_poly(ch, c, u, nrm, sq, blue, true)
			_sign_poly(ch, c + nrm * 0.004, u, nrm, [Vector2(0, 0.28), Vector2(0.27, -0.2), Vector2(-0.27, -0.2)], white, false)
			# Piéton qui marche (tête, corps, jambes, bras) et bandes du passage
			var fig := [[Vector2(0.0, 0.1), Vector2(-0.03, -0.04)], [Vector2(-0.03, -0.04), Vector2(-0.09, -0.15)],
				[Vector2(-0.03, -0.04), Vector2(0.05, -0.15)], [Vector2(0.0, 0.07), Vector2(-0.07, 0.0)], [Vector2(0.0, 0.07), Vector2(0.07, 0.01)]]
			for sg in fig:
				_sign_stroke(ch, c + nrm * 0.008, u, nrm, sg[0], sg[1], 0.018, black)
			_sign_poly(ch, c + nrm * 0.008, u, nrm, _ngon(6, 0.035, 0.0).map(func(q): return q + Vector2(0.01, 0.15)), black, false)
			for k in 3:
				_sign_stroke(ch, c + nrm * 0.008, u, nrm, Vector2(-0.16 + k * 0.12, -0.18), Vector2(-0.12 + k * 0.12, -0.18), 0.012, black)


func _ngon(n: int, r: float, rot: float) -> Array:
	var out := []
	for k in n:
		var a := rot + k * TAU / n
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


## Polygone convexe plan dans le repère du panneau (x : u, y : haut), avec dos gris si `back`
func _sign_poly(ch: Chunk, c: Vector3, u: Vector3, nrm: Vector3, pts: Array, col: Color, back: bool) -> void:
	var w := []
	for q in pts:
		w.append(c + u * q.x + Vector3(0, q.y, 0))
	for k in range(1, w.size() - 1):
		_tri(ch.walls, w[0], w[k], w[k + 1], nrm, col)
		if back:
			_tri(ch.walls, w[0] - nrm * 0.03, w[k] - nrm * 0.03, w[k + 1] - nrm * 0.03, -nrm, Color(Color("9a9da0"), 0.3))


func _sign_stroke(ch: Chunk, c: Vector3, u: Vector3, nrm: Vector3, a: Vector2, b: Vector2, half: float, col: Color) -> void:
	var d := (b - a).normalized()
	var nn := Vector2(-d.y, d.x) * half
	var a2 := a - d * half
	var b2 := b + d * half
	_sign_poly(ch, c, u, nrm, [a2 + nn, b2 + nn, b2 - nn, a2 - nn], col, false)


## « STOP » en lettres bâton sur l'octogone
func _sign_text(ch: Chunk, c: Vector3, u: Vector3, nrm: Vector3, col: Color) -> void:
	var lw := 0.11
	var lh := 0.2
	var letters := [
		[[0, 1, 1, 1], [0, 1, 0, 0.5], [0, 0.5, 1, 0.5], [1, 0.5, 1, 0], [0, 0, 1, 0]],
		[[0, 1, 1, 1], [0.5, 1, 0.5, 0]],
		[[0, 1, 1, 1], [1, 1, 1, 0], [1, 0, 0, 0], [0, 0, 0, 1]],
		[[0, 0, 0, 1], [0, 1, 1, 1], [1, 1, 1, 0.5], [1, 0.5, 0, 0.5]],
	]
	var x0 := -(lw * 4.0 + 0.04 * 3.0) / 2.0
	for li in letters.size():
		var lx := x0 + li * (lw + 0.04)
		for sg in letters[li]:
			var a := Vector2(lx + float(sg[0]) * lw, -lh / 2.0 + float(sg[1]) * lh)
			var b := Vector2(lx + float(sg[2]) * lw, -lh / 2.0 + float(sg[3]) * lh)
			_sign_stroke(ch, c, u, nrm, a, b, 0.016, col)


func _set_owner(n: Node, owner: Node) -> void:
	for ch in n.get_children():
		ch.owner = owner
		_set_owner(ch, owner)


## Matériaux réalistes : textures photo (asphalte, pavés, sable, béton, tôle, enduit) et fenêtres dessinées
## par le shader. Le type de surface est porté par l'alpha de la couleur des sommets.
func _vc_mat(windows: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://world/shaders/city_facade.gdshader" if windows else "res://world/shaders/city_ground.gdshader")
	m.set_shader_parameter("detail_tex", load("res://world/textures/city_albedo.png"))
	m.set_shader_parameter("normal_tex", load("res://world/textures/city_normal.png"))
	return m


func _surface(mesh: ArrayMesh, s: Surf, mat: Material) -> void:
	if s.v.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = s.v
	arr[Mesh.ARRAY_NORMAL] = s.n
	arr[Mesh.ARRAY_COLOR] = s.c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


# --- Données de jeu et mini-carte ------------------------------------------------

func _write_data() -> void:
	var nodes: Array = []
	for p in node_pos:
		nodes.append(snappedf(p.x, 0.1))
		nodes.append(snappedf(p.y, 0.1))
	var ed: Array = []
	for e in edges:
		ed.append_array([e[0], e[1], e[2], e[3], e[4]])
	var d_out: Array = []
	for d in districts:
		d_out.append([d[0], snappedf(d[1].x, 0.1), snappedf(d[1].y, 0.1)])
	var data := {
		"attribution": "© les contributeurs d'OpenStreetMap (ODbL)",
		"bounds": [min_x, min_z, max_x, max_z],
		"map_res": MAP_RES,
		"nodes": nodes,
		"edges": ed,
		"names": street_names,
		"districts": d_out,
		"places": places,
		"parking": parking,
		"signals": signal_nodes,
		"heights": _heights_out(),
		"services": services,
		"rules": _rules_out(),
		"stalls": stalls,
		"zebras": _zebras_out(),
	}
	var f := FileAccess.open(OUT_DIR + "/data.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("data.json : %d lieux, %d véhicules garés" % [places.size(), parking.size()])


func _rules_out() -> Array:
	var out: Array = []
	for k in rules:
		out.append_array([k.x, k.y, rules[k]])
	return out


func _zebras_out() -> Array:
	var out: Array = []
	for k in zebra_arms:
		out.append_array([k.x, k.y])
	return out


func _heights_out() -> Array:
	var out: Array = []
	for n in node_h:
		if node_h[n] > 0.01:
			out.append(n)
			out.append(snappedf(node_h[n], 0.01))
	return out


func _write_minimap() -> void:
	var palette := [Color("cdb68a"), Color("4a4a4c"), Color("a8957a"), Color("8fb36a"), Color("2a6f97")]
	var bytes := PackedByteArray()
	bytes.resize(gw * gh * 3)
	for i in gw * gh:
		var c: Color = palette[grid[i]]
		bytes[i * 3] = c.r8
		bytes[i * 3 + 1] = c.g8
		bytes[i * 3 + 2] = c.b8
	var img := Image.create_from_data(gw, gh, false, Image.FORMAT_RGB8, bytes)
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "/minimap.png"))
	print("minimap.png : %dx%d" % [gw, gh])


# =====================================================================================
# Ville vivante : quartiers, services, ponts et tunnels, voie ferrée, parkings, arbres
# =====================================================================================

const EXTRA := "res://tools/osm/dakar_rail.json" ## voies ferrées, zones industrielles, parkings
const BRIDGE_H := 6.5
const RAMP := 70.0
const POPULAR := ["Médina", "Gueule Tapée", "Fass Delorme", "Gueule Tapée-Fass-Colobane", "Rebeuss"]
const POPULAR_FACADES := [Color("b8ad9a"), Color("c9b38f"), Color("a9a294"), Color("d1b48c"), Color("9fa8a3"), Color("c7a07a"), Color("bfb6a6")]
const LUXE_FACADES := [Color("f7f4ec"), Color("efe6d2"), Color("f4ede0"), Color("e9e2d6"), Color("fbfaf6")]
## Immeubles de bureaux modernes (bandeaux vitrés) et verre des tours (bleu, vert, bronze, argent)
const MODERN_FACADES := [Color("eceae4"), Color("d8d3c8"), Color("c9ccce"), Color("e6d7bd"), Color("b7c2c9")]
const TOWER_GLASS := [Color("4f7d8c"), Color("3d5a73"), Color("6b5a45"), Color("8a9aa6"), Color("2f6b5e"), Color("5d6f86")]
const INDUS_FACADES := [Color("9aa3ad"), Color("b8b5ad"), Color("7f8c99"), Color("a7a39a")]
const BRANDS := {"shell": ["Shell", Color("f7d117"), Color("dd1d21")], "total": ["Total", Color("ed1c24"), Color("1a4b9c")],
	"oilibya": ["Oilibya", Color("009a44"), Color("f5a800")], "lybia": ["Oilibya", Color("009a44"), Color("f5a800")],
	"star": ["Star Oil", Color("0057a8"), Color("e30613")], "puma": ["Puma Energy", Color("e30613"), Color("1d1d1b")],
	"enoc": ["Enoc", Color("00539b"), Color("e4002b")]}
const RESTO_COLORS := [Color("c1121f"), Color("2a9d8f"), Color("e9c46a"), Color("264653"), Color("f4a261"), Color("6a4c93")]

var amenities: Array = [] ## {type, name, c}
var rails: Array = [] ## PackedVector2Array
var industrial: Array = [] ## polygones
var parking_lots: Array = []
var node_h := {} ## nœud → hauteur (ponts et rampes)
var bridge_edges := {} ## Vector2i(min, max) → true
var tunnel_edges: Array = [] ## [a, b, largeur]
var bridge_col := PackedVector3Array()
var node_deg := {} ## nœud → nombre de tronçons (carrefour si ≠ 2)
var services := {} ## nom du lieu → type (intérieur visitable)
var variety := {} ## compte des variantes de bâtiments (tours, toits en tuiles, villas…)
var removed := {} ## décors retirés parce qu'ils tombaient sur la chaussée
const RULE_STOP := 1
const RULE_YIELD := 2
var rules := {} ## Vector2i(depuis, carrefour) → RULE_STOP / RULE_YIELD pour qui arrive par ce tronçon
var zebra_arms := {} ## Vector2i(branche, carrefour) → true : passage piéton sur cette branche du carrefour
var sign_count := {} ## panneaux posés, par type
var palm_spots: Array = []
var tree_spots: Array = []
var stalls: Array = [] ## étals de rue [x, z, type, face x, face z, hauteur du sol] (data.json : achats au jeu)


func _collect_extra(els: Array) -> void:
	for e in els:
		var tags: Dictionary = e.get("tags", {})
		var am := str(tags.get("amenity", ""))
		var shop := str(tags.get("shop", ""))
		var t := ""
		if am in ["fuel", "bank", "hospital", "clinic", "police", "restaurant", "fast_food"]:
			t = am
		elif shop in ["car_repair", "supermarket", "mall"]:
			t = shop
		if t == "":
			continue
		var c := Vector2.ZERO
		if e["type"] == "node":
			c = proj(e["lat"], e["lon"])
		elif e.has("geometry"):
			c = _centroid(_geom(e["geometry"]))
		elif e.has("bounds"):
			var b: Dictionary = e["bounds"]
			c = proj((b["minlat"] + b["maxlat"]) / 2.0, (b["minlon"] + b["maxlon"]) / 2.0)
		if not _inside(c, 20.0):
			continue
		var nm := _norm(str(tags.get("name", tags.get("brand", ""))))
		amenities.append({"type": t, "name": nm, "c": c})
	if FileAccess.file_exists(EXTRA):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(EXTRA))
		for e in raw["elements"]:
			var tags: Dictionary = e.get("tags", {})
			if not e.has("geometry"):
				continue
			if str(tags.get("railway", "")) in ["rail", "light_rail"]:
				rails.append(_geom(e["geometry"], false))
			elif str(tags.get("landuse", "")) in ["industrial", "port", "railway"]:
				var poly := _geom(e["geometry"])
				if poly.size() >= 3:
					industrial.append(poly)
					var pname := str(tags.get("name", ""))
					if pname.to_lower().contains("conteneur") or pname.begins_with("Mole"):
						port_yards.append({"poly": poly, "name": pname, "dense": pname.to_lower().contains("conteneur")})
			elif str(tags.get("amenity", "")) == "parking" and e["type"] == "way":
				var poly2 := _geom(e["geometry"])
				if poly2.size() >= 3 and _area(poly2) > 150.0 and _inside(_centroid(poly2)):
					parking_lots.append(poly2)
	print("ville vivante : %d services, %d voies ferrées, %d zones industrielles, %d parkings" % [amenities.size(), rails.size(), industrial.size(), parking_lots.size()])


## Type de quartier : affaires (Plateau), populaire (Médina...), luxe (Cap Manuel), industriel (port)
func _zone(c: Vector2) -> String:
	for poly in industrial:
		if Geometry2D.is_point_in_polygon(c, poly):
			return "industriel"
	var d := _district(c)
	if d in POPULAR:
		return "populaire"
	if c.y > proj(14.6615, -17.44).y:
		return "luxe"
	return "affaires"


# --- Ponts et tunnels ------------------------------------------------------------------

func _compute_elevation() -> void:
	var adj := {}
	for e in edges:
		for k in [[e[0], e[1]], [e[1], e[0]]]:
			if not adj.has(k[0]):
				adj[k[0]] = []
			adj[k[0]].append(k[1])
	for k in adj:
		node_deg[k] = adj[k].size()
	var raised := {}
	# 1) Ponts routiers (grands axes seulement : les rampes du port restent au sol)
	for r in roads:
		if not r.get("bridge", false) or not r["hw"] in ["trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link"]:
			continue
		var ids: Array = r["ids"]
		for i in ids.size() - 1:
			if node_index.has(int(ids[i])) and node_index.has(int(ids[i + 1])):
				var a: int = node_index[int(ids[i])]
				var b: int = node_index[int(ids[i + 1])]
				raised[a] = BRIDGE_H
				raised[b] = BRIDGE_H
				bridge_edges[Vector2i(mini(a, b), maxi(a, b))] = true
	# 2) Tunnels : la route qui passe au-dessus devient un pont
	for r in roads:
		if not r.get("tunnel", false):
			continue
		var ids: Array = r["ids"]
		for i in ids.size() - 1:
			if not (node_index.has(int(ids[i])) and node_index.has(int(ids[i + 1]))):
				continue
			var a: int = node_index[int(ids[i])]
			var b: int = node_index[int(ids[i + 1])]
			var w := 7.0
			for e in edges:
				if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
					w = e[2]
			tunnel_edges.append([a, b, w])
			var pa := node_pos[a]
			var pb := node_pos[b]
			var dir := (pb - pa).normalized()
			# Le tunnel couvre un peu plus que le tronçon
			var ta := pa - dir * 12.0
			var tb := pb + dir * 12.0
			for e in edges:
				if e[0] in [a, b] or e[1] in [a, b]:
					continue
				var hit = Geometry2D.segment_intersects_segment(ta, tb, node_pos[e[0]], node_pos[e[1]])
				if hit != null:
					raised[e[0]] = BRIDGE_H
					raised[e[1]] = BRIDGE_H
					bridge_edges[Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))] = true
	for n in raised:
		node_h[n] = raised[n]
	# 3) Rampes : on redescend en suivant la route (directions alignées) sur RAMP mètres
	for start in raised:
		for nb in adj.get(start, []):
			if raised.has(nb):
				continue
			var prev: int = start
			var cur: int = nb
			var dist: float = node_pos[start].distance_to(node_pos[nb])
			var guard := 0
			while dist < RAMP and guard < 60:
				guard += 1
				var t := 1.0 - dist / RAMP
				var h := BRIDGE_H * t * t * (3.0 - 2.0 * t)
				node_h[cur] = maxf(node_h.get(cur, 0.0), h)
				var d0 := (node_pos[cur] - node_pos[prev]).normalized()
				var best := -1
				var best_dot := 0.8
				for nx in adj.get(cur, []):
					if nx == prev or raised.has(nx):
						continue
					var dd: float = d0.dot((node_pos[nx] - node_pos[cur]).normalized())
					if dd > best_dot:
						best_dot = dd
						best = nx
				if best == -1:
					break
				dist += node_pos[cur].distance_to(node_pos[best])
				prev = cur
				cur = best
	print("ponts : %d tronçons, %d nœuds surélevés, %d tronçons en tunnel" % [bridge_edges.size(), node_h.size(), tunnel_edges.size()])


func _h(n: int) -> float:
	return node_h.get(n, 0.0)


## Tablier de pont ou rampe : chaussée inclinée, épaisseur, parapets, piliers, collision
func _bridge_edge(ch: Chunk, a_i: int, b_i: int, w: float, hw: String) -> void:
	var a := node_pos[a_i]
	var b := node_pos[b_i]
	var ha := _h(a_i) + ROAD_Y
	var hb := _h(b_i) + ROAD_Y
	var L := a.distance_to(b)
	if L < 0.05:
		return
	var d := (b - a) / L
	var n := Vector2(-d.y, d.x)
	var half := w / 2.0 + 0.6
	var ext := half * 0.5
	var a2 := a - d * ext
	var b2 := b + d * ext
	var A0 := Vector3(a2.x + n.x * half, ha, a2.y + n.y * half)
	var A1 := Vector3(a2.x - n.x * half, ha, a2.y - n.y * half)
	var B0 := Vector3(b2.x + n.x * half, hb, b2.y + n.y * half)
	var B1 := Vector3(b2.x - n.x * half, hb, b2.y - n.y * half)
	var asphalt := Color("3a3a3ce6") # alpha 0.9 : asphalte (voir city_ground.gdshader)
	var concrete := Color("a9a59cb3")
	_tri(ch.roads, A0, B0, B1, Vector3.UP, asphalt)
	_tri(ch.roads, A0, B1, A1, Vector3.UP, asphalt)
	bridge_col.append_array(PackedVector3Array([A0, B0, B1, A0, B1, A1]))
	# Marquage central
	if hw in DASHED and _h(a_i) > 0.5:
		var m0 := Vector3(a.x, ha + 0.02, a.y)
		var m1 := Vector3(b.x, hb + 0.02, b.y)
		var nn := Vector3(n.x, 0, n.y) * 0.1
		_tri(ch.roads, m0 + nn, m1 + nn, m1 - nn, Vector3.UP, Color("eeeeeef7"))
		_tri(ch.roads, m0 + nn, m1 - nn, m0 - nn, Vector3.UP, Color("eeeeeef7"))
	var high := maxf(ha, hb) > 1.2
	if not high:
		return
	# Aux carrefours, pas de parapet (il couperait l'autre route)
	var junction: bool = node_deg.get(a_i, 2) != 2 or node_deg.get(b_i, 2) != 2
	# Épaisseur du tablier et parapets
	var under := Vector3(0, -0.9, 0)
	for side in ([] if junction else [1, -1]):
		var s0: Vector3 = A0 if side == 1 else A1
		var s1: Vector3 = B0 if side == 1 else B1
		var nrm: Vector3 = Vector3(n.x, 0, n.y) * side
		_tri(ch.roofs, s0 + under, s1 + under, s1, nrm, concrete)
		_tri(ch.roofs, s0 + under, s1, s0, nrm, concrete)
		var up := Vector3(0, 0.95, 0)
		var inset: Vector3 = -Vector3(n.x, 0, n.y) * side * 0.25
		_tri(ch.roofs, s0, s1, s1 + up, nrm, concrete.lightened(0.08))
		_tri(ch.roofs, s0, s1 + up, s0 + up, nrm, concrete.lightened(0.08))
		_tri(ch.roofs, s0 + inset, s1 + inset, s1 + inset + up, -nrm, concrete)
		_tri(ch.roofs, s0 + inset, s1 + inset + up, s0 + inset + up, -nrm, concrete)
		_tri(ch.roofs, s0 + up, s1 + up, s1 + inset + up, Vector3.UP, concrete.lightened(0.15))
		_tri(ch.roofs, s0 + up, s1 + inset + up, s0 + inset + up, Vector3.UP, concrete.lightened(0.15))
		bridge_col.append_array(PackedVector3Array([s0, s1, s1 + up, s0, s1 + up, s0 + up]))
	_tri(ch.roofs, A0 + under, B1 + under, B0 + under, Vector3.DOWN, concrete.darkened(0.25))
	_tri(ch.roofs, A0 + under, A1 + under, B1 + under, Vector3.DOWN, concrete.darkened(0.25))
	# Piliers
	var t := 7.0
	while t < L:
		var p := a + d * t
		var hp := lerpf(ha, hb, t / L)
		if hp > 2.5 and not _in_road(p, half * 0.6 + 0.3, true):
			_obox(ch.roofs, Vector3(p.x, (hp - 0.9) / 2.0, p.y), Vector3(0.5, (hp - 0.9) / 2.0, half * 0.6), Vector3(n.x, 0, n.y), concrete.darkened(0.1))
			ch.col.append_array(_box_faces(Vector3(p.x, (hp - 0.9) / 2.0, p.y), Vector3(0.5, (hp - 0.9) / 2.0, half * 0.6), Vector3(n.x, 0, n.y)))
		t += 16.0


func _box_faces(c: Vector3, he: Vector3, ax: Vector3) -> PackedVector3Array:
	var x := ax.normalized() * he.x
	var y := Vector3(0, he.y, 0)
	var z := ax.normalized().cross(Vector3.UP).normalized() * he.z
	var out := PackedVector3Array()
	for f in [[x, y, z], [-x, y, z], [z, x, y], [-z, x, y]]:
		var fc: Vector3 = c + f[0]
		out.append_array(PackedVector3Array([fc - f[1] - f[2], fc + f[1] - f[2], fc + f[1] + f[2], fc - f[1] - f[2], fc + f[1] + f[2], fc - f[1] + f[2]]))
	return out


## Tunnel : murs, plafond éclairé et portails sous la route qui passe au-dessus
func _build_tunnels(root: Node3D) -> void:
	var labelled := false
	for t in tunnel_edges:
		var a := node_pos[t[0]]
		var b := node_pos[t[1]]
		var w: float = t[2]
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x)
		var a2 := a - dir * 6.0
		var b2 := b + dir * 6.0
		var ch := _chunk_of((a + b) / 2.0)
		var concrete := Color("8f8b82")
		var hgt := BRIDGE_H - 0.95
		for side in [1, -1]:
			var off: Vector2 = n * side * (w / 2.0 + 0.8)
			var p0 := Vector3(a2.x + off.x, 0, a2.y + off.y)
			var p1 := Vector3(b2.x + off.x, 0, b2.y + off.y)
			var nrm: Vector3 = -Vector3(n.x, 0, n.y) * side
			_quad_v(ch.roofs, p0, p1, hgt, nrm, concrete)
			_quad_v(ch.roofs, p0 - nrm * 0.4, p1 - nrm * 0.4, hgt, -nrm, concrete.darkened(0.1))
			ch.col.append_array(PackedVector3Array([p0, p1, p1 + Vector3(0, hgt, 0), p0, p1 + Vector3(0, hgt, 0), p0 + Vector3(0, hgt, 0)]))
			# Bandeau lumineux le long du mur
			var l0 := Vector3(a2.x + off.x * 0.98, hgt - 0.6, a2.y + off.y * 0.98)
			var l1 := Vector3(b2.x + off.x * 0.98, hgt - 0.6, b2.y + off.y * 0.98)
			_tri(ch.roads, l0, l1, l1 + Vector3(0, 0.12, 0), nrm, Color("fff1c4"))
			_tri(ch.roads, l0, l1 + Vector3(0, 0.12, 0), l0 + Vector3(0, 0.12, 0), nrm, Color("fff1c4"))
		var half := w / 2.0 + 1.2
		var c0 := Vector3(a2.x + n.x * half, hgt, a2.y + n.y * half)
		var c1 := Vector3(b2.x + n.x * half, hgt, b2.y + n.y * half)
		var c2 := Vector3(b2.x - n.x * half, hgt, b2.y - n.y * half)
		var c3 := Vector3(a2.x - n.x * half, hgt, a2.y - n.y * half)
		_tri(ch.roofs, c0, c1, c2, Vector3.DOWN, concrete.darkened(0.3))
		_tri(ch.roofs, c0, c2, c3, Vector3.DOWN, concrete.darkened(0.3))
		_tri(ch.roofs, c0 + Vector3(0, 0.2, 0), c1 + Vector3(0, 0.2, 0), c2 + Vector3(0, 0.2, 0), Vector3.UP, Color("7d8a6a"))
		_tri(ch.roofs, c0 + Vector3(0, 0.2, 0), c2 + Vector3(0, 0.2, 0), c3 + Vector3(0, 0.2, 0), Vector3.UP, Color("7d8a6a"))
		if not labelled:
			labelled = true
			var lp := a2 - dir * 0.5
			var lab := Mk.label(root, "Tunnel de Soumbédioune", Vector3(lp.x, hgt + 0.5, lp.y), 70, Color("f1f1f1"))
			lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			lab.rotation.y = atan2(-dir.x, -dir.y) + PI


func _build_bridge_col(root: Node3D) -> void:
	if bridge_col.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "PontsCollision"
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(bridge_col)
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)


# --- Voie ferrée et parkings -----------------------------------------------------------

func _build_rails() -> void:
	var steel := Color("6e6a64")
	var ballast := Color("7d7468")
	var sleeper := Color("5a4636")
	for pts in rails:
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if not _inside(a) or not _inside(b) or a.distance_to(b) < 0.05:
				continue
			var ch := _chunk_of((a + b) / 2.0)
			_ribbon(ch.roads, a, b, 1.6, 0.05, ballast, 0.0)
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x)
			for side in [-0.72, 0.72]:
				_ribbon(ch.roads, a + n * side, b + n * side, 0.05, 0.2, steel, 0.0)
			var t := 0.0
			var L := a.distance_to(b)
			while t < L:
				var p := a + d * t
				_rect(ch.roads, p, n, 1.15, 0.12, 0.1, sleeper)
				t += 1.4


func _build_parking_lots() -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = 404
	for poly in parking_lots:
		var c := _centroid(poly)
		var cell := _cell(c)
		if cell == 2:
			continue # parking couvert ou en étage : déjà un bâtiment
		var ch := _chunk_of(c)
		_fill_flat(ch.roads, poly, ROAD_Y + 0.005, Color("4a4a4ce6"))
		var o := _obb(poly)
		var u: Vector2 = o[1]
		var v := Vector2(-u.y, u.x)
		var nslots := clampi(int(o[2] * 2.0 / 2.6), 0, 14)
		for k in nslots:
			var along: float = -o[2] + 1.3 + k * 2.6
			for row in [-1, 1]:
				if o[3] < 3.0 and row == 1:
					continue
				var sc: Vector2 = c + u * along + v * row * (o[3] - 2.6)
				if not Geometry2D.is_point_in_polygon(sc, poly):
					continue
				# Lignes blanches de stationnement
				_rect(ch.roads, sc + u * 1.3, v, 2.4, 0.06, ROAD_Y + 0.02, Color("eeeeeef7"))
				if prng.randf() < 0.45 and parking.size() < 110:
					var yaw := atan2(-v.x, -v.y) * float(row)
					parking.append({"type": ["clando", "taxi", "clando"][prng.randi() % 3], "pos": [sc.x, sc.y], "yaw": yaw})


# --- Services : stations-service, banques, hôpitaux, commissariats, restaurants, garages ---

func _service_name(a: Dictionary, used: Dictionary) -> String:
	var nm: String = a["name"]
	var low := nm.to_lower()
	var t: String = a["type"]
	var base := ""
	match t:
		"fuel":
			base = "Station-service"
			for k in BRANDS:
				if k in low:
					base = "Station " + BRANDS[k][0]
		"bank":
			base = "Banque " + nm.replace(" Dakar Siège", "") if nm != "" else "Banque"
		"hospital":
			base = nm if nm != "" else "Hôpital"
		"clinic":
			base = nm if nm != "" else "Clinique"
		"police":
			base = "Commissariat"
		"restaurant", "fast_food":
			base = nm if (low.begins_with("restaurant") or low.begins_with("chez")) else "Restaurant " + nm
		"car_repair":
			base = "Garage " + nm if nm != "" else "Garage"
		_:
			base = nm
	var out := base
	if used.has(out) or places.has(out):
		out = "%s (%s)" % [base, _district(a["c"])]
	var k2 := 2
	while used.has(out) or places.has(out):
		out = "%s %d" % [base, k2]
		k2 += 1
	return out


func _compute_service_places() -> void:
	var used := {}
	var keep: Array = []
	for a in amenities:
		var t: String = a["type"]
		# Pas de doublon avec les lieux déjà présents (Hôpital Principal, Commissariat de Rebeuss)
		if t in ["hospital", "police"]:
			var dup := false
			for k in ["Hôpital Principal", "Commissariat"]:
				if places.has(k) and _poi_c(k).distance_to(a["c"]) < 120.0:
					dup = true
			if dup:
				continue
		if t in ["restaurant", "fast_food"] and a["name"] == "":
			continue
		var nm := _service_name(a, used)
		used[nm] = true
		a["place"] = nm
		places[nm] = _with_center(_curb(a["c"]), a["c"])
		keep.append(a)
	amenities = keep
	# Garages de quartier (mécaniciens de rue) dans les quartiers populaires
	var prng := RandomNumberGenerator.new()
	prng.seed = 77
	var made := 0
	for i in buildings.size():
		if made >= 4:
			break
		var b: Dictionary = buildings[(i * 37) % buildings.size()]
		var c := _centroid(b["poly"])
		if _zone(c) != "populaire" or prng.randf() > 0.08:
			continue
		var nm := "Garage mécanique (%s)" % _district(c)
		if places.has(nm):
			continue
		places[nm] = _with_center(_curb(c), c)
		amenities.append({"type": "car_repair", "name": "", "c": c, "place": nm})
		made += 1
	var kinds := {"fuel": "station", "bank": "banque", "hospital": "hopital", "clinic": "hopital", "police": "police",
		"restaurant": "restaurant", "fast_food": "restaurant", "car_repair": "garage", "supermarket": "boutique", "mall": "boutique"}
	for a in amenities:
		services[a["place"]] = kinds[a["type"]]
	services["Hôpital Principal"] = "hopital"
	services["Commissariat"] = "police"
	print("services : %d lieux (stations, banques, hôpitaux, restaurants, garages...)" % services.size())


func _build_amenities(root: Node3D) -> void:
	for a in amenities:
		var p: Array = places[a["place"]]
		var curb := Vector2(p[0], p[1])
		var n := Vector2(p[3], p[4])
		var f := Vector2(p[7], p[8])
		var ch := _chunk_of(curb)
		var yaw := atan2(n.x, n.y)
		match a["type"]:
			"fuel":
				_build_station(root, ch, curb, n, f, a)
			"bank":
				_sign(root, curb, n, "BANQUE\n" + str(a["place"]).replace("Banque ", ""), Color("1d3557"), Color.WHITE)
				# Distributeur automatique (GAB) contre la façade
				var g := curb + n * 2.4
				_obox(ch.roofs, Vector3(g.x, 0.95, g.y), Vector3(0.45, 0.95, 0.3), Vector3(f.x, 0, f.y), Color("2b2d42"))
				_obox(ch.roofs, Vector3(g.x - n.x * 0.31, 1.25, g.y - n.y * 0.31), Vector3(0.3, 0.2, 0.01), Vector3(f.x, 0, f.y), Color("4cc9f0"))
			"hospital", "clinic":
				_sign(root, curb, n, "+ " + str(a["place"]), Color("f8f9fa"), Color("d62828"))
			"police":
				_sign(root, curb, n, "POLICE", Color("1e3a8a"), Color.WHITE)
				parking.append({"type": "police", "pos": [p[5], p[6]], "yaw": p[2]})
			"restaurant", "fast_food":
				_build_resto(root, ch, curb, n, f, a)
			"car_repair":
				_sign(root, curb, n, "GARAGE\nMÉCANIQUE", Color("ffb703"), Color("1d1d1d"))
				for k in 3:
					var tp := curb + n * 1.6 + f * (1.5 + k * 0.7)
					for s in 3:
						Mk.cyl(root, 0.32, 0.32, 0.22, Vector3(tp.x, 0.27 + s * 0.23, tp.y), Color("1b1b1b"), false, 10)
			"supermarket", "mall":
				_sign(root, curb, n, str(a["place"]), Color("e63946"), Color.WHITE)


## Panneau sur poteau au bord du trottoir
func _sign(root: Node3D, curb: Vector2, n: Vector2, text: String, bg: Color, fg: Color) -> void:
	var pos := curb - n * 0.6
	Mk.cyl(root, 0.05, 0.05, 3.2, Vector3(pos.x, 1.6 + SIDEWALK_Y, pos.y), Color("6c757d"), true, 6)
	var board := Mk.box(root, Vector3(1.9, 0.8, 0.08), Vector3(pos.x, 3.3 + SIDEWALK_Y, pos.y), bg)
	board.rotation.y = atan2(n.x, n.y)
	for side in [1.0, -1.0]:
		var lab := Mk.label(root, text, Vector3(pos.x, 3.3 + SIDEWALK_Y, pos.y) + Vector3(n.x, 0, n.y) * 0.05 * side, 40, fg)
		lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lab.outline_size = 0
		lab.rotation.y = atan2(n.x, n.y) + (0.0 if side < 0 else PI)


func _build_station(root: Node3D, ch: Chunk, curb: Vector2, n: Vector2, f: Vector2, a: Dictionary) -> void:
	var low := str(a["name"]).to_lower()
	var brand := ["Station", Color("2a9d8f"), Color("e9c46a")]
	for k in BRANDS:
		if k in low:
			brand = BRANDS[k]
	var c := curb + n * 5.5
	var cell := _cell(c)
	var big := cell != 2
	var hl := 5.5 if big else 2.5
	var hw := 3.5 if big else 1.6
	var y := 4.8
	# Auvent sur piliers, bandeau aux couleurs de la marque
	_obox(ch.roofs, Vector3(c.x, y, c.y), Vector3(hl, 0.25, hw), Vector3(f.x, 0, f.y), Color("f1f1f1"))
	_obox(ch.roofs, Vector3(c.x, y - 0.05, c.y), Vector3(hl + 0.05, 0.18, hw + 0.05), Vector3(f.x, 0, f.y), brand[1])
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var pp: Vector2 = c + f * sx * (hl - 0.6) + Vector2(-f.y, f.x) * sz * (hw - 0.6)
			_obox(ch.roofs, Vector3(pp.x, y / 2.0, pp.y), Vector3(0.18, y / 2.0, 0.18), Vector3(f.x, 0, f.y), Color("dcdcdc"))
			ch.col.append_array(_box_faces(Vector3(pp.x, y / 2.0, pp.y), Vector3(0.18, y / 2.0, 0.18), Vector3(f.x, 0, f.y)))
	# Îlots de pompes
	for k in ([-1, 1] if big else [0]):
		var ip: Vector2 = c + f * k * 2.6
		_obox(ch.roofs, Vector3(ip.x, 0.15, ip.y), Vector3(1.2, 0.15, 0.5), Vector3(f.x, 0, f.y), Color("bdbdbd"))
		for s in [-0.6, 0.6]:
			var pp2: Vector2 = ip + f * s
			_obox(ch.roofs, Vector3(pp2.x, 1.0, pp2.y), Vector3(0.28, 0.7, 0.22), Vector3(f.x, 0, f.y), brand[1])
			_obox(ch.roofs, Vector3(pp2.x, 1.35, pp2.y), Vector3(0.22, 0.18, 0.23), Vector3(f.x, 0, f.y), Color("222222"))
	_fill_flat(ch.roads, PackedVector2Array([c + f * hl + Vector2(-f.y, f.x) * hw, c - f * hl + Vector2(-f.y, f.x) * hw,
		c - f * hl - Vector2(-f.y, f.x) * hw, c + f * hl - Vector2(-f.y, f.x) * hw]), SIDEWALK_Y + 0.01, Color("9a9a9a"))
	for side in [1.0, -1.0]:
		var lab := Mk.label(root, brand[0], Vector3(c.x, y, c.y) + Vector3(-f.y, 0, f.x) * (hw + 0.07) * side, 90, brand[2])
		lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lab.rotation.y = atan2(-f.y, f.x) + (0.0 if side > 0 else PI)
	# Totem avec le prix du litre
	var tt := curb - n * 0.4 + f * (hl + 1.5)
	if _in_road(tt, 0.6, true):
		tt = curb + n * 1.2 + f * (hl + 1.5)
	Mk.box(root, Vector3(0.9, 4.0, 0.3), Vector3(tt.x, 2.0, tt.y), brand[1], true).rotation.y = atan2(n.x, n.y)
	var price := Mk.label(root, "%s\nSuper 990\nGasoil 755" % brand[0], Vector3(tt.x, 3.0, tt.y), 36, Color.WHITE)
	price.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _build_resto(root: Node3D, ch: Chunk, curb: Vector2, n: Vector2, f: Vector2, a: Dictionary) -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = hash(a["place"])
	var col: Color = RESTO_COLORS[prng.randi() % RESTO_COLORS.size()]
	var front := curb + n * 1.75
	# Auvent coloré au-dessus de la porte
	_obox(ch.roofs, Vector3(front.x, 2.7, front.y), Vector3(1.8, 0.06, 0.6), Vector3(f.x, 0, f.y), col)
	_obox(ch.roofs, Vector3(front.x - n.x * 0.6, 2.55, front.y - n.y * 0.6), Vector3(1.8, 0.2, 0.02), Vector3(f.x, 0, f.y), col.darkened(0.2))
	var lab := Mk.label(root, str(a["place"]).replace("Restaurant ", ""), Vector3(front.x, 3.05, front.y) - Vector3(n.x, 0, n.y) * 0.62, 34, Color.WHITE)
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lab.rotation.y = atan2(-n.x, -n.y) + PI
	# Petite table et chaises sur le trottoir
	var tp := curb + f * 2.2
	_obox(ch.roofs, Vector3(tp.x, SIDEWALK_Y + 0.72, tp.y), Vector3(0.4, 0.03, 0.4), Vector3(f.x, 0, f.y), Color("f1f1f1"))
	_obox(ch.roofs, Vector3(tp.x, SIDEWALK_Y + 0.36, tp.y), Vector3(0.04, 0.36, 0.04), Vector3(f.x, 0, f.y), Color("9a9a9a"))
	for s in [-1, 1]:
		var cp: Vector2 = tp + f * s * 0.7
		_obox(ch.roofs, Vector3(cp.x, SIDEWALK_Y + 0.42, cp.y), Vector3(0.2, 0.03, 0.2), Vector3(f.x, 0, f.y), col)
		_obox(ch.roofs, Vector3(cp.x, SIDEWALK_Y + 0.21, cp.y), Vector3(0.03, 0.21, 0.03), Vector3(f.x, 0, f.y), Color("9a9a9a"))


# --- Arbres et palmiers (fusionnés dans les blocs : très peu coûteux) ------------------

func _collect_trees() -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = 909
	# Arbres d'alignement sur les grands boulevards
	for e in edges:
		if not e[5] in ["primary", "secondary", "trunk"] or _h(e[0]) > 0.1 or _h(e[1]) > 0.1:
			continue
		var a := node_pos[e[0]]
		var b := node_pos[e[1]]
		var L := a.distance_to(b)
		if L < 12.0:
			continue
		var d := (b - a) / L
		var nn := Vector2(-d.y, d.x)
		var t := 6.0
		while t < L - 4.0:
			for side in [-1, 1]:
				var p: Vector2 = a + d * t + nn * side * (e[2] / 2.0 + SIDEWALK_W - 0.35)
				var cell := _cell(p)
				if cell == 2:
					continue
				var z := _zone(p)
				if z == "luxe" or _near_coast(p):
					palm_spots.append(p)
				else:
					tree_spots.append([p, prng.randi()])
			t += 19.0
	# Palmiers dans les jardins des villas
	for b in buildings:
		var c := _centroid(b["poly"])
		if _zone(c) == "luxe" and prng.randf() < 0.3:
			var nr := _nearest_road(c)
			if nr[0] < 40.0:
				var p: Vector2 = c.lerp(nr[3], 0.55)
				var cell := _cell(p)
				if cell != 2 and cell != 1:
					palm_spots.append(p)
	print("végétation : %d arbres, %d palmiers" % [tree_spots.size(), palm_spots.size()])


func _near_coast(p: Vector2) -> bool:
	for dx in [-60, 0, 60]:
		for dz in [-60, 0, 60]:
			var cell := _cell(p + Vector2(dx, dz))
			if cell == 4:
				return true
	return false


func _build_trees() -> void:
	var greens := [Color("4f7d3a"), Color("5b8c3e"), Color("3e6b2f"), Color("6a994e"), Color("55803c")]
	var trunk := Color("6b4f3a")
	for e in tree_spots:
		var p: Vector2 = e[0]
		if _in_road(p, 0.4, true):
			removed["arbres"] = int(removed.get("arbres", 0)) + 1
			continue
		var r := RandomNumberGenerator.new()
		r.seed = e[1]
		var ch := _chunk_of(p)
		var h := r.randf_range(2.6, 3.8)
		_obox(ch.roofs, Vector3(p.x, h / 2.0, p.y), Vector3(0.14, h / 2.0, 0.14), Vector3.RIGHT, trunk)
		ch.col.append_array(_box_faces(Vector3(p.x, h / 2.0, p.y), Vector3(0.14, h / 2.0, 0.14), Vector3.RIGHT))
		# Houppier fait de quelques volumes (octaèdres) de verts différents
		for k in 4:
			var off := Vector3(r.randf_range(-1.0, 1.0), r.randf_range(0.0, 1.2), r.randf_range(-1.0, 1.0))
			var s := r.randf_range(1.3, 2.0)
			_blob(ch.roofs, Vector3(p.x, h + 0.8, p.y) + off, Vector3(s, s * 0.7, s), greens[r.randi() % greens.size()])
	for p in palm_spots:
		if _in_road(p, 0.4, true):
			removed["palmiers"] = int(removed.get("palmiers", 0)) + 1
			continue
		var ch := _chunk_of(p)
		var r := RandomNumberGenerator.new()
		r.seed = int(p.x * 13.0 + p.y * 7.0)
		var h := r.randf_range(6.0, 9.0)
		var lean := Vector3(r.randf_range(-0.4, 0.4), 0, r.randf_range(-0.4, 0.4))
		for k in 5:
			var t0 := k / 5.0
			var t1 := (k + 1) / 5.0
			var c0 := Vector3(p.x, t0 * h, p.y) + lean * t0 * t0
			var c1 := Vector3(p.x, t1 * h, p.y) + lean * t1 * t1
			_obox(ch.roofs, (c0 + c1) / 2.0, Vector3(0.16 - t0 * 0.04, h / 10.0, 0.16 - t0 * 0.04), Vector3.RIGHT, Color("8a6e4b").darkened(0.1 * (k % 2)))
		ch.col.append_array(_box_faces(Vector3(p.x, h / 2.0, p.y), Vector3(0.15, h / 2.0, 0.15), Vector3.RIGHT))
		var top := Vector3(p.x, h, p.y) + lean
		for k in 8:
			var ang := k * TAU / 8.0 + r.randf() * 0.3
			var dir := Vector3(cos(ang), 0, sin(ang))
			var tip := top + dir * 2.8 + Vector3(0, -1.1, 0)
			var mid := top + dir * 1.5 + Vector3(0, 0.25, 0)
			var side := dir.cross(Vector3.UP) * 0.35
			var g: Color = Color("3f8f3a") if k % 2 == 0 else Color("4c9a44")
			_tri(ch.roofs, top, mid + side, mid - side, Vector3.UP, g)
			_tri(ch.roofs, mid + side, tip, mid - side, Vector3.UP, g)
			_tri(ch.roofs, top, mid - side, mid + side, Vector3.DOWN, g.darkened(0.2))
			_tri(ch.roofs, mid + side, mid - side, tip, Vector3.DOWN, g.darkened(0.2))


## Volume de feuillage arrondi : sphère grossière (anneaux de 7 côtés), sommets légèrement bosselés
func _blob(s: Surf, c: Vector3, he: Vector3, col: Color) -> void:
	var seg := 7
	var rings := [[-0.55, 0.55], [0.0, 1.0], [0.55, 0.8], [0.95, 0.0]]
	var pts: Array = []
	for r in rings:
		var ring: Array = []
		for k in seg:
			var ang: float = k * TAU / seg + float(r[0]) * 0.7
			var wob: float = 1.0 + 0.12 * sin(ang * 3.0 + c.x)
			ring.append(c + Vector3(cos(ang) * he.x * r[1] * wob, r[0] * he.y, sin(ang) * he.z * r[1] * wob))
		pts.append(ring)
	var bottom := c + Vector3(0, -0.75 * he.y, 0)
	for k in seg:
		var k2 := (k + 1) % seg
		_tri(s, bottom, pts[0][k2], pts[0][k], Vector3.DOWN, col.darkened(0.25))
		for r in 3:
			var a0: Vector3 = pts[r][k]
			var a1: Vector3 = pts[r][k2]
			var b0: Vector3 = pts[r + 1][k]
			var b1: Vector3 = pts[r + 1][k2]
			var nrm := ((a0 + a1 + b0 + b1) / 4.0 - c).normalized()
			var shade := col.darkened(0.12 * (2 - r)) if r < 2 else col.lightened(0.08)
			_tri(s, a0, a1, b1, nrm, shade)
			_tri(s, a0, b1, b0, nrm, shade)


# --- Football : terrains réalistes et stade ---------------------------------------------

const PITCH_WHITE := Color("f5f5f5")


## Arc de cercle blanc (centre c, rayon r) autour de la direction `mid`, sur ±half radians
func _arc(s: Surf, c: Vector2, r: float, mid: Vector2, half: float, y: float, t: float) -> void:
	var a0 := mid.angle() - half
	var seg := maxi(4, int(half * 12.0))
	for k in seg:
		var p0 := c + Vector2.from_angle(a0 + 2.0 * half * k / seg) * r
		var p1 := c + Vector2.from_angle(a0 + 2.0 * half * (k + 1) / seg) * r
		_ribbon(s, p0, p1, t, y, PITCH_WHITE, 0.0)


## Terrain de football : pelouse rayée par la tonte, marquage aux proportions officielles
## (surfaces de réparation et de but, points de penalty, arcs, coins), buts avec filets, drapeaux de coin.
## L, W : demi-longueur et demi-largeur du terrain (lignes de but et de touche).
func _soccer_pitch(root: Node3D, ch: Chunk, c: Vector2, u: Vector2, L: float, W: float, y: float) -> void:
	var v := Vector2(-u.y, u.x)
	var k := clampf(W / 34.0, 0.45, 1.0) # terrains de quartier : marquage réduit en proportion
	var bands := 12 if L > 30.0 else 8
	var band_hl := (2.0 * L + 6.0) / bands / 2.0
	for b in bands:
		var bc := c + u * (-L - 3.0 + band_hl * (2 * b + 1))
		_rect(ch.roads, bc, u, band_hl, W + 3.0, y - 0.006, Color("3f8f3a") if b % 2 == 0 else Color("4fa046"))
	var t := 0.06
	_rect_lines(ch.roads, c, u, L, W, y, t)
	_rect(ch.roads, c, v, W, t, y, PITCH_WHITE)
	_ring(ch.roads, c, 9.15 * k, y, t)
	_rect(ch.roads, c, u, 0.14, 0.14, y, PITCH_WHITE)
	var c3 := Vector3(c.x, 0, c.y)
	var u3 := Vector3(u.x, 0, u.y)
	var v3 := Vector3(v.x, 0, v.y)
	for side in [-1, 1]:
		var gl: Vector2 = c + u * side * L
		var inward: Vector2 = -u * side
		var pa_d := 16.5 * k
		var pa_w := minf(20.16 * k, W * 0.75)
		_rect_lines(ch.roads, gl + inward * pa_d / 2.0, u, pa_d / 2.0, pa_w, y, t)
		var ga_d := 5.5 * k
		var ga_w := minf(9.16 * k, W * 0.35)
		_rect_lines(ch.roads, gl + inward * ga_d / 2.0, u, ga_d / 2.0, ga_w, y, t)
		var spot: Vector2 = gl + inward * 11.0 * k
		_rect(ch.roads, spot, u, 0.13, 0.13, y, PITCH_WHITE)
		# Arc de la surface : la partie du cercle de 9,15 m qui dépasse de la surface
		_arc(ch.roads, spot, 9.15 * k, inward, acos(clampf((pa_d - 11.0 * k) / (9.15 * k), -1.0, 1.0)), y, t)
		for s2 in [-1, 1]:
			var corner: Vector2 = gl + v * s2 * W
			_arc(ch.roads, corner, 1.0 * maxf(k, 0.6), (inward - v * s2).normalized(), PI / 4.0, y, t)
			var cf := Vector3(corner.x, 0, corner.y)
			Mk.cyl(root, 0.025, 0.025, 1.5, cf + Vector3(0, 0.75, 0), Color("e8e8e8"), false, 4)
			var flag := Mk.box(root, Vector3(0.02, 0.32, 0.42), cf + Vector3(0, 1.32, 0) + v3 * s2 * 0.0 - u3 * side * 0.22, Color("ffd60a"))
			flag.rotation.y = atan2(-u.x, -u.y)
		_goal(root, c3 + u3 * side * L, u3 * side, minf(3.66, W * 0.22))


## But : poteaux et barre (2,44 m), cadre arrière et filets blancs semi-transparents.
## o : direction vers l'extérieur du terrain ; hw : demi-largeur (3,66 m en règlementaire).
func _goal(root: Node3D, center: Vector3, o: Vector3, hw: float) -> void:
	var h := Node3D.new()
	root.add_child(h)
	h.position = center + Vector3(0, 0.09, 0)
	h.rotation.y = atan2(-o.x, -o.z) # -Z local = vers l'extérieur
	var white := Color.WHITE
	var depth := 2.0
	for s in [-1, 1]:
		Mk.box(h, Vector3(0.12, 2.44, 0.12), Vector3(s * hw, 1.22, 0), white, true)
		Mk.box(h, Vector3(0.06, 0.06, depth), Vector3(s * hw, 2.42, -depth / 2.0), white)
		Mk.box(h, Vector3(0.06, 2.44, 0.06), Vector3(s * hw, 1.22, -depth), white)
		var side_net := Mk.box(h, Vector3(0.02, 2.4, depth), Vector3(s * hw, 1.2, -depth / 2.0), Color(1, 1, 1, 0.28))
		side_net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Mk.box(h, Vector3(hw * 2.0 + 0.12, 0.12, 0.12), Vector3(0, 2.44, 0), white)
	Mk.box(h, Vector3(hw * 2.0, 0.06, 0.06), Vector3(0, 2.42, -depth), white)
	var back := Mk.box(h, Vector3(hw * 2.0, 2.4, 0.02), Vector3(0, 1.2, -depth), Color(1, 1, 1, 0.28))
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top := Mk.box(h, Vector3(hw * 2.0, 0.02, depth), Vector3(0, 2.43, -depth / 2.0), Color(1, 1, 1, 0.28))
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Contour en forme de piste d'athlétisme : deux lignes droites (±S le long de u) et deux virages de rayon R.
func _track_shape(c: Vector2, u: Vector2, S: float, R: float) -> PackedVector2Array:
	var v := Vector2(-u.y, u.x)
	var pts := PackedVector2Array()
	var seg := 20
	for k in seg + 1:
		var a := -PI / 2.0 + PI * k / seg
		pts.append(c + u * S + (u * cos(a) + v * sin(a)) * R)
	for k in seg + 1:
		var a := PI / 2.0 + PI * k / seg
		pts.append(c - u * S + (u * cos(a) + v * sin(a)) * R)
	return pts


func _outline(s: Surf, pts: PackedVector2Array, y: float, t: float, col: Color) -> void:
	for k in pts.size():
		_ribbon(s, pts[k], pts[(k + 1) % pts.size()], t, y, col, 0.0)


## Stade (Iba Mar Diop…) : piste d'athlétisme rouge à 6 couloirs, terrain réglementaire, gradins en béton
## aux sièges vert-jaune-rouge, tribune couverte, pylônes d'éclairage, mur d'enceinte avec entrées,
## bancs de touche et tableau d'affichage.
## Arène de lutte (distincte du stade de football) : rayon de l'enceinte, centre du cercle de sable
const ARENA_R := 19.5
const ARENA_SAND := 9.0
const ARENA_TIERS := 8


## Cherche, près de la Médina, un endroit sans rue, sans mer, sans terrain ni lieu du jeu, avec le moins
## de bâtiments possible : l'arène y remplace les maisons. Renvoie {c, door} (door : vers la rue la plus proche).
func _pick_arena_site() -> Dictionary:
	var ref := Vector2(-560, -760)
	if places.has("Polyclinique de la Médina"):
		ref = Vector2(places["Polyclinique de la Médina"][0], places["Polyclinique de la Médina"][1])
	var best := {}
	var best_score := INF
	var samples: Array = []
	for r in range(0, int(ARENA_R) + 1, 3):
		var n := maxi(1, int(TAU * r / 3.0))
		for k in n:
			samples.append(Vector2.from_angle(k * TAU / n) * r)
	for gx in range(-60, 61):
		for gz in range(-60, 61):
			var cpos := ref + Vector2(gx, gz) * 10.0
			var dist := cpos.distance_to(ref)
			if dist > 600.0:
				continue
			var houses := 0
			var ok := true
			for s in samples:
				var v := _cell(cpos + s)
				if v == 1 or v == 3 or v == 4:
					ok = false
					break
				if v == 2:
					houses += 1
			if not ok:
				continue
			for k in places:
				if Vector2(places[k][0], places[k][1]).distance_to(cpos) < ARENA_R + 8.0:
					ok = false
			if not ok:
				continue
			var score := houses + dist / 25.0
			if score < best_score:
				best_score = score
				best = {"c": cpos}
	if best.is_empty():
		print("arène de lutte : aucun site trouvé")
		return best
	# Porte : vers la cellule de rue la plus proche
	var c0: Vector2 = best["c"]
	var door := Vector2.RIGHT
	var found := false
	for r in range(int(ARENA_R), 90, 2):
		for k in 48:
			var d := Vector2.from_angle(k * TAU / 48.0)
			if _cell(c0 + d * r) == 1:
				door = d
				best["road_d"] = float(r)
				found = true
				break
		if found:
			break
	best["door"] = door
	print("arène de lutte : site %s, porte vers %s, %.0f bâtiments-échantillons retirés" % [c0, door, best_score - c0.distance_to(Vector2(ref)) / 25.0])
	return best


## Bâtiment à retirer : dans l'enceinte, ou dans l'allée entre la porte et la rue
func _hits_arena(poly: PackedVector2Array, a: Dictionary) -> bool:
	var c0: Vector2 = a["c"]
	var door: Vector2 = a["door"]
	var side := Vector2(-door.y, door.x)
	var reach: float = a.get("road_d", ARENA_R) + 2.0
	for p in poly:
		var d := p - c0
		if d.length() < ARENA_R + 1.5:
			return true
		var along := d.dot(door)
		if along > 0.0 and along < reach and absf(d.dot(side)) < 4.0:
			return true
	return Geometry2D.is_point_in_polygon(c0, poly)


## Arène de lutte : esplanade, cercle de sable, gradins en anneau ouverts sur la porte, mur d'enceinte
## peint avec le nom au-dessus de l'entrée. Repère « CentreArene » pour scripts/world/lutte.gd.
func _build_lutte_arena(root: Node3D, c0: Vector2, door: Vector2) -> void:
	var ch := _chunk_of(c0)
	# Sol de l'enceinte en terre battue, cercle de sable fin (bien rond : 40 côtés)
	_disc_n(ch.roads, c0, ARENA_R + 0.5, ROAD_Y - 0.02, Color("c4a77a99"), 40)
	_disc_n(ch.roads, c0, ARENA_SAND, ROAD_Y + 0.01, Color("e8cf9c99"), 40)
	# Allée de l'entrée jusqu'à la rue
	_ribbon(ch.roads, c0 + door * (ARENA_R - 1.0), c0 + door * (ARENA_R + 14.0), 3.2, ROAD_Y - 0.015, Color("a9a59cb3"), 0.0)
	var body := StaticBody3D.new()
	body.name = "GradinsArene"
	root.add_child(body)
	var seat_cols := [Color("00853f"), Color("fdef42"), Color("e31b23")]
	var segs := 40
	var door_ang := door.angle()
	var r_in := ARENA_SAND + 2.0
	var top := 0.0
	for s in segs:
		var a := (s + 0.5) * TAU / segs
		if absf(angle_difference(a, door_ang)) < 0.36:
			continue # ouverture de l'entrée
		var dir := Vector2.from_angle(a)
		var tang := Vector2(-dir.y, dir.x)
		var tang3 := Vector3(tang.x, 0, tang.y)
		for i in ARENA_TIERS:
			var hgt := 0.45 * (i + 1)
			var r := r_in + i * 0.85 + 0.425
			var half := PI * r / segs + 0.05
			var mid := c0 + dir * r
			_obox(ch.roofs, Vector3(mid.x, hgt / 2.0, mid.y), Vector3(half, hgt / 2.0, 0.425), tang3, Color("b8b2a6b3"))
			var seat := c0 + dir * (r - 0.15)
			_obox(ch.roofs, Vector3(seat.x, hgt + 0.1, seat.y), Vector3(half - 0.05, 0.1, 0.18), tang3, seat_cols[(s / 4) % 3])
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(half * 2.0, hgt, 0.85)
			cs.shape = bs
			cs.position = Vector3(mid.x, hgt / 2.0, mid.y)
			cs.rotation.y = atan2(-tang.y, tang.x)
			body.add_child(cs)
			top = hgt
		# Mur d'enceinte, enduit ocre
		var wr := r_in + ARENA_TIERS * 0.85 + 0.2
		var wm := c0 + dir * wr
		var wh := top + 1.6
		var whalf := PI * wr / segs + 0.08
		_obox(ch.walls, Vector3(wm.x, wh / 2.0, wm.y), Vector3(whalf, wh / 2.0, 0.2), tang3, Color("c98b5a80"))
		var wcs := CollisionShape3D.new()
		var wbs := BoxShape3D.new()
		wbs.size = Vector3(whalf * 2.0, wh, 0.4)
		wcs.shape = wbs
		wcs.position = Vector3(wm.x, wh / 2.0, wm.y)
		wcs.rotation.y = atan2(-tang.y, tang.x)
		body.add_child(wcs)
	# Portail : deux piliers et un fronton avec le nom de l'arène
	var wr2 := r_in + ARENA_TIERS * 0.85 + 0.2
	var side := Vector2(-door.y, door.x)
	var gate := c0 + door * (wr2 + 0.4)
	for sd in [-1.0, 1.0]:
		var pc: Vector2 = gate + side * sd * 3.6
		_obox(ch.walls, Vector3(pc.x, (top + 3.0) / 2.0, pc.y), Vector3(0.45, (top + 3.0) / 2.0, 0.45), Vector3(side.x, 0, side.y), Color("8c5a3c80"))
	_obox(ch.walls, Vector3(gate.x, top + 2.4, gate.y), Vector3(4.1, 0.75, 0.35), Vector3(side.x, 0, side.y), Color("8c5a3c80"))
	var lab := Label3D.new()
	lab.text = "ARÈNE DE LA MÉDINA"
	lab.font_size = 64
	lab.pixel_size = 0.0075
	lab.outline_size = 10
	lab.modulate = Color("ffe8a3")
	lab.double_sided = false
	var lp := gate + door * 0.4
	lab.position = Vector3(lp.x, top + 2.4, lp.y)
	lab.rotation.y = atan2(door.x, door.y)
	root.add_child(lab)
	var centre := Marker3D.new()
	centre.name = "CentreArene"
	centre.position = Vector3(c0.x, ROAD_Y, c0.y)
	centre.set_meta("door", door)
	centre.set_meta("seat_r", r_in + 0.4)
	root.add_child(centre)


func _build_stadium(root: Node3D, p: Dictionary, y: float) -> void:
	var poly: PackedVector2Array = p["poly"]
	var o: Array = p.get("pitch_obb", _obb(poly))
	var c: Vector2 = o[0]
	var u: Vector2 = o[1]
	var v := Vector2(-u.y, u.x)
	# Place disponible autour du terrain réel, mesurée dans l'enceinte selon ses axes
	var hl := INF
	var hw := INF
	for k in 72:
		var dir := Vector2.from_angle(k * TAU / 72.0)
		var far := 0.0
		for i in poly.size():
			var hit = Geometry2D.segment_intersects_segment(c, c + dir * 1000.0, poly[i], poly[(i + 1) % poly.size()])
			if hit != null:
				far = maxf(far, c.distance_to(hit))
		if far <= 0.0:
			continue
		hl = minf(hl, far / maxf(absf(dir.dot(u)), 0.001))
		hw = minf(hw, far / maxf(absf(dir.dot(v)), 0.001))
	if hl == INF:
		hl = o[2]
		hw = o[3]
	var ch := _chunk_of(c)
	var u3 := Vector3(u.x, 0, u.y)
	var v3 := Vector3(v.x, 0, v.y)
	var c3 := Vector3(c.x, 0, c.y)
	# Repère du centre du terrain : les journées de lutte (scripts/world/lutte.gd) y posent leur cercle de sable
	var centre := Marker3D.new()
	centre.name = "CentreStade"
	centre.position = Vector3(c.x, y, c.y)
	centre.set_meta("axis", u)
	root.add_child(centre)
	# Piste réglementaire (lignes droites 84,4 m, virages de 36,5 m) mise à l'échelle de l'enceinte
	var k := clampf(minf((hl - 10.0) / 86.0, (hw - 10.0) / 43.8), 0.55, 1.0)
	var S := 42.2 * k
	var R0 := 36.5 * k
	var lanes := 6
	var lane_w := 1.22
	var R1 := R0 + lanes * lane_w
	# Esplanade en béton, piste, pelouse
	_fill_flat(ch.roads, poly, y - 0.03, Color("a9a59cb3"))
	_fill_flat(ch.roads, _track_shape(c, u, S, R1), y - 0.02, Color("b5523b"))
	_fill_flat(ch.roads, _track_shape(c, u, S, R0), y - 0.015, Color("3b8a36"))
	for i in range(1, lanes + 1):
		_outline(ch.roads, _track_shape(c, u, S, R0 + i * lane_w), y - 0.012, 0.03, PITCH_WHITE)
	_outline(ch.roads, _track_shape(c, u, S, R0), y - 0.012, 0.05, PITCH_WHITE)
	_soccer_pitch(root, ch, c, u, 52.5 * k, 34.0 * k, y)
	# Gradins : marches en béton, sièges colorés par sections ; collision une boîte par marche
	var body := StaticBody3D.new()
	body.name = "Gradins"
	root.add_child(body)
	var seat_cols := [Color("00853f"), Color("fdef42"), Color("e31b23")]
	var stand_specs := [] # [centre 2D, axe le long, demi-longueur, normale vers l'extérieur, nb de marches]
	var side_room := hw - R1 - 2.0
	var end_room := hl - S - R1 - 2.0
	var n_side := clampi(int(side_room / 0.85), 0, 16)
	var n_end := clampi(int(end_room / 0.85), 0, 10)
	for sd in [-1, 1]:
		if n_side >= 3:
			stand_specs.append([c + v * sd * (R1 + 1.5), u, S + R1 * 0.55, v * sd, n_side])
		if n_end >= 3:
			stand_specs.append([c + u * sd * (S + R1 + 1.5), v, R1 * 0.8, u * sd, n_end])
	var main_stand_top := 0.0
	for spec in stand_specs:
		var sc: Vector2 = spec[0]
		var along: Vector2 = spec[1]
		var half_len: float = spec[2]
		var out: Vector2 = spec[3]
		var steps: int = spec[4]
		var along3 := Vector3(along.x, 0, along.y)
		for i in steps:
			var hgt := 0.45 * (i + 1)
			var mid: Vector2 = sc + out * (i * 0.85 + 0.425)
			var m3 := Vector3(mid.x, hgt / 2.0, mid.y)
			_obox(ch.roofs, m3, Vector3(half_len, hgt / 2.0, 0.425), along3, Color("b8b2a6b3"))
			# Sièges : trois sections vert, jaune, rouge
			for sec in 3:
				var sec_c: Vector2 = mid + along * (-half_len + half_len * (2 * sec + 1) / 3.0) - out * 0.15
				_obox(ch.roofs, Vector3(sec_c.x, hgt + 0.12, sec_c.y), Vector3(half_len / 3.0 - 0.3, 0.12, 0.18), along3, seat_cols[sec])
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(half_len * 2.0, hgt, 0.85)
			cs.shape = bs
			cs.position = m3
			cs.rotation.y = atan2(-along.y, along.x)
			body.add_child(cs)
		# Mur arrière et tribune couverte sur le premier grand côté
		var back: Vector2 = sc + out * (steps * 0.85)
		var top := 0.45 * steps
		_obox(ch.walls, Vector3(back.x, (top + 1.2) / 2.0, back.y), Vector3(half_len, (top + 1.2) / 2.0, 0.15), along3, Color("d8cfb880"))
		if main_stand_top == 0.0 and spec[4] == n_side:
			main_stand_top = top
			var roof_mid: Vector2 = sc + out * (steps * 0.85 * 0.5)
			_obox(ch.roofs, Vector3(roof_mid.x, top + 4.2, roof_mid.y), Vector3(half_len * 0.75, 0.15, steps * 0.85 * 0.55 + 1.0), along3, Color("e9ecef"))
			var ncol := int(half_len * 1.5 / 10.0) + 1
			for q in ncol:
				var cp: Vector2 = back + along * (-half_len * 0.75 + q * half_len * 1.5 / maxf(1, ncol - 1)) - out * 0.3
				_obox(ch.roofs, Vector3(cp.x, (top + 4.2) / 2.0 + 0.6, cp.y), Vector3(0.18, (top + 4.2) / 2.0, 0.18), along3, Color("adb5bd"))
	# Pylônes d'éclairage aux quatre coins
	for su in [-1, 1]:
		for sv in [-1, 1]:
			var fp: Vector3 = c3 + u3 * su * (S + R0 * 0.55) + v3 * sv * (R1 + 2.5 + (n_side * 0.85 + 1.0 if n_side >= 3 else 0.0))
			Mk.cyl(root, 0.35, 0.5, 30.0, fp + Vector3(0, 15.0, 0), Color("8d99ae"), true, 8)
			var head := Mk.box(root, Vector3(4.0, 2.4, 0.4), fp + Vector3(0, 30.5, 0), Color("fffbe6"))
			head.material_override = Mk.mat(Color("fffbe6"), 1.5)
			var to_c := c3 - fp
			head.rotation = Vector3(-0.35, atan2(to_c.x, to_c.z), 0)
	# Mur d'enceinte (3,5 m) avec une entrée au milieu de chaque grand pan
	var n := poly.size()
	var p0 := poly[0]
	var p1 := poly[1]
	var e0 := (p1 - p0).normalized()
	var flip := Geometry2D.is_point_in_polygon((p0 + p1) / 2.0 + Vector2(e0.y, -e0.x) * 0.05, poly)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var L := a.distance_to(b)
		if L < 0.5:
			continue
		var d := (b - a) / L
		var nrm2 := Vector2(d.y, -d.x) * (-1.0 if flip else 1.0)
		var nrm := Vector3(nrm2.x, 0, nrm2.y)
		var pieces := [[0.0, L]]
		if L > 24.0:
			pieces = [[0.0, L / 2.0 - 3.0], [L / 2.0 + 3.0, L]]
		for pc in pieces:
			var A2: Vector2 = a + d * pc[0]
			var B2: Vector2 = a + d * pc[1]
			var A := Vector3(A2.x, 0, A2.y)
			var B := Vector3(B2.x, 0, B2.y)
			_quad_v(ch.walls, A, B, 3.5, nrm, Color("e9e2d080"))
			_quad_v(ch.walls, A - nrm * 0.25, B - nrm * 0.25, 3.5, -nrm, Color("e9e2d080"))
			ch.col.append_array(PackedVector3Array([A, B, B + Vector3(0, 3.5, 0), A, B + Vector3(0, 3.5, 0), A + Vector3(0, 3.5, 0)]))
	# Bancs de touche abrités
	for s3 in [-1, 1]:
		var bpos: Vector3 = c3 + u3 * s3 * 9.0 * k - v3 * (34.0 * k + 4.0)
		var bench := Node3D.new()
		root.add_child(bench)
		bench.position = bpos + Vector3(0, 0.09, 0)
		bench.rotation.y = atan2(-u.x, -u.y)
		Mk.box(bench, Vector3(0.6, 0.45, 5.0), Vector3(0, 0.22, 0), Color("1f3b73"), true)
		Mk.box(bench, Vector3(1.4, 0.08, 5.4), Vector3(0, 2.1, 0), Color(0.75, 0.85, 0.95, 0.5))
		for zz in [-2.6, 2.6]:
			Mk.box(bench, Vector3(0.08, 2.1, 0.08), Vector3(0.6, 1.05, zz), Color("adb5bd"))
	# Tableau d'affichage derrière un but
	var sb: Vector3 = c3 - u3 * (S + R1 + 2.5 + (n_end * 0.85 + 1.0 if n_end >= 3 else 0.0))
	var board := Node3D.new()
	root.add_child(board)
	board.position = sb
	board.rotation.y = atan2(u.x, u.y)
	for sx in [-4.0, 4.0]:
		Mk.box(board, Vector3(0.3, 8.0, 0.3), Vector3(sx, 4.0, 0), Color("495057"), true)
	Mk.box(board, Vector3(11.0, 4.0, 0.4), Vector3(0, 9.5, 0), Color("111111"))
	var nm: String = p["name"] if p["name"] != "" else "STADE"
	Mk.label(board, nm.to_upper(), Vector3(0, 10.6, 0.25), 90, Color("ffd60a"), false)
	Mk.label(board, "SÉNÉGAL  0 - 0  VISITEURS", Vector3(0, 9.1, 0.25), 80, Color.WHITE, false)


# --- Port : parcs à conteneurs ------------------------------------------------------------
# Texture : « Road » par aesre938 (Sketchfab, CC BY 4.0), voir world/port/CREDITS.md.
# Atlas 256 × 512 : une ligne par couleur (rouge, orange, vert, bleu), porte à gauche, flanc ondulé à droite.

const CONT_L := 12.19 ## conteneur 40 pieds (m)
const CONT_W := 2.44
const CONT_H := 2.59
const CONT_ROWS := [[13.0, 124.0], [140.0, 251.0], [266.0, 377.0], [390.0, 501.0]] ## lignes de l'atlas (px)


## dense_only : seulement le terminal à conteneurs (pas de maisons de remplissage dessus)
func _in_port(p: Vector2, dense_only := false) -> bool:
	for y in port_yards:
		if (y["dense"] or not dense_only) and Geometry2D.is_point_in_polygon(p, y["poly"]):
			return true
	return false


## Ajoute un conteneur de couleur k (origine au sol, au centre ; long côté selon X local), sans dessous, placé par t.
## Les conteneurs sont fusionnés en un maillage par parc : un MultiMesh perdrait ses positions dans le bake
## (sans écran, Godot ne garde pas les instances).
func _add_container(k: int, t: Transform3D, verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var r: Array = CONT_ROWS[k]
	var v0: float = (float(r[0]) + 2.0) / 512.0
	var v1: float = (float(r[1]) - 2.0) / 512.0
	var door := Rect2(9.0 / 256.0, v0, (71.0 - 9.0) / 256.0, v1 - v0)
	var side := Rect2(84.0 / 256.0, v0, (245.0 - 84.0) / 256.0, v1 - v0)
	var hx := CONT_L / 2.0
	var hz := CONT_W / 2.0
	var h := CONT_H
	# Face : 4 coins (bas-gauche, bas-droite, haut-droite, haut-gauche vus de dehors), normale, zone d'atlas
	var faces := [
		[Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, h, hz), Vector3(-hx, h, hz), Vector3.BACK, side],
		[Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), Vector3(-hx, h, -hz), Vector3(hx, h, -hz), Vector3.FORWARD, side],
		[Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(hx, h, -hz), Vector3(hx, h, hz), Vector3.RIGHT, door],
		[Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(-hx, h, hz), Vector3(-hx, h, -hz), Vector3.LEFT, door],
		[Vector3(-hx, h, hz), Vector3(hx, h, hz), Vector3(hx, h, -hz), Vector3(-hx, h, -hz), Vector3.UP, side],
	]
	for f in faces:
		var rc: Rect2 = f[5]
		var uv := [Vector2(rc.position.x, rc.end.y), Vector2(rc.end.x, rc.end.y), Vector2(rc.end.x, rc.position.y), Vector2(rc.position.x, rc.position.y)]
		# Godot : faces avant dans le sens horaire vues de dehors
		for idx in [0, 2, 1, 0, 3, 2]:
			verts.append(t * (f[idx] as Vector3))
			norms.append(t.basis * (f[4] as Vector3))
			uvs.append(uv[idx])


## Remplit le terminal à conteneurs (dense) et les môles (plus clairsemés) : blocs de rangées serrées
## séparés par des allées pour les engins, piles de 1 à 4. Sol en béton. Collisions dans les blocs de la ville.
func _build_containers(root: Node3D) -> void:
	if port_yards.is_empty():
		print("port : aucun parc à conteneurs")
		return
	# Le terminal ne garde pas les maisons de remplissage (sauf près d'un lieu du jeu) : elles restent dans
	# la liste (les lieux choisis d'après elle ne bougent pas) mais ne sont pas dessinées, et leur place se libère.
	var hidden := 0
	for b in buildings:
		if b["kind"] != "fill":
			continue
		var bc := _centroid(b["poly"])
		if not _in_port(bc, true):
			continue
		var near := false
		for k in places:
			var pv: Array = places[k]
			if Vector2(pv[0], pv[1]).distance_to(bc) < 40.0:
				near = true
				break
		if near:
			continue
		b["hidden"] = true
		_fill_poly(b["poly"], 0)
		hidden += 1
	print("port : %d maisons de remplissage retirées du terminal" % hidden)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://world/port/containers.jpg")
	mat.roughness = 0.7
	mat.metallic = 0.3
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var prng := RandomNumberGenerator.new()
	prng.seed = 4040
	var total := 0
	for yard in port_yards:
		var poly: PackedVector2Array = yard["poly"]
		var dense: bool = yard["dense"]
		var c0 := _centroid(poly)
		if not _inside(c0, 0.0):
			print("  port : %s hors de la carte" % yard["name"])
			continue
		# Dalle de béton (sous les conteneurs)
		_fill_flat(_chunk_of(c0).roads, poly, ROAD_Y - 0.01, Color("9d9a92b3"))
		var ob := _obb(poly)
		var oc: Vector2 = ob[0]
		var u: Vector2 = ob[1]
		var v := Vector2(-u.y, u.x)
		var hl: float = ob[2]
		var hw: float = ob[3]
		var bay := CONT_L + 0.6 ## pas le long de u
		var row := CONT_W + 0.35 ## pas en travers
		var count := 0
		var ia := 0
		var a := -hl + 4.0
		while a + CONT_L < hl - 4.0:
			var b := -hw + 4.0
			var k := 0
			while b + CONT_W < hw - 4.0:
				var p: Vector2 = oc + u * (a + CONT_L / 2.0) + v * (b + CONT_W / 2.0)
				var ok := prng.randf() < (0.9 if dense else 0.55)
				# Les quatre coins et le centre sur du terrain libre (ni route, ni bâtiment, ni mer) dans le parc
				if ok:
					for q in [p, p + u * CONT_L * 0.5 + v * CONT_W * 0.5, p - u * CONT_L * 0.5 + v * CONT_W * 0.5,
							p + u * CONT_L * 0.5 - v * CONT_W * 0.5, p - u * CONT_L * 0.5 - v * CONT_W * 0.5]:
						if _cell(q) != 0 or not Geometry2D.is_point_in_polygon(q, poly):
							ok = false
							break
				if ok:
					var levels := prng.randi_range(1, 4 if dense else 2)
					var ch := _chunk_of(p)
					var yaw := atan2(-u.y, u.x) + (PI if prng.randf() < 0.5 else 0.0)
					for lv in levels:
						var pp := p + u * prng.randf_range(-0.12, 0.12) + v * prng.randf_range(-0.05, 0.05)
						var t := Transform3D(Basis(Vector3.UP, yaw + prng.randf_range(-0.01, 0.01)), Vector3(pp.x, ROAD_Y + lv * CONT_H, pp.y))
						_add_container(prng.randi() % 4, t, verts, norms, uvs)
						count += 1
					ch.col.append_array(_box_faces(Vector3(p.x, ROAD_Y + levels * CONT_H / 2.0, p.y),
						Vector3(CONT_L / 2.0, levels * CONT_H / 2.0, CONT_W / 2.0), Vector3(u.x, 0, u.y)))
				b += row
				k += 1
				if k % 6 == 0:
					b += 9.0 # allée entre deux blocs de 6 rangées
			a += bay
			ia += 1
			if ia % 3 == 0:
				a += 7.0 # allée transversale
		total += count
		print("  port : %s : %d conteneurs, centre %.0f, %.0f" % [yard["name"], count, c0.x, c0.y])
	if not verts.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.name = "Conteneurs"
		mi.mesh = m
		root.add_child(mi)
	print("port : %d conteneurs (%d triangles)" % [total, total * 10])
