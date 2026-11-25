"""Convertit les véhicules CC0 de Quaternius (FBX) en .glb pour Galsen-Life.

    blender --background --python tools/convert_vehicles.py -- <dossier_cars_fbx> <dossier_transport_fbx> <sortie>

- Packs : « Realistic Car Pack » et « LowPoly Public Transport » de Quaternius (licence CC0).
- Chaque véhicule est mis à l'échelle (longueur voulue), centré, posé au sol, l'avant tourné vers -Z dans Godot.
- Les roues restent des objets séparés (nom contenant « Wheel ») pour pouvoir tourner.
- Les noms des matériaux sont conservés : le jeu repeint la carrosserie selon le type (taxi, clando...).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

## sortie → [pack, fichier, longueur en mètres]
VEHICLES = {
    "taxi": ["cars", "Taxi.fbx", 4.3],
    "clando1": ["cars", "NormalCar1.fbx", 4.4],
    "clando2": ["cars", "NormalCar2.fbx", 4.5],
    "police": ["cars", "Cop.fbx", 4.6],
    "suv": ["cars", "SUV.fbx", 4.7],
    "bus": ["transport", "Bus.fbx", 12.0, [2.55, 3.3]],
    "car_rapide": ["transport", "SchoolBus.fbx", 6.2],
    "van": ["transport", "Ambulance.fbx", 5.4],
}


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def world_bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def front_sign(objs, axis):
    """Signe (+1/-1) du côté avant le long de l'axe : roues avant si elles sont nommées, sinon les phares."""
    lo, hi = world_bbox(objs)
    mid = (lo + hi) / 2
    fronts = [o for o in objs if "front" in o.name.lower() and "wheel" in o.name.lower()]
    if fronts:
        lw, hw = world_bbox(fronts)
        return 1.0 if ((lw + hw) / 2)[axis] > mid[axis] else -1.0
    total = 0.0
    count = 0
    for o in objs:
        if o.type != "MESH":
            continue
        me = o.data
        for poly in me.polygons:
            mat = o.material_slots[poly.material_index].material if o.material_slots else None
            name = mat.name.lower() if mat else ""
            if "headlight" in name or name.startswith("light") or "front" in name:
                c = o.matrix_world @ poly.center
                total += c[axis]
                count += 1
    if count == 0:
        return None
    return 1.0 if total / count > 0 else -1.0


def convert(name, path, length, out_dir, wh=None):
    clear()
    bpy.ops.import_scene.fbx(filepath=path)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    # Appliquer les transformations de l'import (échelle FBX, rotations)
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    lo, hi = world_bbox(objs)
    size = hi - lo
    # Axe de la longueur : X ou Y (Blender, Z vers le haut)
    axis = 0 if size.x > size.y else 1
    sign = front_sign(objs, axis)
    if sign is None:
        sign = 1.0
        print("  (pas de phares trouvés pour", name, ": avant supposé vers +)")
    # Rotation autour de Z pour mettre l'avant vers +Y Blender (= -Z dans Godot)
    if axis == 0:
        angle = math.pi / 2 if sign > 0 else -math.pi / 2
    else:
        angle = 0.0 if sign > 0 else math.pi
    scale = length / max(size.x, size.y)
    center = (lo + hi) / 2
    m = Matrix.Rotation(angle, 4, "Z") @ Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-center.x, -center.y, -lo.z)))
    for o in objs:
        o.matrix_world = m @ o.matrix_world
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if wh is not None:
        # Proportions réelles (largeur, hauteur) ; les roues gardent leur forme ronde
        lo1, hi1 = world_bbox(objs)
        sx = wh[0] / (hi1.x - lo1.x)
        sz = wh[1] / (hi1.z - lo1.z)
        for o in objs:
            if "wheel" in o.name.lower():
                continue
            o.matrix_world = Matrix.Scale(sx, 4, (1, 0, 0)) @ Matrix.Scale(sz, 4, (0, 0, 1)) @ o.matrix_world
        for o in objs:
            if "wheel" not in o.name.lower():
                continue
            # Roue : rayon suivant la hauteur, position suivant la caisse
            lw, hw = world_bbox([o])
            c = (lw + hw) / 2
            o.matrix_world = Matrix.Translation(Vector((c.x * sx - c.x, 0, c.z * sz - c.z))) @ Matrix.Translation(c) @ Matrix.Scale(sz, 4) @ Matrix.Scale(sx / sz, 4, (1, 0, 0)) @ Matrix.Translation(-c) @ o.matrix_world
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # Les roues : origine au centre de la roue (pour tourner sur elles-mêmes)
    for o in objs:
        if "wheel" in o.name.lower():
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    lo2, hi2 = world_bbox(objs)
    path_out = os.path.join(out_dir, name + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path_out, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    mats = sorted({s.material.name for o in objs for s in o.material_slots if s.material})
    print("VEHICULE", name, "taille %.2f x %.2f x %.2f" % tuple(hi2 - lo2), "objets:", ", ".join(o.name for o in objs), "| matériaux:", ", ".join(mats))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    dirs = {"cars": argv[0], "transport": argv[1]}
    out_dir = os.path.abspath(argv[2])
    os.makedirs(out_dir, exist_ok=True)
    for name, v in VEHICLES.items():
        convert(name, os.path.join(dirs[v[0]], v[1]), v[2], out_dir, v[3] if len(v) > 3 else None)


main()
