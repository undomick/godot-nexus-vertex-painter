@tool
extends Node
class_name VertexColorData

# --- STORAGE ---
# Format: { surface_index (int) : colors (PackedColorArray) }
@export var surface_data: Dictionary = {}

# --- RUNTIME CACHE ---
var _cache_positions: Dictionary = {} # { surface_idx: PackedVector3Array }
var _cache_normals: Dictionary = {}   # { surface_idx: PackedVector3Array }
var _cache_vertex_count: Dictionary = {} # { surface_idx: int }
var _cache_surface_aabb: Dictionary = {} # { surface_idx: { "min": Vector3, "max": Vector3 } }
var _neighbor_cache: Dictionary = {}  # { surface_idx: { vertex_idx: [neighbor_idx, ...] } } (Used for Blur)
var _pending_gpu_surfaces: Dictionary = {} # { surface_idx: PackedColorArray }
var _gpu_flush_scheduled: bool = false
var _cached_mesh: Mesh = null # Mesh reference for cache invalidation

var _runtime_mesh: ArrayMesh
var _source_mesh: Mesh  # Original mesh (for MeshDataTool - avoids Godot 4.2+ compressed array format issues)
var _source_arrays_cache: Dictionary = {} # Maps surface_index -> Array (for _prep_cache / get_positions etc.)
var _source_materials_cache: Dictionary = {} # Maps surface_index -> Material

# Phase 2: C++ acceleration - use apply_colors_to_mesh instead of GDScript MeshDataTool loop
var _paint_core_ref: RefCounted = null
var _attrib_upload_cache: Dictionary = {} # { surface_idx: PackedByteArray }
var _color_mesh_normalized: bool = false
var _paint_sync_mode: int = 0
## Surfaces whose CUSTOM color channel was migrated to ARRAY_COLOR (strip only that slot).
var _normalized_color_custom_slot: Dictionary = {} # { surface_idx: Mesh.ARRAY_CUSTOM* }

const DATA_VERSION = 2
const SYNC_ARRAYS := 0
const SYNC_ATTRIBUTE := 1
const MESH_BUILD_FLAGS = Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE
const _CUSTOM_ARRAY_SLOTS: Array[int] = [
	Mesh.ARRAY_CUSTOM0,
	Mesh.ARRAY_CUSTOM1,
	Mesh.ARRAY_CUSTOM2,
	Mesh.ARRAY_CUSTOM3,
]
const _CUSTOM_FORMAT_PRESENCE: Array[int] = [
	Mesh.ARRAY_FORMAT_CUSTOM0,
	Mesh.ARRAY_FORMAT_CUSTOM1,
	Mesh.ARRAY_FORMAT_CUSTOM2,
	Mesh.ARRAY_FORMAT_CUSTOM3,
]
const _CUSTOM_FORMAT_SHIFTS: Array[int] = [
	Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT,
	Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT,
	Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT,
	Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT,
]

func _ready():
	request_ready()

func _enter_tree():
	# Clear caches only when mesh changed (avoids unnecessary _prep_cache on every enter)
	var parent = get_parent() as MeshInstance3D
	var current_mesh = parent.mesh if parent else null
	if current_mesh != _cached_mesh or _cached_mesh == null:
		_cache_positions.clear()
		_cache_normals.clear()
		_cache_vertex_count.clear()
		_cache_surface_aabb.clear()
		_cached_mesh = null
		_attrib_upload_cache.clear()
		_color_mesh_normalized = false
		_normalized_color_custom_slot.clear()
	_neighbor_cache.clear() # Topology-dependent, cheap to rebuild

	var parent_mesh: Mesh = parent.mesh if parent else null
	if parent_mesh and (current_mesh != _cached_mesh or _cached_mesh == null):
		_prep_cache(parent_mesh)

	# Only rebuild GPU mesh when we already have painted data (saved session).
	# Avoids replacing the glTF mesh on load and baking preview materials into surfaces.
	if not surface_data.is_empty():
		call_deferred("_ensure_paintable_and_apply")


func _ensure_paintable_and_apply() -> void:
	ensure_paintable_color_mesh()
	ensure_paintable_runtime_mesh()
	_sync_surface_data_to_gpu()

# --- INITIALIZATION ---

func initialize_from_mesh() -> void:
	var parent := get_parent() as MeshInstance3D
	if not parent or not parent.mesh:
		return

	var mesh: Mesh = parent.mesh
	_prep_cache(mesh)
	_import_mesh_colors_to_surface_data(mesh)


func _import_mesh_colors_to_surface_data(mesh: Mesh) -> void:
	for surf_idx in range(mesh.get_surface_count()):
		if surface_data.has(surf_idx):
			var existing: Variant = surface_data[surf_idx]
			if existing is PackedColorArray and (existing as PackedColorArray).size() > 0:
				continue
		var colors: PackedColorArray = SurfaceColorBinding.read_surface_colors(mesh, surf_idx)
		if SurfaceColorBinding.colors_are_paintable(colors):
			surface_data[surf_idx] = colors

# --- CACHE MANAGEMENT ---

## Fast path: surface_get_arrays. Fallback: MeshDataTool for compressed/invalid arrays.
func _prep_cache(mesh: Mesh) -> void:
	_cache_positions.clear()
	_cache_normals.clear()
	_cache_vertex_count.clear()
	_cache_surface_aabb.clear()
	_cached_mesh = mesh

	if not mesh is ArrayMesh:
		return

	var arr_mesh: ArrayMesh = mesh as ArrayMesh
	for i in range(arr_mesh.get_surface_count()):
		if _prep_cache_surface_from_arrays(arr_mesh, i):
			continue
		_prep_cache_surface_from_mdt(arr_mesh, i)


func _prep_cache_surface_from_arrays(mesh: ArrayMesh, surf_idx: int) -> bool:
	var format: int = mesh.surface_get_format(surf_idx)
	if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
		return false

	var arrays: Array = mesh.surface_get_arrays(surf_idx)
	if arrays == null or arrays.size() < Mesh.ARRAY_MAX:
		return false

	var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
	if verts == null or not verts is PackedVector3Array:
		return false
	var vert_array: PackedVector3Array = verts as PackedVector3Array
	if vert_array.is_empty():
		return false

	_cache_vertex_count[surf_idx] = vert_array.size()
	_cache_positions[surf_idx] = vert_array
	var norms: Variant = arrays[Mesh.ARRAY_NORMAL]
	if norms is PackedVector3Array and (norms as PackedVector3Array).size() == vert_array.size():
		_cache_normals[surf_idx] = norms as PackedVector3Array
	else:
		_cache_normals[surf_idx] = PackedVector3Array()
	_cache_surface_aabb[surf_idx] = _compute_surface_aabb(vert_array)
	return true


func _prep_cache_surface_from_mdt(mesh: ArrayMesh, surf_idx: int) -> void:
	var mdt := MeshDataTool.new()
	if mdt.create_from_surface(mesh, surf_idx) != OK:
		return
	var vc: int = mdt.get_vertex_count()
	_cache_vertex_count[surf_idx] = vc
	var verts := PackedVector3Array()
	verts.resize(vc)
	var norms := PackedVector3Array()
	norms.resize(vc)
	for j in range(vc):
		verts[j] = mdt.get_vertex(j)
		norms[j] = mdt.get_vertex_normal(j)
	_cache_positions[surf_idx] = verts
	_cache_normals[surf_idx] = norms
	_cache_surface_aabb[surf_idx] = _compute_surface_aabb(verts)

# Public getters for the painter (High Performance)
func get_positions(surf_idx: int) -> PackedVector3Array:
	if not _cache_positions.has(surf_idx): return PackedVector3Array()
	return _cache_positions[surf_idx]

func get_normals(surf_idx: int) -> PackedVector3Array:
	if not _cache_normals.has(surf_idx): return PackedVector3Array()
	return _cache_normals[surf_idx]


func surface_intersects_brush(surf_idx: int, local_hit: Vector3, brush_size: float) -> bool:
	if not _cache_surface_aabb.has(surf_idx):
		return true
	var bounds: Dictionary = _cache_surface_aabb[surf_idx]
	var surf_min: Vector3 = bounds["min"]
	var surf_max: Vector3 = bounds["max"]
	var brush_min := local_hit - Vector3(brush_size, brush_size, brush_size)
	var brush_max := local_hit + Vector3(brush_size, brush_size, brush_size)
	return surf_min.x <= brush_max.x and surf_max.x >= brush_min.x \
			and surf_min.y <= brush_max.y and surf_max.y >= brush_min.y \
			and surf_min.z <= brush_max.z and surf_max.z >= brush_min.z


func _compute_surface_aabb(positions: PackedVector3Array) -> Dictionary:
	if positions.is_empty():
		return {"min": Vector3.ZERO, "max": Vector3.ZERO}
	var surf_min := positions[0]
	var surf_max := positions[0]
	for i in range(1, positions.size()):
		var p := positions[i]
		surf_min = surf_min.min(p)
		surf_max = surf_max.max(p)
	return {"min": surf_min, "max": surf_max}

# --- NEIGHBOR CACHE (Lazy Loaded) ---
# Finding neighbors is expensive (O(N)), so we only do it if the user selects the BLUR tool
# and we only calculate it once per surface.
func get_neighbors(surf_idx: int, vert_idx: int) -> Array:
	if not _neighbor_cache.has(surf_idx):
		_build_neighbor_cache(surf_idx)
	if not _neighbor_cache.has(surf_idx):
		return []
	if _neighbor_cache[surf_idx].has(vert_idx):
		return _neighbor_cache[surf_idx][vert_idx]
	return []

func get_neighbor_map(surf_idx: int) -> Dictionary:
	if not _neighbor_cache.has(surf_idx):
		_build_neighbor_cache(surf_idx)
	if _neighbor_cache.has(surf_idx):
		return _neighbor_cache[surf_idx]
	return {}


func _topology_mesh() -> Mesh:
	if _source_mesh:
		return _source_mesh
	var parent = get_parent() as MeshInstance3D
	if parent and parent.mesh:
		return parent.mesh
	return null


func _build_neighbor_cache(surf_idx: int):
	var topo := _topology_mesh()
	if topo == null:
		return

	if _get_paint_core() and topo is ArrayMesh:
		var cpp_map: Dictionary = _paint_core_ref.build_neighbor_cache(topo as ArrayMesh, surf_idx)
		if not cpp_map.is_empty():
			_neighbor_cache[surf_idx] = cpp_map
			return

	var mdt = MeshDataTool.new()
	if mdt.create_from_surface(topo, surf_idx) != OK:
		return

	var surf_neighbors = {}
	for v in range(mdt.get_vertex_count()):
		var edges = mdt.get_vertex_edges(v)
		var n_list = []
		for e in edges:
			var v1 = mdt.get_edge_vertex(e, 0)
			var v2 = mdt.get_edge_vertex(e, 1)
			# The neighbor is the vertex that isn't me
			n_list.append(v2 if v1 == v else v1)
		surf_neighbors[v] = n_list
	
	_neighbor_cache[surf_idx] = surf_neighbors

# --- VISUAL UPDATE ---

func ensure_paintable_runtime_mesh() -> bool:
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent or not parent.mesh:
		return false
	if not parent.mesh is ArrayMesh:
		return false
	if not _mesh_needs_paintable_rebuild(parent.mesh):
		_bind_paint_mesh_from_parent()
		return true

	# Painting stays data-only until bake; bind source mesh for cache / fast-path when COLOR exists.
	_bind_paint_mesh_from_parent()
	return true


func _mesh_has_vertex_color_format(mesh: Mesh) -> bool:
	for i in range(mesh.get_surface_count()):
		if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			return false
	return true


func _mesh_needs_paintable_rebuild(mesh: Mesh) -> bool:
	if mesh == null:
		return true
	if not mesh is ArrayMesh:
		return true
	if not _mesh_has_vertex_color_format(mesh):
		return true
	for i in range(mesh.get_surface_count()):
		var fmt: int = mesh.surface_get_format(i)
		if (fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
			return true
	return false


## Use the MeshInstance mesh in-place (no swap). Only vertex colors change via fast path.
func _bind_paint_mesh_from_parent() -> void:
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent or not (parent.mesh is ArrayMesh):
		return

	var mesh: ArrayMesh = parent.mesh as ArrayMesh
	if _runtime_mesh == mesh and _source_mesh != null:
		return

	_runtime_mesh = mesh
	var picked: Mesh = _pick_source_mesh(parent, mesh)
	_source_mesh = picked if picked else mesh
	_source_arrays_cache.clear()
	_source_materials_cache.clear()
	_cache_source_materials(parent, _source_mesh)
	_cache_source_arrays(_runtime_mesh)
	_detect_paint_sync_mode(_runtime_mesh)

	if _cache_positions.is_empty() or _cached_mesh != mesh:
		_prep_cache(mesh)


func _mesh_has_compressed_surfaces(mesh: Mesh) -> bool:
	for i in range(mesh.get_surface_count()):
		if (mesh.surface_get_format(i) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
			return true
	return false


func _surface_supports_fast_color_upload(format: int) -> bool:
	if (format & Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE) == 0:
		return false
	if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
		return false
	if (format & Mesh.ARRAY_FORMAT_COLOR) == 0:
		return false
	return true


func mesh_needs_color_normalize(mesh: Mesh) -> bool:
	if mesh == null or not mesh is ArrayMesh:
		return true
	for surf_idx in range(mesh.get_surface_count()):
		var channel: int = SurfaceColorBinding.detect_color_channel(mesh, surf_idx)
		if channel != Mesh.ARRAY_COLOR:
			return true
		var fmt: int = mesh.surface_get_format(surf_idx)
		if (fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
			return true
	return false


## Rebuilds mesh with ARRAY_COLOR (vertex domain) for painting. Returns true if mesh was replaced.
func ensure_paintable_color_mesh() -> bool:
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent or not (parent.mesh is ArrayMesh):
		return false
	if _color_mesh_normalized:
		return false

	var mesh: Mesh = parent.mesh
	if not mesh_needs_color_normalize(mesh):
		return false

	_import_mesh_colors_to_surface_data(mesh)
	_record_normalized_color_custom_slots(mesh)

	_attrib_upload_cache.clear()
	if not _prepare_rebuild_from_parent(parent):
		VertexPainterLog.warn("Could not prepare mesh for vertex color normalization on '%s'." % parent.name)
		return false

	var rebuilt: ArrayMesh = _rebuild_colored_mesh_internal()
	if rebuilt == null or rebuilt.get_surface_count() == 0:
		VertexPainterLog.warn("Failed to normalize vertex colors on '%s'." % parent.name)
		return false

	if not parent.has_meta("_vertex_paint_original_path"):
		var original_path: String = mesh.resource_path
		if not original_path.is_empty():
			parent.set_meta("_vertex_paint_original_path", original_path)

	var instance_overrides: Dictionary = {}
	for idx in range(parent.get_surface_override_material_count()):
		var mat: Material = parent.get_surface_override_material(idx)
		if mat:
			instance_overrides[idx] = mat

	_runtime_mesh = rebuilt
	parent.mesh = rebuilt
	_color_mesh_normalized = true
	_cached_mesh = rebuilt
	_source_mesh = rebuilt
	_source_arrays_cache.clear()
	_source_materials_cache.clear()
	_cache_source_materials(parent, rebuilt)
	_neighbor_cache.clear()
	_prep_cache(rebuilt)
	_seed_surface_data_after_normalize(rebuilt)
	_cache_source_arrays(rebuilt)
	_detect_paint_sync_mode(rebuilt)
	if _paint_sync_mode == SYNC_ATTRIBUTE:
		_prewarm_attrib_upload_cache(rebuilt)

	for idx in instance_overrides:
		if idx < parent.get_surface_override_material_count():
			parent.set_surface_override_material(idx, instance_overrides[idx])

	VertexPainterLog.info("Normalized vertex colors to ARRAY_COLOR for painting (%s)." % parent.name)
	return true


func _paint_vertex_count(mesh: ArrayMesh, surf_idx: int) -> int:
	if _cache_vertex_count.has(surf_idx):
		return _cache_vertex_count[surf_idx]
	return mesh.surface_get_array_len(surf_idx)


func _attrib_region_fits(
		buffer_size: int,
		stride: int,
		attrib_ofs: int,
		bytes_per_vertex: int,
		vertex_count: int) -> bool:
	if stride <= 0 or attrib_ofs < 0 or bytes_per_vertex <= 0 or vertex_count <= 0:
		return false
	if attrib_ofs + bytes_per_vertex > stride:
		return false
	var needed_size: int = vertex_count * stride
	if buffer_size < needed_size:
		return false
	var last_base: int = (vertex_count - 1) * stride + attrib_ofs
	return last_base + bytes_per_vertex <= buffer_size


func _attrib_encode_bounds_ok(buffer_size: int, offset: int, encoded_bytes: int) -> bool:
	return offset >= 0 and offset + encoded_bytes <= buffer_size


func _write_color_bytes_to_attrib(
		out: PackedByteArray,
		colors: PackedColorArray,
		stride: int,
		color_ofs: int,
		vertex_count: int) -> void:
	if not _attrib_region_fits(out.size(), stride, color_ofs, 4, vertex_count):
		return
	for i in range(colors.size()):
		var base: int = i * stride + color_ofs
		if not _attrib_encode_bounds_ok(out.size(), base, 4):
			break
		var c: Color = colors[i]
		out[base] = c.r8
		out[base + 1] = c.g8
		out[base + 2] = c.b8
		out[base + 3] = c.a8


func _uv_attrib_bytes_in_stride(stride: int, uv_ofs: int) -> int:
	if uv_ofs < 0:
		return 0
	if uv_ofs + 8 <= stride:
		return 8
	if uv_ofs + 4 <= stride:
		return 4
	return 0


func _write_uvs_to_attrib(
		out: PackedByteArray,
		uvs: PackedVector2Array,
		vertex_count: int,
		stride: int,
		uv_ofs: int) -> void:
	if uvs.is_empty():
		return
	var uv_bytes: int = _uv_attrib_bytes_in_stride(stride, uv_ofs)
	if uv_bytes == 0:
		return
	if not _attrib_region_fits(out.size(), stride, uv_ofs, uv_bytes, vertex_count):
		return
	var use_half: bool = uv_bytes == 4
	var count: int = mini(vertex_count, uvs.size())
	for i in range(count):
		var uv: Vector2 = uvs[i]
		var base: int = i * stride + uv_ofs
		if use_half:
			if not _attrib_encode_bounds_ok(out.size(), base, 4):
				break
			out.encode_half(base, uv.x)
			out.encode_half(base + 2, uv.y)
		else:
			if not _attrib_encode_bounds_ok(out.size(), base, 8):
				break
			out.encode_float(base, uv.x)
			out.encode_float(base + 4, uv.y)


func _resize_uv_array(uvs: PackedVector2Array, vertex_count: int) -> PackedVector2Array:
	if uvs.size() == vertex_count:
		return uvs
	if uvs.size() > vertex_count:
		return uvs.slice(0, vertex_count)
	var out := uvs.duplicate()
	out.resize(vertex_count)
	return out


func _surface_uv_arrays_for_pack(mesh: ArrayMesh, surf_idx: int, vertex_count: int, format: int) -> Dictionary:
	var out := {"uv": PackedVector2Array(), "uv2": PackedVector2Array()}
	var needs_uv: bool = (format & Mesh.ARRAY_FORMAT_TEX_UV) != 0
	var needs_uv2: bool = (format & Mesh.ARRAY_FORMAT_TEX_UV2) != 0
	if not needs_uv and not needs_uv2:
		return out

	if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0:
		var arrays: Array = mesh.surface_get_arrays(surf_idx)
		if arrays.size() > Mesh.ARRAY_TEX_UV2:
			if needs_uv:
				var uv_data: Variant = arrays[Mesh.ARRAY_TEX_UV]
				if uv_data is PackedVector2Array:
					out.uv = _resize_uv_array(uv_data as PackedVector2Array, vertex_count)
			if needs_uv2:
				var uv2_data: Variant = arrays[Mesh.ARRAY_TEX_UV2]
				if uv2_data is PackedVector2Array:
					out.uv2 = _resize_uv_array(uv2_data as PackedVector2Array, vertex_count)

	if needs_uv and out.uv.is_empty():
		out.uv = _read_uvs_via_mesh_data_tool(mesh, surf_idx, vertex_count, false)
	if needs_uv2 and out.uv2.is_empty():
		out.uv2 = _read_uvs_via_mesh_data_tool(mesh, surf_idx, vertex_count, true)
	return out


func _read_uvs_via_mesh_data_tool(mesh: ArrayMesh, surf_idx: int, vertex_count: int, use_uv2: bool) -> PackedVector2Array:
	var mdt := MeshDataTool.new()
	if mdt.create_from_surface(mesh, surf_idx) != OK:
		return PackedVector2Array()
	var count: int = mini(vertex_count, mdt.get_vertex_count())
	var uvs := PackedVector2Array()
	uvs.resize(count)
	for i in range(count):
		uvs[i] = mdt.get_vertex_uv2(i) if use_uv2 else mdt.get_vertex_uv(i)
	return uvs


func _pack_surface_attrib_bytes(mesh: ArrayMesh, surf_idx: int, colors: PackedColorArray) -> PackedByteArray:
	var format: int = mesh.surface_get_format(surf_idx)
	var vertex_count: int = _paint_vertex_count(mesh, surf_idx)
	if vertex_count <= 0 or colors.size() != vertex_count:
		return PackedByteArray()

	var stride: int = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	if stride <= 0:
		return PackedByteArray()

	var out := PackedByteArray()
	out.resize(vertex_count * stride)

	var color_ofs: int = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_COLOR)
	if color_ofs < 0:
		return PackedByteArray()
	_write_color_bytes_to_attrib(out, colors, stride, color_ofs, vertex_count)

	var uv_arrays: Dictionary = _surface_uv_arrays_for_pack(mesh, surf_idx, vertex_count, format)
	if (format & Mesh.ARRAY_FORMAT_TEX_UV) != 0:
		var uv_ofs: int = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_TEX_UV)
		_write_uvs_to_attrib(out, uv_arrays.uv, vertex_count, stride, uv_ofs)

	if (format & Mesh.ARRAY_FORMAT_TEX_UV2) != 0:
		var uv2_ofs: int = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_TEX_UV2)
		_write_uvs_to_attrib(out, uv_arrays.uv2, vertex_count, stride, uv2_ofs)

	return out


func _prewarm_attrib_upload_cache(mesh: ArrayMesh) -> void:
	for surf_idx in range(mesh.get_surface_count()):
		if _attrib_upload_cache.has(surf_idx):
			continue
		var format: int = mesh.surface_get_format(surf_idx)
		if not _surface_supports_fast_color_upload(format):
			continue
		var vertex_count: int = _paint_vertex_count(mesh, surf_idx)
		if vertex_count <= 0:
			continue
		var colors: PackedColorArray
		if surface_data.has(surf_idx) and surface_data[surf_idx] is PackedColorArray:
			colors = _ensure_packed_color_array(surface_data[surf_idx], vertex_count)
		else:
			colors = PackedColorArray()
			colors.resize(vertex_count)
			colors.fill(Color.BLACK)
		var packed: PackedByteArray = _pack_surface_attrib_bytes(mesh, surf_idx, colors)
		if not packed.is_empty():
			_attrib_upload_cache[surf_idx] = packed


func get_surface_paint_report(surf_idx: int) -> String:
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent or not parent.mesh or surf_idx < 0 or surf_idx >= parent.mesh.get_surface_count():
		return "surface %d: no mesh" % surf_idx

	var fmt: int = parent.mesh.surface_get_format(surf_idx)
	var verts: int = parent.mesh.surface_get_array_len(surf_idx)
	var compress: bool = (fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0
	var dynamic: bool = (fmt & Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE) != 0
	var has_color: bool = (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0
	var color_channel: String = SurfaceColorBinding.channel_label(
			SurfaceColorBinding.detect_color_channel(parent.mesh, surf_idx))
	var sync_label: String = "arrays" if _uses_arrays_color_sync(surf_idx) else "attribute"
	var attrib_ok: bool = false
	if _runtime_mesh and surf_idx < _runtime_mesh.get_surface_count():
		attrib_ok = _surface_supports_fast_color_upload(_runtime_mesh.surface_get_format(surf_idx))

	return "surface %d: verts=%d compress=%s dynamic=%s color=%s channel=%s sync=%s attrib_path=%s format=%d" % [
		surf_idx, verts, compress, dynamic, has_color, color_channel, sync_label, attrib_ok, fmt
	]


func log_paint_diagnostics() -> void:
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent or not parent.mesh:
		return
	VertexPainterLog.debug("Paint diagnostics for '%s':" % parent.name)
	for i in range(parent.mesh.get_surface_count()):
		VertexPainterLog.debug("  " + get_surface_paint_report(i))


func surface_supports_live_color_upload(surf_idx: int) -> bool:
	return _uses_arrays_color_sync(surf_idx) or _surface_supports_attribute_color_upload(surf_idx)


func _surface_supports_attribute_color_upload(surf_idx: int) -> bool:
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent or not parent.mesh or surf_idx < 0:
		return false
	if surf_idx >= parent.mesh.get_surface_count():
		return false
	return _surface_supports_fast_color_upload(parent.mesh.surface_get_format(surf_idx))


func _uses_arrays_color_sync(surf_idx: int) -> bool:
	if _paint_sync_mode != SYNC_ARRAYS:
		return false
	if surf_idx < 0:
		return false
	var cached: Variant = _source_arrays_cache.get(surf_idx)
	return cached is Array


func _detect_paint_sync_mode(mesh: ArrayMesh) -> void:
	_paint_sync_mode = SYNC_ARRAYS
	for surf_idx in range(mesh.get_surface_count()):
		var fmt: int = mesh.surface_get_format(surf_idx)
		if (fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
			_paint_sync_mode = SYNC_ATTRIBUTE
			return
		var cached: Variant = _source_arrays_cache.get(surf_idx)
		if not cached is Array:
			_paint_sync_mode = SYNC_ATTRIBUTE
			return


## v2.0-style GPU sync: duplicate cached surface arrays and inject surface_data colors.
func _sync_colors_via_arrays_runtime_mesh() -> void:
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent or _source_arrays_cache.is_empty():
		return

	if _runtime_mesh == null:
		_runtime_mesh = ArrayMesh.new()
		_runtime_mesh.resource_name = _source_mesh.resource_name if _source_mesh else ""

	var instance_overrides: Dictionary = {}
	for idx in range(parent.get_surface_override_material_count()):
		var mat: Material = parent.get_surface_override_material(idx)
		if mat:
			instance_overrides[idx] = mat

	_runtime_mesh.clear_surfaces()
	var sorted_indices: Array = _source_arrays_cache.keys()
	sorted_indices.sort()
	for surf_idx in sorted_indices:
		var cached: Variant = _source_arrays_cache[surf_idx]
		if not cached is Array:
			continue
		var arrays: Array = (cached as Array).duplicate(true)
		_strip_migrated_color_custom(arrays, surf_idx)
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if verts == null or not verts is PackedVector3Array:
			continue
		var vertex_count: int = (verts as PackedVector3Array).size()
		if vertex_count <= 0:
			continue
		if surface_data.has(surf_idx):
			arrays[Mesh.ARRAY_COLOR] = _ensure_packed_color_array(surface_data[surf_idx], vertex_count)
		else:
			var cols := PackedColorArray()
			cols.resize(vertex_count)
			cols.fill(Color.BLACK)
			arrays[Mesh.ARRAY_COLOR] = cols
		_runtime_mesh.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, _surface_build_flags(surf_idx))
		_apply_surface_material(_runtime_mesh, surf_idx)

	parent.mesh = _runtime_mesh
	for idx in instance_overrides:
		if idx < parent.get_surface_override_material_count():
			parent.set_surface_override_material(idx, instance_overrides[idx])


## Writes surface_data to the mesh GPU buffer.
func _sync_surface_data_to_gpu() -> void:
	if surface_data.is_empty():
		return
	_bind_paint_mesh_from_parent()
	if _paint_sync_mode == SYNC_ARRAYS:
		_sync_colors_via_arrays_runtime_mesh()
		return
	for surf_idx in surface_data.keys():
		if not _surface_supports_attribute_color_upload(surf_idx):
			continue
		var colors: Variant = surface_data[surf_idx]
		if colors is PackedColorArray:
			_try_fast_color_update(surf_idx, colors)


func update_surface_colors(surface_idx: int, new_colors: PackedColorArray, defer_gpu: bool = false):
	surface_data[surface_idx] = new_colors

	if not surface_supports_live_color_upload(surface_idx):
		return

	if _runtime_mesh == null:
		_bind_paint_mesh_from_parent()

	if defer_gpu:
		_pending_gpu_surfaces[surface_idx] = new_colors
		if not _gpu_flush_scheduled:
			_gpu_flush_scheduled = true
			call_deferred("_flush_pending_gpu_updates")
		return

	if _uses_arrays_color_sync(surface_idx):
		_sync_colors_via_arrays_runtime_mesh()
		return

	_try_fast_color_update(surface_idx, new_colors)


func flush_gpu_updates() -> void:
	if _gpu_flush_scheduled or not _pending_gpu_surfaces.is_empty():
		_flush_pending_gpu_updates()


func _flush_pending_gpu_updates() -> void:
	_gpu_flush_scheduled = false
	if _pending_gpu_surfaces.is_empty():
		return

	var use_arrays_sync: bool = false
	var attribute_surfaces: Array[int] = []
	for surf_idx in _pending_gpu_surfaces.keys():
		if _uses_arrays_color_sync(surf_idx):
			use_arrays_sync = true
		elif _surface_supports_attribute_color_upload(surf_idx):
			attribute_surfaces.append(surf_idx)

	if use_arrays_sync:
		_sync_colors_via_arrays_runtime_mesh()
	for surf_idx in attribute_surfaces:
		var colors: PackedColorArray = _pending_gpu_surfaces[surf_idx]
		_try_fast_color_update(surf_idx, colors)

	_pending_gpu_surfaces.clear()


func _get_paint_core() -> bool:
	if _paint_core_ref != null:
		return _paint_core_ref.has_method("apply_colors_to_mesh")
	if ClassDB.class_exists("VertexPainterCore"):
		_paint_core_ref = ClassDB.instantiate("VertexPainterCore")
	return _paint_core_ref != null and _paint_core_ref.has_method("apply_colors_to_mesh")


## Update color in the GPU attribute buffer (keeps UV/UV2 bytes in the same stride).
func _try_fast_color_update(surface_idx: int, new_colors: PackedColorArray) -> bool:
	if _runtime_mesh == null or surface_idx < 0 or surface_idx >= _runtime_mesh.get_surface_count():
		return false
	var format: int = _runtime_mesh.surface_get_format(surface_idx)
	if not _surface_supports_fast_color_upload(format):
		return false
	var vertex_count: int = _paint_vertex_count(_runtime_mesh, surface_idx)
	if new_colors.size() != vertex_count:
		return false

	var stride: int = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	var color_ofs: int = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_COLOR)
	if color_ofs < 0 or stride <= 0:
		return false
	var upload: PackedByteArray

	if _attrib_upload_cache.has(surface_idx):
		upload = _attrib_upload_cache[surface_idx]
		if upload.size() != vertex_count * stride:
			_attrib_upload_cache.erase(surface_idx)
			upload = PackedByteArray()
	if upload.is_empty():
		upload = _pack_surface_attrib_bytes(_runtime_mesh, surface_idx, new_colors)
		if upload.is_empty():
			return false
		_attrib_upload_cache[surface_idx] = upload
	else:
		_write_color_bytes_to_attrib(upload, new_colors, stride, color_ofs, vertex_count)
		if not _attrib_region_fits(upload.size(), stride, color_ofs, 4, vertex_count):
			_attrib_upload_cache.erase(surface_idx)
			return false

	_runtime_mesh.surface_update_attribute_region(surface_idx, 0, upload)
	return true


## Only clear the CUSTOM slot that was migrated to ARRAY_COLOR; keep UV3+ / other customs.
func _strip_migrated_color_custom(arr: Array, surf_idx: int) -> void:
	if not _normalized_color_custom_slot.has(surf_idx):
		return
	var slot: int = int(_normalized_color_custom_slot[surf_idx])
	if slot >= Mesh.ARRAY_CUSTOM0 and slot <= Mesh.ARRAY_CUSTOM3 and arr.size() > slot:
		arr[slot] = null


func _record_normalized_color_custom_slots(mesh: Mesh) -> void:
	_normalized_color_custom_slot.clear()
	if mesh == null:
		return
	for surf_idx in range(mesh.get_surface_count()):
		var channel: int = SurfaceColorBinding.detect_color_channel(mesh, surf_idx)
		if channel >= Mesh.ARRAY_CUSTOM0 and channel <= Mesh.ARRAY_CUSTOM3:
			_normalized_color_custom_slot[surf_idx] = channel


func _try_surface_get_arrays_single(surf_idx: int, result: ArrayMesh) -> bool:
	var format = _source_mesh.surface_get_format(surf_idx)
	if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
		return false

	var arr: Array = _source_mesh.surface_get_arrays(surf_idx)
	if arr == null or arr.size() < Mesh.ARRAY_MAX:
		return false
	var verts = arr[Mesh.ARRAY_VERTEX]
	if verts == null or verts.size() == 0:
		return false

	var vertex_count = verts.size()
	arr = arr.duplicate(true)
	_strip_migrated_color_custom(arr, surf_idx)
	var cols = _ensure_packed_color_array(
		surface_data.get(surf_idx) if surface_data.has(surf_idx) else null,
		vertex_count)
	arr[Mesh.ARRAY_COLOR] = cols

	var count_before = result.get_surface_count()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, _surface_build_flags(surf_idx))
	if result.get_surface_count() == count_before:
		return false  # add_surface_from_arrays failed (e.g. invalid arrays), use MeshDataTool
	_apply_surface_material(result, surf_idx)
	return true


## Rebuild flags: preserve custom format types + bone-weight flag; optional dynamic update.
func _surface_build_flags(surf_idx: int) -> int:
	var flags: int = 0
	var fmt: int = 0
	if _source_mesh and surf_idx < _source_mesh.get_surface_count():
		fmt = _source_mesh.surface_get_format(surf_idx)

	var skip_slot: int = int(_normalized_color_custom_slot.get(surf_idx, -1))
	for i in range(_CUSTOM_ARRAY_SLOTS.size()):
		if _CUSTOM_ARRAY_SLOTS[i] == skip_slot:
			continue
		if (fmt & _CUSTOM_FORMAT_PRESENCE[i]) == 0:
			continue
		var custom_type: int = (fmt >> _CUSTOM_FORMAT_SHIFTS[i]) & Mesh.ARRAY_FORMAT_CUSTOM_MASK
		flags |= custom_type << _CUSTOM_FORMAT_SHIFTS[i]

	if (fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS

	if _paint_sync_mode == SYNC_ATTRIBUTE:
		if (fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0:
			flags |= MESH_BUILD_FLAGS
	return flags


## Apply material to the last surface of result (cache → source mesh → instance override).
func _apply_surface_material(result: ArrayMesh, surf_idx: int) -> void:
	if result == null or result.get_surface_count() == 0:
		return
	var last: int = result.get_surface_count() - 1
	var mat: Material = _source_materials_cache.get(surf_idx) as Material
	if mat == null and _source_mesh and surf_idx < _source_mesh.get_surface_count():
		mat = _source_mesh.surface_get_material(surf_idx)
	if mat == null:
		var parent: MeshInstance3D = get_parent() as MeshInstance3D
		if parent and surf_idx < parent.get_surface_override_material_count():
			var ov: Material = parent.get_surface_override_material(surf_idx)
			if ov and not _is_preview_paint_material(ov):
				mat = ov
	if mat:
		result.surface_set_material(last, mat)
		_source_materials_cache[surf_idx] = mat


## Per-Surface-Hybrid: use surface_get_arrays for non-compressed surfaces, MeshDataTool for compressed.
## Handles mixed meshes like BigMesh_VP_TEST where some surfaces are compressed.
func _build_mesh_per_surface_hybrid() -> ArrayMesh:
	if _source_mesh == null or not _source_mesh is ArrayMesh:
		return null

	var result = ArrayMesh.new()
	result.resource_name = _source_mesh.resource_name

	var sorted_indices = _source_arrays_cache.keys()
	sorted_indices.sort()
	for surf_idx in sorted_indices:
		if _try_surface_get_arrays_single(surf_idx, result):
			continue
		# Fallback: MeshDataTool for this surface
		_add_surface_via_mesh_data_tool(surf_idx, result)

	return result if result.get_surface_count() > 0 else null


## Adds one surface to result mesh using MeshDataTool (for compressed or fallback).
func _add_surface_via_mesh_data_tool(surf_idx: int, result: ArrayMesh) -> void:
	var mdt = MeshDataTool.new()
	var err = mdt.create_from_surface(_source_mesh, surf_idx)
	if err != OK:
		return
	var vertex_count = mdt.get_vertex_count()
	var face_count = mdt.get_face_count()
	var fmt = _source_mesh.surface_get_format(surf_idx)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var verts = PackedVector3Array()
	verts.resize(vertex_count)
	var norms = PackedVector3Array()
	norms.resize(vertex_count)
	var cols = PackedColorArray()
	cols.resize(vertex_count)
	var indices = PackedInt32Array()
	indices.resize(face_count * 3)
	for i in range(vertex_count):
		verts[i] = mdt.get_vertex(i)
		norms[i] = mdt.get_vertex_normal(i)
		if surface_data.has(surf_idx):
			var c = _ensure_packed_color_array(surface_data[surf_idx], vertex_count)
			cols[i] = c[i]
		else:
			cols[i] = Color.BLACK
	for f in range(face_count):
		indices[f * 3 + 0] = mdt.get_face_vertex(f, 0)
		indices[f * 3 + 1] = mdt.get_face_vertex(f, 1)
		indices[f * 3 + 2] = mdt.get_face_vertex(f, 2)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = indices
	if (fmt & Mesh.ARRAY_FORMAT_TEX_UV) != 0:
		var uvs = PackedVector2Array()
		uvs.resize(vertex_count)
		for i in range(vertex_count):
			uvs[i] = mdt.get_vertex_uv(i)
		arr[Mesh.ARRAY_TEX_UV] = uvs
	if (fmt & Mesh.ARRAY_FORMAT_TEX_UV2) != 0:
		var uv2 = PackedVector2Array()
		uv2.resize(vertex_count)
		for i in range(vertex_count):
			uv2[i] = mdt.get_vertex_uv2(i)
		arr[Mesh.ARRAY_TEX_UV2] = uv2
	if (fmt & Mesh.ARRAY_FORMAT_TANGENT) != 0:
		var tangents = PackedFloat32Array()
		tangents.resize(vertex_count * 4)
		for i in range(vertex_count):
			var t = mdt.get_vertex_tangent(i)
			tangents[i * 4 + 0] = t.x
			tangents[i * 4 + 1] = t.y
			tangents[i * 4 + 2] = t.z
			tangents[i * 4 + 3] = t.d
		arr[Mesh.ARRAY_TANGENT] = tangents
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, _surface_build_flags(surf_idx))
	_apply_surface_material(result, surf_idx)


## For non-compressed meshes: use surface_get_arrays to preserve UVs/tangents.
## Returns ArrayMesh if successful, null to fall back to MeshDataTool/C++ path.
func _try_surface_get_arrays_path() -> ArrayMesh:
	if _source_mesh == null: return null
	if not _source_mesh is ArrayMesh: return null

	for i in range(_source_mesh.get_surface_count()):
		var format = _source_mesh.surface_get_format(i)
		if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
			return null  # Compressed - surface_get_arrays returns invalid data

	var result = ArrayMesh.new()
	result.resource_name = _source_mesh.resource_name

	var sorted_indices = _source_arrays_cache.keys()
	sorted_indices.sort()
	for surf_idx in sorted_indices:
		var arr: Array = _source_mesh.surface_get_arrays(surf_idx)
		if arr == null or arr.size() < Mesh.ARRAY_MAX:
			return null
		var verts = arr[Mesh.ARRAY_VERTEX]
		if verts == null or verts.size() == 0:
			return null

		var vertex_count = verts.size()
		arr = arr.duplicate(true)
		_strip_migrated_color_custom(arr, surf_idx)
		var cols = _ensure_packed_color_array(
			surface_data.get(surf_idx) if surface_data.has(surf_idx) else null,
			vertex_count)
		arr[Mesh.ARRAY_COLOR] = cols

		var count_before = result.get_surface_count()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, _surface_build_flags(surf_idx))
		if result.get_surface_count() == count_before:
			return null  # Invalid array format (Godot 4.2+), use Per-Surface-Hybrid
		_apply_surface_material(result, surf_idx)

	return result if result.get_surface_count() > 0 else null


func _rebuild_runtime_mesh_cpp() -> bool:
	if _source_mesh == null or not _get_paint_core():
		return false
	var rebuilt = _paint_core_ref.apply_colors_to_mesh(_source_mesh, surface_data, _source_materials_cache)
	if rebuilt == null or rebuilt.get_surface_count() == 0:
		return false
	rebuilt.resource_name = _source_mesh.resource_name
	_runtime_mesh = rebuilt
	return true


func _mesh_has_surface_materials(mesh: Mesh) -> bool:
	for i in range(mesh.get_surface_count()):
		if mesh.surface_get_material(i):
			return true
	return false


func _pick_source_mesh(parent: MeshInstance3D, current_mesh: Mesh) -> Mesh:
	if current_mesh == null or current_mesh.get_surface_count() == 0:
		return null

	if parent.has_meta("_vertex_paint_original_path"):
		var path: String = parent.get_meta("_vertex_paint_original_path")
		if ResourceLoader.exists(path):
			var loaded = load(path)
			if loaded is Mesh and (loaded as Mesh).get_surface_count() > 0:
				return loaded

	if _mesh_has_compressed_surfaces(current_mesh):
		return current_mesh
	return current_mesh


const _PREVIEW_MATERIAL_SUFFIXES: PackedStringArray = [
	"check_vertex_color.tres",
	"vertex_color_preview_overlay.tres",
	"new_standard_material_3d.tres",
]


func _cache_source_arrays(source_mesh: Mesh) -> void:
	if not source_mesh is ArrayMesh:
		return
	var mesh: ArrayMesh = source_mesh as ArrayMesh
	for surf_idx in range(mesh.get_surface_count()):
		var format: int = mesh.surface_get_format(surf_idx)
		if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
			_source_arrays_cache[surf_idx] = null
			continue
		var arr: Array = mesh.surface_get_arrays(surf_idx)
		if arr == null or arr.size() < Mesh.ARRAY_MAX:
			_source_arrays_cache[surf_idx] = null
			continue
		var verts: Variant = arr[Mesh.ARRAY_VERTEX]
		if verts == null or not verts is PackedVector3Array:
			_source_arrays_cache[surf_idx] = null
			continue
		if (verts as PackedVector3Array).is_empty():
			_source_arrays_cache[surf_idx] = null
			continue
		_source_arrays_cache[surf_idx] = arr.duplicate(true)


func _cache_source_materials(parent: MeshInstance3D, source_mesh: Mesh) -> void:
	for surf_idx in range(source_mesh.get_surface_count()):
		if not _source_arrays_cache.has(surf_idx):
			_source_arrays_cache[surf_idx] = null
		var mat: Material = _resolve_surface_material(parent, source_mesh, surf_idx)
		if mat:
			_source_materials_cache[surf_idx] = mat


## Materials for rebuild: glTF surface mats, then current instance mesh (before any swap).
func _resolve_surface_material(parent: MeshInstance3D, source_mesh: Mesh, surf_idx: int) -> Material:
	var mat: Material = source_mesh.surface_get_material(surf_idx)
	if mat:
		return mat

	if parent.mesh and parent.mesh != source_mesh:
		mat = parent.mesh.surface_get_material(surf_idx)
		if mat:
			return mat

	var surf_override: Material = parent.get_surface_override_material(surf_idx)
	if surf_override and not _is_preview_paint_material(surf_override):
		return surf_override

	if parent.material_override == null:
		mat = parent.get_active_material(surf_idx)
		if mat and not _is_preview_paint_material(mat):
			return mat
	return null


func _is_preview_paint_material(mat: Material) -> bool:
	var path: String = mat.resource_path
	for suffix in _PREVIEW_MATERIAL_SUFFIXES:
		if path.ends_with(suffix):
			return true
	return false


## Re-apply glTF surface materials on the runtime mesh (material_override is separate).
func refresh_runtime_surface_materials() -> void:
	if _runtime_mesh == null or _source_mesh == null:
		return
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent:
		return
	for surf_idx in range(_runtime_mesh.get_surface_count()):
		var mat: Material = _resolve_surface_material(parent, _source_mesh, surf_idx)
		if mat:
			_runtime_mesh.surface_set_material(surf_idx, mat)


func repair_mesh_display_state() -> void:
	_attrib_upload_cache.clear()
	_sync_surface_data_to_gpu()


## Builds a mesh with surface_data applied (for preview overlay or bake). Does not change parent.mesh.
func build_colored_mesh() -> ArrayMesh:
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent or not parent.mesh:
		return null
	if not _prepare_rebuild_from_parent(parent):
		return null
	return _rebuild_colored_mesh_internal()


func _ensure_packed_color_array(val: Variant, vertex_count: int) -> PackedColorArray:
	if val is PackedColorArray:
		var c = val as PackedColorArray
		if c.size() != vertex_count:
			if vertex_count < c.size():
				c = c.slice(0, vertex_count)  # Copy, avoid mutating original in surface_data
			else:
				c.resize(vertex_count)
		return c
	if val is Array:
		var arr = val as Array
		var result = PackedColorArray()
		result.resize(vertex_count)
		for i in range(mini(arr.size(), vertex_count)):
			if arr[i] is Color:
				result[i] = arr[i]
			else:
				result[i] = Color.BLACK
		return result
	var c = PackedColorArray()
	c.resize(vertex_count)
	c.fill(Color.BLACK)
	return c


func _seed_surface_data_after_normalize(mesh: ArrayMesh) -> void:
	for surf_idx in range(mesh.get_surface_count()):
		if surface_data.has(surf_idx):
			var existing: Variant = surface_data[surf_idx]
			if existing is PackedColorArray and (existing as PackedColorArray).size() > 0:
				continue
		var vertex_count: int = _paint_vertex_count(mesh, surf_idx)
		if vertex_count <= 0:
			continue
		var cols := PackedColorArray()
		cols.resize(vertex_count)
		cols.fill(Color.BLACK)
		surface_data[surf_idx] = cols

func _prepare_rebuild_from_parent(parent: MeshInstance3D) -> bool:
	var current_mesh: Mesh = parent.mesh
	if current_mesh == null:
		return false

	var live_materials: Dictionary = {}
	for surf_idx in range(current_mesh.get_surface_count()):
		var live_mat: Material = _resolve_surface_material(parent, current_mesh, surf_idx)
		if live_mat:
			live_materials[surf_idx] = live_mat

	if _source_mesh == null or _source_arrays_cache.is_empty():
		var source_mesh: Mesh = _pick_source_mesh(parent, current_mesh)
		if source_mesh == null or source_mesh.get_surface_count() == 0:
			return false
		_source_mesh = source_mesh
		_source_arrays_cache.clear()
		_source_materials_cache.clear()
		_neighbor_cache.clear()
		_prep_cache(source_mesh)
		_cache_source_materials(parent, source_mesh)
		_cache_source_arrays(source_mesh)

	for surf_idx in live_materials:
		_source_materials_cache[surf_idx] = live_materials[surf_idx]

	if _mesh_has_compressed_surfaces(_source_mesh):
		VertexPainterLog.debug(
				"Source mesh has compressed attributes; rebuild may be slow. "
				+ "Enable meshes/force_disable_compression on the glTF import and reimport.")
	return true


func _rebuild_colored_mesh_internal() -> ArrayMesh:
	if _source_mesh == null or _source_arrays_cache.is_empty():
		return null

	var rebuilt: ArrayMesh = _try_surface_get_arrays_path()
	if rebuilt == null:
		if _mesh_has_compressed_surfaces(_source_mesh) and _rebuild_runtime_mesh_cpp():
			var cpp_mesh: ArrayMesh = _runtime_mesh as ArrayMesh
			if cpp_mesh.get_surface_count() > 0:
				cpp_mesh.resource_name = _source_mesh.resource_name
				return cpp_mesh
		rebuilt = _build_mesh_per_surface_hybrid()
	if rebuilt and rebuilt.get_surface_count() > 0:
		rebuilt.resource_name = _source_mesh.resource_name
		return rebuilt
	return null


## Bake / commit: rebuild mesh with COLOR and assign to MeshInstance (replaces glTF mesh).
func _apply_colors():
	var parent: MeshInstance3D = get_parent() as MeshInstance3D
	if not parent:
		return

	_attrib_upload_cache.clear()
	if not _prepare_rebuild_from_parent(parent):
		return

	var rebuilt: ArrayMesh = _rebuild_colored_mesh_internal()
	if rebuilt == null:
		return

	_runtime_mesh = rebuilt

	var instance_overrides: Dictionary = {}
	for idx in range(parent.get_surface_override_material_count()):
		var mat: Material = parent.get_surface_override_material(idx)
		if mat:
			instance_overrides[idx] = mat

	if parent.mesh != _runtime_mesh:
		parent.mesh = _runtime_mesh

	for idx in instance_overrides:
		if idx < parent.get_surface_override_material_count():
			parent.set_surface_override_material(idx, instance_overrides[idx])

	_cache_source_arrays(_runtime_mesh)
	_detect_paint_sync_mode(_runtime_mesh)

# --- UNDO / REDO API ---

func get_data_snapshot() -> Dictionary:
	return surface_data.duplicate(true)

func apply_data_snapshot(snapshot: Dictionary) -> void:
	_pending_gpu_surfaces.clear()
	_gpu_flush_scheduled = false
	surface_data = snapshot.duplicate(true)
	repair_mesh_display_state()
