"""Pose le squelette du jeu sur un personnage généré par IA (image → 3D, ex. Hunyuan3D) et l'exporte en .glb.

    blender --background --python tools/rig_ai_character.py -- <modele_ia.glb> <sortie.glb> [--height=1.78] [--faces=24000]
        [--image=face.png --top=32 --bottom=1112 --cx=250]   (forme sans couleurs : on projette l'image de face)
        [--rebake=1]   (atlas de texture morcelé : couleur recuite sur le maillage allégé, voir rebake)

Le squelette « game_engine » de MakeHuman (celui de characters/realistic/heros.glb) est repris tel quel, avec
les mêmes noms d'os : les animations du jeu (tools/bake_animations.gd) s'appliquent donc aux nouveaux personnages.
Étapes : orientation (le personnage regarde -Y comme les modèles MakeHuman), taille, pieds au sol ; ajustement
du squelette au corps (bras le long du corps, jambes) ; poids de peau automatiques ; allègement pour téléphone.
Texture (option --image) : l'image de face est projetée sur le devant ; le dos reçoit la même image très floutée
(couleurs des vêtements sans les inscriptions à l'envers), puis tout est « cuit » dans une texture 2048 px.
--top/--bottom : lignes (pixels) du sommet de la tête et du bas des pieds dans l'image ; --cx : colonne du milieu du corps.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "characters", "realistic", "heros.glb")


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"height": 1.78, "faces": 24000}
    opts_str = {"image"}
    pos = []
    for a in argv:
        if a.startswith("--"):
            k, v = a[2:].split("=", 1)
            opts[k] = v if k in opts_str else float(v)
        else:
            pos.append(a)
    return pos[0], pos[1], opts


def world_verts(obj):
    m = obj.matrix_world
    return [m @ v.co for v in obj.data.vertices]


def import_ai(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    # Les parents vides de l'import sont retirés en gardant la transformation
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.name = "corps"
    return obj


def normalize(obj, height):
    vs = world_verts(obj)
    zmin = min(v.z for v in vs)
    zmax = max(v.z for v in vs)
    h = zmax - zmin
    # Avant/arrière : les orteils dépassent devant les chevilles
    toes = [v for v in vs if v.z < zmin + 0.04 * h]
    ankles = [v for v in vs if zmin + 0.06 * h < v.z < zmin + 0.10 * h]
    dy = sum(v.y for v in toes) / max(1, len(toes)) - sum(v.y for v in ankles) / max(1, len(ankles))
    dx = sum(v.x for v in toes) / max(1, len(toes)) - sum(v.x for v in ankles) / max(1, len(ankles))
    # Direction du regard ramenée vers -Y (convention des modèles MakeHuman)
    ang = math.atan2(dx, -dy) if abs(dx) > abs(dy) * 0.5 else (0.0 if dy < 0 else math.pi)
    # Les modèles d'IA sont générés de face : on arrondit au quart de tour (les pieds écartés faussent la mesure)
    ang = round(ang / (math.pi / 2)) * (math.pi / 2)
    obj.rotation_euler = (0, 0, -ang)
    bpy.ops.object.transform_apply(rotation=True)
    vs = world_verts(obj)
    s = height / h
    obj.scale = (s, s, s)
    bpy.ops.object.transform_apply(scale=True)
    vs = world_verts(obj)
    zmin = min(v.z for v in vs)
    mid = [v for v in vs if abs(v.z - zmin - 0.5 * height) < 0.05 * height]
    cx = sum(v.x for v in mid) / len(mid)
    cy = sum(v.y for v in mid) / len(mid)
    obj.location = (-cx, -cy, -zmin)
    bpy.ops.object.transform_apply(location=True)
    print("ORIENT angle=%.1f° taille=%.2f m" % (math.degrees(ang), height))


def texture_from_image(body, path, top, bottom, cx, height, size=2048):
    """Projette l'image de face sur le corps (devant net, dos flouté) et cuit le résultat dans une texture."""
    img = bpy.data.images.load(path)
    W, H = img.size
    k = (bottom - top) / height  # pixels par mètre
    # Dos : la même image très floutée (réduite puis agrandie)
    blur = img.copy()
    blur.name = "dos_flou"
    blur.scale(max(4, W // 4), max(4, H // 4))
    blur.scale(W, H)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    # Dépliage UV automatique de la forme
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")
    mat = bpy.data.materials.new("projection")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    bsdf = nodes["Principled BSDF"]
    tc = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(tc.outputs["Object"], sep.inputs[0])
    # u = (cx + x·k) / W ; v = 1 - (bottom - z·k) / H  (le personnage regarde -Y : sa gauche est +X, à droite de l'image)
    # Bords du corps (surfaces tournées vers le côté) : on échantillonne un peu vers l'intérieur,
    # sinon la projection attrape le fond de l'image (ciel, rue) au ras de la silhouette
    geo0 = nodes.new("ShaderNodeNewGeometry")
    sn0 = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo0.outputs["Normal"], sn0.inputs[0])
    ax = nodes.new("ShaderNodeMath"); ax.operation = "ABSOLUTE"
    links.new(sn0.outputs["X"], ax.inputs[0])
    shrink = nodes.new("ShaderNodeMath"); shrink.operation = "MULTIPLY_ADD"
    shrink.inputs[1].default_value = -0.14; shrink.inputs[2].default_value = 1.0
    links.new(ax.outputs[0], shrink.inputs[0])
    xs = nodes.new("ShaderNodeMath"); xs.operation = "MULTIPLY"
    links.new(sep.outputs["X"], xs.inputs[0])
    links.new(shrink.outputs[0], xs.inputs[1])
    mu = nodes.new("ShaderNodeMath"); mu.operation = "MULTIPLY_ADD"
    mu.inputs[1].default_value = k / W; mu.inputs[2].default_value = cx / W
    links.new(xs.outputs[0], mu.inputs[0])
    mv = nodes.new("ShaderNodeMath"); mv.operation = "MULTIPLY_ADD"
    mv.inputs[1].default_value = k / H; mv.inputs[2].default_value = 1.0 - bottom / H
    links.new(sep.outputs["Z"], mv.inputs[0])
    comb = nodes.new("ShaderNodeCombineXYZ")
    links.new(mu.outputs[0], comb.inputs["X"])
    links.new(mv.outputs[0], comb.inputs["Y"])
    t_front = nodes.new("ShaderNodeTexImage"); t_front.image = img; t_front.extension = "EXTEND"
    t_back = nodes.new("ShaderNodeTexImage"); t_back.image = blur; t_back.extension = "EXTEND"
    links.new(comb.outputs[0], t_front.inputs["Vector"])
    # Dos : image en miroir (les inscriptions se lisent dans le bon sens, comme un vrai gilet) ;
    # arrière de la tête : la colonne du milieu de la tête (casquette, cheveux) et non le visage
    mb = nodes.new("ShaderNodeMath"); mb.operation = "MULTIPLY_ADD"
    mb.inputs[1].default_value = -0.9 * k / W; mb.inputs[2].default_value = cx / W
    links.new(xs.outputs[0], mb.inputs[0])
    head = nodes.new("ShaderNodeMath"); head.operation = "GREATER_THAN"
    head.inputs[1].default_value = 0.85 * height
    links.new(sep.outputs["Z"], head.inputs[0])
    ub = nodes.new("ShaderNodeMix"); ub.data_type = "FLOAT"
    links.new(head.outputs[0], ub.inputs["Factor"])
    links.new(mb.outputs[0], ub.inputs["A"])
    ub.inputs["B"].default_value = cx / W
    comb_b = nodes.new("ShaderNodeCombineXYZ")
    links.new(ub.outputs["Result"], comb_b.inputs["X"])
    links.new(mv.outputs[0], comb_b.inputs["Y"])
    links.new(comb_b.outputs[0], t_back.inputs["Vector"])
    # Mélange selon l'orientation de la surface (normale vers -Y : devant)
    geo = nodes.new("ShaderNodeNewGeometry")
    sn = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Normal"], sn.inputs[0])
    ramp = nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = -0.15
    ramp.inputs["From Max"].default_value = 0.35
    links.new(sn.outputs["Y"], ramp.inputs["Value"])
    mix = nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    links.new(ramp.outputs[0], mix.inputs["Factor"])
    links.new(t_front.outputs["Color"], mix.inputs[6])
    links.new(t_back.outputs["Color"], mix.inputs[7])
    links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    body.data.materials.clear()
    body.data.materials.append(mat)
    # Cuisson dans une texture UV
    baked = bpy.data.images.new("peau_" + body.name, size, size)
    tgt = nodes.new("ShaderNodeTexImage"); tgt.image = baked
    nodes.active = tgt
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    sc.cycles.device = "CPU"
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.margin = 8
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    # Matériau final : la texture cuite seule
    for n in list(nodes):
        if n not in (bsdf, nodes["Material Output"]):
            nodes.remove(n)
    final = nodes.new("ShaderNodeTexImage"); final.image = baked
    links.new(final.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    baked.pack()
    print("TEXTURE cuite %dx%d depuis %s (k=%.0f px/m)" % (size, size, os.path.basename(path), k))


def landmarks(obj, height):
    vs = world_verts(obj)
    out = {}
    for side, sgn in (("l", 1.0), ("r", -1.0)):
        sv = [v for v in vs if v.x * sgn > 0]
        arm_zone = [v for v in sv if 0.30 * height < v.z < 0.90 * height]
        far = max(arm_zone, key=lambda v: abs(v.x))
        if abs(far.x) > 0.30 * height:
            # Pose en T ou en A (bras écartés) : la main est le point le plus éloigné du corps, le poignet
            # un dixième de la taille plus près de l'épaule, le long du bras
            tip = far
            shoulder = Vector((sgn * 0.11 * height, tip.y, 0.81 * height))
            c = tip - (tip - shoulder).normalized() * 0.10 * height
            wr = [v for v in sv if (v - c).length < 0.03 * height]
            wrist = Vector((sum(v.x for v in wr) / len(wr), sum(v.y for v in wr) / len(wr), sum(v.z for v in wr) / len(wr))) if wr else c
        else:
            band = [v for v in sv if 0.30 * height < v.z < 0.62 * height]
            xmax = max(abs(v.x) for v in band)
            hand = [v for v in band if abs(v.x) > 0.78 * xmax]
            tip = min(hand, key=lambda v: v.z)
            wz = tip.z + 0.10 * height
            wr = [v for v in sv if abs(v.z - wz) < 0.015 * height and abs(v.x) > 0.70 * xmax]
            if not wr:
                wr = hand
            wrist = Vector((sum(v.x for v in wr) / len(wr), sum(v.y for v in wr) / len(wr), wz))
        an = [v for v in sv if 0.03 * height < v.z < 0.07 * height]
        ankle = Vector((sum(v.x for v in an) / len(an), sum(v.y for v in an) / len(an), 0.045 * height))
        out[side] = {"wrist": wrist, "ankle": ankle, "tip": tip}
        print("REPERES", side, "poignet", tuple(round(c, 3) for c in wrist), "cheville", tuple(round(c, 3) for c in ankle))
    return out


def import_template(height):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(TEMPLATE))
    new = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in new if o.type == "ARMATURE"][0]
    for o in new:
        if o.type != "ARMATURE":
            bpy.data.objects.remove(o, do_unlink=True)
    # Taille du modèle de référence : du sol au sommet de la tête (os « head » + crâne)
    head = arm.data.bones["head"]
    top = (arm.matrix_world @ head.tail_local).z + 0.06
    s = height / top
    arm.scale = (s, s, s)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.ops.object.transform_apply(scale=True)
    arm.name = "squelette"
    return arm


def aim(arm, bone_name, target):
    """Tourne l'os (en pose) pour que son extrémité vise `target` (coordonnées du monde)."""
    pb = arm.pose.bones[bone_name]
    bpy.context.view_layer.update()
    head = arm.matrix_world @ pb.head
    tail = arm.matrix_world @ pb.tail
    cur = (tail - head).normalized()
    want = (target - head).normalized()
    rot = cur.rotation_difference(want)
    pb.rotation_mode = "QUATERNION"
    # Rotation exprimée dans l'espace de l'os
    m = pb.matrix.to_3x3()
    local = m.inverted() @ rot.to_matrix() @ m
    pb.rotation_quaternion = local.to_quaternion() @ pb.rotation_quaternion
    bpy.context.view_layer.update()


def fit(arm, lm):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for side in ("l", "r"):
        w = lm[side]["wrist"]
        up = arm.pose.bones["upperarm_" + side]
        sh = arm.matrix_world @ up.head
        # Coude : entre l'épaule et le poignet, un peu en arrière (bras détendu)
        elbow = sh.lerp(w, 0.52) + Vector((0, 0.025, 0))
        aim(arm, "upperarm_" + side, elbow)
        aim(arm, "lowerarm_" + side, w)
        # Main dans le prolongement de l'avant-bras
        low = arm.pose.bones["lowerarm_" + side]
        d = ((arm.matrix_world @ low.tail) - (arm.matrix_world @ low.head)).normalized()
        aim(arm, "hand_" + side, w + d * 0.1)
        a = lm[side]["ankle"]
        th = arm.pose.bones["thigh_" + side]
        hip = arm.matrix_world @ th.head
        knee = hip.lerp(a, 0.5) + Vector((0, -0.02, 0))
        aim(arm, "thigh_" + side, knee)
        aim(arm, "calf_" + side, a)
    # Cette pose devient la pose de repos (le squelette épouse le corps)
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def skin(arm, body):
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    empty = sum(1 for v in body.data.vertices if len(v.groups) == 0)
    if empty > 0.05 * len(body.data.vertices):
        # Maillage en pièces détachées (vêtements, cheveux…) : les poids automatiques échouent. Poids calculés
        # d'après la distance de chaque sommet aux os (les 4 plus proches, 1/d⁴), comme une enveloppe douce.
        print("PEAU échec direct (%d sommets sans poids) : poids d'après la distance aux os" % empty)
        segs = [(b.name, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local)
                for b in arm.data.bones if b.use_deform]
        groups = {}
        for name, _h, _t in segs:
            groups[name] = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)
        mw = body.matrix_world
        for v in body.data.vertices:
            p = mw @ v.co
            near = []
            for name, h, t in segs:
                ab = t - h
                k = max(0.0, min(1.0, (p - h).dot(ab) / max(ab.length_squared, 1e-12)))
                d = (p - (h + ab * k)).length
                near.append((d, name))
            near.sort()
            near = near[:4]
            ws = [1.0 / (d ** 4 + 1e-10) for d, _n in near]
            tot = sum(ws)
            for (d, name), w in zip(near, ws):
                if w / tot > 0.01:
                    groups[name].add([v.index], w / tot, "REPLACE")
        if not any(m.type == "ARMATURE" for m in body.modifiers):
            body.modifiers.new("squelette", "ARMATURE").object = arm
        empty = sum(1 for v in body.data.vertices if len(v.groups) == 0)
    groups = len(body.vertex_groups)
    print("PEAU groupes=%d sommets sans poids=%d / %d" % (groups, empty, len(body.data.vertices)))
    return empty


def decimate(body, faces):
    n = len(body.data.polygons)
    if n <= faces:
        return
    # Sommets doublés aux coutures de texture (import glTF) soudés d'abord : sinon chaque îlot est allégé
    # séparément et des fentes s'ouvrent entre eux (on voit à travers le personnage)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.00001)
    bpy.ops.object.mode_set(mode="OBJECT")
    m = body.modifiers.new("allege", "DECIMATE")
    m.ratio = faces / n
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=m.name)
    print("ALLEGE %d -> %d faces" % (n, len(body.data.polygons)))


def rebake(low, high, size=2048):
    """Atlas de texture très morcelé (scan, IA) : l'allègement déplace les bords des îlots et la peau prend
    la couleur du tissu voisin. On déplie le maillage allégé et on y projette la couleur du modèle complet."""
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    uv = low.data.uv_layers.new(name="cuite")
    low.data.uv_layers.active = uv
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new("couleur_cuite", size, size)
    mat = bpy.data.materials.new("cuit")
    mat.use_nodes = True
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    nt.nodes.active = tex
    low.data.materials.clear()
    low.data.materials.append(mat)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.05
    sc.render.bake.max_ray_distance = 0.12
    sc.render.bake.margin = 8
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    img.pack()
    bpy.data.objects.remove(high, do_unlink=True)
    for u in [u for u in low.data.uv_layers if u.name != "cuite"]:
        low.data.uv_layers.remove(u)
    print("CUISSON texture %dx%d" % (size, size))


def main():
    src, dst, opts = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = import_ai(src)
    high = None
    if opts.get("rebake"):
        high = body.copy()
        high.data = body.data.copy()
        bpy.context.collection.objects.link(high)
    decimate(body, int(opts["faces"]))
    if high:
        rebake(body, high)
    normalize(body, opts["height"])
    if "image" in opts:
        texture_from_image(body, opts["image"], opts["top"], opts["bottom"], opts["cx"], opts["height"])
    lm = landmarks(body, opts["height"])
    arm = import_template(opts["height"])
    fit(arm, lm)
    skin(arm, body)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm.select_set(True)
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_animations=False, export_skins=True, export_image_format="AUTO")
    print("EXPORT", dst, "%.1f Mo" % (os.path.getsize(dst) / 1048576))


main()
