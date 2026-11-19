#!/usr/bin/env python3
"""Static checker for the GDScript sources of this project.

There is no Godot engine in the authoring sandbox, so this script stands in for the editor's parser and
catches the mistakes that normally show up as red errors in the script editor:

  * unbalanced brackets, mixed indentation, missing ':' on block headers, dangling elif/else
  * names that resolve to nothing (typos, forgotten declarations, wrong class names)
  * duplicate declarations (functions, members, locals shadowing locals of an enclosing block)
  * calls with the wrong number of arguments (own functions, ClassName.static(), Class.new(), signals)
  * members that do not exist on our own classes (typed variables, ClassName.member, world.member)
  * instance members used from a static function
  * `:=` with a right-hand side the GDScript analyzer cannot infer (Variant results)
  * Godot 3 leftovers, lambdas, missing res:// resources
  * a report of every engine member the code touches, grouped by engine type (to eyeball against the docs)

Usage:  python3 tools/check_gd.py [--api] [--quiet]
Exit code 1 when an error is found.
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gdtypes  # noqa: E402

# ======================================================================== tokenizer
TOK = re.compile(r'''
 (?P<ws>[ \t\r]+)
|(?P<comment>\#[^\n]*)
|(?P<str>[&^]?r?(?:"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'))
|(?P<num>0x[0-9a-fA-F_]+|0b[01_]+|\d[\d_]*(?:\.(?!\.)[\d_]*)?(?:[eE][+-]?\d+)?|\.\d[\d_]*(?:[eE][+-]?\d+)?)
|(?P<id>[A-Za-z_][A-Za-z_0-9]*)
|(?P<at>@[A-Za-z_]+)
|(?P<op>:=|->|==|!=|<=|>=|&&|\|\||<<=|>>=|<<|>>|\*\*=|\*\*|\+=|-=|\*=|/=|%=|&=|\|=|\^=|\.\.|[-+*/%=<>!&|^~.,:;()\[\]{}$?])
''', re.X)

OPEN = {"(": ")", "[": "]", "{": "}"}
CLOSE = {v: k for k, v in OPEN.items()}


class Line:
    __slots__ = ("no", "indent", "toks", "raw")

    def __init__(self, no, indent, toks, raw):
        self.no, self.indent, self.toks, self.raw = no, indent, toks, raw

    @property
    def first(self):
        return self.toks[0][1] if self.toks else ""


class Report:
    def __init__(self):
        self.errors = []
        self.warns = []

    def err(self, f, no, msg):
        self.errors.append("%s:%d: %s" % (f, no, msg))

    def warn(self, f, no, msg):
        self.warns.append("%s:%d: %s" % (f, no, msg))


def read_lines(path, rep, rel):
    text = open(path, encoding="utf-8").read()
    if "\r" in text:
        rep.err(rel, 1, "CRLF line endings")
    lines = []
    depth = 0
    stack = []
    cur = None
    cont = False
    for no, raw in enumerate(text.split("\n"), 1):
        body = raw.rstrip("\r")
        m = re.match(r"[ \t]*", body)
        lead = m.group(0)
        pos = len(lead)
        toks = []
        while pos < len(body):
            mm = TOK.match(body, pos)
            if not mm:
                rep.err(rel, no, "cannot tokenize near %r" % body[pos:pos + 12])
                break
            pos = mm.end()
            k = mm.lastgroup
            if k in ("ws", "comment"):
                continue
            toks.append((k, mm.group(0)))
        if cur is None:
            if not toks:
                continue
            if " " in lead:
                rep.err(rel, no, "spaces in indentation")
            cur = Line(no, lead.count("\t"), [], body)
            stack = []
        for k, t in toks:
            cur.toks.append((k, t))
            if k == "op":
                if t in OPEN:
                    stack.append((t, no))
                elif t in CLOSE:
                    if not stack or stack[-1][0] != CLOSE[t]:
                        rep.err(rel, no, "unbalanced %r" % t)
                    else:
                        stack.pop()
        cont = body.rstrip().endswith("\\")
        if not stack and not cont:
            lines.append(cur)
            cur = None
    if stack:
        rep.err(rel, stack[-1][1], "unclosed %r" % stack[-1][0])
    return lines


# ======================================================================== knowledge tables
KEYWORDS = set("""if elif else for while match break continue pass return class class_name extends is in as self
signal func static const enum var breakpoint preload await assert void and or not true false null super when""".split())
GLOBAL_CONSTS = {"PI", "TAU", "INF", "NAN"}
UTILITY = set("""abs absf absi acos asin atan atan2 bezier_derivative bezier_interpolate bytes_to_var ceil ceilf ceili
clamp clampf clampi cos cosh cubic_interpolate db_to_linear deg_to_rad ease error_string exp floor floorf floori fmod
fposmod hash instance_from_id inverse_lerp is_equal_approx is_finite is_inf is_instance_id_valid is_instance_valid
is_nan is_same is_zero_approx lerp lerp_angle lerpf linear_to_db log max maxf maxi min minf mini move_toward
nearest_po2 pingpong posmod pow print print_debug print_rich printerr printraw prints printt push_error push_warning
rad_to_deg rand_from_seed randf randf_range randfn randi randi_range randomize remap round roundf roundi seed
sign signf signi sin sinh smoothstep snapped snappedf snappedi sqrt step_decimals str str_to_var tan tanh
type_convert type_string typeof var_to_bytes var_to_str weakref wrap wrapf wrapi load preload len range int float
bool char ord assert""".split())
# utility functions whose static return type is Variant -> `:=` cannot infer from them
VARIANT_FUNCS = {"abs", "clamp", "min", "max", "lerp", "sign", "snapped", "wrap", "round", "floor", "ceil", "load",
                 "smoothstep_v", "remap_v"}
AUTOLOADS = {}

# Godot 3 leftovers and other things that do not exist in Godot 4
G3 = [
    (r"\byield\b", "yield (use await)"), (r"\bonready var\b", "onready (use @onready)"),
    (r"\bexport var\b", "export var (use @export)"), (r"\bsetget\b", "setget"),
    (r"\bKinematicBody", "KinematicBody"), (r"\bSpatial\b", "Spatial (Node3D)"),
    (r"\.instance\(\)", ".instance() (instantiate)"), (r"\brand_range\(", "rand_range (randf_range)"),
    (r"\bdeg2rad\(|\brad2deg\(", "deg2rad/rad2deg"), (r"\bstepify\(", "stepify (snapped)"),
    (r"\bOS\.get_ticks_msec", "OS.get_ticks_msec (Time.get_ticks_msec)"),
    (r"\.translation\b", ".translation (position)"), (r"\bPool\w+Array\b", "Pool*Array (Packed*Array)"),
    (r"\bQuat\b", "Quat (Quaternion)"), (r"\bTransform\b(?!2D|3D)", "Transform (Transform3D)"),
    (r"\bconnect\(\s*\"", "connect(\"signal\", ...) Godot 3 style"),
    (r"\bTween\.new\(\)", "Tween.new() (use create_tween)"), (r"\bget_tree\(\)\.change_scene\(", "change_scene"),
    (r"\.interpolate_property\(", "interpolate_property"), (r"\bfuncref\(", "funcref"),
    (r"\bRigidBody\b(?!3D)", "RigidBody (RigidBody3D)"), (r"\bArea\b(?!2D|3D)", "Area (Area3D)"),
    (r"\bMeshInstance\b(?!2D|3D)", "MeshInstance (MeshInstance3D)"), (r"\bSpatialMaterial\b", "SpatialMaterial"),
    (r"\bis_on_floor\(\)\s*==", ""), (r"\bmove_and_slide\([^)]+\)", "move_and_slide(args) (no args in Godot 4)"),
    (r"\bVisibilityNotifier", "VisibilityNotifier"), (r"\bCPUParticles\b", "CPUParticles"),
    (r"\bParticles\b", "Particles (GPUParticles3D)"), (r"\bwait_frames\b", "wait_frames"),
    (r"\.rect_(position|size|min_size|scale|rotation|pivot_offset)\b", ".rect_* (Godot 3 Control properties)"),
    (r"\bmargin_(left|right|top|bottom)\b", "margin_* (offset_*)"),
    (r"\bAnimationPlayer\.\w*PLAYBACK", "")]
G3 = [(re.compile(a), b) for a, b in G3 if b]

# names inherited from engine base classes that are bare-accessible inside our scripts (generous union)
ENGINE_NAMES = set("""
get set call callv call_deferred set_deferred connect disconnect is_connected emit_signal has_method has_signal
get_class is_class get_instance_id get_meta set_meta has_meta get_script set_script notification free to_string
get_property_list get_signal_list get_method_list is_queued_for_deletion cancel_free
name owner process_mode process_priority physics_process_priority get_tree get_parent get_child get_children
get_child_count add_child remove_child reparent add_to_group remove_from_group is_in_group get_node get_node_or_null
has_node find_child find_children queue_free set_process set_physics_process set_process_input set_process_unhandled_input
set_process_unhandled_key_input is_inside_tree get_viewport get_window get_path move_child get_index ready tree_entered
tree_exiting tree_exited child_entered_tree child_exiting_tree is_node_ready get_tree_string set_physics_process_internal
is_physics_processing is_processing can_process get_process_delta_time get_physics_process_delta_time set_name
add_sibling get_groups get_scene_file_path scene_file_path unique_name_in_owner
PROCESS_MODE_INHERIT PROCESS_MODE_PAUSABLE PROCESS_MODE_WHEN_PAUSED PROCESS_MODE_ALWAYS PROCESS_MODE_DISABLED
NOTIFICATION_APPLICATION_PAUSED NOTIFICATION_APPLICATION_RESUMED NOTIFICATION_APPLICATION_FOCUS_OUT
NOTIFICATION_APPLICATION_FOCUS_IN NOTIFICATION_PREDELETE NOTIFICATION_WM_GO_BACK_REQUEST NOTIFICATION_WM_CLOSE_REQUEST
NOTIFICATION_READY NOTIFICATION_ENTER_TREE NOTIFICATION_EXIT_TREE NOTIFICATION_RESIZED NOTIFICATION_VISIBILITY_CHANGED
NOTIFICATION_WM_SIZE_CHANGED NOTIFICATION_PAUSED NOTIFICATION_UNPAUSED NOTIFICATION_TRANSFORM_CHANGED
_ready _process _physics_process _input _unhandled_input _unhandled_key_input _notification _enter_tree _exit_tree
_draw _gui_input _init _get_minimum_size _to_string _can_drop_data _get_drag_data _drop_data _has_point _make_custom_tooltip
position rotation rotation_degrees scale transform basis global_position global_rotation global_rotation_degrees
global_transform quaternion visible top_level show hide is_visible_in_tree look_at look_at_from_position rotate
rotate_x rotate_y rotate_z rotate_object_local translate translate_object_local global_translate to_local to_global
get_global_transform set_global_position get_global_position orthonormalize scale_object_local global_scale
visibility_parent visibility_changed rotation_edit_mode rotation_order set_identity
collision_layer collision_mask set_collision_layer_value set_collision_mask_value get_collision_layer_value
get_collision_mask_value shape_owner_add_shape create_shape_owner shape_owner_set_transform shape_owner_get_shape
body_entered body_exited area_entered area_exited body_shape_entered monitoring monitorable get_overlapping_bodies
get_overlapping_areas overlaps_body overlaps_area has_overlapping_bodies has_overlapping_areas priority gravity
gravity_space_override linear_damp angular_damp linear_damp_space_override input_ray_pickable input_event
mouse_entered mouse_exited physics_material_override constant_linear_velocity constant_angular_velocity
sync_to_physics velocity up_direction floor_stop_on_slope floor_max_angle floor_snap_length motion_mode
wall_min_slide_angle max_slides platform_on_leave platform_floor_layers platform_wall_layers
move_and_slide is_on_floor is_on_wall is_on_ceiling is_on_floor_only get_floor_normal get_wall_normal
get_slide_collision get_slide_collision_count get_last_motion get_position_delta get_real_velocity
get_platform_velocity get_last_slide_collision apply_floor_snap move_and_collide test_move safe_margin
global_position
size custom_minimum_size anchor_left anchor_right anchor_top anchor_bottom offset_left offset_right offset_top
offset_bottom pivot_offset modulate self_modulate mouse_filter focus_mode clip_contents layout_direction material
z_index z_as_relative show_behind_parent queue_redraw draw_string draw_rect draw_line draw_circle draw_arc
draw_polygon draw_colored_polygon draw_polyline draw_texture draw_texture_rect draw_set_transform draw_style_box
draw_multiline draw_primitive draw_char draw_string_outline draw_polyline_colors draw_set_transform_matrix
get_global_mouse_position get_local_mouse_position theme add_theme_color_override add_theme_font_override
add_theme_font_size_override add_theme_constant_override add_theme_stylebox_override add_theme_icon_override
set_anchors_preset set_anchors_and_offsets_preset set_offsets_preset grab_focus release_focus has_focus get_rect
get_global_rect size_flags_horizontal size_flags_vertical text_direction texture_filter texture_repeat
use_parent_material light_mask visibility_layer set_position set_size set_scale set_rotation set_pivot_offset
set_modulate get_size get_minimum_size get_combined_minimum_size grow_horizontal grow_vertical
anchors_preset mouse_default_cursor_shape tooltip_text focus_entered focus_exited resized gui_input mouse_entered
mouse_exited item_rect_changed minimum_size_changed draw hidden visibility_changed accept_event
focus_neighbor_left focus_neighbor_right focus_neighbor_top focus_neighbor_bottom focus_next focus_previous
is_visible get_global_transform_with_canvas get_canvas_transform get_viewport_rect get_screen_transform
text horizontal_alignment vertical_alignment label_settings autowrap_mode uppercase visible_characters
visible_ratio lines_skipped max_lines_visible text_overrun_behavior clip_text ellipsis_char language
vertical_alignment justification_flags get_line_count get_line_height get_total_character_count
mesh material_override material_overlay cast_shadow gi_mode extra_cull_margin lod_bias skeleton surface_get_material
set_surface_override_material get_surface_override_material get_active_material create_trimesh_collision
set_instance_shader_parameter get_instance_shader_parameter transparency custom_aabb get_aabb ignore_occlusion_culling
visibility_range_begin visibility_range_end sorting_offset get_mesh set_mesh gi_lightmap_scale
multimesh instance_count visible_instance_count transform_format use_colors use_custom_data
set_instance_transform set_instance_color set_instance_custom_data get_instance_transform buffer
emitting amount lifetime one_shot preprocess speed_scale explosiveness randomness fixed_fps interpolate
fract_delta visibility_aabb local_coords draw_order process_material draw_pass_1 restart finished
trail_enabled trail_lifetime collision_base_size transform_align draw_passes
current fov size near far keep_aspect projection h_offset v_offset cull_mask environment attributes doppler_tracking
make_current clear_current is_position_behind unproject_position project_position project_ray_origin
project_ray_normal get_frustum get_camera_transform get_camera_rid get_camera_projection set_perspective
set_orthogonal set_frustum
light_color light_energy light_indirect_energy light_volumetric_fog_energy light_negative light_specular
light_bake_mode light_cull_mask shadow_enabled shadow_bias shadow_normal_bias shadow_blur shadow_transmittance_bias
directional_shadow_mode directional_shadow_max_distance directional_shadow_split_1 directional_shadow_split_2
directional_shadow_split_3 directional_shadow_blend_splits directional_shadow_fade_start omni_range omni_attenuation
omni_shadow_mode spot_range spot_angle spot_attenuation spot_angle_attenuation sky_mode editor_only
shape disabled debug_color debug_fill
radius height top_radius bottom_radius radial_segments rings is_hemisphere cap_top cap_bottom
shape_owner_set_disabled size_changed
text_changed pressed button_down button_up toggled button_pressed toggle_mode
value min_value max_value step value_changed drag_started drag_ended ratio
stream stream_paused play stop playing autoplay bus volume_db pitch_scale max_distance unit_size
finished seek get_playback_position panning_strength
song_selected
create_tween get_world_3d layer follow_viewport_enabled follow_viewport_scale offset rotation transform canvas_layer
set_deferred get_process_delta_time
""".split())

# engine classes we accept (anything uppercase that is not ours and not here is reported)
ENGINE_CLASSES = set("""
Object RefCounted Resource Node Node2D Node3D Control CanvasItem CanvasLayer Window Viewport SubViewport
SubViewportContainer Camera3D Camera2D Area3D Area2D StaticBody3D RigidBody3D CharacterBody3D AnimatableBody3D
CollisionShape3D CollisionObject3D PhysicsBody3D CapsuleShape3D SphereShape3D BoxShape3D CylinderShape3D
ConvexPolygonShape3D ConcavePolygonShape3D WorldBoundaryShape3D Shape3D RayCast3D ShapeCast3D
MeshInstance3D MultiMeshInstance3D MultiMesh Mesh ArrayMesh PrimitiveMesh BoxMesh SphereMesh CylinderMesh CapsuleMesh
PlaneMesh QuadMesh TorusMesh PrismMesh TextMesh RibbonTrailMesh TubeTrailMesh ImmediateMesh SurfaceTool
GeometryInstance3D VisualInstance3D Material StandardMaterial3D BaseMaterial3D ShaderMaterial Shader
ORMMaterial3D CanvasItemMaterial ParticleProcessMaterial GPUParticles3D CPUParticles3D GPUParticlesCollision3D
Environment Sky ProceduralSkyMaterial PanoramaSkyMaterial PhysicalSkyMaterial WorldEnvironment CameraAttributes
CameraAttributesPractical CameraAttributesPhysical FogMaterial FogVolume
DirectionalLight3D OmniLight3D SpotLight3D Light3D ReflectionProbe VoxelGI LightmapGI Decal
AudioStreamPlayer AudioStreamPlayer3D AudioStream AudioStreamWAV AudioStreamOggVorbis AudioStreamMP3
AudioServer AudioEffect AudioEffectReverb AudioEffectLowPassFilter AudioEffectCompressor AudioEffectLimiter
AudioStreamGenerator AudioStreamPlayback AudioBusLayout
Tween Timer SceneTree PackedScene InputEvent InputEventScreenTouch InputEventScreenDrag InputEventKey
InputEventMouse InputEventMouseButton InputEventMouseMotion InputEventAction InputEventJoypadButton
InputEventJoypadMotion InputMap Input
OS Engine ProjectSettings DisplayServer RenderingServer PhysicsServer3D Time JSON FileAccess DirAccess
ResourceLoader ResourceSaver ClassDB Performance Marshalls Crypto
Label Button TextureButton CheckButton CheckBox LinkButton OptionButton MenuButton Panel PanelContainer ColorRect
TextureRect NinePatchRect ProgressBar TextureProgressBar HSlider VSlider Slider Range ScrollContainer
VBoxContainer HBoxContainer BoxContainer GridContainer MarginContainer CenterContainer AspectRatioContainer
Container FlowContainer HFlowContainer VFlowContainer SplitContainer HSplitContainer VSplitContainer
RichTextLabel LineEdit TextEdit Control Line2D Polygon2D Sprite2D Sprite3D Label3D
StyleBox StyleBoxFlat StyleBoxEmpty StyleBoxTexture StyleBoxLine Theme Font FontFile FontVariation SystemFont
Texture Texture2D ImageTexture GradientTexture1D GradientTexture2D NoiseTexture2D NoiseTexture3D
CompressedTexture2D AtlasTexture CurveTexture Gradient Curve Image FastNoiseLite Noise
Vector2 Vector2i Vector3 Vector3i Vector4 Vector4i Color Rect2 Rect2i AABB Plane Quaternion Basis Transform2D
Transform3D Projection Callable Signal StringName NodePath RID Array Dictionary String PackedByteArray
PackedInt32Array PackedInt64Array PackedFloat32Array PackedFloat64Array PackedStringArray PackedVector2Array
PackedVector3Array PackedColorArray PackedVector4Array
Mutex Thread Semaphore RandomNumberGenerator Expression RegEx RegExMatch EditorPlugin Script GDScript
Shortcut ButtonGroup ConfigFile WorkerThreadPool Geometry3D Geometry2D TextServer TextLine TextParagraph
Marker3D Path3D PathFollow3D Curve3D Skeleton3D BoneAttachment3D AnimationPlayer Animation AnimationTree
NavigationRegion3D NavigationAgent3D NavigationServer3D VisibleOnScreenNotifier3D
XRServer SceneTreeTimer SystemFont BitMap ShaderInclude World3D PhysicsDirectSpaceState3D
PhysicsRayQueryParameters3D PhysicsShapeQueryParameters3D PhysicsPointQueryParameters3D
KinematicCollision3D HeightMapShape3D SeparationRayShape3D CurveXYZTexture Texture3D
InputEventPanGesture InputEventMagnifyGesture InputEventScreenTouch InputEventWithModifiers
""".split())

# members of builtin value types (Vector3, Color, ...) are not tracked
VALUE_TYPES = set("""Vector2 Vector2i Vector3 Vector3i Vector4 Color Rect2 Rect2i AABB Plane Quaternion Basis
Transform2D Transform3D Projection Callable Signal StringName NodePath RID Array Dictionary String int float bool
PackedByteArray PackedInt32Array PackedFloat32Array PackedStringArray PackedVector2Array PackedVector3Array
PackedColorArray Variant
HorizontalAlignment VerticalAlignment Side Corner Orientation Key MouseButton Error PropertyHint InlineAlignment
JoyButton JoyAxis KeyModifierMask Variant.Type Mesh.PrimitiveType""".split())


# ======================================================================== class registry
class Member:
    def __init__(self, kind, name, line, static=False, params=None, ret=None, vtype=None, nreq=0, nmax=0):
        self.kind, self.name, self.line, self.static = kind, name, line, static
        self.params = params or []
        self.ret, self.vtype = ret, vtype
        self.nreq, self.nmax = nreq, nmax


class ClassInfo:
    def __init__(self, qual, short, file, base, outer=None):
        self.qual, self.short, self.file, self.base = qual, short, file, base
        self.outer = outer
        self.members = {}
        self.signals = {}
        self.inner = {}
        self.body_indent = 0
        self.header_indent = -1


GLOBAL = {}  # class_name -> ClassInfo
ALL = {}  # qualified name -> ClassInfo


def split_top(toks, sep=","):
    out, cur, depth = [], [], 0
    for k, t in toks:
        if k == "op" and t in OPEN:
            depth += 1
        elif k == "op" and t in CLOSE:
            depth -= 1
        if depth == 0 and k == "op" and t == sep:
            out.append(cur)
            cur = []
        else:
            cur.append((k, t))
    if cur or out:
        out.append(cur)
    return [c for c in out if c]


def type_text(toks):
    return "".join(t for _, t in toks)


def parse_type(toks):
    """tokens after ':' up to '=' -> type string or None"""
    out = []
    depth = 0
    for k, t in toks:
        if k == "op" and t in OPEN:
            depth += 1
        elif k == "op" and t in CLOSE:
            depth -= 1
        if depth == 0 and k == "op" and t in ("=", ":="):
            break
        out.append((k, t))
    return type_text(out) if out else None


def parse_func_header(toks):
    """tokens of a `func` line (after optional static) -> (name, params, ret, nreq, nmax, body_tokens)"""
    i = 0
    static = False
    if toks[i][1] == "static":
        static = True
        i += 1
    assert toks[i][1] == "func"
    name = toks[i + 1][1]
    assert toks[i + 2][1] == "("
    depth, j = 0, i + 2
    while j < len(toks):
        if toks[j][0] == "op" and toks[j][1] in OPEN:
            depth += 1
        elif toks[j][0] == "op" and toks[j][1] in CLOSE:
            depth -= 1
            if depth == 0:
                break
        j += 1
    inside = toks[i + 3:j]
    params = []
    nreq = 0
    for part in split_top(inside):
        pname = part[0][1]
        has_default = any(k == "op" and t in ("=", ":=") for k, t in part)
        ptype = None
        if len(part) > 2 and part[1][1] == ":" :
            ptype = parse_type(part[2:])
        params.append((pname, ptype, has_default))
        if not has_default:
            nreq += 1
    ret = None
    rest = toks[j + 1:]
    if rest and rest[0][1] == "->":
        r = []
        for k, t in rest[1:]:
            if k == "op" and t == ":":
                break
            r.append((k, t))
        ret = type_text(r)
        rest = rest[1 + len(r):]
    if rest and rest[0][1] == ":":
        rest = rest[1:]
    return static, name, params, ret, nreq, len(params), rest


def skip_annotations(toks):
    i = 0
    while i < len(toks) and toks[i][0] == "at":
        i += 1
        if i < len(toks) and toks[i][1] == "(":
            depth = 0
            while i < len(toks):
                if toks[i][1] == "(":
                    depth += 1
                elif toks[i][1] == ")":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
    return toks[i:]


def type_known(name, ctx):
    if not name:
        return True
    base = name.split("[")[0]
    if base in ("Array", "Dictionary") or base in VALUE_TYPES or base in ENGINE_CLASSES or base in ("void", "Variant"):
        return True
    if resolve_class(base, ctx) is not None:
        return True
    return False


def pass1(rel, lines, rep):
    """Collect classes and their members."""
    top = ClassInfo(rel, os.path.basename(rel), rel, None)
    top.body_indent = 0
    stack = [top]
    ALL[rel] = top
    for ln in lines:
        while len(stack) > 1 and ln.indent < stack[-1].body_indent:
            stack.pop()
        cls = stack[-1]
        toks = skip_annotations(ln.toks)
        if not toks:
            continue
        w = toks[0][1]
        if ln.indent != cls.body_indent:
            continue
        if w == "class_name" and cls is top:
            top.short = toks[1][1]
            top.qual = toks[1][1]
            GLOBAL[top.short] = top
            ALL[top.qual] = top
        elif w == "extends" and cls is top:
            top.base = type_text(toks[1:]).strip('"')
        elif w == "class":
            name = toks[1][1]
            base = None
            if len(toks) > 3 and toks[2][1] == "extends":
                base = type_text([t for t in toks[3:] if t[1] != ":"])
            ci = ClassInfo(cls.qual + "." + name, name, rel, base, cls)
            ci.body_indent = ln.indent + 1
            ci.header_indent = ln.indent
            cls.inner[name] = ci
            cls.members[name] = Member("class", name, ln.no, True)
            ALL[ci.qual] = ci
            stack.append(ci)
        elif w == "static" and len(toks) > 1 and toks[1][1] == "func" or w == "func":
            static, name, params, ret, nreq, nmax, _ = parse_func_header(toks)
            if name in cls.members and cls.members[name].kind == "func":
                rep.err(rel, ln.no, "function %s already defined" % name)
            cls.members[name] = Member("func", name, ln.no, static, params, ret, None, nreq, nmax)
        elif w in ("var", "static") and (w == "var" or toks[1][1] == "var"):
            j = 1 if w == "var" else 2
            name = toks[j][1]
            static = w == "static"
            vtype = None
            if len(toks) > j + 1 and toks[j + 1][1] == ":":
                vtype = parse_type(toks[j + 2:])
            if name in cls.members and cls.members[name].kind in ("var", "const"):
                rep.err(rel, ln.no, "member %s already declared" % name)
            if name == "world" and vtype == "Node":
                vtype = "GameWorld"  # every level object stores its GameWorld here (declared Node to avoid cycles)
            m = Member("var", name, ln.no, static, vtype=vtype)
            if len(toks) > j + 1 and toks[j + 1][1] == ":=":
                m.vtype = infer_from_rhs(toks[j + 2:], cls)
                m.init_toks = toks[j + 2:]
            cls.members[name] = m
        elif w == "const":
            name = toks[1][1]
            vtype = None
            if len(toks) > 2 and toks[2][1] == ":":
                vtype = parse_type(toks[3:])
            cm = Member("const", name, ln.no, True, vtype=vtype)
            if vtype is None:
                k = next((i for i, (kk, t) in enumerate(toks) if kk == "op" and t in ("=", ":=")), None)
                if k is not None:
                    cm.init_toks = toks[k + 1:]
            cls.members[name] = cm
        elif w == "signal":
            name = toks[1][1]
            params = []
            if len(toks) > 2 and toks[2][1] == "(":
                inside = toks[3:-1]
                params = [p[0][1] for p in split_top(inside)]
            cls.signals[name] = params
            cls.members[name] = Member("signal", name, ln.no, False)
        elif w == "enum":
            # enum Name { A, B } / enum { A, B }
            names = [t for k, t in toks[1:] if k == "id"]
            for n in names:
                cls.members[n] = Member("const", n, ln.no, True)
    return top


def infer_from_rhs(toks, cls):
    """type of `:= expr` when it is obvious: Type.new(...), Type.static(...)"""
    if not toks:
        return None
    # Name(.Name)*.new(
    parts = []
    i = 0
    while i < len(toks) and toks[i][0] == "id":
        parts.append(toks[i][1])
        if i + 1 < len(toks) and toks[i + 1][1] == ".":
            i += 2
        else:
            i += 1
            break
    if not parts or i >= len(toks) or toks[i][1] != "(":
        return None
    if parts[-1] == "new":
        return ".".join(parts[:-1])
    return ("call", ".".join(parts))


# ======================================================================== lookups
def resolve_class(name, cls_ctx):
    """name as written in `var x: Name` / `Name.new()` -> ClassInfo or None."""
    if not name:
        return None
    if name.startswith("Array["):
        return None
    parts = name.split(".")
    base = None
    c = cls_ctx
    while c is not None and base is None:
        if parts[0] in c.inner:
            base = c.inner[parts[0]]
        c = c.outer
    if base is None:
        # sibling inner classes of the file-level class are reachable through the outer chain above;
        # global classes:
        base = GLOBAL.get(parts[0])
    if base is None:
        return None
    for p in parts[1:]:
        base = base.inner.get(p)
        if base is None:
            return None
    return base


def base_class(ci):
    """ClassInfo of the parent script class or None (engine parent)."""
    if not ci.base:
        return None
    return resolve_class(ci.base, ci.outer or ci) if ci.outer or ci.base in GLOBAL else resolve_class(ci.base, ci)


def engine_root(ci):
    seen = 0
    while ci is not None and seen < 20:
        b = base_class(ci)
        if b is None:
            return ci.base or "RefCounted"
        ci = b
        seen += 1
    return "RefCounted"


def find_member(ci, name):
    seen = 0
    while ci is not None and seen < 20:
        if name in ci.members:
            return ci.members[name]
        ci = base_class(ci)
        seen += 1
    return None


def chain_signal(ci, name):
    seen = 0
    while ci is not None and seen < 20:
        if name in ci.signals:
            return ci.signals[name]
        ci = base_class(ci)
        seen += 1
    return None


def count_args(toks, i):
    """toks[i] == '(' -> (argcount, index_of_closing)"""
    depth = 0
    j = i
    n = 0
    seen = False
    while j < len(toks):
        k, t = toks[j]
        if k == "op" and t in OPEN:
            depth += 1
        elif k == "op" and t in CLOSE:
            depth -= 1
            if depth == 0:
                if seen:
                    n += 1
                return n, j
        elif depth == 1 and k == "op" and t == ",":
            n += 1
            seen = False
            j += 1
            continue
        if depth >= 1 and not (depth == 1 and k == "op" and t == "("):
            seen = True
        j += 1
    return n, len(toks) - 1


# ======================================================================== pass 2

class Env:
    """what gdtypes.Infer needs to know about the project"""
    def __init__(self, ck):
        self.ck = ck
        self.engine_classes = ENGINE_CLASSES
        self.autoload_types = AUTOLOAD_CLASSES

    def resolve_class(self, name, cls):
        return resolve_class(name, cls)

    def base_class(self, ci):
        return base_class(ci)

    def find_member(self, ci, name):
        return find_member(ci, name)

    def find_inner(self, ci, name):
        return find_inner(ci, name)

    def type_of_name(self, name, cls, scope):
        return self.ck.type_of_name(name, cls, scope)

    def resolve_call(self, dotted, cls):
        parts = dotted.split(".")
        if len(parts) == 1:
            c = cls
            while c is not None:
                m = find_member(c, parts[0])
                if m is not None and m.kind == "func":
                    return m.ret
                c = c.outer
            return None
        ci = resolve_class(".".join(parts[:-1]), cls)
        if ci is None:
            return None
        m = find_member(ci, parts[-1])
        return m.ret if m is not None and m.kind == "func" else None

    def member_type(self, m, ctx):
        v = m.vtype
        if isinstance(v, tuple):
            return self.resolve_call(v[1], ctx.cls)
        if m.kind == "var" and v is None:
            return None
        return v

    def local_type(self, info, ctx):
        if isinstance(info, tuple):
            return self.resolve_call(info[1], ctx.cls)
        return info

    def func_ret(self, m, ctx):
        return None if m.ret in (None, "void") else m.ret


AUTOLOAD_CLASSES = {}
STATS = [0, 0]

class Checker:
    def __init__(self, rel, lines, top, rep, api):
        self.rel, self.lines, self.top, self.rep, self.api = rel, lines, top, rep, api
        self.flag_assign = []
        self.env = Env(self)
        self.inf = gdtypes.Infer(self.env)
        self.cur_func = None
        self.parse_fail = 0
        self.parse_ok = 0

    def E(self, ln, msg):
        self.rep.err(self.rel, ln.no, msg)

    def W(self, ln, msg):
        self.rep.warn(self.rel, ln.no, msg)

    # ---------------------------------------------------------------- structure
    def run(self):
        lines = self.lines
        top = self.top
        cstack = [top]
        scope = None  # list of (indent, {name: type})
        func = None  # (indent, Member, static)
        match_stack = []
        prev_by_indent = {}
        for idx, ln in enumerate(lines):
            while len(cstack) > 1 and ln.indent < cstack[-1].body_indent:
                cstack.pop()
            cls = cstack[-1]
            toks = skip_annotations(ln.toks)
            if not toks:
                continue
            w = toks[0][1]
            last_colon = toks[-1][1] == ":" and toks[-1][0] == "op"
            self.structure_checks(ln, toks, w, idx, prev_by_indent)
            self.go3_checks(ln)
            if ln.indent == cls.body_indent and (w in ("func", "class") or (w == "static" and len(toks) > 1 and toks[1][1] == "func")):
                if w == "class":
                    nm = toks[1][1]
                    cstack.append(cls.inner[nm])
                    scope = None
                    func = None
                    continue
                static, name, params, ret, nreq, nmax, rest = parse_func_header(toks)
                func = (ln.indent, cls.members[name], static, cls)
                self.cur_func = cls.members[name]
                scope = [(ln.indent, {p[0]: (p[1] or None) for p in params})]
                match_stack = []
                self.check_default_exprs(ln, toks, cls)
                if rest:  # one-liner body
                    self.check_expr(ln, rest, cls, scope, static)
                continue
            if ln.indent == cls.body_indent and (w in ("var", "const", "signal", "enum", "extends", "class_name") or (w == "static" and len(toks) > 1 and toks[1][1] == "var")):
                # member initialisers
                if w in ("var", "const") or w == "static":
                    self.check_member_init(ln, toks, cls)
                func = None
                scope = None
                continue
            if func is None or scope is None:
                if ln.indent > cls.body_indent or toks:
                    # lines outside a function but deeper than class level (continued enum / dict literal)
                    pass
                continue
            # ---------------------------------------------- inside a function body
            while scope and len(scope) > 1 and scope[-1][0] >= ln.indent:
                scope.pop()
            while match_stack and match_stack[-1] >= ln.indent:
                match_stack.pop()
            static = func[2]
            is_pattern = bool(match_stack) and ln.indent == match_stack[-1] + 1 and last_colon and w not in ("if", "for", "while", "match", "else", "elif", "var", "return")
            if is_pattern:
                # match pattern line: `pattern:` or `var x:`
                scope.append((ln.indent, {}))
                self.check_pattern(ln, toks[:-1], cls, scope, static)
                continue
            if w == "var" or w == "const" or (w == "static" and False):
                self.local_decl(ln, toks, cls, scope, static)
                continue
            if w == "for":
                # for name[: Type] in expr:
                name = toks[1][1]
                if self.is_declared(scope, name):
                    self.E(ln, "loop variable %s redeclares an existing local" % name)
                try:
                    k = [t for _, t in toks].index("in")
                except ValueError:
                    self.E(ln, "for without in")
                    continue
                ex = toks[k + 1:-1] if last_colon else toks[k + 1:]
                self.check_expr(ln, ex, cls, scope, static)
                it = self.type_expr(ln, ex, cls, scope, static)
                vt = None
                if it == "int":
                    vt = "int"
                elif ex and ex[0][1] == "range" and len(ex) > 1 and ex[1][1] == "(":
                    vt = "int"
                elif it and it.startswith("Array[") and it.endswith("]"):
                    vt = it[6:-1]
                elif it in gdtypes.PACKED:
                    vt = gdtypes.PACKED[it]
                if toks[2][1] == ":":
                    vt = type_text(toks[3:k])
                if last_colon:
                    scope.append((ln.indent, {name: vt}))
                else:  # one-liner
                    colon = self.find_body_colon(toks)
                    sc2 = scope + [(ln.indent, {name: vt})]
                    self.check_expr(ln, toks[colon + 1:], cls, sc2, static)
                continue
            if w in ("if", "elif", "while"):
                if last_colon:
                    self.check_expr(ln, toks[1:-1], cls, scope, static)
                    self.type_expr(ln, toks[1:-1], cls, scope, static)
                    scope.append((ln.indent, {}))
                else:
                    colon = self.find_body_colon(toks)
                    self.check_expr(ln, toks[1:colon], cls, scope, static)
                    self.type_expr(ln, toks[1:colon], cls, scope, static)
                    self.check_stmt(ln, toks[colon + 1:], cls, scope, static)
                continue
            if w == "else":
                if last_colon:
                    scope.append((ln.indent, {}))
                else:
                    self.check_stmt(ln, toks[2:], cls, scope, static)
                continue
            if w == "match":
                self.check_expr(ln, toks[1:-1], cls, scope, static)
                self.type_expr(ln, toks[1:-1], cls, scope, static)
                scope.append((ln.indent, {}))
                match_stack.append(ln.indent)
                continue
            self.check_stmt(ln, toks, cls, scope, static)
        return


    # ---------------------------------------------------------------- type-lite
    def type_expr(self, ln, toks, cls, scope, static):
        """infer the type of an expression (reporting operator/argument errors); None when unknown"""
        if not toks:
            return None
        try:
            tree = gdtypes.parse_expr(toks)
        except gdtypes.ParseError:
            self.parse_fail += 1
            return None
        self.parse_ok += 1
        ctx = gdtypes.Ctx(self, ln, cls, scope, static, self.cur_func.ret if self.cur_func else None)
        t = self.inf.infer(tree, ctx)
        return t if isinstance(t, str) else None

    def type_assign(self, ln, toks, cls, scope, static):
        """statement with an assignment operator; returns True when handled"""
        k = gdtypes.split_assign(toks)
        if k is None:
            return False
        op = toks[k][1]
        lhs, rhs = toks[:k], toks[k + 1:]
        lt = self.type_expr(ln, lhs, cls, scope, static)
        rt = self.type_expr(ln, rhs, cls, scope, static)
        ctx = gdtypes.Ctx(self, ln, cls, scope, static, None)
        if lt and rt:
            if op == "=":
                if self.inf.assignable(lt, rt, ctx) is False:
                    self.E(ln, "cannot assign '%s' to '%s'" % (rt, lt))
            else:
                r = gdtypes.binop(op[:-1], lt, rt)
                if r == "ERR":
                    self.E(ln, "invalid operands '%s' and '%s' in operator '%s'" % (lt, rt, op))
                elif r and self.inf.assignable(lt, r, ctx) is False:
                    self.E(ln, "result of '%s' has type '%s', cannot assign to '%s'" % (op, r, lt))
        return True

    def find_body_colon(self, toks):
        depth = 0
        for i, (k, t) in enumerate(toks):
            if k == "op" and t in OPEN:
                depth += 1
            elif k == "op" and t in CLOSE:
                depth -= 1
            elif depth == 0 and k == "op" and t == ":":
                return i
        return len(toks) - 1

    # ---------------------------------------------------------------- generic line checks
    def structure_checks(self, ln, toks, w, idx, prev_by_indent):
        last = toks[-1]
        if w in ("if", "elif", "else", "for", "while", "match", "func", "class") or (w == "static" and len(toks) > 1 and toks[1][1] == "func"):
            if not any(k == "op" and t == ":" for k, t in toks):
                self.E(ln, "block header without ':'")
            # next logical line must be indented deeper unless a one-liner
            if last == ("op", ":"):
                nxt = self.lines[idx + 1] if idx + 1 < len(self.lines) else None
                if nxt is None or nxt.indent != ln.indent + 1:
                    self.E(ln, "block header not followed by an indented body")
        if w in ("elif", "else"):
            prev = prev_by_indent.get(ln.indent)
            if prev not in ("if", "elif"):
                self.E(ln, "%s without matching if" % w)
        prev_by_indent[ln.indent] = w
        for d in list(prev_by_indent):
            if d > ln.indent:
                del prev_by_indent[d]
        for q in range(1, len(toks)):
            if toks[q] == ("id", "func") and toks[q - 1][1] != "static":
                self.W(ln, "lambda (func inside an expression)")
                break
        text = " ".join(t for _, t in toks)
        if ";" in [t for _, t in toks]:
            self.W(ln, "semicolon")

    def go3_checks(self, ln):
        raw = ln.raw
        code = re.sub(r"#.*$", "", raw)
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', code)
        for rx, msg in G3:
            if rx.search(code):
                self.E(ln, "Godot 3 / invalid construct: " + msg)

    # ---------------------------------------------------------------- declarations
    def is_declared(self, scope, name):
        for _, d in scope:
            if name in d:
                return True
        return False

    def local_decl(self, ln, toks, cls, scope, static):
        name = toks[1][1]
        rest = toks[2:]
        vt = None
        if rest and rest[0][1] == ":":
            vt = parse_type(rest[1:])
            k = next((i for i, (kk, t) in enumerate(rest) if kk == "op" and t == "="), None)
            rhs = rest[k + 1:] if k is not None else []
        elif rest and rest[0][1] == ":=":
            rhs = rest[1:]
            vt = infer_from_rhs(rhs, cls)
            self.check_infer(ln, rhs, cls, scope)
        elif rest and rest[0][1] == "=":
            rhs = rest[1:]
        else:
            rhs = []
        if rhs:
            self.check_expr(ln, rhs, cls, scope, static)
            rt = self.type_expr(ln, rhs, cls, scope, static)
            ctx = gdtypes.Ctx(self, ln, cls, scope, static, None)
            if rest and rest[0][1] == ":" and vt and rt and self.inf.assignable(vt, rt, ctx) is False:
                self.E(ln, "cannot initialise '%s' (%s) with a value of type '%s'" % (name, vt, rt))
            if rest and rest[0][1] == ":=" and rt and rt != "null":
                vt = rt
        if self.is_declared(scope, name):
            self.E(ln, "local %s is already declared in an enclosing scope" % name)
        scope[-1][1][name] = vt

    def check_member_init(self, ln, toks, cls):
        w = toks[0][1]
        k = next((i for i, (kk, t) in enumerate(toks) if kk == "op" and t in ("=", ":=") and i > 1), None)
        if k is None:
            return
        if toks[k][1] == ":=":
            self.check_infer(ln, toks[k + 1:], cls, [])
        self.check_expr(ln, toks[k + 1:], cls, [(0, {})], True if w in ("const",) else False, member_init=True)
        rt = self.type_expr(ln, toks[k + 1:], cls, [(0, {})], True)
        if toks[k][1] == "=" and rt:
            j = 1 if w in ("var", "const") else 2
            if len(toks) > j + 1 and toks[j + 1][1] == ":":
                dt = parse_type(toks[j + 2:])
                ctx = gdtypes.Ctx(self, ln, cls, [(0, {})], True, None)
                if dt and self.inf.assignable(dt, rt, ctx) is False:
                    self.E(ln, "cannot initialise '%s' (%s) with a value of type '%s'" % (toks[j][1], dt, rt))

    def check_default_exprs(self, ln, toks, cls):
        pass

    def check_pattern(self, ln, toks, cls, scope, static):
        i = 0
        toks = list(toks)
        # bindings: `var x` inside the pattern
        out = []
        while i < len(toks):
            if toks[i][1] == "var" and i + 1 < len(toks):
                scope[-1][1][toks[i + 1][1]] = None
                i += 2
                continue
            out.append(toks[i])
            i += 1
        # `when` guard
        for j, (k, t) in enumerate(out):
            if t == "when":
                out = out[:j] + out[j + 1:]
                break
        self.check_expr(ln, out, cls, scope, static)

    def check_stmt(self, ln, toks, cls, scope, static):
        if not toks:
            return
        w = toks[0][1]
        if w in ("pass", "break", "continue", "breakpoint"):
            return
        if w == "return":
            self.check_expr(ln, toks[1:], cls, scope, static)
            rt = self.type_expr(ln, toks[1:], cls, scope, static)
            fr = self.cur_func.ret if self.cur_func else None
            ctx = gdtypes.Ctx(self, ln, cls, scope, static, None)
            if toks[1:] and fr and fr != "void" and rt and self.inf.assignable(fr, rt, ctx) is False:
                self.E(ln, "returning '%s' from a function declared to return '%s'" % (rt, fr))
            if toks[1:] and fr == "void":
                self.E(ln, "returning a value from a void function")
            return
        if w == "var":
            self.local_decl(ln, toks, cls, scope, static)
            return
        self.check_expr(ln, toks, cls, scope, static)
        if not self.type_assign(ln, toks, cls, scope, static):
            self.type_expr(ln, toks, cls, scope, static)

    # ---------------------------------------------------------------- := inference check
    def check_infer(self, ln, rhs, cls, scope):
        if not rhs:
            return
        txt = [t for _, t in rhs]
        # outermost call
        if rhs[0][0] == "id" and len(rhs) > 1 and rhs[1][1] == "(":
            fn = rhs[0][1]
            n, j = count_args(rhs, 1)
            if j == len(rhs) - 1 and fn in VARIANT_FUNCS:
                self.E(ln, "`:=` with %s() has a Variant result; give the variable an explicit type" % fn)
                return
        # top-level ternary / dictionary or array indexing / .get(
        depth = 0
        for i, (k, t) in enumerate(rhs):
            if k == "op" and t in OPEN:
                if t == "[" and depth == 0 and i > 0 and rhs[i - 1][0] in ("id",) or (t == "[" and depth == 0 and i > 0 and rhs[i - 1][1] in ("]", ")")):
                    self.W(ln, "`:=` with an indexed value (Variant if the container is untyped)")
                depth += 1
            elif k == "op" and t in CLOSE:
                depth -= 1
            elif depth == 0 and k == "id" and t == "if" and i > 0:
                self.W(ln, "`:=` with a ternary (needs both branches to share a type)")
            elif depth == 0 and k == "id" and t in ("get", "pop_back", "pop_front", "pick_random", "back", "front", "min", "max") and i > 0 and rhs[i - 1][1] == "." and i + 1 < len(rhs) and rhs[i + 1][1] == "(":
                self.W(ln, "`:=` with .%s() (Variant result)" % t)
            elif depth == 0 and k == "id" and t in ("get_node", "get_node_or_null", "get_child", "get_parent"):
                self.W(ln, "`:=` with %s() (Node/Variant result)" % t)

    # ---------------------------------------------------------------- expressions
    def type_of_name(self, name, cls, scope):
        """-> (found, type string or None)"""
        for _, d in reversed(scope or []):
            if name in d:
                return True, d[name]
        c = cls
        while c is not None:
            m = find_member(c, name)
            if m is not None:
                return True, m
            c = c.outer
        return False, None

    def check_expr(self, ln, toks, cls, scope, static, member_init=False):
        n = len(toks)
        brace = 0
        for i, (k, t) in enumerate(toks):
            if k == "op" and t == "{":
                brace += 1
            elif k == "op" and t == "}":
                brace -= 1
            if k != "id":
                continue
            prev = toks[i - 1][1] if i > 0 else ""
            nxt = toks[i + 1][1] if i + 1 < n else ""
            if prev in (".", "$", "%") or t in KEYWORDS and t not in ("self", "super", "true", "false", "null"):
                continue
            if t in ("true", "false", "null", "self", "super", "PI", "TAU", "INF", "NAN", "void"):
                continue
            if prev in ("as", "is") or prev == "->":
                self.check_class_ref(ln, toks, i, cls)
                continue
            if brace > 0 and nxt == "=" and prev in ("{", ","):
                continue  # Lua-style dictionary key
            if prev == "var" or (prev == "," and False):
                continue
            self.check_name(ln, toks, i, cls, scope, static, member_init)

    def check_class_ref(self, ln, toks, i, cls):
        t = toks[i][1]
        if resolve_class(t, cls) or t in ENGINE_CLASSES or t in VALUE_TYPES:
            return
        # dotted: first segment only
        self.E(ln, "unknown class %r" % t)

    def check_name(self, ln, toks, i, cls, scope, static, member_init):
        t = toks[i][1]
        nxt = toks[i + 1][1] if i + 1 < len(toks) else ""
        found, info = self.type_of_name(t, cls, scope)
        if found:
            if isinstance(info, Member):
                if static and not info.static and info.kind in ("var", "func", "signal"):
                    # accessing an instance member from a static context
                    self.E(ln, "instance member %s used in a static context" % t)
                if info.kind == "func" and nxt == "(":
                    n, _ = count_args(toks, i + 1)
                    if n < info.nreq or n > info.nmax:
                        self.E(ln, "%s() takes %d..%d arguments, got %d" % (t, info.nreq, info.nmax, n))
                if info.kind == "signal" and i + 3 < len(toks) and toks[i + 1][1] == "." and toks[i + 2][1] == "emit":
                    sig = chain_signal(cls, t) or []
                    c, _ = count_args(toks, i + 3)
                    if c != len(sig):
                        self.E(ln, "signal %s takes %d arguments, emit() got %d" % (t, len(sig), c))
                rtype = info.ret if info.kind == "func" else info.vtype
                self.walk_chain(ln, toks, i + 1, rtype, cls, scope, info.kind == "func")
            else:
                self.walk_chain(ln, toks, i + 1, info, cls, scope, False)
            return
        # global script class / inner class
        ci = resolve_class(t, cls)
        if ci is not None:
            self.walk_class_chain(ln, toks, i + 1, ci)
            return
        if t in ENGINE_CLASSES or t in VALUE_TYPES:
            self.walk_engine_static(ln, toks, i + 1, t)
            return
        if t in AUTOLOADS:
            ac = AUTOLOADS[t]
            self.walk_chain(ln, toks, i + 1, ac, cls, scope, False)
            return
        if t in UTILITY:
            return
        if t == "emit_signal" and i + 3 < len(toks) and toks[i + 1][1] == "(" and toks[i + 2][0] == "str":
            sname = toks[i + 2][1].strip("&\"'")
            sig = chain_signal(cls, sname)
            if sig is None:
                self.E(ln, "emit_signal of unknown signal %r" % sname)
            else:
                c, _ = count_args(toks, i + 1)
                if c - 1 != len(sig):
                    self.E(ln, "signal %s takes %d arguments, emit_signal got %d" % (sname, len(sig), c - 1))
            return
        if t in ENGINE_NAMES:
            return
        if t[0].isupper() and t.isupper():
            return  # engine constant (e.g. a bare enum value)
        self.E(ln, "unknown name %r" % t)

    # --- chain walkers
    def walk_chain(self, ln, toks, i, vtype, cls, scope, was_call):
        """toks[i:] continues after a name whose type is vtype (string or ('call', name) or None)."""
        n = len(toks)
        cur_ci = None
        cur_engine = None
        if isinstance(vtype, tuple):
            vtype = None
        if was_call and i < n and toks[i][1] == "(":
            _, j = count_args(toks, i)
            i = j + 1
        if vtype:
            base = vtype.split("[")[0]
            cur_ci = resolve_class(base, cls)
            if cur_ci is None and (base in ENGINE_CLASSES or base in VALUE_TYPES):
                cur_engine = base
        elif False:
            pass
        while i < n:
            k, t = toks[i]
            if t == "[":
                _, j = count_args(toks, i) if False else (0, self.match_close(toks, i))
                i = j + 1
                cur_ci, cur_engine = None, None
                continue
            if t == "(":
                j = self.match_close(toks, i)
                i = j + 1
                cur_ci, cur_engine = None, None
                continue
            if t != "." or i + 1 >= n or toks[i + 1][0] != "id":
                return
            m = toks[i + 1][1]
            after = toks[i + 2][1] if i + 2 < n else ""
            op_after = after
            kind = member_kind(toks, i + 2)
            if cur_ci is not None:
                mem = find_member(cur_ci, m)
                if mem is None:
                    if m in ("new", "queue_free", "free", "connect", "disconnect", "emit", "is_connected", "call", "get", "set", "duplicate"):
                        pass
                    elif m in ENGINE_NAMES:
                        self.api_note(engine_root(cur_ci), m, kind)
                    else:
                        self.api_note(engine_root(cur_ci), m, kind)
                        self.W(ln, "%s has no member %r (and it is not a known engine member of %s)" % (cur_ci.qual, m, engine_root(cur_ci)))
                    cur_ci, cur_engine = None, None
                    if kind == "call":
                        j = self.match_close(toks, i + 2)
                        i = j + 1
                    else:
                        i += 2
                    continue
                if mem.kind == "func":
                    if kind == "call":
                        c, j = count_args(toks, i + 2)
                        if c < mem.nreq or c > mem.nmax:
                            self.E(ln, "%s.%s() takes %d..%d arguments, got %d" % (cur_ci.short, m, mem.nreq, mem.nmax, c))
                        i = j + 1
                        r = mem.ret
                        cur_ci = resolve_class(r, cur_ci) if r else None
                        cur_engine = r if r and (r in ENGINE_CLASSES or r in VALUE_TYPES) else None
                        continue
                    i += 2
                    cur_ci, cur_engine = None, None
                    continue
                if mem.kind == "signal":
                    if after == "." and i + 4 < n and toks[i + 3][1] == "emit":
                        c, j = count_args(toks, i + 4)
                        sig = chain_signal(cur_ci, m) or []
                        if c != len(sig):
                            self.E(ln, "signal %s takes %d arguments, emit() got %d" % (m, len(sig), c))
                        return
                    return
                vt = mem.vtype if isinstance(mem.vtype, str) else None
                cur_ci = resolve_class(vt, cur_ci) if vt else None
                cur_engine = vt if vt and (vt in ENGINE_CLASSES or vt in VALUE_TYPES) else None
                i += 2
                continue
            if cur_engine is not None:
                self.api_note(cur_engine, m, kind, count_args(toks, i + 2)[0] if kind == "call" else None)
                cur_ci, cur_engine = None, None
                if kind == "call":
                    j = self.match_close(toks, i + 2)
                    i = j + 1
                else:
                    i += 2
                continue
            # unknown receiver
            self.api_note("?", m, kind, count_args(toks, i + 2)[0] if kind == "call" else None)
            if kind == "call":
                j = self.match_close(toks, i + 2)
                i = j + 1
            else:
                i += 2

    def match_close(self, toks, i):
        depth = 0
        j = i
        while j < len(toks):
            k, t = toks[j]
            if k == "op" and t in OPEN:
                depth += 1
            elif k == "op" and t in CLOSE:
                depth -= 1
                if depth == 0:
                    return j
            j += 1
        return len(toks) - 1

    def walk_class_chain(self, ln, toks, i, ci):
        """ClassName.<...>"""
        n = len(toks)
        if i >= n or toks[i][1] != ".":
            return
        if i + 1 >= n or toks[i + 1][0] != "id":
            return
        m = toks[i + 1][1]
        after = toks[i + 2][1] if i + 2 < n else ""
        if m == "new":
            if after == "(":
                c, j = count_args(toks, i + 2)
                init = ci.members.get("_init")
                if init is not None and (c < init.nreq or c > init.nmax):
                    self.E(ln, "%s.new() takes %d..%d arguments, got %d" % (ci.short, init.nreq, init.nmax, c))
                elif init is None and c > 0 and base_class(ci) is None and engine_root(ci) in ("RefCounted", "Object", "Node", "Node3D", "Area3D", "StaticBody3D", "Control", "Node2D"):
                    self.E(ln, "%s.new() takes no arguments, got %d" % (ci.short, c))
                self.walk_chain(ln, toks, j + 1, ci.qual, ci, [], False)
            return
        mem = find_member(ci, m)
        if mem is None:
            self.E(ln, "%s has no member %r" % (ci.qual, m))
            return
        if mem.kind == "class":
            self.walk_class_chain(ln, toks, i + 2, ci.inner[m] if m in ci.inner else find_inner(ci, m))
            return
        if mem.kind == "func":
            if not mem.static:
                self.E(ln, "%s.%s() is not static" % (ci.short, m))
            if after == "(":
                c, j = count_args(toks, i + 2)
                if c < mem.nreq or c > mem.nmax:
                    self.E(ln, "%s.%s() takes %d..%d arguments, got %d" % (ci.short, m, mem.nreq, mem.nmax, c))
                self.walk_chain(ln, toks, j + 1, mem.ret, ci, [], False)
            return
        if mem.kind == "var" and not mem.static:
            self.E(ln, "%s.%s is an instance variable used through the class name" % (ci.short, m))
            return
        if mem.kind == "const":
            self.walk_chain(ln, toks, i + 2, mem.vtype, ci, [], False)

    def walk_engine_static(self, ln, toks, i, cname):
        n = len(toks)
        if i < n and toks[i][1] == "." and i + 1 < n and toks[i + 1][0] == "id":
            m = toks[i + 1][1]
            after = toks[i + 2][1] if i + 2 < n else ""
            self.api_note(cname + " (static)", m, "call" if after == "(" else "get", count_args(toks, i + 2)[0] if after == "(" else None)

    def api_note(self, tname, member, kind, argc=None):
        if kind == "call" and argc is not None:
            member = "%s/%d" % (member, argc)
        self.api[tname][kind].add(member)


ASSIGN_OPS = ("=", "+=", "-=", "*=", "/=", "%=", "|=", "&=", "^=", "<<=", ">>=", "**=")


def member_kind(toks, j):
    """what follows a member name at toks[j]: call / set / get"""
    if j >= len(toks):
        return "get"
    k, t = toks[j]
    if t == "(":
        return "call"
    if k == "op" and t in ASSIGN_OPS:
        return "set"
    return "get"


def find_inner(ci, name):
    seen = 0
    while ci is not None and seen < 20:
        if name in ci.inner:
            return ci.inner[name]
        ci = base_class(ci)
        seen += 1
    return None


# ======================================================================== main
def load_autoloads():
    p = os.path.join(ROOT, "project.godot")
    if not os.path.exists(p):
        return
    sec = ""
    for raw in open(p, encoding="utf-8"):
        raw = raw.strip()
        if raw.startswith("["):
            sec = raw
        elif sec == "[autoload]" and "=" in raw:
            name, val = raw.split("=", 1)
            AUTOLOADS[name.strip()] = val.strip().strip('"').lstrip("*")


def main():
    quiet = "--quiet" in sys.argv
    show_api = "--api" in sys.argv
    rep = Report()
    files = []
    for dp, _, fns in os.walk(os.path.join(ROOT, "scripts")):
        for fn in sorted(fns):
            if fn.endswith(".gd"):
                files.append(os.path.join(dp, fn))
    files.sort()
    load_autoloads()
    parsed = {}
    for f in files:
        rel = os.path.relpath(f, ROOT)
        lines = read_lines(f, rep, rel)
        parsed[rel] = lines
    tops = {}
    for rel, lines in parsed.items():
        tops[rel] = pass1(rel, lines, rep)
    # autoload name -> ClassInfo type (script path -> top class)
    for name, path in list(AUTOLOADS.items()):
        rel = path.replace("res://", "")
        AUTOLOADS[name] = tops[rel].qual if rel in tops else None
        if rel in tops:
            GLOBAL.setdefault("__autoload_" + name, tops[rel])
    for name, path in list(AUTOLOADS.items()):
        rel = path.replace("res://", "") if path else ""
        if rel in tops:
            AUTOLOAD_CLASSES[name] = tops[rel]
    # resolve autoload type strings: store as class name; make resolvable via GLOBAL alias
    for name in list(AUTOLOADS):
        v = AUTOLOADS[name]
        if v:
            GLOBAL[v] = ALL[v]
    # pass 1b: types of `var x := expr` / `const X = expr` members
    uniq = []
    seen_ids = set()
    for ci in ALL.values():
        if id(ci) not in seen_ids:
            seen_ids.add(id(ci))
            uniq.append(ci)
    for _round in range(2):
        for ci in uniq:
            ck0 = Checker(ci.file, [], ci, Report(), defaultdict(lambda: defaultdict(set)))
            dummy = Line(0, 0, [], "")
            for m in ci.members.values():
                it = getattr(m, "init_toks", None)
                if it:
                    t = ck0.type_expr(dummy, it, ci, [(0, {})], True)
                    if t and t != "null":
                        m.vtype = t
    api = defaultdict(lambda: defaultdict(set))
    for rel, lines in parsed.items():
        top = tops[rel]
        ck = Checker(rel, lines, top, rep, api)
        try:
            ck.run()
            STATS[0] += ck.parse_ok
            STATS[1] += ck.parse_fail
        except Exception as ex:  # a checker bug must not hide the other results
            import traceback
            traceback.print_exc()
            rep.err(rel, 0, "checker crashed: %r" % ex)
        # res:// resources
        for ln in lines:
            for k, t in ln.toks:
                if k == "str" and "res://" in t:
                    q = t[0] if t[0] in "\"'" else t[1 if t[0] in "&^r" else 2]
                    path = t[t.index(q) + 1:-1].replace("res://", "")
                    if "%" in path or "{" in path:
                        continue
                    if not os.path.exists(os.path.join(ROOT, path)):
                        rep.err(rel, ln.no, "missing resource %s" % t)
    # annotated types must exist
    seen_ci = set()
    for ci in list(ALL.values()):
        if id(ci) in seen_ci:
            continue
        seen_ci.add(id(ci))
        for m in ci.members.values():
            vt = m.vtype if isinstance(m.vtype, str) else None
            for tn, what in [(vt, "variable " + m.name), (m.ret, "return type of " + m.name)] + [(pt, "parameter " + pn) for pn, pt, _ in m.params]:
                if tn and not type_known(tn, ci):
                    rep.err(ci.file, m.line, "unknown type %r for %s" % (tn, what))
    for e in rep.errors:
        print("ERROR  " + e)
    if not quiet:
        for w in rep.warns:
            print("warn   " + w)
    if show_api:
        print("\n==== engine members used (type: set / get / call) ====")
        for tname in sorted(api):
            d = api[tname]
            print("%s" % tname)
            for kind in ("set", "get", "call"):
                if d.get(kind):
                    print("   %-4s %s" % (kind, " ".join(sorted(d[kind]))))
    if "--stats" in sys.argv:
        print("type-lite: parsed %d expressions, %d not parsed" % (STATS[0], STATS[1]))
    print("\n%d errors, %d warnings in %d files" % (len(rep.errors), len(rep.warns), len(parsed)))
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main())
