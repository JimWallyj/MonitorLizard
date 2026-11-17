# Monitor Lizard: rigging script for Blender (written for Blender 5.x)
#
# What it does, in order:
#   1. Finds the imported lizard model and removes Blender's default cube.
#   2. Merges duplicate vertices along texture seams (helps automatic weights).
#   3. Builds a skeleton designed for the app: pelvis, 4 spine bones,
#      2 neck bones, head, 18 tail bones, and 3 bones per leg.
#   4. Binds the skin to the bones with Blender's automatic weights,
#      and repairs any vertices left without a bone.
#   5. Shrinks the 4096-pixel textures to 2048 pixels.
#   6. Saves MonitorLizard_rigged.glb, MonitorLizard_rigged.usdz and
#      MonitorLizard_rig.blend in ~/Downloads/MonitorLizardRig/
#   7. Shows a short report (also saved in the Text editor as "Rig Report").
#
# How to run: Scripting tab > Open > choose this file > press the Run Script button (triangle).

import bpy, bmesh, os
from mathutils import Vector

REPORT = []
def log(msg):
    print(msg)
    REPORT.append(msg)

# Joint positions measured from the model file (glTF units, before Blender's import conversion).
SCALE = 1.6065998077392578          # the model's own scale in the file
SPINE = [[-0.0002, -0.0083, 0.04], [-0.0043, 0.0009, 0.1], [-0.0041, 0.002, 0.16], [-0.0042, 0.0062, 0.22], [-0.0037, 0.0139, 0.29], [-0.0033, 0.059, 0.34], [-0.0047, 0.0866, 0.39]]
HEAD_TIP = [-0.004, 0.106, 0.5]
TAIL = [[-0.0002, -0.0083, 0.04], [-0.0037, -0.0035, 0.0075], [-0.0042, 0.0042, -0.0259], [-0.0044, 0.0024, -0.061], [-0.0043, -0.0004, -0.0961], [-0.0045, -0.0031, -0.1311], [-0.0042, -0.0053, -0.1661], [-0.0045, -0.0061, -0.2012], [-0.0039, -0.0064, -0.2364], [-0.0037, -0.0058, -0.2715], [-0.0012, -0.0044, -0.3065], [0.0073, -0.0037, -0.3404], [0.0213, -0.0025, -0.3726], [0.0412, -0.0015, -0.4016], [0.0656, 0.0, -0.4265], [0.0942, 0.0006, -0.4469], [0.1235, 0.0009, -0.4662], [0.1541, -0.0003, -0.4833], [0.185, -0.002, -0.5]]
LEGS = {
 "Thigh.L": [
  [
   0.045,
   -0.012,
   0.05
  ],
  [
   0.088,
   -0.06,
   0.045
  ]
 ],
 "Shin.L": [
  [
   0.088,
   -0.06,
   0.045
  ],
  [
   0.101,
   -0.112,
   0.025
  ]
 ],
 "Foot.L": [
  [
   0.101,
   -0.112,
   0.025
  ],
  [
   0.1,
   -0.13,
   0.07
  ]
 ],
 "UpperArm.L": [
  [
   0.045,
   0.005,
   0.29
  ],
  [
   0.106,
   -0.06,
   0.277
  ]
 ],
 "Forearm.L": [
  [
   0.106,
   -0.06,
   0.277
  ],
  [
   0.119,
   -0.105,
   0.29
  ]
 ],
 "Hand.L": [
  [
   0.119,
   -0.105,
   0.29
  ],
  [
   0.132,
   -0.13,
   0.335
  ]
 ],
 "Thigh.R": [
  [
   -0.045,
   -0.012,
   0.05
  ],
  [
   -0.091,
   -0.06,
   0.045
  ]
 ],
 "Shin.R": [
  [
   -0.091,
   -0.06,
   0.045
  ],
  [
   -0.103,
   -0.111,
   0.022
  ]
 ],
 "Foot.R": [
  [
   -0.103,
   -0.111,
   0.022
  ],
  [
   -0.105,
   -0.13,
   0.065
  ]
 ],
 "UpperArm.R": [
  [
   -0.045,
   0.005,
   0.29
  ],
  [
   -0.113,
   -0.06,
   0.277
  ]
 ],
 "Forearm.R": [
  [
   -0.113,
   -0.06,
   0.277
  ],
  [
   -0.128,
   -0.105,
   0.29
  ]
 ],
 "Hand.R": [
  [
   -0.128,
   -0.105,
   0.29
  ],
  [
   -0.141,
   -0.13,
   0.335
  ]
 ]
}

def B(p):
    """glTF (x, y up, z forward) -> Blender world (x, y back, z up), with the model's scale."""
    x, y, z = p
    return Vector((SCALE * x, -SCALE * z, SCALE * y))

# ---------------------------------------------------------------- 1. find the lizard
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')

meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
if not meshes:
    raise RuntimeError("No model found. Import the lizard GLB first (File > Import > glTF 2.0).")
liz = max(meshes, key=lambda o: len(o.data.vertices))
liz.name = "MonitorLizard"
for o in list(bpy.context.scene.objects):
    if o.type == 'MESH' and o is not liz and o.name.startswith("Cube"):
        bpy.data.objects.remove(o, do_unlink=True)

# Bake the object's position, rotation and scale into the mesh itself.
mw = liz.matrix_world.copy()
liz.parent = None
liz.matrix_world = mw
bpy.ops.object.select_all(action='DESELECT')
liz.select_set(True)
bpy.context.view_layer.objects.active = liz
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Sanity check: the lizard should be about 1.6 long (Y), 0.63 wide (X), 0.45 tall (Z).
xs = [v.co.x for v in liz.data.vertices]; ys = [v.co.y for v in liz.data.vertices]; zs = [v.co.z for v in liz.data.vertices]
size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
log("Model size (x, y, z): %.3f, %.3f, %.3f" % size)
if abs(size[1] - 1.607) > 0.1 or abs(size[0] - 0.630) > 0.1 or abs(size[2] - 0.450) > 0.1:
    raise RuntimeError("The model isn't the size or orientation this script expects: %s. "
                       "Please send Claude this message." % (size,))

# ---------------------------------------------------------------- 2. merge seam duplicates
before = len(liz.data.vertices)
bm = bmesh.new(); bm.from_mesh(liz.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
bm.to_mesh(liz.data); bm.free()
liz.data.update()
log("Vertices: %d -> %d after merging texture-seam duplicates" % (before, len(liz.data.vertices)))

# ---------------------------------------------------------------- 3. skeleton
for o in list(bpy.data.objects):
    if o.name.startswith("LizardRig"):
        bpy.data.objects.remove(o, do_unlink=True)
arm_data = bpy.data.armatures.new("LizardRig")
arm = bpy.data.objects.new("LizardRig", arm_data)
bpy.context.scene.collection.objects.link(arm)
arm.show_in_front = True
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones

def bone(name, head, tail, parent=None, connect=False):
    b = eb.new(name)
    b.head = B(head); b.tail = B(tail)
    if parent:
        b.parent = eb[parent]
        b.use_connect = connect
    return b

# Body: pelvis -> spine -> neck -> head
bone("Pelvis", SPINE[0], SPINE[1])
names = ["Spine1", "Spine2", "Spine3", "Neck1", "Neck2"]
for i, n in enumerate(names):
    bone(n, SPINE[i + 1], SPINE[i + 2], parent=("Pelvis" if i == 0 else names[i - 1]), connect=True)
bone("Head", SPINE[-1], HEAD_TIP, parent="Neck2", connect=True)

# Tail: 18 bones from the pelvis back to the tip
for i in range(len(TAIL) - 1):
    n = "Tail%02d" % (i + 1)
    bone(n, TAIL[i], TAIL[i + 1], parent=("Pelvis" if i == 0 else "Tail%02d" % i), connect=(i > 0))

# Legs: three bones each. Back legs hang from the pelvis, front legs from Spine3 (the chest).
for side in ("L", "R"):
    bone("Thigh." + side, *LEGS["Thigh." + side], parent="Pelvis")
    bone("Shin." + side, *LEGS["Shin." + side], parent="Thigh." + side, connect=True)
    bone("Foot." + side, *LEGS["Foot." + side], parent="Shin." + side, connect=True)
    bone("UpperArm." + side, *LEGS["UpperArm." + side], parent="Spine3")
    bone("Forearm." + side, *LEGS["Forearm." + side], parent="UpperArm." + side, connect=True)
    bone("Hand." + side, *LEGS["Hand." + side], parent="Forearm." + side, connect=True)

bone_count = len(eb)
bpy.ops.object.mode_set(mode='OBJECT')
log("Skeleton: %d bones (pelvis, 3 spine, 2 neck, head, 18 tail, 12 leg)" % bone_count)

# ---------------------------------------------------------------- 4. skin
bpy.ops.object.select_all(action='DESELECT')
liz.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
try:
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
except Exception as e:
    log("Automatic weights reported a problem: %s" % e)
    if liz.parent is not arm:
        bpy.ops.object.parent_set(type='ARMATURE_NAME')

# Make sure every bone has a vertex group, then repair vertices with no weight
# by giving them to the nearest bone.
for b in arm.data.bones:
    if liz.vertex_groups.get(b.name) is None:
        liz.vertex_groups.new(name=b.name)
segments = [(liz.vertex_groups[b.name].index, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local)
            for b in arm.data.bones]

def nearest_group(p):
    best, best_d = None, 1e9
    for gi, a, c in segments:
        ab = c - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
        d = (a + ab * t - p).length
        if d < best_d:
            best, best_d = gi, d
    return best

fixed = 0
for v in liz.data.vertices:
    if not any(g.weight > 0.0 for g in v.groups):
        liz.vertex_groups[nearest_group(liz.matrix_world @ v.co)].add([v.index], 1.0, 'REPLACE')
        fixed += 1
log("Vertices with no bone, repaired: %d" % fixed)

# Keep at most 4 bones per vertex and make the weights add up to 1 (needed by glTF/USD).
trimmed = 0
for v in liz.data.vertices:
    gs = sorted([(g.group, g.weight) for g in v.groups if g.weight > 0.0], key=lambda t: -t[1])
    if len(gs) > 4:
        for gi, _ in gs[4:]:
            liz.vertex_groups[gi].remove([v.index])
        gs = gs[:4]; trimmed += 1
    total = sum(w for _, w in gs)
    if total > 0:
        for gi, w in gs:
            liz.vertex_groups[gi].add([v.index], w / total, 'REPLACE')
log("Vertices trimmed to 4 bones: %d" % trimmed)

# ---------------------------------------------------------------- 5. textures
for img in bpy.data.images:
    if img.size[0] > 2048 or img.size[1] > 2048:
        old = tuple(img.size)
        img.scale(2048, 2048)
        try:
            img.pack()
        except Exception as e:
            log("Couldn't repack %s: %s" % (img.name, e))
        log("Texture %s: %dx%d -> 2048x2048" % (img.name, old[0], old[1]))

# ---------------------------------------------------------------- 6. save
out = os.path.expanduser("~/Downloads/MonitorLizardRig")
os.makedirs(out, exist_ok=True)
bpy.ops.object.select_all(action='DESELECT')
liz.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active = arm

glb = os.path.join(out, "MonitorLizard_rigged.glb")

def run_export(op, path, option_sets):
    """Try export options from most to least specific (option names vary between Blender versions)."""
    last = None
    for opts in option_sets:
        try:
            op(filepath=path, **opts)
            return True
        except TypeError as e:          # an option name this Blender version doesn't know
            last = e
    raise RuntimeError(last)

base = dict(export_format='GLB', use_selection=True, export_skins=True, export_animations=False)
run_export(bpy.ops.export_scene.gltf, glb, [
    dict(base, export_image_format='JPEG', export_image_quality=90),
    dict(base, export_image_format='JPEG', export_jpeg_quality=90),
    dict(base, export_image_format='JPEG'),
    base,
    dict(export_format='GLB', use_selection=True),
])
log("Saved %s (%.1f MB)" % (glb, os.path.getsize(glb) / 1e6))

usdz = os.path.join(out, "MonitorLizard_rigged.usdz")
try:
    run_export(bpy.ops.wm.usd_export, usdz, [
        dict(selected_objects_only=True, export_animation=False, export_armatures=True,
             export_materials=True, generate_preview_surface=True),
        dict(selected_objects_only=True, export_armatures=True),
        dict(selected_objects_only=True),
    ])
    log("Saved %s (%.1f MB)" % (usdz, os.path.getsize(usdz) / 1e6))
except Exception as e:
    log("USDZ export didn't work (the GLB is enough for now): %s" % e)

blend = os.path.join(out, "MonitorLizard_rig.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend)
log("Saved %s" % blend)
log("DONE. Send Claude the GLB file and this report.")

# ---------------------------------------------------------------- 7. report
txt = bpy.data.texts.get("Rig Report") or bpy.data.texts.new("Rig Report")
txt.clear(); txt.write("\n".join(REPORT))
def draw(self, context):
    for line in REPORT:
        self.layout.label(text=line)
bpy.context.window_manager.popup_menu(draw, title="Monitor Lizard rig", icon='ARMATURE_DATA')
