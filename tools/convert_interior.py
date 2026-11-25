"""Convertit un intérieur Sketchfab (FBX + dossier textures) en .glb léger pour Galsen-Life.

    blender --background --python tools/convert_interior.py -- <fichier.fbx> <dossier textures> <sortie.glb> [xmin,xmax,ymin,ymax]

- Le cadre (repère Blender) garde la pièce : les objets dont le centre est dehors (décor lointain) sont retirés.

- Les images que le FBX cherche dans son dossier « .fbm » sont retrouvées dans le dossier textures (même nom).
- Couleur seule (pas de normal map ni de rugosité), textures réduites à 512 px : téléphones.
- Transformations appliquées ; repère Godot (Y en haut), mètres.
"""
import os
import sys

import bpy
from mathutils import Vector

MAX_TEX = 512

a = sys.argv[sys.argv.index("--") + 1:]
src, tex_dir, out = a[0], a[1], a[2]
crop = [float(v) for v in a[3].split(",")] if len(a) > 3 else None
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
stems = {os.path.splitext(f)[0].lower(): os.path.join(tex_dir, f) for f in os.listdir(tex_dir)}
for img in bpy.data.images:
	stem = os.path.splitext(os.path.basename(img.filepath))[0].lower()
	if not img.has_data and stem in stems:
		img.filepath = stems[stem]
		img.reload()
for m in bpy.data.materials:
	if not m.use_nodes:
		continue
	b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
	if b is None:
		continue
	for nm in ["Normal", "Roughness", "Metallic", "Specular IOR Level", "Alpha"]:
		for lk in list(b.inputs[nm].links):
			m.node_tree.links.remove(lk)
	b.inputs["Alpha"].default_value = 1.0
for img in bpy.data.images:
	if img.has_data and max(img.size) > MAX_TEX:
		f = MAX_TEX / max(img.size)
		img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
for o in [o for o in bpy.data.objects if o.type != "MESH"]:
	bpy.data.objects.remove(o)
if crop:
	for o in list(bpy.data.objects):
		pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
		cx = sum(p.x for p in pts) / 8.0
		cy = sum(p.y for p in pts) / 8.0
		if not (crop[0] <= cx <= crop[1] and crop[2] <= cy <= crop[3]):
			bpy.data.objects.remove(o)
objs = list(bpy.data.objects)
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
	if o.data.users > 1:
		o.data = o.data.copy()
	o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
	export_image_format="JPEG", export_jpeg_quality=85)
missing = [i.name for i in bpy.data.images if not i.has_data]
print("INTERIEUR", out, "objets", len(objs), "triangles", sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons), "images manquantes", missing)
