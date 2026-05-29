class_name VertexPaint3DInput
extends RefCounted

const PAINT_MOTION_STRIDE := 2


func forward_3d_gui_input(
		plugin: EditorPlugin,
		colliders: VertexPaintColliders,
		stroke: VertexPaintStroke,
		preview: VertexPaintPreview,
		camera: Camera3D,
		event: InputEvent) -> int:
	if not plugin.paint_mode_active:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not camera:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.keycode == KEY_X:
			plugin.dock_instance.toggle_add_subtract(false)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_Y or event.keycode == KEY_Z:
			plugin.dock_instance.toggle_add_subtract(true)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_1:
			plugin.dock_instance.toggle_channel_by_index(0)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_2:
			plugin.dock_instance.toggle_channel_by_index(1)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_3:
			plugin.dock_instance.toggle_channel_by_index(2)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_4:
			plugin.dock_instance.toggle_channel_by_index(3)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if event.ctrl_pressed:
					plugin.is_adjusting_brush = true
					plugin.adjust_mode = 1
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				elif event.shift_pressed:
					plugin.is_adjusting_brush = true
					plugin.adjust_mode = 2
					return EditorPlugin.AFTER_GUI_INPUT_STOP
			else:
				if plugin.is_adjusting_brush:
					plugin.is_adjusting_brush = false
					plugin.adjust_mode = 0
					return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseMotion and plugin.is_adjusting_brush:
		var settings = plugin.dock_instance.get_settings()
		var relative = event.relative
		var speed_size = 0.01
		var speed_strength = 0.005
		var speed_falloff = 0.005
		var speed_rotation = 0.05

		if plugin.adjust_mode == 1:
			if relative.y != 0:
				var new_size = settings.size + (-relative.y * speed_size)
				plugin.dock_instance.set_brush_size(clamp(new_size, 0.01, 10.0))
			if relative.x != 0:
				var new_str = settings.strength + (relative.x * speed_strength)
				plugin.dock_instance.set_brush_strength(clamp(new_str, 0.0, 1.0))
		elif plugin.adjust_mode == 2:
			if relative.y != 0:
				var new_fall = settings.falloff + (-relative.y * speed_falloff)
				plugin.dock_instance.set_brush_falloff(clamp(new_fall, 0.0, 1.0))
			if relative.x != 0:
				plugin.dock_instance.rotate_brush(relative.x * speed_rotation)

		var new_settings = plugin.dock_instance.get_settings()
		plugin.shared_brush_material.set_shader_parameter("brush_radius", new_settings.size)
		plugin.shared_brush_material.set_shader_parameter("falloff_range", new_settings.falloff)
		plugin.shared_brush_material.set_shader_parameter("brush_strength", new_settings.strength)
		plugin.shared_brush_material.set_shader_parameter("brush_angle", new_settings.brush_angle)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if plugin.selected_meshes.is_empty():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if not (event is InputEventMouse):
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var mouse_pos = event.position
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	var ray_length = 4000.0

	var w3d = null
	for m in plugin.selected_meshes:
		w3d = m.get_world_3d()
		if w3d:
			break
	if not w3d:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var space_state = w3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * ray_length)
	query.collide_with_bodies = true
	query.collision_mask = colliders.get_paint_collision_mask()
	var result = space_state.intersect_ray(query)

	var hit_pos = Vector3.ZERO
	var hit_mesh_instance: MeshInstance3D = null
	var hit_something = false

	if result and result.collider:
		hit_something = true
		var collider = result.collider
		if collider in plugin.temp_colliders:
			hit_mesh_instance = collider.get_parent()
		else:
			for mesh in plugin.selected_meshes:
				if collider == mesh or collider == mesh.get_parent():
					hit_mesh_instance = mesh
					break
		if hit_mesh_instance:
			hit_pos = result.position

		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if hit_something and not hit_mesh_instance:
				VertexPainterLog.debug(
						"Raycast hit collider but not a selected mesh (collider: %s)" % collider.get_class())
			elif hit_mesh_instance:
				VertexPainterLog.debug("Raycast OK: hit_pos=%s mesh=%s" % [hit_pos, hit_mesh_instance.name])
			else:
				VertexPainterLog.debug("Raycast: no hit")

	if hit_something and not plugin.is_adjusting_brush:
		var settings = plugin.dock_instance.get_settings()
		if hit_mesh_instance:
			plugin.shared_brush_material.set_shader_parameter("brush_pos", hit_pos)
			plugin.shared_brush_material.set_shader_parameter("brush_radius", settings.size)
			plugin.shared_brush_material.set_shader_parameter("falloff_range", settings.falloff)
			plugin.shared_brush_material.set_shader_parameter("channel_mask", settings.channels)
			plugin.shared_brush_material.set_shader_parameter("brush_strength", settings.strength)
			plugin.shared_brush_material.set_shader_parameter("brush_angle", settings.brush_angle)
			if result.has("normal"):
				plugin.shared_brush_material.set_shader_parameter("brush_normal", result.normal)
			if settings.brush_texture:
				plugin.shared_brush_material.set_shader_parameter("use_texture", true)
				plugin.shared_brush_material.set_shader_parameter("brush_texture", settings.brush_texture)
			else:
				plugin.shared_brush_material.set_shader_parameter("use_texture", false)
			preview.copy_displacement_params_from_mesh(hit_mesh_instance, plugin.shared_brush_material)
		else:
			plugin.shared_brush_material.set_shader_parameter("brush_radius", 0.0)
	elif not plugin.is_adjusting_brush:
		plugin.shared_brush_material.set_shader_parameter("brush_radius", 0.0)

	if hit_mesh_instance and not plugin.is_adjusting_brush:
		var settings = plugin.dock_instance.get_settings()
		if hit_something and result.has("normal"):
			settings["brush_hit_normal"] = result.normal
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				plugin.is_painting = true
				plugin._start_undo_cycle()
				plugin._paint_motion_counter = 0
				stroke.paint_mesh(plugin, colliders, preview, plugin.selected_meshes, hit_pos, settings, hit_mesh_instance)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			else:
				plugin.is_painting = false
				plugin._commit_undo_snapshot()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif event is InputEventMouseMotion and plugin.is_painting:
			plugin._paint_motion_counter += 1
			if plugin._paint_motion_counter % PAINT_MOTION_STRIDE != 0:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			stroke.paint_mesh(plugin, colliders, preview, plugin.selected_meshes, hit_pos, settings, hit_mesh_instance)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	else:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			plugin.is_painting = false
			plugin._commit_undo_snapshot()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if plugin.is_painting and event is InputEventMouseMotion:
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS
