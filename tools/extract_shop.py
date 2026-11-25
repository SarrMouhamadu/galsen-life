"""Extrait des meubles du modèle « Super market for free » (dasy444, licence standard Sketchfab) pour les magasins.

    blender --background --python tools/extract_shop.py -- <magasin.glb> <world/shop> nom=objet[:simplification],...

Chaque meuble = un objet repère (une gondole) + tout ce qui est posé dedans (les produits), fusionnés en un
seul maillage, centré, posé au sol ; textures réduites à 512 px, sans normal map (téléphones).
"""
import bpy, sys, os
from mathutils import Vector, Matrix
a = sys.argv[sys.argv.index("--")+1:]
src, out_dir = a[0], a[1]; jobs = [j.split("=") for j in a[2].split(",")]  # nom=objet ou nom=objet:ratio
def bb(o):
    pts=[o.matrix_world @ Vector(c) for c in o.bound_box]
    return Vector((min(p.x for p in pts),min(p.y for p in pts),min(p.z for p in pts))), Vector((max(p.x for p in pts),max(p.y for p in pts),max(p.z for p in pts)))
for out_name, spec in jobs:
    name, ratio = (spec.split(":") + ["1"])[:2]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes=[o for o in bpy.data.objects if o.type=='MESH']
    g=bpy.data.objects[name]; lo,hi=bb(g); pad=Vector((0.05,0.25,0.05))
    keep=[]
    for o in meshes:
        l,h=bb(o); c=(l+h)/2
        if all(lo[i]-pad[i]<=c[i]<=hi[i]+pad[i] for i in range(3)) and (h-l).length < (hi-lo).length*1.01: keep.append(o)
    for o in list(bpy.data.objects):
        if o not in keep: bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        if o.data.users>1: o.data=o.data.copy()
        o.select_set(True)
    bpy.context.view_layer.objects.active=keep[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    o=bpy.context.view_layer.objects.active; o.name=out_name
    l,h=bb(o); c=(l+h)/2
    o.data.transform(Matrix.Translation(Vector((-c.x,-c.y,-l.z)))); o.location=(0,0,0)
    bpy.ops.mesh.customdata_custom_splitnormals_clear() if o.data.has_custom_normals else None
    md=o.modifiers.new("w","WELD"); md.merge_threshold=0.0005; bpy.ops.object.modifier_apply(modifier="w")
    if float(ratio) < 1.0:
        md=o.modifiers.new("d","DECIMATE"); md.ratio=float(ratio); bpy.ops.object.modifier_apply(modifier="d")
    for img in bpy.data.images:
        if img.size[0]>512 or img.size[1]>512:
            f=512/max(img.size); img.scale(max(1,int(img.size[0]*f)),max(1,int(img.size[1]*f)))
    for m in bpy.data.materials:
        if m.use_nodes:
            b=next((n for n in m.node_tree.nodes if n.type=="BSDF_PRINCIPLED"),None)
            if b:
                for nm in ["Normal","Roughness","Metallic"]:
                    for lk in list(b.inputs[nm].links): m.node_tree.links.remove(lk)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir,out_name+".glb"),export_format="GLB",use_selection=True,export_yup=True,export_image_format="JPEG",export_jpeg_quality=85)
    l,h=bb(o); print("EXTRAIT",out_name,"tris",sum(len(p.vertices)-2 for p in o.data.polygons),"taille",tuple(round(v,2) for v in h-l))
