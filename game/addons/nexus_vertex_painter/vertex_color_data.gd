@tool
extends Node
class_name VertexColorData

# --- STORAGE ---
# Format: { surface_index (int) : colors (PackedColorArray) }
@export var surface_data: Dictionary = {}

# --- RUNTIME CACHE ---
var _cache_positions: Dictionary = {} # { surface_idx: PackedVector3Array }
var _cache_normals: Dictionary = {}   # { surface_idx: PackedVector3Array }
var _neighbor_cache: Dictionary = {}  # { surface_idx: { vertex_idx: [neighbor_idx, ...] } } (Used for Blur)
var _cached_mesh: Mesh = null # Mesh reference for cache invalidation

var _runtime_mesh: ArrayMesh
var _source_mesh: Mesh  # Original mesh (for MeshDataTool - avoids Godot 4.2+ compressed array format issues)
var _source_arrays_cache: Dictionary = {} # Maps surface_index -> Array (for _prep_cache / get_positions etc.)
var _source_materials_cache: Dictionary = {} # Maps surface_index -> Material

# Phase 2: C++ acceleration - use apply_colors_to_mesh instead of GDScript MeshDataTool loop
var _paint_core_ref: RefCounted = null

const DATA_VERSION = 2

func _ready():
	request_ready()

func _enter_tree():
	# Clear caches only when mesh changed (avoids unnecessary _prep_cache on every enter)
	var parent = get_parent() as MeshInstance3D
	var current_mesh = parent.mesh if parent else null
	if current_mesh != _cached_mesh or _cached_mesh == null:
		_cache_positions.clear()
		_cache_normals.clear()
		_cached_mesh = null
	_neighbor_cache.clear() # Topology-dependent, cheap to rebuild
	
	# Re-apply colors ensures the mesh is built correctly from the stored 'surface_data'
	call_deferred("_apply_colors")

# --- INITIALIZATION ---

func initialize_from_mesh():
	# Called when the node is created. Imports existing colors (e.g., from a bake)
	# so we don't start with a black mesh.
	var parent = get_parent() as MeshInstance3D
	if not parent or not parent.mesh: return
	
	var mesh = parent.mesh
	_prep_cache(mesh) # Build cache immediately
	
	for i in range(mesh.get_surface_count()):
		var format = mesh.surface_get_format(i)
		if (format & Mesh.ARRAY_FORMAT_COLOR) == 0:
			continue
		var mdt = MeshDataTool.new()
		if mdt.create_from_surface(mesh, i) != OK:
			continue
		var vc = mdt.get_vertex_count()
		var colors = PackedColorArray()
		colors.resize(vc)
		for j in range(vc):
			colors[j] = mdt.get_vertex_color(j)
		surface_data[i] = colors

# --- CACHE MANAGEMENT ---

## Uses MeshDataTool instead of surface_get_arrays for Godot 4.2+ compatibility.
## Compressed mesh formats can return invalid/empty arrays from surface_get_arrays.
func _prep_cache(mesh: Mesh):
	_cache_positions.clear()
	_cache_normals.clear()
	_cached_mesh = mesh
	
	for i in range(mesh.get_surface_count()):
		var mdt = MeshDataTool.new()
		if mdt.create_from_surface(mesh, i) != OK:
			continue
		var vc = mdt.get_vertex_count()
		var verts = PackedVector3Array()
		verts.resize(vc)
		var norms = PackedVector3Array()
		norms.resize(vc)
		for j in range(vc):
			verts[j] = mdt.get_vertex(j)
			norms[j] = mdt.get_vertex_normal(j)
		_cache_positions[i] = verts
		_cache_normals[i] = norms

# Public getters for the painter (High Performance)
func get_positions(surf_idx: int) -> PackedVector3Array:
	if not _cache_positions.has(surf_idx): return PackedVector3Array()
	return _cache_positions[surf_idx]

func get_normals(surf_idx: int) -> PackedVector3Array:
	if not _cache_normals.has(surf_idx): return PackedVector3Array()
	return _cache_normals[surf_idx]

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

func _build_neighbor_cache(surf_idx: int):
	var parent = get_parent() as MeshInstance3D
	if not parent or not parent.mesh: return
	
	# We use MeshDataTool ONLY here for topology analysis
	var mdt = MeshDataTool.new()
	if mdt.create_from_surface(parent.mesh, surf_idx) != OK:
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

func update_surface_colors(surface_idx: int, new_colors: PackedColorArray):
	surface_data[surface_idx] = new_colors

	# Phase 3: Fast path - surface_update_attribute_region if mesh has USE_DYNAMIC_UPDATE
	if _try_fast_color_update(surface_idx, new_colors):
		return
	_apply_colors()


func _get_paint_core() -> bool:
	if _paint_core_ref != null:
		return _paint_core_ref.has_method("apply_colors_to_mesh")
	if ClassDB.class_exists("VertexPainterCore"):
		_paint_core_ref = ClassDB.instantiate("VertexPainterCore")
	return _paint_core_ref != null and _paint_core_ref.has_method("apply_colors_to_mesh")


## Phase 3: Update only color attribute via surface_update_attribute_region (no full rebuild).
## Returns true if fast path succeeded, false to fall back to _apply_colors().
func _try_fast_color_update(surface_idx: int, new_colors: PackedColorArray) -> bool:
	if _runtime_mesh == null or surface_idx < 0 or surface_idx >= _runtime_mesh.get_surface_count():
		return false
	var format := _runtime_mesh.surface_get_format(surface_idx)
	if (format & Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE) == 0:
		return false
	var vertex_count := _runtime_mesh.surface_get_array_len(surface_idx)
	if new_colors.size() != vertex_count:
		return false
	if not _get_paint_core() or not _paint_core_ref.has_method("pack_colors_to_rgba8"):
		return false
	var color_bytes: PackedByteArray = _paint_core_ref.pack_colors_to_rgba8(new_colors)
	if color_bytes.size() != vertex_count * 4:
		return false
	# Note: surface_update_attribute_region returns void in Godot 4; on failure it prints errors.
	# Format checks above (USE_DYNAMIC_UPDATE etc.) filter most problematic cases.
	_runtime_mesh.surface_update_attribute_region(surface_idx, 0, color_bytes)
	return true


## Single surface: try surface_get_arrays if not compressed. Returns true if added, false to use MeshDataTool.
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
	var cols = _ensure_packed_color_array(
		surface_data.get(surf_idx) if surface_data.has(surf_idx) else null,
		vertex_count)
	arr[Mesh.ARRAY_COLOR] = cols

	var count_before = result.get_surface_count()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if result.get_surface_count() == count_before:
		return false  # add_surface_from_arrays failed (e.g. invalid arrays), use MeshDataTool
	var mat = _source_materials_cache.get(surf_idx)
	if mat:
		result.surface_set_material(result.get_surface_count() - 1, mat)
	return true


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
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat = _source_materials_cache.get(surf_idx)
	if mat:
		result.surface_set_material(result.get_surface_count() - 1, mat)


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
		var cols = _ensure_packed_color_array(
			surface_data.get(surf_idx) if surface_data.has(surf_idx) else null,
			vertex_count)
		arr[Mesh.ARRAY_COLOR] = cols

		var count_before = result.get_surface_count()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if result.get_surface_count() == count_before:
			return null  # Invalid array format (Godot 4.2+), use Per-Surface-Hybrid
		var mat = _source_materials_cache.get(surf_idx)
		if mat:
			result.surface_set_material(result.get_surface_count() - 1, mat)

	return result if result.get_surface_count() > 0 else null


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
	# Fallback: black
	var c = PackedColorArray()
	c.resize(vertex_count)
	c.fill(Color.BLACK)
	return c

func _apply_colors():
	var parent = get_parent() as MeshInstance3D
	if not parent: return
	
	var current_mesh = parent.mesh

	# 1. Handle Mesh Switching / Init
	if current_mesh != _runtime_mesh:
		if current_mesh and current_mesh.get_surface_count() > 0:
			_source_mesh = current_mesh
			_source_arrays_cache.clear()
			_source_materials_cache.clear()
			_prep_cache(current_mesh) # Refresh cache if mesh changed
			
			for i in range(current_mesh.get_surface_count()):
				_source_arrays_cache[i] = true # Placeholder for iteration; avoids surface_get_arrays (Godot 4.2+ compressed format)
				_source_materials_cache[i] = current_mesh.surface_get_material(i)
			
			if not _runtime_mesh:
				_runtime_mesh = ArrayMesh.new()
				_runtime_mesh.resource_name = current_mesh.resource_name

	if _source_mesh == null or _source_arrays_cache.is_empty(): return

	# 2. Rescue Instance Overrides
	var instance_overrides = {}
	for idx in range(parent.get_surface_override_material_count()):
		var mat = parent.get_surface_override_material(idx)
		if mat: instance_overrides[idx] = mat

	# 3. Rebuild Runtime Mesh
	# Fast path: surface_get_arrays when ALL surfaces non-compressed.
	# Per-Surface-Hybrid: when any surface compressed, use surface_get_arrays per surface where possible.
	var rebuilt: ArrayMesh = null
	rebuilt = _try_surface_get_arrays_path()
	if rebuilt == null:
		# At least one surface compressed or validation failed -> Per-Surface-Hybrid preserves UVs on non-compressed surfaces
		rebuilt = _build_mesh_per_surface_hybrid()
	if rebuilt and rebuilt.get_surface_count() > 0:
		rebuilt.resource_name = _source_mesh.resource_name
		_runtime_mesh = rebuilt

	# 4. Reattach - only if rebuild succeeded (avoid invisible mesh)
	if _runtime_mesh == null or _runtime_mesh.get_surface_count() == 0:
		return  # Keep original mesh

	parent.mesh = _runtime_mesh
	
	for idx in instance_overrides:
		if idx < parent.get_surface_override_material_count():
			parent.set_surface_override_material(idx, instance_overrides[idx])

# --- UNDO / REDO API ---

func get_data_snapshot() -> Dictionary:
	return surface_data.duplicate(true)

func apply_data_snapshot(snapshot: Dictionary):
	surface_data = snapshot.duplicate(true)
	_apply_colors()
