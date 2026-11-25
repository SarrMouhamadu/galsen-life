"""Génère les personnages réalistes de Galsen-Life avec Blender + MPFB (MakeHuman pour Blender).

    blender --background --python tools/make_characters.py -- <dossier_sortie> [--preview]

Pré-requis : Blender 4.2+ avec l'extension MPFB et les bibliothèques CC0 de MakeHuman
(makehuman_system_assets, skins01, skins02, hair01, shirts01, pants01, shoes01, dress01,
skirts01, hats01). Seules des ressources CC0 sont utilisées.

Chaque personnage est exporté en .glb : corps allégé (proxy), vêtements, cheveux, yeux,
sourcils, squelette « game_engine » (pelvis, thigh_l, calf_l, upperarm_l, ...).
"""
import os
import sys

import bpy

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.objectservice import ObjectService

AFRICAN = {"african": 1.0, "asian": 0.0, "caucasian": 0.0}

CHARACTERS = [
    # Le héros : jeune homme en polo, pantalon et baskets, coupe courte
    {"name": "heros", "gender": 1.0, "age": 0.42, "muscle": 0.5, "weight": 0.5, "height": 0.56,
     "skin": "young_african_male", "hair": "short02", "eyebrows": "eyebrow001", "proxy": "male_generic",
     "clothes": ["namuhekam_male_polo_shirt", "toigo_wool_pants", "shoes02"]},
    {"name": "homme_ville", "gender": 1.0, "age": 0.45, "muscle": 0.5, "weight": 0.52, "height": 0.6,
     "skin": "young_african_male", "hair": "short04", "eyebrows": "eyebrow002", "proxy": "male_generic",
     "clothes": ["male_casualsuit02"]},
    {"name": "homme_age", "gender": 1.0, "age": 0.78, "muscle": 0.42, "weight": 0.6, "height": 0.5,
     "skin": "middleage_african_male", "hair": "short01", "eyebrows": "eyebrow003", "proxy": "male_generic",
     "clothes": ["male_casualsuit04"]},
    {"name": "homme_afro", "gender": 1.0, "age": 0.36, "muscle": 0.52, "weight": 0.46, "height": 0.62,
     "skin": "young_african_male", "hair": "afro01", "eyebrows": "eyebrow001", "proxy": "male_generic",
     "clothes": ["elvs_crude_t-shirt_male", "cortu_cargo_pants", "shoes03"]},
    {"name": "homme_tunique", "gender": 1.0, "age": 0.62, "muscle": 0.46, "weight": 0.55, "height": 0.55,
     "skin": "mindfront_skin_male_african_middleage", "hair": "short01", "eyebrows": "eyebrow004", "proxy": "male_generic",
     "clothes": ["mindfront_kimono", "toigo_mj_cloth_shoes", "jujube_newsboy_cap"]},
    {"name": "femme_robe", "gender": 0.0, "age": 0.42, "muscle": 0.42, "weight": 0.5, "height": 0.55,
     "skin": "young_african_female", "hair": "braid01", "eyebrows": "eyebrow006", "proxy": "female_generic",
     "clothes": ["toigo_dress_with_tiered_skirt", "toigo_flats"]},
    {"name": "femme_jupe", "gender": 0.0, "age": 0.5, "muscle": 0.42, "weight": 0.54, "height": 0.5,
     "skin": "young_african_female", "hair": "afro01", "eyebrows": "eyebrow007", "proxy": "female_generic",
     "clothes": ["toigo_camisole_top", "toigo_long_full_skirt", "toigo_ballet_flats"]},
    {"name": "femme_maman", "gender": 0.0, "age": 0.66, "muscle": 0.38, "weight": 0.62, "height": 0.48,
     "skin": "middleage_african_female", "hair": "braid01", "eyebrows": "eyebrow008", "proxy": "female_generic",
     "clothes": ["toigo_shift_dress", "toigo_flats"]},
    {"name": "femme_ville", "gender": 0.0, "age": 0.4, "muscle": 0.44, "weight": 0.47, "height": 0.6,
     "skin": "young_african_female", "hair": "ponytail01", "eyebrows": "eyebrow006", "proxy": "female_generic",
     "clothes": ["female_casualsuit01", "shoes05"]},
]

CHARACTERS.append(
    # Soldat : pull et pantalon cargo (teintés kaki dans le jeu), bottes ; le casque est ajouté dans le jeu
    {"name": "soldat", "gender": 1.0, "age": 0.4, "muscle": 0.6, "weight": 0.5, "height": 0.6,
     "skin": "young_african_male", "hair": "short02", "eyebrows": "eyebrow002", "proxy": "male_generic",
     "clothes": ["toigo_fisherman_sweater", "cortu_cargo_pants", "toigo_ankle_boots_male"]})

CHARACTERS.extend([
    # Lutteurs : très musclés, torse nu, en short (teinté façon pagne de lutte dans le jeu)
    {"name": "lutteur1", "gender": 1.0, "age": 0.42, "muscle": 1.0, "weight": 0.72, "height": 0.78,
     "skin": "young_african_male", "hair": "short02", "eyebrows": "eyebrow002", "proxy": "male_generic",
     "clothes": ["cortu_jeans_shorts"]},
    {"name": "lutteur2", "gender": 1.0, "age": 0.5, "muscle": 0.95, "weight": 0.8, "height": 0.74,
     "skin": "middleage_african_male", "hair": "short01", "eyebrows": "eyebrow003", "proxy": "male_generic",
     "clothes": ["cortu_jeans_shorts"]},
])

CHARACTERS.extend([
    # Footballeurs du complexe de mini-foot : maillot à manches courtes, short, chaussettes (fabriquées à partir
    # des mollets du corps, voir add_socks), chaussures de sport. Couleurs des équipes données dans le jeu.
    {"name": "footballeur1", "gender": 1.0, "age": 0.38, "muscle": 0.62, "weight": 0.44, "height": 0.62,
     "skin": "young_african_male", "hair": "short02", "eyebrows": "eyebrow001", "proxy": "male_generic",
     "clothes": ["elvs_crude_t-shirt_male", "cortu_jeans_shorts", "shoes04"], "socks": True, "tex": 1024},
    {"name": "footballeur2", "gender": 1.0, "age": 0.32, "muscle": 0.56, "weight": 0.42, "height": 0.58,
     "skin": "young_african_male", "hair": "afro01", "eyebrows": "eyebrow002", "proxy": "male_generic",
     "clothes": ["elvs_crude_t-shirt_male", "cortu_jeans_shorts", "shoes04"], "socks": True, "tex": 1024},
    {"name": "footballeur3", "gender": 1.0, "age": 0.46, "muscle": 0.52, "weight": 0.56, "height": 0.54,
     "skin": "middleage_african_male", "hair": "short04", "eyebrows": "eyebrow003", "proxy": "male_generic",
     "clothes": ["elvs_crude_t-shirt_male", "cortu_jeans_shorts", "shoes04"], "socks": True, "tex": 1024},
    {"name": "footballeuse", "gender": 0.0, "age": 0.36, "muscle": 0.52, "weight": 0.44, "height": 0.56,
     "skin": "young_african_female", "hair": "ponytail01", "eyebrows": "eyebrow006", "proxy": "female_generic",
     "clothes": ["joepal_crude_t-shirt_female", "cortu_jeans_shorts", "shoes04"], "socks": True, "tex": 1024},
    # Gardien : maillot à manches longues
    {"name": "gardien", "gender": 1.0, "age": 0.4, "muscle": 0.58, "weight": 0.5, "height": 0.66,
     "skin": "young_african_male", "hair": "short01", "eyebrows": "eyebrow002", "proxy": "male_generic",
     "clothes": ["toigo_fisherman_sweater", "cortu_jeans_shorts", "shoes04"], "socks": True, "tex": 1024},
])

MAX_SKIN_TEX = 2048
MAX_OTHER_TEX = 512


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


## Corps : réglages proches d'un humain moyen (0,5 = moyenne MakeHuman). Les anciennes valeurs (muscles
## et proportions « idéalisées » plus fortes) donnaient des épaules carrées et une petite tête.
def human_info_for(c):
    return {
        "name": c["name"],
        "phenotype": {"gender": c["gender"], "age": c["age"], "muscle": c["muscle"], "weight": c["weight"],
                      "proportions": 0.5, "height": c["height"], "cupsize": 0.5, "firmness": 0.5, "race": AFRICAN},
        "rig": "game_engine",
        "eyes": "high-poly.mhclo",
        "eyebrows": c["eyebrows"] + ".mhclo",
        "eyelashes": "eyelashes01.mhclo",
        "tongue": "",
        "teeth": "",
        "hair": c["hair"] + ".mhclo",
        "proxy": c["proxy"] + ".proxy",
        "targets": [],
        "clothes": [n + ".mhclo" for n in c["clothes"]],
        "skin_mhmat": c["skin"] + ".mhmat",
        "skin_material_type": "GAMEENGINE",
        "eyes_material_type": "GAMEENGINE",
        "clothes_material_type": "GAMEENGINE",
        "skin_material_settings": {},
        "eyes_material_settings": {},
        "expressions": [],
    }


def add_socks(c, proxy, rig):
    """Chaussettes de foot : copie du bas des jambes du corps (sous le genou), légèrement gonflée, avec son
    propre matériau (teint aux couleurs de l'équipe dans le jeu). Elle garde les groupes de sommets et le
    squelette du corps, donc suit les animations."""
    import bmesh
    sock = proxy.copy()
    sock.data = proxy.data.copy()
    sock.name = c["name"] + "_socks"
    for col in proxy.users_collection:
        col.objects.link(sock)
    # Les modificateurs de masquage du corps (parties cachées par les vêtements) ne servent pas ici
    for m in list(sock.modifiers):
        if m.type != "ARMATURE":
            sock.modifiers.remove(m)
    bones = rig.data.bones
    knee = min(bones["calf_l"].head_local.z, bones["calf_r"].head_local.z) if "calf_l" in bones else 0.5
    ankle = bones["foot_l"].head_local.z if "foot_l" in bones else knee * 0.2
    mw = sock.matrix_world
    rw = rig.matrix_world
    knee_w = (rw @ bones["calf_l"].head_local).z if "calf_l" in bones else knee
    ankle_w = (rw @ bones["foot_l"].head_local).z if "foot_l" in bones else ankle
    top = knee_w - (knee_w - ankle_w) * 0.08
    bm = bmesh.new()
    bm.from_mesh(sock.data)
    # Sous la cheville, la chaussure couvre le pied : on n'en garde rien (sinon la chaussette perce le bout)
    gone = [f for f in bm.faces if any((mw @ v.co).z > top for v in f.verts) or all((mw @ v.co).z < ankle_w for v in f.verts)]
    bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.normal_update()
    off = 0.008 * (knee_w / 0.5)
    for v in bm.verts:
        v.co += v.normal * off
    bm.to_mesh(sock.data)
    bm.free()
    # La peau sous la chaussette est retirée du corps : elle ne peut plus la transpercer quand le mollet se plie
    bb = bmesh.new()
    bb.from_mesh(proxy.data)
    pw = proxy.matrix_world
    hidden = [f for f in bb.faces if all(ankle_w + 0.015 < (pw @ v.co).z < top - 0.015 for v in f.verts)]
    bmesh.ops.delete(bb, geom=hidden, context="FACES_ONLY")
    bb.to_mesh(proxy.data)
    bb.free()
    mat = bpy.data.materials.new("socks")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.95, 0.95, 0.95, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.85
    sock.data.materials.clear()
    sock.data.materials.append(mat)
    print("CHAUSSETTES", sock.name, "sommets:", len(sock.data.vertices), "haut: %.3f genou: %.3f" % (top, knee_w))


def shrink_textures(skin_max=MAX_SKIN_TEX):
    for img in bpy.data.images:
        if img.size[0] == 0:
            continue
        limit = skin_max if "skin" in img.name.lower() or "diffuse" in img.name.lower() and "hair" not in img.name.lower() else MAX_OTHER_TEX
        w, h = img.size
        if max(w, h) > limit:
            f = limit / max(w, h)
            img.scale(max(1, int(w * f)), max(1, int(h * f)))
        img.pack()


def export_character(c, out_dir, preview):
    clear_scene()
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    settings["load_clothes"] = True
    basemesh = HumanService.deserialize_from_dict(human_info_for(c), settings)
    rig = ObjectService.find_object_of_type_amongst_nearest_relatives(basemesh, "Skeleton")
    proxy = ObjectService.find_object_of_type_amongst_nearest_relatives(basemesh, "Proxymeshes")
    if c.get("socks") and proxy is not None:
        add_socks(c, proxy, rig)
    bpy.ops.object.select_all(action="DESELECT")
    exported = []
    for obj in bpy.data.objects:
        if obj == basemesh and proxy is not None:
            continue
        if obj.type in ("MESH", "ARMATURE"):
            obj.select_set(True)
            exported.append(obj.name)
    shrink_textures(c.get("tex", MAX_SKIN_TEX))
    path = os.path.join(out_dir, c["name"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_animations=False, export_morph=False, export_skins=True,
                              export_image_format="AUTO")
    print("EXPORT", c["name"], "rig:", rig.name if rig else None, "proxy:", proxy.name if proxy else None,
          "objets:", ", ".join(exported), "taille: %.1f Mo" % (os.path.getsize(path) / 1048576))
    if preview:
        render_preview(c, out_dir)


def render_preview(c, out_dir):
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.0, -3.6, 1.0)
    cam.rotation_euler = (1.5708, 0.0, 0.0)
    cam_data.lens = 50
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (0.9, 0.2, 0.6)
    sun.data.energy = 3.0
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.color = (0.6, 0.6, 0.62)
    scene.world = world
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 400
    scene.render.resolution_y = 600
    scene.render.filepath = os.path.join(out_dir, "preview_" + c["name"] + ".png")
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(argv[0] if argv else "characters")
    preview = "--preview" in argv
    only = [a.split("=", 1)[1] for a in argv if a.startswith("--only=")]
    os.makedirs(out_dir, exist_ok=True)
    for c in CHARACTERS:
        if only and c["name"] not in only:
            continue
        export_character(c, out_dir, preview)


main()
