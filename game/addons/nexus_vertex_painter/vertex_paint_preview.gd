class_name VertexPaintPreview
extends RefCounted

const PREVIEW_VERTEX_COLOR_MATERIAL := "res://addons/nexus_vertex_painter/check_vertex_color.tres"
const PREVIEW_VERTEX_COLOR_OVERLAY_MATERIAL := "res://addons/nexus_vertex_painter/vertex_color_preview_overlay.tres"


func get_preview_material_paths() -> Dictionary:
	return {
		"vertex_color": PREVIEW_VERTEX_COLOR_MATERIAL,
		"overlay": PREVIEW_VERTEX_COLOR_OVERLAY_MATERIAL,
	}


func init_shared_brush_material(plugin: EditorPlugin) -> void:
	var shader = preload("res://addons/nexus_vertex_painter/shaders/brush_decal.gdshader")
	plugin.shared_brush_material = ShaderMaterial.new()
	plugin.shared_brush_material.shader = shader
	plugin.shared_brush_material.set_shader_parameter("color", Color(1.0, 0.5, 0.0, 0.8))
	plugin.shared_brush_material.render_priority = 100


func copy_displacement_params_from_mesh(mesh_instance: MeshInstance3D, target: ShaderMaterial) -> void:
	var src = mesh_instance.get_active_material(0) as ShaderMaterial
	if not src or not src.shader:
		target.set_shader_parameter("use_displacement", false)
		return
	var path = src.shader.resource_path
	if path == null:
		target.set_shader_parameter("use_displacement", false)
		return
	if path.ends_with("displacement_material.gdshader"):
		target.set_shader_parameter("use_displacement", true)
		target.set_shader_parameter("displacement_mode", 0)
		target.set_shader_parameter("disp_tex", src.get_shader_parameter("displacement_texture"))
		target.set_shader_parameter("uv_scale", src.get_shader_parameter("uv_scale"))
		target.set_shader_parameter("displacement_scale", src.get_shader_parameter("displacement_scale"))
		target.set_shader_parameter("displacement_midpoint", src.get_shader_parameter("displacement_midpoint"))
	elif path.ends_with("vertex_color_material_blend_displacement.gdshader") \
			or path.ends_with("vertex_color_material_blend_displacement_height.gdshader"):
		target.set_shader_parameter("use_displacement", true)
		target.set_shader_parameter("displacement_mode", 1)
		for i in range(1, 6):
			target.set_shader_parameter("mat%d_displacement" % i, src.get_shader_parameter("mat%d_displacement" % i))
		target.set_shader_parameter("uv_scale", src.get_shader_parameter("uv_scale"))
		target.set_shader_parameter("blend_softness", src.get_shader_parameter("blend_softness"))
		target.set_shader_parameter("displacement_scale", src.get_shader_parameter("displacement_scale"))
		target.set_shader_parameter("displacement_midpoint", src.get_shader_parameter("displacement_midpoint"))
		if path.ends_with("vertex_color_material_blend_displacement_height.gdshader"):
			target.set_shader_parameter("height_map", src.get_shader_parameter("height_map"))
			target.set_shader_parameter("height_map_blend_influence", src.get_shader_parameter("height_map_blend_influence"))
		else:
			target.set_shader_parameter("height_map_blend_influence", 0.0)
	else:
		target.set_shader_parameter("use_displacement", false)


func update_shader_debug_view(plugin: EditorPlugin) -> void:
	for mesh in plugin.selected_meshes:
		if not is_instance_valid(mesh):
			continue
		var mat = mesh.get_active_material(0) as ShaderMaterial
		if mat:
			mat.set_shader_parameter("active_layer_view", 0)


func update_smart_mask_preview(plugin: EditorPlugin, colliders: VertexPaintColliders) -> void:
	var settings = plugin.dock_instance.get_settings()
	var preview_active = settings.get("preview_smart_mask", false)
	if not preview_active:
		clear_preview_overlays(plugin, true)
		return
	if plugin.selected_meshes.is_empty():
		return
	var mask_settings = VertexPaintBrushSampling.get_mask_settings(settings)
	clear_preview_overlays(plugin, false)
	var preview_shader = load("res://addons/nexus_vertex_painter/shaders/preview_mask.gdshader") as Shader
	if not preview_shader:
		VertexPainterLog.warn("Preview Smart Mask: Could not load preview_mask.gdshader")
		return
	for mesh_instance in plugin.selected_meshes:
		if not mesh_instance.mesh or not (mesh_instance.mesh is ArrayMesh):
			continue
		_apply_preview_to_mesh(
				plugin, colliders, mesh_instance, preview_shader,
				mask_settings.use_slope_mask, mask_settings.slope_angle_cos, mask_settings.slope_invert,
				mask_settings.use_curv_mask, mask_settings.curv_sensitivity, mask_settings.curv_invert)


func clear_preview_overlays(plugin: EditorPlugin, restore_painted: bool, colliders: VertexPaintColliders = null) -> void:
	var to_remove: Array = []
	for mesh_instance in plugin._preview_stored_state:
		if not is_instance_valid(mesh_instance):
			to_remove.append(mesh_instance)
			continue
		var stored = plugin._preview_stored_state[mesh_instance]
		var overlay = stored.get("overlay_instance") if stored is Dictionary else null
		if overlay and is_instance_valid(overlay):
			mesh_instance.remove_child(overlay)
			overlay.queue_free()
		if restore_painted and colliders:
			var data_node = colliders.get_or_create_data_node(plugin, mesh_instance)
			if data_node:
				data_node.repair_mesh_display_state()
		to_remove.append(mesh_instance)
	for key in to_remove:
		plugin._preview_stored_state.erase(key)


func _apply_preview_to_mesh(
		plugin: EditorPlugin,
		_colliders: VertexPaintColliders,
		mesh_instance: MeshInstance3D,
		preview_shader: Shader,
		use_slope_mask: bool,
		slope_angle_cos: float,
		slope_invert: bool,
		use_curv_mask: bool,
		curv_sensitivity: float,
		curv_invert: bool) -> void:
	var src_mesh = mesh_instance.mesh
	if not src_mesh:
		return
	var world_basis = mesh_instance.global_transform.basis
	var preview_mat = ShaderMaterial.new()
	preview_mat.shader = preview_shader
	var temp_mesh = ArrayMesh.new()
	temp_mesh.resource_name = "PreviewMaskTemp"
	for surf_idx in range(src_mesh.get_surface_count()):
		var mdt = MeshDataTool.new()
		if mdt.create_from_surface(src_mesh, surf_idx) != OK:
			continue
		var vertex_count = mdt.get_vertex_count()
		var surf_neighbors: Dictionary = {}
		if use_curv_mask:
			for v in range(vertex_count):
				var edges = mdt.get_vertex_edges(v)
				var n_list: Array = []
				for e in edges:
					var v1 = mdt.get_edge_vertex(e, 0)
					var v2 = mdt.get_edge_vertex(e, 1)
					n_list.append(v2 if v1 == v else v1)
				surf_neighbors[v] = n_list
		for i in range(vertex_count):
			var slope_pass = true
			if use_slope_mask:
				var normal = mdt.get_vertex_normal(i)
				var world_normal = (world_basis * normal).normalized()
				var dot = world_normal.dot(Vector3.UP)
				if slope_invert:
					slope_pass = dot <= slope_angle_cos
				else:
					slope_pass = dot >= slope_angle_cos
			var curv_pass = true
			if use_curv_mask and surf_neighbors.has(i):
				var neighbors = surf_neighbors[i]
				if not neighbors.is_empty():
					var avg_normal = Vector3.ZERO
					for n_idx in neighbors:
						avg_normal += mdt.get_vertex_normal(n_idx)
					avg_normal = (avg_normal / neighbors.size()).normalized()
					var my_normal = mdt.get_vertex_normal(i)
					var flatness = my_normal.dot(avg_normal)
					var threshold = 1.0 - (curv_sensitivity * 0.2)
					if curv_invert:
						curv_pass = flatness >= threshold
					else:
						curv_pass = flatness <= threshold
			var mask_val = 1.0 if (slope_pass and curv_pass) else 0.0
			mdt.set_vertex_color(i, Color(mask_val, mask_val, mask_val, 1.0))
		mdt.commit_to_surface(temp_mesh)
	for surf_idx in range(temp_mesh.get_surface_count()):
		temp_mesh.surface_set_material(surf_idx, preview_mat)
	var overlay = MeshInstance3D.new()
	overlay.name = "VertexPaint_PreviewOverlay"
	overlay.mesh = temp_mesh
	mesh_instance.add_child(overlay, true, Node.INTERNAL_MODE_BACK)
	plugin._preview_stored_state[mesh_instance] = {"overlay_instance": overlay}


func _get_vertex_color_preview_strength(plugin: EditorPlugin) -> float:
	if plugin.dock_instance and plugin.dock_instance.has_method("get_vertex_color_preview_strength"):
		return plugin.dock_instance.get_vertex_color_preview_strength()
	return 0.55


func _make_vertex_color_preview_material(plugin: EditorPlugin) -> Material:
	var base: Material = _get_vertex_color_preview_material(plugin)
	if base == null:
		return null
	var mat: Material = base.duplicate()
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter(
				"overlay_strength", _get_vertex_color_preview_strength(plugin))
	return mat


func _get_vertex_color_preview_material(plugin: EditorPlugin) -> Material:
	if plugin._vertex_color_preview_mat == null:
		plugin._vertex_color_preview_mat = load(PREVIEW_VERTEX_COLOR_OVERLAY_MATERIAL) as Material
		if plugin._vertex_color_preview_mat == null:
			plugin._vertex_color_preview_mat = load(PREVIEW_VERTEX_COLOR_MATERIAL) as Material
	return plugin._vertex_color_preview_mat


func _assign_preview_materials_to_mesh(plugin: EditorPlugin, mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	for surf_idx in range(mesh.get_surface_count()):
		mesh.surface_set_material(surf_idx, _make_vertex_color_preview_material(plugin))


func _set_preview_strength_on_mesh(mesh: ArrayMesh, strength: float) -> void:
	if mesh == null:
		return
	for surf_idx in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(surf_idx)
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("overlay_strength", strength)


func update_vertex_color_preview_strength(plugin: EditorPlugin) -> void:
	if not plugin._vertex_color_preview_active:
		return
	var strength := _get_vertex_color_preview_strength(plugin)
	for mesh_instance in plugin._vertex_color_preview_overlays.keys():
		var overlay: Variant = plugin._vertex_color_preview_overlays[mesh_instance]
		if not overlay is MeshInstance3D or not is_instance_valid(overlay):
			continue
		var mesh: ArrayMesh = overlay.mesh as ArrayMesh
		_set_preview_strength_on_mesh(mesh, strength)


func _remove_vertex_color_preview_overlay(plugin: EditorPlugin, mesh_instance: MeshInstance3D) -> void:
	var overlay: Variant = plugin._vertex_color_preview_overlays.get(mesh_instance)
	if overlay is MeshInstance3D and is_instance_valid(overlay):
		if overlay.get_parent() == mesh_instance:
			mesh_instance.remove_child(overlay)
		overlay.queue_free()
	plugin._vertex_color_preview_overlays.erase(mesh_instance)


func apply_vertex_color_preview_to_mesh(
		plugin: EditorPlugin,
		colliders: VertexPaintColliders,
		mesh_instance: MeshInstance3D) -> void:
	if not is_instance_valid(mesh_instance):
		return
	if _get_vertex_color_preview_material(plugin) == null:
		VertexPainterLog.warn("Vertex color preview material not found: " + PREVIEW_VERTEX_COLOR_OVERLAY_MATERIAL)
		return

	_remove_vertex_color_preview_overlay(plugin, mesh_instance)

	var data_node := colliders.get_or_create_data_node(plugin, mesh_instance)
	var colored_mesh: ArrayMesh = data_node.build_colored_mesh()
	if colored_mesh == null:
		if data_node.surface_data.is_empty():
			VertexPainterLog.warn(
					"No vertex color data on '%s'. Paint first, then enable preview." % mesh_instance.name)
		else:
			VertexPainterLog.warn(
					"Could not build vertex color preview mesh for '%s'." % mesh_instance.name)
		return

	_assign_preview_materials_to_mesh(plugin, colored_mesh)

	var overlay := MeshInstance3D.new()
	overlay.name = "VertexPaint_ColorPreviewOverlay"
	overlay.mesh = colored_mesh
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh_instance.add_child(overlay, true, Node.INTERNAL_MODE_BACK)
	plugin._vertex_color_preview_overlays[mesh_instance] = overlay


func refresh_vertex_color_preview(
		plugin: EditorPlugin,
		colliders: VertexPaintColliders,
		mesh_instances: Array) -> void:
	if not plugin._vertex_color_preview_active:
		return
	for mesh_instance in mesh_instances:
		if mesh_instance is MeshInstance3D and is_instance_valid(mesh_instance):
			if mesh_instance in plugin._vertex_color_preview_overlays or mesh_instance in plugin.selected_meshes:
				apply_vertex_color_preview_to_mesh(plugin, colliders, mesh_instance)


func clear_vertex_color_preview(plugin: EditorPlugin) -> void:
	plugin._vertex_color_preview_active = false
	for mesh_instance in plugin._vertex_color_preview_overlays.keys().duplicate():
		if is_instance_valid(mesh_instance):
			_remove_vertex_color_preview_overlay(plugin, mesh_instance)
	plugin._vertex_color_preview_overlays.clear()
	if plugin.dock_instance:
		plugin.dock_instance.set_show_vertex_colors_pressed(false)


func sync_vertex_color_preview(plugin: EditorPlugin, colliders: VertexPaintColliders) -> void:
	if not plugin._vertex_color_preview_active:
		return
	for mesh_instance in plugin._vertex_color_preview_overlays.keys().duplicate():
		if not is_instance_valid(mesh_instance) or mesh_instance not in plugin.selected_meshes:
			_remove_vertex_color_preview_overlay(plugin, mesh_instance)
	for mesh_instance in plugin.selected_meshes:
		apply_vertex_color_preview_to_mesh(plugin, colliders, mesh_instance)


func on_show_vertex_colors_toggled(
		plugin: EditorPlugin,
		colliders: VertexPaintColliders,
		pressed: bool) -> void:
	plugin._vertex_color_preview_active = pressed
	if pressed:
		if plugin.selected_meshes.is_empty():
			VertexPainterLog.warn("Select a MeshInstance3D to preview vertex colors.")
			plugin._vertex_color_preview_active = false
			plugin.dock_instance.set_show_vertex_colors_pressed(false)
			return
		for mesh_instance in plugin.selected_meshes:
			apply_vertex_color_preview_to_mesh(plugin, colliders, mesh_instance)
	else:
		clear_vertex_color_preview(plugin)
