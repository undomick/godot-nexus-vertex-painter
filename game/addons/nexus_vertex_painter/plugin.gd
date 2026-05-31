@tool
extends EditorPlugin

const DOCK_SCENE = preload("res://addons/nexus_vertex_painter/painter_dock.tscn")

var dock: EditorDock
var dock_instance: Control
var btn_mode: Button
var shared_brush_material: ShaderMaterial

var selected_meshes: Array[MeshInstance3D] = []
var temp_colliders: Array[Node] = []
var locked_nodes: Array[MeshInstance3D] = []

var is_painting: bool = false
var paint_mode_active: bool = false

var is_adjusting_brush: bool = false
var adjust_mode: int = 0

var undo_snapshots: Dictionary = {}

var _cached_brush_image: Image = null
var _last_brush_texture: Texture2D = null

var _use_cpp: bool = false
var _paint_core: RefCounted = null
var _cpp_paint_surface_has_projection: bool = false

var _warned_large_meshes: Dictionary = {}
var _logged_paint_diagnostics: Dictionary = {}

var _vertex_color_preview_active: bool = false
var _vertex_color_preview_overlays: Dictionary = {}
var _vertex_color_preview_mat: Material = null

var _paint_motion_counter: int = 0
var _preview_stored_state: Dictionary = {}

var file_dialog: EditorFileDialog
var snapshot_export_dialog: EditorFileDialog
var snapshot_import_dialog: EditorFileDialog
var revert_confirm_dialog: ConfirmationDialog
var _pending_snapshot_export: VertexColorPaintSnapshot = null

var _colliders := VertexPaintColliders.new()
var _stroke := VertexPaintStroke.new()
var _input := VertexPaint3DInput.new()
var _preview := VertexPaintPreview.new()
var _bake := VertexPaintBake.new()
var _mesh_combine := VertexPaintMeshCombine.new()


func _enter_tree():
	dock = EditorDock.new()
	dock.title = "Vertex Painter"
	dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL

	var editor_base = get_editor_interface().get_base_control()
	if editor_base.has_theme_icon("Edit", "EditorIcons"):
		dock.dock_icon = editor_base.get_theme_icon("Edit", "EditorIcons")

	dock_instance = DOCK_SCENE.instantiate()
	dock.add_child(dock_instance)
	add_dock(dock)

	dock_instance.fill_requested.connect(_on_fill_requested)
	dock_instance.clear_requested.connect(_on_clear_requested)
	dock_instance.settings_changed.connect(_on_settings_changed)
	dock_instance.texture_changed.connect(_on_texture_changed)
	dock_instance.procedural_requested.connect(_on_procedural_requested)
	dock_instance.bake_requested.connect(_on_bake_requested)
	dock_instance.bake_to_scene_requested.connect(_on_bake_to_scene_requested)
	dock_instance.revert_requested.connect(_on_revert_requested)
	dock_instance.export_snapshot_requested.connect(_on_export_snapshot_requested)
	dock_instance.transfer_snapshot_requested.connect(_on_transfer_snapshot_requested)
	dock_instance.combine_meshes_requested.connect(_on_combine_meshes_requested)
	dock_instance.show_vertex_colors_toggled.connect(_on_show_vertex_colors_toggled)
	dock_instance.set_ui_active(false)

	revert_confirm_dialog = ConfirmationDialog.new()
	revert_confirm_dialog.dialog_text = "Revert selected meshes to their original state? This cannot be undone."
	revert_confirm_dialog.confirmed.connect(_do_revert)
	get_editor_interface().get_base_control().add_child(revert_confirm_dialog)

	btn_mode = Button.new()
	btn_mode.text = "Vertex Paint"
	btn_mode.tooltip_text = "Toggle Vertex Paint Mode"
	btn_mode.toggle_mode = true
	btn_mode.toggled.connect(_on_mode_toggled)

	_setup_project_settings()

	file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.filters = ["*.tres", "*.res"]
	file_dialog.file_selected.connect(_on_bake_file_selected)
	get_editor_interface().get_base_control().add_child(file_dialog)

	snapshot_export_dialog = EditorFileDialog.new()
	snapshot_export_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	snapshot_export_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	snapshot_export_dialog.filters = PackedStringArray(["*.tres", "*.res"])
	snapshot_export_dialog.file_selected.connect(_on_snapshot_export_file_selected)
	get_editor_interface().get_base_control().add_child(snapshot_export_dialog)

	snapshot_import_dialog = EditorFileDialog.new()
	snapshot_import_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	snapshot_import_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	snapshot_import_dialog.filters = PackedStringArray(["*.tres", "*.res"])
	snapshot_import_dialog.file_selected.connect(_on_snapshot_import_file_selected)
	get_editor_interface().get_base_control().add_child(snapshot_import_dialog)

	if editor_base.has_theme_icon("Edit", "EditorIcons"):
		btn_mode.icon = editor_base.get_theme_icon("Edit", "EditorIcons")

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, btn_mode)

	_preview.init_shared_brush_material(self)

	if ClassDB.class_exists("VertexPainterCore"):
		_paint_core = ClassDB.instantiate("VertexPainterCore")
		if _paint_core:
			_use_cpp = true
			_cpp_paint_surface_has_projection = VertexPaintStroke.detect_cpp_paint_surface_projection()
			var cpp_version := ""
			if _paint_core.has_method("get_version"):
				cpp_version = " v%s" % _paint_core.get_version()
			VertexPainterLog.debug("C++ GDExtension%s loaded for improved performance." % cpp_version)
		else:
			_use_cpp = false

	var mode_str := "C++ Mode" if (_use_cpp and _paint_core) else "GDScript Mode"
	if _use_cpp and _paint_core and _paint_core.has_method("get_version"):
		mode_str += " v%s" % _paint_core.get_version()
	print_rich("[color=green]Nexus Vertex Painter: initialized in %s.[/color]" % mode_str)

	var selection = get_editor_interface().get_selection()
	if not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)


func _setup_project_settings():
	var setting_path = "nexus/vertex_painter/collision_layer"
	if not ProjectSettings.has_setting(setting_path):
		ProjectSettings.set_setting(setting_path, VertexPaintColliders.DEFAULT_COLLISION_LAYER)
	ProjectSettings.set_initial_value(setting_path, VertexPaintColliders.DEFAULT_COLLISION_LAYER)
	ProjectSettings.add_property_info({
		"name": setting_path,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "1,32",
	})

	var debug_path = "nexus/vertex_painter/debug_logging"
	if not ProjectSettings.has_setting(debug_path):
		ProjectSettings.set_setting(debug_path, false)
	ProjectSettings.set_initial_value(debug_path, false)
	ProjectSettings.add_property_info({
		"name": debug_path,
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
	})


func _exit_tree():
	if revert_confirm_dialog:
		revert_confirm_dialog.queue_free()
	if file_dialog:
		file_dialog.queue_free()
	if snapshot_export_dialog:
		snapshot_export_dialog.queue_free()
	if snapshot_import_dialog:
		snapshot_import_dialog.queue_free()

	if dock:
		remove_dock(dock)
		dock.queue_free()

	if btn_mode:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, btn_mode)
		btn_mode.free()

	_preview.clear_preview_overlays(self, true, _colliders)
	_colliders.clear_all_locks(self)
	_colliders.clear_all_colliders(self)


func _on_mode_toggled(pressed: bool):
	paint_mode_active = pressed
	dock_instance.set_ui_active(pressed)

	if not pressed:
		_preview.clear_vertex_color_preview(self)
		_preview.clear_preview_overlays(self, true, _colliders)
		_colliders.clear_all_locks(self)
		_colliders.clear_all_colliders(self)
		is_painting = false
		is_adjusting_brush = false
		dock_instance.set_selection_empty(false)
		_update_combine_button_state()
	else:
		dock.make_visible()
		_colliders.refresh_selection_and_colliders(self, _preview)
		_update_brush_image_cache()
		dock_instance.set_selection_empty(selected_meshes.is_empty())
		_update_combine_button_state()


func _handles(object):
	if object is not MeshInstance3D and object.get_class() != "MultiNodeEdit":
		return false
	for node in get_editor_interface().get_selection().get_selected_nodes():
		if node is not MeshInstance3D:
			return false
	return true


func _edit(_object):
	pass


func _on_selection_changed():
	_colliders.on_selection_changed(self, _preview)
	_update_combine_button_state()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	return _input.forward_3d_gui_input(self, _colliders, _stroke, _preview, camera, event)


func _start_undo_cycle():
	undo_snapshots.clear()


func _ensure_undo_snapshot_for_mesh(data_node: VertexColorData):
	if not undo_snapshots.has(data_node):
		undo_snapshots[data_node] = data_node.get_data_snapshot()


func _apply_paint_undo_snapshot(data_node: VertexColorData, snapshot: Dictionary) -> void:
	if not is_instance_valid(data_node):
		return
	data_node.apply_data_snapshot(snapshot)
	_refresh_viewport_after_paint_data_change(data_node)


func _refresh_viewport_after_paint_data_change(data_node: VertexColorData) -> void:
	var mesh_instance := data_node.get_parent() as MeshInstance3D
	if not mesh_instance or not is_instance_valid(mesh_instance):
		return
	if _vertex_color_preview_active:
		_preview.apply_vertex_color_preview_to_mesh(self, _colliders, mesh_instance)
	mesh_instance.update_gizmos()


func _commit_undo_snapshot():
	if undo_snapshots.is_empty():
		return

	for data_node in undo_snapshots.keys():
		if is_instance_valid(data_node) and data_node.has_method("flush_gpu_updates"):
			data_node.flush_gpu_updates()

	var ur = get_undo_redo()
	ur.create_action("Paint Vertex Colors")

	for data_node in undo_snapshots.keys():
		var before_state = undo_snapshots[data_node]
		var after_state = data_node.get_data_snapshot()
		ur.add_undo_method(self, "_apply_paint_undo_snapshot", data_node, before_state)
		ur.add_do_method(self, "_apply_paint_undo_snapshot", data_node, after_state)

	ur.commit_action()
	undo_snapshots.clear()


func _on_texture_changed(_tex):
	_update_brush_image_cache()


func _on_settings_changed():
	_preview.update_shader_debug_view(self)
	_preview.update_smart_mask_preview(self, _colliders)
	_preview.update_vertex_color_preview_strength(self)
	_update_brush_image_cache()


func _update_brush_image_cache():
	var settings = dock_instance.get_settings()
	var current_tex = settings.get("brush_texture")

	if current_tex == _last_brush_texture and _cached_brush_image != null:
		if current_tex != null:
			return

	_last_brush_texture = current_tex

	if current_tex:
		var img = current_tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			_cached_brush_image = img
	else:
		_cached_brush_image = null


func _on_show_vertex_colors_toggled(pressed: bool) -> void:
	_preview.on_show_vertex_colors_toggled(self, _colliders, pressed)


func _on_procedural_requested(type: String, settings: Dictionary):
	if selected_meshes.is_empty():
		return

	var ur = get_undo_redo()
	ur.create_action("Procedural Paint: " + type)

	for mesh in selected_meshes:
		var data_node = _colliders.get_or_create_data_node(self, mesh)
		ur.add_undo_method(self, "_apply_paint_undo_snapshot", data_node, data_node.get_data_snapshot())

	for mesh_instance in selected_meshes:
		_stroke.apply_procedural_to_mesh(self, _colliders, mesh_instance, type, settings)

	for mesh in selected_meshes:
		var data_node = _colliders.get_or_create_data_node(self, mesh)
		ur.add_do_method(self, "_apply_paint_undo_snapshot", data_node, data_node.get_data_snapshot())

	ur.commit_action()
	_preview.refresh_vertex_color_preview(self, _colliders, selected_meshes)


func _on_fill_requested(channels: Vector4, value: float):
	if selected_meshes.is_empty():
		return

	var ur = get_undo_redo()
	ur.create_action("Fill Colors")

	for mesh in selected_meshes:
		var data_node = _colliders.get_or_create_data_node(self, mesh)
		ur.add_undo_method(self, "_apply_paint_undo_snapshot", data_node, data_node.get_data_snapshot())

	for mesh in selected_meshes:
		_stroke.apply_global_color(self, _colliders, mesh, channels, value, true)

	for mesh in selected_meshes:
		var data_node = _colliders.get_or_create_data_node(self, mesh)
		ur.add_do_method(self, "_apply_paint_undo_snapshot", data_node, data_node.get_data_snapshot())

	ur.commit_action()
	_preview.refresh_vertex_color_preview(self, _colliders, selected_meshes)


func _on_clear_requested(channels: Vector4):
	if selected_meshes.is_empty():
		return

	var ur = get_undo_redo()
	ur.create_action("Clear Colors")

	for mesh in selected_meshes:
		var data_node = _colliders.get_or_create_data_node(self, mesh)
		ur.add_undo_method(self, "_apply_paint_undo_snapshot", data_node, data_node.get_data_snapshot())

	for mesh in selected_meshes:
		_stroke.apply_global_color(self, _colliders, mesh, channels, 0.0, false)

	for mesh in selected_meshes:
		var data_node = _colliders.get_or_create_data_node(self, mesh)
		ur.add_do_method(self, "_apply_paint_undo_snapshot", data_node, data_node.get_data_snapshot())

	ur.commit_action()
	_preview.refresh_vertex_color_preview(self, _colliders, selected_meshes)


func _on_bake_requested():
	_bake.on_bake_requested(self)


func _on_bake_to_scene_requested():
	_bake.on_bake_to_scene_requested(self)


func _on_bake_file_selected(path: String):
	_bake.on_bake_file_selected(self, path, _colliders, _preview)


func _on_revert_requested():
	if selected_meshes.is_empty():
		VertexPainterLog.warn("No mesh selected to revert. Please select a MeshInstance3D.")
		return
	revert_confirm_dialog.popup_centered()


func _do_revert():
	_bake.do_revert(self, _colliders, _preview)


func _on_export_snapshot_requested():
	_bake.on_export_snapshot_requested(self)


func _on_transfer_snapshot_requested():
	_bake.on_transfer_snapshot_requested(self)


func _on_snapshot_export_file_selected(path: String):
	_bake.on_snapshot_export_file_selected(self, path)


func _on_snapshot_import_file_selected(path: String):
	_bake.on_snapshot_import_file_selected(self, path, _colliders, _preview)


func _assign_scene_owner(node: Node, scene_root: Node) -> void:
	if is_instance_valid(node) and is_instance_valid(scene_root):
		node.owner = scene_root


func _finish_snapshot_transfer(colliders: VertexPaintColliders, preview: VertexPaintPreview) -> void:
	_preview.refresh_vertex_color_preview(self, colliders, selected_meshes)
	_colliders.refresh_selection_and_colliders(self, preview)


func _update_combine_button_state() -> void:
	if not dock_instance:
		return
	var selection := get_editor_interface().get_selection().get_selected_nodes()
	var combinable := _mesh_combine.count_combinable_mesh_instances(selection)
	var enabled := paint_mode_active and combinable >= 2
	dock_instance.set_combine_meshes_enabled(enabled)


func _on_combine_meshes_requested() -> void:
	var selection := get_editor_interface().get_selection().get_selected_nodes()
	var mesh_instances: Array[MeshInstance3D] = []
	for node in selection:
		if _mesh_combine.is_combinable_mesh_instance(node):
			mesh_instances.append(node)

	if mesh_instances.size() < 2:
		VertexPainterLog.warn("Select at least two MeshInstance3D nodes with ArrayMesh to combine.")
		return

	var combine_result: Dictionary = _mesh_combine.combine_mesh_instances(mesh_instances)
	var combined_mesh: ArrayMesh = combine_result.get("mesh")
	if combined_mesh == null or combined_mesh.get_surface_count() == 0:
		VertexPainterLog.error("Combine failed: no mesh surfaces were built.")
		return

	var scene_root := get_editor_interface().get_edited_scene_root()
	if not scene_root:
		VertexPainterLog.error("No edited scene root.")
		return

	var insert_parent := _mesh_combine.resolve_insert_parent(mesh_instances, scene_root)
	var combined_node := MeshInstance3D.new()
	combined_node.mesh = combined_mesh
	combined_node.name = _mesh_combine.unique_combined_name(insert_parent)
	var world_pivot: Vector3 = combine_result.get("world_pivot", Vector3.ZERO)

	var ur := get_undo_redo()
	ur.create_action("Combine Meshes")
	ur.add_do_method(self, "_undo_add_combined_mesh", combined_node, insert_parent, scene_root, world_pivot)
	ur.add_undo_method(self, "_undo_remove_combined_mesh", combined_node, insert_parent)
	ur.commit_action()

	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(combined_node)
	VertexPainterLog.info("Combined %d meshes into '%s'." % [mesh_instances.size(), combined_node.name])


func _undo_add_combined_mesh(
		combined_node: MeshInstance3D,
		insert_parent: Node,
		scene_root: Node,
		world_pivot: Vector3) -> void:
	if not is_instance_valid(combined_node) or not is_instance_valid(insert_parent):
		return
	if combined_node.get_parent():
		return
	insert_parent.add_child(combined_node, true)
	combined_node.global_transform = Transform3D(Basis.IDENTITY, world_pivot)
	_assign_scene_owner(combined_node, scene_root)
	get_editor_interface().edit_node(combined_node)


func _undo_remove_combined_mesh(combined_node: MeshInstance3D, insert_parent: Node) -> void:
	if not is_instance_valid(combined_node):
		return
	if combined_node.get_parent() == insert_parent:
		insert_parent.remove_child(combined_node)
	combined_node.queue_free()
