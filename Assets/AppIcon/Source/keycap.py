"""Renders the Keyflow app icon: one graphite Command keycap.

Run with Blender (5.x):
    Blender -b --factory-startup --python keycap.py -- <legend.png> <out.png> [resolution] [samples] [lens] [mode]

mode "key" (default): the key alone on a transparent background, its shadow
from a shadow catcher. mode "deck": the key resting on a satin aluminium
keyboard deck that fills the frame; icontool clips it to the macOS icon shape.

The key is modelled from its cross-section: a rounded-rectangle footprint
that tapers up the sides, turns over a rounded top edge and dips into a
shallow spherical dish. The legend texture (from legend.swift) covers the
footprint, model x and y from -1 to 1, and is printed onto the top through a
planar UV. The background is transparent; the floor is a shadow catcher, so
only the key and its soft shadow remain.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
LEGEND, OUT = argv[0], argv[1]
RES = int(argv[2]) if len(argv) > 2 else 2048
SAMPLES = int(argv[3]) if len(argv) > 3 else 512
LENS = float(argv[4]) if len(argv) > 4 else 208
MODE = argv[5] if len(argv) > 5 else "key"

# Shape, in model units (the footprint is 2 × 2).
HALF = 1.0          # half the footprint width
HEIGHT = 0.50       # keycap height
TAPER = 0.10        # how far the sides lean in
EDGE = 0.11         # radius of the rounded top edge
CORNER = 0.34       # footprint corner radius
DISH = 0.028        # depth of the concave top
CORNER_STEPS = 24

scene = bpy.context.scene
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)


def rounded_rect(half, radius):
    """Points around a rounded square, the same count for every size."""
    points = []
    c = half - radius
    for cx, cy, start in ((c, -c, -90), (c, c, 0), (-c, c, 90), (-c, -c, 180)):
        for i in range(CORNER_STEPS + 1):
            a = math.radians(start + 90 * i / CORNER_STEPS)
            points.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return points


def build_keycap():
    rings = []   # (half, radius, z)
    # Sides: lean in from the footprint to where the top edge starts.
    for i in range(7):
        t = i / 6
        inset = TAPER * t
        rings.append((HALF - inset, CORNER - inset * 0.6, (HEIGHT - EDGE) * t))
    # Rounded top edge: a quarter turn from the side onto the top.
    side_half, side_radius = HALF - TAPER, CORNER - TAPER * 0.6
    for i in range(1, 17):
        a = math.radians(90 * i / 16)
        inset = EDGE * (1 - math.cos(a))
        rings.append((side_half - inset, side_radius - inset * 0.6, HEIGHT - EDGE + EDGE * math.sin(a)))
    # Top: a shallow spherical dish, scaled copies of the edge's last ring.
    top_half, top_radius = rings[-1][0], rings[-1][1]
    steps = 28
    for i in range(1, steps):
        f = 1 - (i / steps) ** 1.35
        rings.append((top_half * f, top_radius * f, HEIGHT - DISH * (1 - f * f)))

    mesh = bpy.data.meshes.new("Keycap")
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    loops = []
    for half, radius, z in rings:
        loops.append([bm.verts.new((x, y, z)) for x, y in rounded_rect(half, max(radius, 0.001))])
    count = len(loops[0])
    for lower, upper in zip(loops, loops[1:]):
        for j in range(count):
            k = (j + 1) % count
            bm.faces.new((lower[j], lower[k], upper[k], upper[j]))
    centre = bm.verts.new((0, 0, HEIGHT - DISH))
    for j in range(count):
        bm.faces.new((loops[-1][j], loops[-1][(j + 1) % count], centre))
    bottom = bm.faces.new(list(reversed(loops[0])))
    bottom.smooth = False
    for face in bm.faces:
        if face is not bottom:
            face.smooth = True
        for loop in face.loops:
            x, y, _ = loop.vert.co
            loop[uv].uv = ((x + 1) / 2, (y + 1) / 2)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Keycap", mesh)
    scene.collection.objects.link(obj)
    return obj


def keycap_material():
    mat = bpy.data.materials.new("Graphite")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    # Body darker, top a little lighter: blended by how much a face points up.
    geometry = nodes.new("ShaderNodeNewGeometry")
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geometry.outputs["Normal"], split.inputs[0])
    facing = nodes.new("ShaderNodeMapRange")
    facing.inputs["From Min"].default_value = 0.55
    facing.inputs["From Max"].default_value = 0.97
    links.new(split.outputs["Z"], facing.inputs["Value"])
    body = nodes.new("ShaderNodeMix")
    body.data_type = "RGBA"
    body.inputs["A"].default_value = (0.021, 0.022, 0.026, 1)   # deep graphite sides
    body.inputs["B"].default_value = (0.033, 0.035, 0.040, 1)   # lighter top
    links.new(facing.outputs["Result"], body.inputs["Factor"])

    # Printed legend.
    coords = nodes.new("ShaderNodeTexCoord")
    image = nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(LEGEND)
    image.interpolation = "Cubic"
    image.extension = "CLIP"
    links.new(coords.outputs["UV"], image.inputs["Vector"])
    legend = nodes.new("ShaderNodeMix")
    legend.data_type = "RGBA"
    legend.inputs["B"].default_value = (0.74, 0.745, 0.75, 1)  # soft off-white
    links.new(body.outputs["Result"], legend.inputs["A"])
    links.new(image.outputs["Alpha"], legend.inputs["Factor"])
    links.new(legend.outputs["Result"], bsdf.inputs["Base Color"])

    rough = nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.45   # satin, not gloss
    rough.inputs["To Max"].default_value = 0.6   # legends a little flatter
    links.new(image.outputs["Alpha"], rough.inputs["Value"])
    links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    bsdf.inputs["Specular IOR Level"].default_value = 0.45

    # A very fine satin grain, barely there.
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 900
    noise.inputs["Detail"].default_value = 2
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.012
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def area(name, location, size, energy, color=(1, 1, 1), target=(0, 0, 0.25), shadows=True):
    light = bpy.data.lights.new(name, "AREA")
    light.use_shadow = shadows
    light.shape = "DISK"
    light.size = size
    light.energy = energy
    light.color = color
    obj = bpy.data.objects.new(name, light)
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(obj)


def world():
    w = bpy.data.worlds.new("Studio")
    scene.world = w
    w.use_nodes = True
    nodes, links = w.node_tree.nodes, w.node_tree.links
    background = nodes["Background"]
    # A soft studio gradient for reflections: dark below, brighter overhead.
    coords = nodes.new("ShaderNodeTexCoord")
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coords.outputs["Generated"], split.inputs[0])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45
    ramp.color_ramp.elements[0].color = (0.004, 0.0045, 0.006, 1)
    ramp.color_ramp.elements[1].position = 1.0
    top = (0.11, 0.12, 0.14, 1) if MODE == "key" else (0.2, 0.21, 0.23, 1)   # the deck reflects more sky
    ramp.color_ramp.elements[1].color = top
    links.new(split.outputs["Z"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], background.inputs["Color"])
    background.inputs["Strength"].default_value = 1.0


keycap = build_keycap()
keycap.data.materials.append(keycap_material())

def aluminium():
    """Bead-blasted, anodised aluminium: a soft silver, never mirror-like."""
    mat = bpy.data.materials.new("Aluminium")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.62, 0.64, 0.67, 1)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.42
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1400
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.02
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


if MODE == "deck":
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    bpy.context.active_object.data.materials.append(aluminium())
else:
    bpy.ops.mesh.primitive_plane_add(size=9, location=(0, 0, 0))
    bpy.context.active_object.is_shadow_catcher = True

# Key light high above and behind on the left, so the top reads clearly and
# the shadow falls softly down the icon; a cool rim from behind on the right
# outlines the key on dark backgrounds; a weak fill opens up the front.
area("Key", (-2.6, 3.2, 7.5), 4.5, 470)
area("Rim", (4.2, 4.8, 1.8), 3.0, 160, color=(0.82, 0.89, 1.0), shadows=False)
area("Fill", (1.0, -7.0, 3.2), 6.0, 130, color=(0.95, 0.97, 1.0), shadows=False)
world()

# A long lens from a gentle three-quarter view: mostly the top, some of the
# front, a little of the right side.
camera_data = bpy.data.cameras.new("Camera")
camera_data.lens = 100
camera = bpy.data.objects.new("Camera", camera_data)
elevation, azimuth, distance = math.radians(55), math.radians(13), 16.0
target = Vector((0.0, -0.06, 0.18))
camera.location = target + distance * Vector((math.sin(azimuth) * math.cos(elevation),
                                              -math.cos(azimuth) * math.cos(elevation),
                                              math.sin(elevation)))
camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.sensor_width = 36
camera_data.sensor_fit = "HORIZONTAL"
camera_data.lens = LENS

render = scene.render
render.engine = "CYCLES"
render.resolution_x = render.resolution_y = RES
render.film_transparent = True
render.image_settings.file_format = "PNG"
render.image_settings.color_mode = "RGBA"
render.image_settings.color_depth = "16"
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.device = "GPU"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "METAL"
prefs.get_devices()
for device in prefs.devices:
    device.use = True

render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("rendered", OUT)
