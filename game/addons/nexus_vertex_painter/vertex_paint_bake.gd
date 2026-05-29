class_name VertexPaintBake
extends RefCounted

var _gltf_mesh_path_cache: Dictionary = {}


func infer_gltf_mesh_path(gltf_scene_path: String, mesh_node_name: String) -> String:
	var cache_key: String = gltf_scene_path + "|" + mesh_node_name
	if _gltf_mesh_path_cache.has(cache_key):
		return _gltf_mesh_path_cache[cache_key]

	var scene := load(gltf_scene_path) as PackedScene
	if scene == null:
		return ""

	var inst = scene.instantiate()
	var mi := inst.find_child(mesh_node_name, true, false) as MeshInstance3D
	var path: String = ""
	if mi and mi.mesh:
		path = mi.mesh.resource_path
	inst.free()

	_gltf_mesh_path_cache[cache_key] = path
	return path


func infer_original_mesh_path(mesh_instance: MeshInstance3D) -> String:
	if mesh_instance.mesh:
		var direct: String = mesh_instance.mesh.resource_path
		if not direct.is_empty():
			return direct

	var gltf_lookup_name: String = mesh_instance.name
	var node: Node = mesh_instance
	while node:
		var scene_path: String = node.scene_file_path
		if scene_path.ends_with(".gltf") or scene_path.ends_with(".glb"):
			return infer_gltf_mesh_path(scene_path, gltf_lookup_name)
		if node.name == "BigMesh_VP_TEST":
			return infer_gltf_mesh_path(
					"res://props/assets/big_mesh/BigMesh_VP_TEST.gltf",
					gltf_lookup_name
			)
		node = node.get_parent()
	return ""


func get_ancestor_scene_root(plugin: EditorPlugin, node: Node) -> Node:
	var current := node
	while current:
		if current.scene_file_path != "":
			return current
		current = current.get_parent()
	return plugin.get_editor_interface().get_edited_scene_root()


func bake_vertex_color_data_in_scene(plugin: EditorPlugin, scene_root: Node) -> bool:
	if not scene_root:
		return false

	var data_nodes: Array = scene_root.find_children("*", "VertexColorData", true, false)
	if data_nodes.is_empty():
		return true

	var baked_any := false
	var nodes_to_remove: Array[VertexColorData] = []
	for data_node in data_nodes:
		if not is_instance_valid(data_node):
			continue
		var mesh_instance := data_node.get_parent() as MeshInstance3D
		if not mesh_instance or not mesh_instance.mesh:
			continue
		data_node._apply_colors()
		mesh_instance.mesh = mesh_instance.mesh.duplicate()
		plugin.undo_snapshots.erase(data_node)
		nodes_to_remove.append(data_node)
		baked_any = true

	if baked_any:
		plugin.get_undo_redo().clear_history(false)
		for data_node in nodes_to_remove:
			if not is_instance_valid(data_node):
				continue
			var parent := data_node.get_parent()
			if parent:
				parent.remove_child(data_node)
			data_node.free()

	return baked_any


func save_scene_root_to_path(scene_root: Node, path: String) -> bool:
	var save_root := scene_root.duplicate()
	var original_transform = scene_root.property_get_revert(&"transform")
	if original_transform:
		save_root.transform = original_transform

	var lower_path = path.to_lower()
	if lower_path.ends_with(".tscn") or lower_path.ends_with(".scn"):
		var packed_scene := PackedScene.new()
		var pack_error := packed_scene.pack(save_root)
		if pack_error != OK:
			VertexPainterLog.error("Failed to pack scene root for saving: " + error_string(pack_error))
			return false
		var save_error := ResourceSaver.save(packed_scene, path)
		if save_error != OK:
			VertexPainterLog.error("Failed to save packed scene: " + error_string(save_error))
			return false
		return true

	if lower_path.ends_with(".gltf") or lower_path.ends_with(".glb"):
		var gltf_document := GLTFDocument.new()
		var gltf_state := GLTFState.new()
		gltf_state.base_path = path.get_base_dir()
		var append_error := gltf_document.append_from_scene(save_root, gltf_state)
		if append_error != OK:
			VertexPainterLog.error("Failed to convert scene to glTF: " + error_string(append_error))
			return false
		var write_error := gltf_document.write_to_filesystem(gltf_state, path)
		if write_error != OK:
			VertexPainterLog.error("Failed to write glTF scene: " + error_string(write_error))
			return false
		return true

	VertexPainterLog.error("Unsupported scene file type for Bake to Scene: " + path)
	return false


static func is_preview_vertex_color_material(mat: Material, preview_paths: Dictionary) -> bool:
	if mat == null:
		return false
	var path: String = mat.resource_path
	return path == preview_paths.vertex_color \
			or path == preview_paths.overlay \
			or path == preview_paths.standard_vc \
			or path.ends_with("check_vertex_color.tres") \
			or path.ends_with("vertex_color_preview_overlay.tres") \
			or path.ends_with("new_standard_material_3d.tres")


func on_bake_requested(plugin: EditorPlugin) -> void:
	if plugin.selected_meshes.is_empty():
		VertexPainterLog.warn("No mesh selected to bake. Please select a MeshInstance3D.")
		return

	var mesh_instance = plugin.selected_meshes[0]
	if not mesh_instance.mesh:
		VertexPainterLog.warn("Selected mesh has no mesh resource. Cannot bake.")
		return

	var original_name = mesh_instance.mesh.resource_name
	if original_name == "":
		original_name = "painted_mesh"

	plugin.file_dialog.current_file = original_name + "_painted.res"
	plugin.file_dialog.popup_centered_ratio(0.5)


func on_bake_to_scene_requested(plugin: EditorPlugin) -> void:
	if plugin.selected_meshes.is_empty():
		VertexPainterLog.warn("No mesh selected to bake. Please select a MeshInstance3D.")
		return

	var mesh_instance = plugin.selected_meshes[0]
	if not mesh_instance.mesh:
		VertexPainterLog.warn("Selected mesh has no mesh resource. Cannot bake.")
		return

	var scene_root := get_ancestor_scene_root(plugin, mesh_instance)
	if not scene_root:
		VertexPainterLog.warn(
				"Selected mesh is not part of a saved scene. Open a saved .tscn, .scn, .gltf, or .glb scene to bake to scene file.")
		return

	var current_scene_root := plugin.get_editor_interface().get_edited_scene_root()
	var scene_path := scene_root.scene_file_path
	if scene_path == "":
		VertexPainterLog.warn("Ancestor scene has no file path. Save the scene before baking to file.")
		return

	if not bake_vertex_color_data_in_scene(plugin, scene_root):
		VertexPainterLog.warn("Bake to Scene aborted because no mesh data could be baked.")
		return

	plugin._on_mode_toggled(false)

	if not save_scene_root_to_path(scene_root, scene_path):
		VertexPainterLog.error("Failed to save scene to " + scene_path)
		return

	plugin.get_editor_interface().get_resource_filesystem().reimport_files([scene_path])
	plugin.get_editor_interface().reload_scene_from_path(current_scene_root.scene_file_path)
	plugin._on_mode_toggled(true)

	print_rich("[color=cyan]Baked vertex colors into scene file: %s.[/color]" % scene_path)


func on_bake_file_selected(plugin: EditorPlugin, path: String, colliders: VertexPaintColliders, preview: VertexPaintPreview) -> void:
	if plugin.selected_meshes.is_empty():
		return
	var mesh_instance = plugin.selected_meshes[0]
	if not mesh_instance.mesh:
		VertexPainterLog.error("Cannot bake: selected mesh has no mesh resource.")
		return
	var data_node := colliders.get_or_create_data_node(plugin, mesh_instance)

	data_node._apply_colors()
	var final_mesh = mesh_instance.mesh.duplicate()

	var err = ResourceSaver.save(final_mesh, path)
	if err != OK:
		VertexPainterLog.error("Failed to save mesh to " + path + ". Check file permissions and path.")
		return

	var loaded_mesh = load(path)
	if not loaded_mesh:
		VertexPainterLog.error("Failed to load baked mesh from " + path)
		return
	if not loaded_mesh is Mesh:
		VertexPainterLog.error("Loaded resource is not a Mesh: " + path)
		return

	mesh_instance.mesh = loaded_mesh
	plugin.undo_snapshots.erase(data_node)
	plugin.get_undo_redo().clear_history(false)
	data_node.queue_free()

	VertexPainterLog.debug("Baked mesh to " + path)
	preview.clear_preview_overlays(plugin, false)
	colliders.refresh_selection_and_colliders(plugin, preview)


func do_revert(plugin: EditorPlugin, colliders: VertexPaintColliders, preview: VertexPaintPreview) -> void:
	preview.clear_vertex_color_preview(plugin)
	var reverted_count = 0
	var paths := preview.get_preview_material_paths()

	for mesh_instance in plugin.selected_meshes:
		if not is_instance_valid(mesh_instance):
			continue
		if mesh_instance.has_meta("_vertex_paint_original_path"):
			var original_path = mesh_instance.get_meta("_vertex_paint_original_path")
			if ResourceLoader.exists(original_path):
				var original_mesh = load(original_path)
				if original_mesh and original_mesh is Mesh:
					mesh_instance.mesh = original_mesh
					reverted_count += 1
				elif not original_mesh:
					VertexPainterLog.error("Could not load original mesh from " + str(original_path))
				else:
					VertexPainterLog.error("Loaded resource is not a Mesh: " + str(original_path))
			else:
				VertexPainterLog.error("Original file not found: " + str(original_path))
		else:
			VertexPainterLog.warn(
					"Mesh '%s' has no _vertex_paint_original_path; cannot restore geometry." % mesh_instance.name)

		if is_preview_vertex_color_material(mesh_instance.material_override, paths):
			mesh_instance.material_override = null

		for child in mesh_instance.get_children():
			if child is VertexColorData or child.name == "VertexColorData":
				child.queue_free()

	if reverted_count > 0:
		VertexPainterLog.debug("Reverted " + str(reverted_count) + " meshes to original state.")
		colliders.refresh_selection_and_colliders(plugin, preview)
	else:
		VertexPainterLog.warn(
				"No mesh could be reverted. Select a painted MeshInstance3D with a valid original path.")
