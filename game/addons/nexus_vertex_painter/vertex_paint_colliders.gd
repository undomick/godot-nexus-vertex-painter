class_name VertexPaintColliders
extends RefCounted

const DEFAULT_COLLISION_LAYER := 30
const VERTEX_COLOR_DATA_SCRIPT := "res://addons/nexus_vertex_painter/vertex_color_data.gd"

var _bake := VertexPaintBake.new()


func get_paint_collision_mask() -> int:
	var layer_idx = DEFAULT_COLLISION_LAYER
	if ProjectSettings.has_setting("nexus/vertex_painter/collision_layer"):
		var val = ProjectSettings.get_setting("nexus/vertex_painter/collision_layer")
		if val != null:
			layer_idx = val
	layer_idx = clamp(layer_idx, 1, 32)
	return 1 << (layer_idx - 1)


func refresh_selection_and_colliders(plugin: EditorPlugin, preview: VertexPaintPreview) -> void:
	var selection := plugin.get_editor_interface().get_selection().get_selected_nodes()
	var new_mesh_list: Array[MeshInstance3D] = []

	selection = selection.filter(func(node):
		return is_instance_valid(node)
	)

	for node in selection:
		if node is MeshInstance3D:
			new_mesh_list.append(node)

	if plugin.paint_mode_active:
		for mesh in new_mesh_list:
			if not mesh.has_meta("_edit_lock_"):
				mesh.notify_property_list_changed()
				mesh.update_gizmos()

		for i in range(plugin.locked_nodes.size() - 1, -1, -1):
			var mesh = plugin.locked_nodes[i]
			if is_instance_valid(mesh) and not (mesh in new_mesh_list):
				if mesh.has_meta("_edit_lock_"):
					mesh.remove_meta("_edit_lock_")
					mesh.notify_property_list_changed()
					mesh.update_gizmos()
				plugin.locked_nodes.remove_at(i)
			elif not is_instance_valid(mesh):
				plugin.locked_nodes.remove_at(i)

	for mesh in new_mesh_list:
		if not _has_internal_collider(plugin, mesh):
			_create_collider_for(plugin, mesh)

	for i in range(plugin.temp_colliders.size() - 1, -1, -1):
		var node: Node = plugin.temp_colliders[i]
		if not is_instance_valid(node):
			plugin.temp_colliders.remove_at(i)
			continue
		if not is_instance_valid(node.get_parent()) or node.get_parent() not in new_mesh_list:
			node.queue_free()
			plugin.temp_colliders.remove_at(i)

	plugin.selected_meshes = new_mesh_list
	preview.sync_vertex_color_preview(plugin, self)


func on_selection_changed(plugin: EditorPlugin, preview: VertexPaintPreview) -> void:
	if plugin.paint_mode_active:
		refresh_selection_and_colliders(plugin, preview)
		preview.update_shader_debug_view(plugin)
		preview.update_smart_mask_preview(plugin, self)
		plugin.dock_instance.set_selection_empty(plugin.selected_meshes.is_empty())


func clear_all_locks(plugin: EditorPlugin) -> void:
	for mesh in plugin.locked_nodes:
		if is_instance_valid(mesh):
			if mesh.has_meta("_edit_lock_"):
				mesh.remove_meta("_edit_lock_")
				mesh.notify_property_list_changed()
				mesh.update_gizmos()
	plugin.locked_nodes.clear()


func _has_internal_collider(plugin: EditorPlugin, mesh: MeshInstance3D) -> bool:
	for child in mesh.get_children():
		if child in plugin.temp_colliders:
			return true
	return false


func _create_collider_for(plugin: EditorPlugin, mesh_instance: MeshInstance3D) -> void:
	if not mesh_instance.mesh:
		return
	if mesh_instance.mesh.get_surface_count() == 0:
		return

	var sb = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = mesh_instance.mesh.create_trimesh_shape()
	if not shape:
		col.free()
		sb.free()
		return
	col.shape = shape
	sb.add_child(col)
	sb.collision_layer = get_paint_collision_mask()
	sb.collision_mask = 0
	sb.owner = null

	mesh_instance.add_child(sb, true, Node.INTERNAL_MODE_BACK)
	plugin.temp_colliders.append(sb)

	var phantom = MeshInstance3D.new()
	phantom.mesh = mesh_instance.mesh
	phantom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	phantom.material_override = plugin.shared_brush_material
	mesh_instance.add_child(phantom, true, Node.INTERNAL_MODE_BACK)
	plugin.temp_colliders.append(phantom)


func clear_all_colliders(plugin: EditorPlugin) -> void:
	for node in plugin.temp_colliders:
		if is_instance_valid(node):
			if node is MeshInstance3D:
				node.material_override = null
			node.queue_free()
	plugin.temp_colliders.clear()


func get_or_create_data_node(plugin: EditorPlugin, mesh_instance: MeshInstance3D) -> VertexColorData:
	if not mesh_instance.has_meta("_vertex_paint_original_path"):
		var path: String = _bake.infer_original_mesh_path(mesh_instance)
		if not path.is_empty():
			mesh_instance.set_meta("_vertex_paint_original_path", path)

	for child in mesh_instance.get_children():
		if child is VertexColorData:
			return child

	for child in mesh_instance.get_children():
		if child.name == "VertexColorData":
			var script_ref = child.get_script()
			var valid = script_ref != null and script_ref.resource_path == VERTEX_COLOR_DATA_SCRIPT
			if not valid:
				child.queue_free()
				break

	var node = VertexColorData.new()
	node.name = "VertexColorData"
	mesh_instance.add_child(node, true)
	node.initialize_from_mesh()

	var scene_root = plugin.get_editor_interface().get_edited_scene_root()
	if scene_root:
		plugin.call_deferred("_assign_scene_owner", node, scene_root)

	return node
