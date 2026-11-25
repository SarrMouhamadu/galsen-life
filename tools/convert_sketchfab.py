"""Convertit les véhicules Sketchfab (CC-BY / licence standard) en .glb légers pour Galsen-Life.

    blender --background --python tools/convert_sketchfab.py -- <dossier _vehicules_sketchfab> <sortie> [nom...]

- Les auteurs et licences sont listés dans vehicles/CREDITS.md (crédit obligatoire).
- Chaque modèle est orienté (avant vers -Z dans Godot), mis à l'échelle, centré et posé au sol.
- Les roues sont regroupées avec leur jante et renommées « Wheel… » pour pouvoir tourner.
- Les maillages trop lourds sont simplifiés et les textures réduites (téléphones).
"""
import math
import os
import re
import sys

import bpy
from mathutils import Matrix, Vector

## sortie → réglages
##   src : fichier dans le dossier source   front : côté avant du modèle importé (Blender, Z en haut)
##   length : longueur en mètres            wh : [largeur, hauteur] imposées (sinon proportions d'origine)
##   wheels : motif des objets roues        drop : motif des objets supprimés (pièces invisibles)
##   ratio : simplification des maillages (1 = aucune)
##   albedo : dossier des textures « <matériau>_albedo.jpg » que le FBX n'a pas reliées
MODELS = {
	"sf_car_rapide": {"src": "car_rapide__iconic_senegal_public_transport/scene.gltf", "front": "-y", "length": 6.2,
		"wh": [2.4, 2.85], "wheels": r"^Pneu", "drop": r"^(Pedales|Levier)", "ratio": 0.45},
	"sf_ndiaga": {"src": "ndiaga_niaye_low_poly/scene.gltf", "front": "-y", "length": 6.0,
		"wheels": r"^(Pneu|pneux)", "ratio": 0.5},
	"sf_coach": {"src": "bus--tata/source/Bus_Tata.fbx", "front": "-y", "length": 12.0, "wh": [2.55, 3.3],
		"wheels": r"^Cylinder", "ratio": 0.6},
	"sf_bmw2002": {"src": "1968_bmw_2002/scene.gltf", "front": "+y", "length": 4.25},
	"sf_caprice": {"src": "2013-chevrolet-caprice-highway-patrol/source/2013 Chevrolet Caprice CHP.glb", "front": "+x",
		"length": 4.9, "wheels": r"^16in", "ratio": 0.7},
	"sf_caprice78": {"src": "ps1_police_car_-_chevrolet_caprice_1978/scene.gltf", "front": "+y", "length": 5.1,
		"wheels": r"^Object_(6|8|10|12)$"},
	"sf_dt125": {"src": "yamaha-dt-125-repainted/source/DT REPAINTED.fbx", "front": "+y", "length": 2.05, "ratio": 0.5,
		"albedo": "yamaha-dt-125-repainted/textures"},
}
MAX_TEX = 512


def mesh_objs():
	return [o for o in bpy.data.objects if o.type == "MESH"]


def world_bbox(objs):
	lo = Vector((1e9, 1e9, 1e9))
	hi = Vector((-1e9, -1e9, -1e9))
	for o in objs:
		for c in o.bound_box:
			w = o.matrix_world @ Vector(c)
			lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
			hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
	return lo, hi


def select(objs, active=None):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = active or objs[0]


def tris(objs):
	return sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)


def group_wheels(pattern):
	"""Regroupe chaque roue avec les pièces contenues dans son volume (jante, écrous) → objets « Wheel_N »."""
	cands = [o for o in mesh_objs() if re.search(pattern, o.name)]
	vol = lambda o: (lambda b: (b[1] - b[0]).x * (b[1] - b[0]).y * (b[1] - b[0]).z)(world_bbox([o]))
	cands.sort(key=vol, reverse=True)
	groups = []
	for o in cands:
		lo, hi = world_bbox([o])
		c = (lo + hi) / 2
		host = None
		for g in groups:
			glo, ghi = world_bbox([g[0]])
			pad = (ghi - glo) * 0.15
			if all(glo[i] - pad[i] <= c[i] <= ghi[i] + pad[i] for i in range(3)):
				host = g
				break
		if host:
			host.append(o)
		else:
			groups.append([o])
	wheels = []
	for k, g in enumerate(groups):
		if len(g) > 1:
			select(g, g[0])
			bpy.ops.object.join()
		g[0].name = "Wheel_%d" % k
		wheels.append(g[0])
	return wheels


def lighten_materials():
	"""Textures : seule la couleur est gardée (pas de normal/AO/rugosité), réduite à MAX_TEX."""
	for m in bpy.data.materials:
		if not m.use_nodes:
			continue
		bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
		if bsdf is None:
			continue
		for name in ["Normal", "Roughness", "Metallic", "Specular IOR Level", "Emission Color"]:
			inp = bsdf.inputs.get(name)
			if inp is not None:
				for l in list(inp.links):
					m.node_tree.links.remove(l)
		bsdf.inputs["Roughness"].default_value = 0.55
		bsdf.inputs["Metallic"].default_value = 0.0
	for img in bpy.data.images:
		if img.size[0] > MAX_TEX or img.size[1] > MAX_TEX:
			f = MAX_TEX / max(img.size[0], img.size[1])
			img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))


def link_albedo(folder):
	"""FBX sans textures reliées : branche « <matériau>_albedo.jpg » sur la couleur de base."""
	files = {f.lower(): os.path.join(folder, f) for f in os.listdir(folder)}
	for m in bpy.data.materials:
		key = m.name.replace(" ", "_").lower() + "_albedo.jpg"
		bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if m.use_nodes else None
		if bsdf is None or key not in files or bsdf.inputs["Base Color"].links:
			continue
		tex = m.node_tree.nodes.new("ShaderNodeTexImage")
		tex.image = bpy.data.images.load(files[key])
		m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])


def convert(name, cfg, src_dir, out_dir):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	path = os.path.join(src_dir, cfg["src"])
	if path.lower().endswith(".fbx"):
		bpy.ops.import_scene.fbx(filepath=path)
	else:
		bpy.ops.import_scene.gltf(filepath=path)
	# Transformations appliquées, hiérarchie aplatie, objets non-maillages retirés
	select(list(bpy.data.objects), mesh_objs()[0])
	bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
	for o in [o for o in bpy.data.objects if o.type != "MESH"]:
		bpy.data.objects.remove(o)
	for o in mesh_objs():
		if o.data.users > 1:
			o.data = o.data.copy()
	select(mesh_objs())
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	if cfg.get("albedo"):
		link_albedo(os.path.join(src_dir, cfg["albedo"]))
	if cfg.get("drop"):
		for o in [o for o in mesh_objs() if re.search(cfg["drop"], o.name)]:
			bpy.data.objects.remove(o)
	before = tris(mesh_objs())
	wheels = group_wheels(cfg["wheels"]) if cfg.get("wheels") else []
	# Simplification
	ratio = cfg.get("ratio", 1.0)
	if ratio < 1.0:
		for o in mesh_objs():
			if len(o.data.polygons) < 60:
				continue
			md = o.modifiers.new("dec", "DECIMATE")
			md.ratio = ratio
			select([o])
			bpy.ops.object.modifier_apply(modifier=md.name)
	# Orientation : avant vers +Y Blender (= -Z dans Godot)
	angle = {"+y": 0.0, "-y": math.pi, "+x": math.pi / 2, "-x": -math.pi / 2}[cfg["front"]]
	objs = mesh_objs()
	lo, hi = world_bbox(objs)
	size = hi - lo
	center = (lo + hi) / 2
	along = size.y if cfg["front"][1] == "y" else size.x
	scale = cfg["length"] / along
	m = Matrix.Rotation(angle, 4, "Z") @ Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-center.x, -center.y, -lo.z)))
	for o in objs:
		o.matrix_world = m @ o.matrix_world
	select(objs)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	if cfg.get("wh"):
		lo1, hi1 = world_bbox(objs)
		sx = cfg["wh"][0] / (hi1.x - lo1.x)
		sz = cfg["wh"][1] / (hi1.z - lo1.z)
		for o in objs:
			if o in wheels:
				continue
			o.matrix_world = Matrix.Scale(sx, 4, (1, 0, 0)) @ Matrix.Scale(sz, 4, (0, 0, 1)) @ o.matrix_world
		for o in wheels:
			# Roue : rayon suivant la hauteur, position suivant la caisse
			lw, hw = world_bbox([o])
			c = (lw + hw) / 2
			o.matrix_world = Matrix.Translation(Vector((c.x * sx - c.x, 0, c.z * sz - c.z))) @ Matrix.Translation(c) @ Matrix.Scale(sz, 4) @ Matrix.Scale(sx / sz, 4, (1, 0, 0)) @ Matrix.Translation(-c) @ o.matrix_world
		select(objs)
		bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
	# Roues : origine au centre (rotation sur elles-mêmes)
	for o in wheels:
		select([o])
		bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
	lighten_materials()
	lo2, hi2 = world_bbox(objs)
	out = os.path.join(out_dir, name + ".glb")
	select(objs)
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
		export_image_format="JPEG", export_jpeg_quality=85)
	mats = sorted({s.material.name for o in objs for s in o.material_slots if s.material})
	print("VEHICULE %s taille %.2f x %.2f x %.2f  triangles %d -> %d  roues %d | matériaux: %s" % (
		name, *(hi2 - lo2), before, tris(objs), len(wheels), ", ".join(mats)))


def main():
	argv = sys.argv[sys.argv.index("--") + 1:]
	src_dir = os.path.abspath(argv[0])
	out_dir = os.path.abspath(argv[1])
	only = argv[2:]
	os.makedirs(out_dir, exist_ok=True)
	for name, cfg in MODELS.items():
		if only and name not in only:
			continue
		convert(name, cfg, src_dir, out_dir)


main()
