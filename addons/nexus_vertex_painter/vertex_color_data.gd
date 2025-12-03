@tool
extends Node
class_name VertexColorData

# Stores only the color data to keep .tscn files small.
@export var color_data: PackedColorArray

func _ready():
	# Apply colors when the node enters the scene (Editor load or Game start)
	request_ready()

func _enter_tree():
	# Ensure colors are applied even if the node is reparented
	call_deferred("_apply_colors")

# Public API to update data and refresh the mesh
func update_colors(new_colors: PackedColorArray):
	color_data = new_colors
	_apply_colors()

func _apply_colors():
	var parent = get_parent() as MeshInstance3D
	if not parent or not parent.mesh: return
	
	if color_data.is_empty(): return
	
	# 1. Get geometry from current mesh
	var source_mesh = parent.mesh
	if source_mesh.get_surface_count() == 0: return
	
	var arrays = source_mesh.surface_get_arrays(0)
	var vertex_count = arrays[Mesh.ARRAY_VERTEX].size()
	
	# 2. Validation: Resize storage if mesh geometry changed (e.g. re-import)
	if color_data.size() != vertex_count:
		color_data.resize(vertex_count)
	
	# 3. Inject stored colors into the geometry arrays
	arrays[Mesh.ARRAY_COLOR] = color_data
	
	# 4. Construct a new runtime Mesh
	# We do NOT pass flags/format to force Godot to recalculate a clean format.
	# This prevents "black mesh" or compression artifacts.
	var new_mesh = ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Restore material and name
	new_mesh.surface_set_material(0, source_mesh.surface_get_material(0))
	new_mesh.resource_name = source_mesh.resource_name
	
	# 5. Swap the mesh on the instance
	parent.mesh = new_mesh
