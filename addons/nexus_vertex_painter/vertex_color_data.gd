@tool
extends Node
class_name VertexColorData

# Stores only the color data to keep .tscn files small and efficient.
@export var color_data: PackedColorArray

# Runtime cache for the mesh resource and source data
var _runtime_mesh: ArrayMesh
var _source_arrays: Array = []
var _source_material: Material

func _ready():
	request_ready()

func _enter_tree():
	call_deferred("_apply_colors")

func update_colors(new_colors: PackedColorArray):
	color_data = new_colors
	_apply_colors()

func _apply_colors():
	var parent = get_parent() as MeshInstance3D
	if not parent: return
	
	# --- 1. INITIALIZATION & SOURCE DATA CACHING ---
	
	var current_mesh = parent.mesh
	
	# Check if the current mesh is the original source (GLB/Scene) or our runtime copy.
	if current_mesh != _runtime_mesh:
		if current_mesh and current_mesh.get_surface_count() > 0:
			# Cache the original data so we can rebuild from it later
			_source_arrays = current_mesh.surface_get_arrays(0)
			_source_material = current_mesh.surface_get_material(0)
			
			# Create the runtime mesh container once
			if not _runtime_mesh:
				_runtime_mesh = ArrayMesh.new()
				_runtime_mesh.resource_name = current_mesh.resource_name
			
			# Assign the runtime mesh to the parent. From now on, we modify this instance.
			parent.mesh = _runtime_mesh
	
	# If source arrays are missing, we cannot proceed
	if _source_arrays.is_empty():
		return

	# --- 2. PREPARE DATA ---
	
	var vertex_count = _source_arrays[Mesh.ARRAY_VERTEX].size()
	
	# Validation: Ensure color data matches vertex count (e.g. after mesh re-import)
	if color_data.size() != vertex_count:
		color_data.resize(vertex_count)
	
	# Work on a copy of the source arrays to keep the original data clean
	var paint_arrays = _source_arrays.duplicate(true)
	paint_arrays[Mesh.ARRAY_COLOR] = color_data
	
	# --- 3. IN-PLACE UPDATE ---
	
	# Clear and rebuild the surface on the existing runtime mesh instance.
	# Keeping the object reference stable prevents the Editor Inspector from flickering.
	_runtime_mesh.clear_surfaces()
	
	# Note: We do not pass format flags here. We let Godot recalculate the format
	# based on the raw arrays to avoid issues with imported compression flags.
	_runtime_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, paint_arrays)
	
	# Restore the original material
	if _source_material:
		_runtime_mesh.surface_set_material(0, _source_material)
