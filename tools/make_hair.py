"""Exporte les coiffures du coiffeur (appli Sapé) avec Blender + MPFB, une par corps d'homme et de femme.

    blender --background --python tools/make_hair.py -- characters/hair [--preview] [--only=afro01]

Chaque fichier <corps>_<coiffure>.glb contient la coiffure seule, posée sur le squelette « game_engine »
d'un corps de référence (le héros pour les hommes, femme_robe pour les femmes). Dans le jeu, elle est
rattachée au squelette du personnage par le nom des os (scripts/util/real_character.gd, set_outfit).
Seules des ressources CC0 de MakeHuman sont utilisées.
"""
import os
import sys

import bpy

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.objectservice import ObjectService

AFRICAN = {"african": 1.0, "asian": 0.0, "caucasian": 0.0}
## Même phénotype que heros et femme_robe (tools/make_characters.py)
BODIES = {
    "homme": {"gender": 1.0, "age": 0.42, "muscle": 0.5, "weight": 0.5, "height": 0.56,
              "skin": "young_african_male", "proxy": "male_generic"},
    "femme": {"gender": 0.0, "age": 0.42, "muscle": 0.42, "weight": 0.5, "height": 0.55,
              "skin": "young_african_female", "proxy": "female_generic"},
}
HAIRS = ["short01", "short02", "short04", "afro01", "elvs_double_mh_braid", "braid01",
         "rehmanpolanski_hair_bun_brown", "ponytail01", "bob02"]
MAX_TEX = 512


def human_info(body, hair):
    b = BODIES[body]
    return {
        "name": "ref",
        "phenotype": {"gender": b["gender"], "age": b["age"], "muscle": b["muscle"], "weight": b["weight"],
                      "proportions": 0.5, "height": b["height"], "cupsize": 0.5, "firmness": 0.5, "race": AFRICAN},
        "rig": "game_engine",
        "eyes": "", "eyebrows": "", "eyelashes": "", "tongue": "", "teeth": "",
        "hair": hair + ".mhclo",
        "proxy": b["proxy"] + ".proxy",
        "targets": [], "clothes": [],
        "skin_mhmat": b["skin"] + ".mhmat",
        "skin_material_type": "GAMEENGINE", "eyes_material_type": "GAMEENGINE", "clothes_material_type": "GAMEENGINE",
        "skin_material_settings": {}, "eyes_material_settings": {}, "expressions": [],
    }


def export_hair(body, hair, out_dir, preview):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    HumanService.deserialize_from_dict(human_info(body, hair), settings)
    bpy.ops.object.select_all(action="DESELECT")
    hair_obj = None
    for obj in bpy.data.objects:
        if obj.type == "ARMATURE":
            obj.select_set(True)
        elif obj.type == "MESH" and ObjectService.get_object_type(obj) == "Hair":
            hair_obj = obj
            obj.select_set(True)
    if hair_obj is None:
        raise SystemExit("coiffure introuvable : " + hair + " / " + ", ".join(o.name for o in bpy.data.objects))
    hair_obj.name = "coiffure"
    for img in bpy.data.images:
        w, h = img.size
        if w and max(w, h) > MAX_TEX:
            f = MAX_TEX / max(w, h)
            img.scale(max(1, int(w * f)), max(1, int(h * f)))
        if w:
            img.pack()
    path = os.path.join(out_dir, "%s_%s.glb" % (body, hair))
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_animations=False, export_morph=False, export_skins=True,
                              export_image_format="AUTO")
    print("EXPORT", body, hair, "%.2f Mo" % (os.path.getsize(path) / 1048576))
    if preview:
        scene = bpy.context.scene
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scene.collection.objects.link(cam)
        cam.location = (0.0, -1.1, 1.62)
        cam.rotation_euler = (1.5708, 0.0, 0.0)
        scene.camera = cam
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.rotation_euler = (0.9, 0.2, 0.6)
        sun.data.energy = 3.0
        scene.collection.objects.link(sun)
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.resolution_x = 300
        scene.render.resolution_y = 300
        scene.render.filepath = os.path.join(out_dir, "preview_%s_%s.png" % (body, hair))
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(argv[0] if argv else "characters/hair")
    preview = "--preview" in argv
    only = [a.split("=", 1)[1] for a in argv if a.startswith("--only=")]
    os.makedirs(out_dir, exist_ok=True)
    for body in BODIES:
        for hair in HAIRS:
            if not only or hair in only:
                export_hair(body, hair, out_dir, preview)


main()
