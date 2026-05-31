class_name VertexPaintMeshCombine
extends RefCounted

const COMBINED_MESH_DEFAULT_NAME := "CombinedMesh"


func count_combinable_mesh_instances(nodes: Array) -> int:
	var count := 0
	for node in nodes:
		if is_combinable_mesh_instance(node):
			count += 1
	return count


func is_combinable_mesh_instance(node: Node) -> bool:
	if not node is MeshInstance3D:
		return false
	var mesh_instance := node as MeshInstance3D
	if mesh_instance.mesh == null or not (mesh_instance.mesh is ArrayMesh):
		return false
	return (mesh_instance.mesh as ArrayMesh).get_surface_count() > 0


func combine_mesh_instances(mesh_instances: Array[MeshInstance3D]) -> Dictionary:
	var final_mesh := ArrayMesh.new()

	for mesh_instance in mesh_instances:
		var source_mesh := _mesh_for_combine(mesh_instance)
		if source_mesh == null:
			continue
		var world_xform := mesh_instance.global_transform
		for surface_idx in range(source_mesh.get_surface_count()):
			var surface_tool := SurfaceTool.new()
			surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface_tool.set_material(source_mesh.surface_get_material(surface_idx))
			surface_tool.append_from(source_mesh, surface_idx, world_xform)
			surface_tool.commit(final_mesh)

	if final_mesh.get_surface_count() == 0:
		return {"mesh": final_mesh, "world_pivot": Vector3.ZERO}

	return _center_mesh_at_aabb(final_mesh)


func _mesh_for_combine(mesh_instance: MeshInstance3D) -> Mesh:
	var data_node := mesh_instance.get_node_or_null("VertexColorData")
	if data_node is VertexColorData:
		var color_data := data_node as VertexColorData
		if not color_data.surface_data.is_empty():
			if color_data.has_method("flush_gpu_updates"):
				color_data.flush_gpu_updates()
			color_data._apply_colors()
	return mesh_instance.mesh


func _center_mesh_at_aabb(mesh: ArrayMesh) -> Dictionary:
	var aabb := mesh.get_aabb()
	var center := aabb.position + aabb.size * 0.5
	if center.length_squared() < 1e-12:
		return {"mesh": mesh, "world_pivot": center}

	var centered := ArrayMesh.new()
	for surface_idx in range(mesh.get_surface_count()):
		var mesh_data_tool := MeshDataTool.new()
		mesh_data_tool.create_from_surface(mesh, surface_idx)
		for vertex_idx in range(mesh_data_tool.get_vertex_count()):
			mesh_data_tool.set_vertex(vertex_idx, mesh_data_tool.get_vertex(vertex_idx) - center)
		mesh_data_tool.commit_to_surface(centered)
		var material := mesh.surface_get_material(surface_idx)
		if material:
			centered.surface_set_material(centered.get_surface_count() - 1, material)
	return {"mesh": centered, "world_pivot": center}


func resolve_insert_parent(mesh_instances: Array[MeshInstance3D], scene_root: Node) -> Node:
	if mesh_instances.is_empty():
		return scene_root
	var shared_parent := mesh_instances[0].get_parent()
	for mesh_instance in mesh_instances:
		if mesh_instance.get_parent() != shared_parent:
			return scene_root
	return shared_parent if shared_parent else scene_root


func unique_combined_name(parent: Node) -> String:
	var base_name := COMBINED_MESH_DEFAULT_NAME
	if not parent.has_node(base_name):
		return base_name
	var index := 2
	while parent.has_node("%s_%d" % [base_name, index]):
		index += 1
	return "%s_%d" % [base_name, index]
