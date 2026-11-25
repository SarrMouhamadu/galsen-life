"""Cadres de texture de chaque produit d'un rayon (pour redessiner les étiquettes).

    blender --background --python tools/shop_uv_rects.py -- world/shop/<rayon>.glb <sortie.json>

Le rayon est un seul maillage : on le recoupe en pièces détachées (un produit = une pièce) et on note,
pour chaque image, le cadre UV occupé par chaque produit. Utilisé par tools/senegal_labels.py.
"""
import json
import sys

import bpy

a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
img_of = {}
for m in bpy.data.materials:
	if m.use_nodes:
		for n in m.node_tree.nodes:
			if n.type == "TEX_IMAGE" and n.image:
				img_of[m.name] = n.image.name
for o in [o for o in bpy.data.objects if o.type == "MESH"]:
	bpy.ops.object.select_all(action="DESELECT")
	o.select_set(True)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.mesh.separate(type="LOOSE")
	bpy.ops.object.mode_set(mode="OBJECT")
rects = {}
for o in bpy.data.objects:
	if o.type != "MESH" or not o.data.uv_layers:
		continue
	uv = o.data.uv_layers.active.data
	per = {}
	for p in o.data.polygons:
		mat = o.material_slots[p.material_index].material if o.material_slots else None
		if not mat or mat.name not in img_of:
			continue
		b = per.setdefault(img_of[mat.name], [9, 9, -9, -9])
		for i in p.loop_indices:
			u = uv[i].uv
			b[0] = min(b[0], u.x)
			b[1] = min(b[1], u.y)
			b[2] = max(b[2], u.x)
			b[3] = max(b[3], u.y)
	for im, b in per.items():
		rects.setdefault(im, set()).add(tuple(round(v, 3) for v in b))
out = {k: sorted(v) for k, v in rects.items()}
json.dump(out, open(a[1], "w", encoding="utf-8"), ensure_ascii=False)
for k, v in out.items():
	print("RECTS", k, len(v))
