@tool
extends EditorPlugin

const DOCK_SCENE = preload("res://addons/nexus_vertex_painter/painter_dock.tscn")
const DEFAULT_COLLISION_LAYER := 30
const LARGE_MESH_VERTEX_WARN := 500000

# --- UI & REFERENCES ---
var dock_instance: Control
var btn_mode: Button
var shared_brush_material: ShaderMaterial 

# --- DATA ---
var selected_meshes: Array[MeshInstance3D] = []
var temp_colliders: Array[Node] = [] 
var locked_nodes: Array[MeshInstance3D] = [] 

var is_painting: bool = false
var paint_mode_active: bool = false 

# Shortcut State
var is_adjusting_brush: bool = false
var adjust_mode: int = 0 # 0=None, 1=Size/Strength (Ctrl), 2=Falloff (Shift)

# UNDO / REDO STATE
var undo_snapshots: Dictionary = {}

# CACHING
var _cached_brush_image: Image = null
var _last_brush_texture: Texture2D = null

# C++ GDExtension (optional performance boost)
var _use_cpp: bool = false
var _paint_core: RefCounted = null

# Edge-case: avoid spamming large mesh warning
var _warned_large_meshes: Dictionary = {}

# Baking
var file_dialog: EditorFileDialog
var revert_confirm_dialog: ConfirmationDialog



func _enter_tree():
	dock_instance = DOCK_SCENE.instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_instance)
	dock_instance.fill_requested.connect(_on_fill_requested)
	dock_instance.clear_requested.connect(_on_clear_requested)
	dock_instance.settings_changed.connect(_on_settings_changed)
	dock_instance.texture_changed.connect(_on_texture_changed)
	dock_instance.procedural_requested.connect(_on_procedural_requested)
	dock_instance.bake_requested.connect(_on_bake_requested)
	dock_instance.revert_requested.connect(_on_revert_requested)
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
	
	# Setup File Dialog for Baking
	file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.filters = ["*.tres", "*.res"]
	file_dialog.file_selected.connect(_on_bake_file_selected)
	get_editor_interface().get_base_control().add_child(file_dialog)
	
	var editor_base = get_editor_interface().get_base_control()
	if editor_base.has_theme_icon("Edit", "EditorIcons"):
		btn_mode.icon = editor_base.get_theme_icon("Edit", "EditorIcons")
	
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, btn_mode)
	
	_init_shared_brush_material()
	
	# --- C++ GDExtension check ---
	if ClassDB.class_exists("VertexPainterCore"):
		_use_cpp = true
		_paint_core = ClassDB.instantiate("VertexPainterCore")
		if _paint_core:
			VertexPainterLog.debug("C++ GDExtension loaded for improved performance.")
		else:
			_use_cpp = false
	
	var mode_str := "C++ Mode" if (_use_cpp and _paint_core) else "GDScript Mode"
	print_rich("[color=green]Nexus Vertex Painter: initialized in %s.[/color]" % mode_str)
	
	# --- SIGNAL FIX (Guard Clause) ---
	var selection = get_editor_interface().get_selection()
	if not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)

func _setup_project_settings():
	# Collision layer for paint raycasts
	var setting_path = "nexus/vertex_painter/collision_layer"
	if not ProjectSettings.has_setting(setting_path):
		ProjectSettings.set_setting(setting_path, DEFAULT_COLLISION_LAYER)
	ProjectSettings.set_initial_value(setting_path, DEFAULT_COLLISION_LAYER)
	ProjectSettings.add_property_info({
		"name": setting_path,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "1,32"
	})

	# Debug logging (print statements only when enabled)
	var debug_path = "nexus/vertex_painter/debug_logging"
	if not ProjectSettings.has_setting(debug_path):
		ProjectSettings.set_setting(debug_path, false)
	ProjectSettings.set_initial_value(debug_path, false)
	ProjectSettings.add_property_info({
		"name": debug_path,
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": ""
	})

func _exit_tree():
	if revert_confirm_dialog:
		revert_confirm_dialog.queue_free()
	if file_dialog:
		file_dialog.queue_free()
	
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.free()
	
	if btn_mode:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, btn_mode)
		btn_mode.free()
	
	_clear_all_locks()
	_clear_all_colliders()

func _on_mode_toggled(pressed: bool):
	paint_mode_active = pressed
	dock_instance.set_ui_active(pressed)
	
	if not pressed:
		_clear_all_locks()
		_clear_all_colliders()
		is_painting = false
		is_adjusting_brush = false
		dock_instance.set_selection_empty(false)
	else:
		_refresh_selection_and_colliders()
		_update_brush_image_cache()
		dock_instance.set_selection_empty(selected_meshes.is_empty())

func _handles(object):
	# Support MultiNodeEdit and multi-selection of MeshInstance3D
	if object is not MeshInstance3D and object.get_class() != "MultiNodeEdit":
		return false
	
	for node in get_editor_interface().get_selection().get_selected_nodes():
		if node is not MeshInstance3D:
			return false
	return true

func _edit(object):
	pass 

func _on_selection_changed():
	if paint_mode_active:
		_refresh_selection_and_colliders()
		_update_shader_debug_view()
		dock_instance.set_selection_empty(selected_meshes.is_empty())

# --- SELECTION & LOCKING ---

func _refresh_selection_and_colliders():
	var selection = get_editor_interface().get_selection().get_selected_nodes()
	var new_mesh_list: Array[MeshInstance3D] = []
	
	for node in selection:
		if node is MeshInstance3D:
			new_mesh_list.append(node)
	
	if paint_mode_active:
		for mesh in new_mesh_list:
			if not mesh.has_meta("_edit_lock_"):
				# NOTE: Lock disabled to allow multi-selection painting
				#mesh.set_meta("_edit_lock_", true)
				#locked_nodes.append(mesh)
				mesh.notify_property_list_changed()
				mesh.update_gizmos()

		for i in range(locked_nodes.size() - 1, -1, -1):
			var mesh = locked_nodes[i]
			if is_instance_valid(mesh) and not (mesh in new_mesh_list):
				if mesh.has_meta("_edit_lock_"):
					mesh.remove_meta("_edit_lock_")
					mesh.notify_property_list_changed()
					mesh.update_gizmos()
				locked_nodes.remove_at(i)
			elif not is_instance_valid(mesh):
				locked_nodes.remove_at(i)

	for mesh in new_mesh_list:
		if not _has_internal_collider(mesh):
			_create_collider_for(mesh)
	
	for i in range(temp_colliders.size() - 1, -1, -1):
		var node = temp_colliders[i]
		if not is_instance_valid(node.get_parent()) or node.get_parent() not in new_mesh_list:
			node.queue_free()
			temp_colliders.remove_at(i)
	
	selected_meshes = new_mesh_list

func _clear_all_locks():
	for mesh in locked_nodes:
		if is_instance_valid(mesh):
			if mesh.has_meta("_edit_lock_"):
				mesh.remove_meta("_edit_lock_")
				mesh.notify_property_list_changed()
				mesh.update_gizmos()
	locked_nodes.clear()

func _has_internal_collider(mesh: MeshInstance3D) -> bool:
	for child in mesh.get_children():
		if child in temp_colliders:
			return true
	return false

func _create_collider_for(mesh_instance: MeshInstance3D):
	if not mesh_instance.mesh: return
	
	# 1. Physics Collider
	var sb = StaticBody3D.new()
	var col = CollisionShape3D.new()
	col.shape = mesh_instance.mesh.create_trimesh_shape()
	sb.add_child(col)
	sb.collision_layer = _get_paint_collision_mask()
	sb.collision_mask = 0 
	sb.owner = null
	
	mesh_instance.add_child(sb)
	temp_colliders.append(sb)
	
	# 2. Phantom Mesh (Visuals)
	var phantom = MeshInstance3D.new()
	phantom.mesh = mesh_instance.mesh
	phantom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	phantom.material_override = shared_brush_material
	
	mesh_instance.add_child(phantom)
	temp_colliders.append(phantom)

func _clear_all_colliders():
	for node in temp_colliders:
		if is_instance_valid(node):
			node.queue_free()
	temp_colliders.clear()

func _get_or_create_data_node(mesh_instance: MeshInstance3D) -> VertexColorData:
	# --- METADATA PERSISTENCE ---
	if not mesh_instance.has_meta("_vertex_paint_original_path"):
		if mesh_instance.mesh:
			var path = mesh_instance.mesh.resource_path
			if path and path != "":
				mesh_instance.set_meta("_vertex_paint_original_path", path)

	for child in mesh_instance.get_children():
		if child is VertexColorData:
			return child
	
	var node = VertexColorData.new()
	node.name = "VertexColorData"
	mesh_instance.add_child(node)
	
	node.initialize_from_mesh() # Import existing colors if present
	
	var scene_root = get_editor_interface().get_edited_scene_root()
	if scene_root:
		node.owner = scene_root
		
	return node

# --- INPUT ---

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not paint_mode_active: return AFTER_GUI_INPUT_PASS
	
	# --- 1. KEYBOARD SHORTCUTS ---
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
			return AFTER_GUI_INPUT_PASS
		# Cycle Mode Forward
		if event.keycode == KEY_X:
			dock_instance.toggle_add_subtract(false)
			return AFTER_GUI_INPUT_STOP
		# Cycle Mode Backward (Support Y for QWERTZ and Z for QWERTY)
		if event.keycode == KEY_Y or event.keycode == KEY_Z:
			dock_instance.toggle_add_subtract(true)
			return AFTER_GUI_INPUT_STOP
		
		# Channel Toggles
		if event.keycode == KEY_1: dock_instance.toggle_channel_by_index(0); return AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_2: dock_instance.toggle_channel_by_index(1); return AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_3: dock_instance.toggle_channel_by_index(2); return AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_4: dock_instance.toggle_channel_by_index(3); return AFTER_GUI_INPUT_STOP
	
	# --- 2. MOUSE SHORTCUTS (Size/Strength/Falloff/Rotation) ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# Start Adjusting
				if event.ctrl_pressed:
					is_adjusting_brush = true
					adjust_mode = 1 # Size / Strength
					return AFTER_GUI_INPUT_STOP
				elif event.shift_pressed:
					is_adjusting_brush = true
					adjust_mode = 2 # Falloff & Rotation
					return AFTER_GUI_INPUT_STOP
			else:
				# Stop Adjusting (Release RMB)
				if is_adjusting_brush:
					is_adjusting_brush = false
					adjust_mode = 0
					return AFTER_GUI_INPUT_STOP
	
	if event is InputEventMouseMotion and is_adjusting_brush:
		var settings = dock_instance.get_settings()
		var relative = event.relative
		
		# Sensitivity
		var speed_size = 0.01
		var speed_strength = 0.005
		var speed_falloff = 0.005
		var speed_rotation = 0.05 # New for Rotation
		
		if adjust_mode == 1: # Ctrl + RMB
			# Vertical = Size
			if relative.y != 0:
				var new_size = settings.size + (-relative.y * speed_size)
				dock_instance.set_brush_size(clamp(new_size, 0.01, 10.0))
			
			# Horizontal = Strength
			if relative.x != 0:
				var new_str = settings.strength + (relative.x * speed_strength)
				dock_instance.set_brush_strength(clamp(new_str, 0.0, 1.0))
				
		elif adjust_mode == 2: # Shift + RMB
			# Vertical = Falloff
			if relative.y != 0:
				var new_fall = settings.falloff + (-relative.y * speed_falloff)
				dock_instance.set_brush_falloff(clamp(new_fall, 0.0, 1.0))
			
			# Horizontal = Rotation (NEW)
			if relative.x != 0:
				dock_instance.rotate_brush(relative.x * speed_rotation)
		
		# Force visual update immediately on the shared material
		var new_settings = dock_instance.get_settings()
		shared_brush_material.set_shader_parameter("brush_radius", new_settings.size)
		shared_brush_material.set_shader_parameter("falloff_range", new_settings.falloff)
		shared_brush_material.set_shader_parameter("brush_strength", new_settings.strength)
		shared_brush_material.set_shader_parameter("brush_angle", new_settings.brush_angle)
		
		return AFTER_GUI_INPUT_STOP

	# --- 3. STANDARD TOOLS ---
	
	if selected_meshes.is_empty(): 
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS

	if not (event is InputEventMouse): return AFTER_GUI_INPUT_PASS

	# Raycast
	var mouse_pos = event.position
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	var ray_length = 4000.0
	
	for selected_mesh in selected_meshes:
		var space_state = selected_mesh.get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * ray_length)
		query.collide_with_bodies = true
		query.collision_mask = _get_paint_collision_mask()
	
		var result = space_state.intersect_ray(query)
		var hit_pos = Vector3.ZERO
		var hit_mesh_instance: MeshInstance3D = null
		var hit_something = false
		
		if result and result.collider:
			hit_something = true
			var collider = result.collider
			
			if collider in temp_colliders:
				hit_mesh_instance = collider.get_parent()
			else:
				for mesh in selected_meshes:
					if collider == mesh or collider == mesh.get_parent():
						hit_mesh_instance = mesh
						break

			if hit_mesh_instance:
				hit_pos = result.position

		# Update Brush Visuals (Global)
		if hit_something and not is_adjusting_brush:
			var settings = dock_instance.get_settings()
			
			if hit_mesh_instance:
				shared_brush_material.set_shader_parameter("brush_pos", hit_pos)
				shared_brush_material.set_shader_parameter("brush_radius", settings.size)
				shared_brush_material.set_shader_parameter("falloff_range", settings.falloff)
				shared_brush_material.set_shader_parameter("channel_mask", settings.channels)
				shared_brush_material.set_shader_parameter("brush_strength", settings.strength)
				shared_brush_material.set_shader_parameter("brush_angle", settings.brush_angle)
				
				if result.has("normal"):
					shared_brush_material.set_shader_parameter("brush_normal", result.normal)
				
				if settings.brush_texture:
					shared_brush_material.set_shader_parameter("use_texture", true)
					shared_brush_material.set_shader_parameter("brush_texture", settings.brush_texture)
				else:
					shared_brush_material.set_shader_parameter("use_texture", false)
			else:
				shared_brush_material.set_shader_parameter("brush_radius", 0.0)
		elif not is_adjusting_brush:
			shared_brush_material.set_shader_parameter("brush_radius", 0.0)

		# Painting Action
		if hit_mesh_instance and not is_adjusting_brush:
			var settings = dock_instance.get_settings()
			
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					is_painting = true
					_start_undo_cycle() # Prepare for undo
					paint_mesh(selected_meshes, hit_pos, settings)
					return AFTER_GUI_INPUT_STOP
				else:
					is_painting = false
					_commit_undo_snapshot() # Commit collected snapshots
					return AFTER_GUI_INPUT_STOP
			
			elif event is InputEventMouseMotion and is_painting:
				paint_mesh(selected_meshes, hit_pos, settings)
				return AFTER_GUI_INPUT_STOP
				
		else:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				is_painting = false
				return AFTER_GUI_INPUT_STOP
			
			if is_painting and event is InputEventMouseMotion:
				return AFTER_GUI_INPUT_STOP

		return AFTER_GUI_INPUT_PASS
	return AFTER_GUI_INPUT_PASS

# --- UNDO / REDO IMPLEMENTATION ---

func _start_undo_cycle():
	undo_snapshots.clear()

func _ensure_undo_snapshot_for_mesh(data_node: VertexColorData):
	# Lazy Snapshot: Only store the mesh state if we haven't touched it yet in this stroke.
	if not undo_snapshots.has(data_node):
		undo_snapshots[data_node] = data_node.get_data_snapshot()

func _commit_undo_snapshot():
	if undo_snapshots.is_empty(): return
	
	var ur = get_undo_redo()
	ur.create_action("Paint Vertex Colors")
	
	for data_node in undo_snapshots.keys():
		var before_state = undo_snapshots[data_node]
		var after_state = data_node.get_data_snapshot()
		
		# Undo: Restore old state
		ur.add_undo_method(data_node, "apply_data_snapshot", before_state)
		# Do: Restore new state
		ur.add_do_method(data_node, "apply_data_snapshot", after_state)
	
	ur.commit_action()
	undo_snapshots.clear()

# --- IMAGE CACHING ---

func _on_texture_changed(tex):
	_update_brush_image_cache()

func _on_settings_changed():
	_update_shader_debug_view()
	# In case texture was changed in settings without drop event
	_update_brush_image_cache()

func _update_brush_image_cache():
	var settings = dock_instance.get_settings()
	var current_tex = settings.get("brush_texture")
	
	# Only update if texture actually changed or cache is missing
	if current_tex == _last_brush_texture and _cached_brush_image != null:
		if current_tex != null: return
		
	_last_brush_texture = current_tex
	
	if current_tex:
		var img = current_tex.get_image()
		if img:
			# Decompress and Convert ONCE here, not in the paint loop
			if img.is_compressed():
				img.decompress()
			
			# Ensure RGBA8 for fast get_pixel
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
				
			_cached_brush_image = img
	else:
		_cached_brush_image = null

# --- PAINTING LOGIC (Multi-Surface, Multi-Mesh) ---

func paint_mesh(mesh_instances: Array[MeshInstance3D], global_hit_pos: Vector3, settings: Dictionary):
	for mesh_instance in mesh_instances:
		if not mesh_instance.mesh:
			continue
		if not (mesh_instance.mesh is ArrayMesh):
			VertexPainterLog.warn("Mesh '" + mesh_instance.mesh.resource_name + "' is not an ArrayMesh. Only ArrayMesh is supported for painting.")
			continue
		
		var data_node = _get_or_create_data_node(mesh_instance)
		
		# Ensure Cache is ready
		if data_node._cache_positions.is_empty():
			data_node._prep_cache(mesh_instance.mesh)
		
		# Large mesh warning (once per mesh)
		var vert_count := 0
		for k in data_node._cache_positions:
			vert_count += data_node._cache_positions[k].size()
		if vert_count >= LARGE_MESH_VERTEX_WARN and not _warned_large_meshes.get(mesh_instance.get_instance_id(), false):
			_warned_large_meshes[mesh_instance.get_instance_id()] = true
			VertexPainterLog.warn("Mesh has " + str(vert_count) + " vertices. Painting may be slow. Consider the C++ extension for better performance.")
		
		# UNDO FIX: Lazy snapshot
		if is_painting:
			_ensure_undo_snapshot_for_mesh(data_node)
			
		var local_hit_pos = mesh_instance.to_local(global_hit_pos)
		var radius_sq = settings.size * settings.size
		var brush_size = settings.size
		
		# --- IMAGE RESOURCE (FIX POINT 3) ---
		# Use the cached image directly
		var brush_image = _cached_brush_image
		
		# Slope Mask
		var use_slope_mask = settings.get("mask_slope_enabled", false)
		var slope_angle_cos = 0.0
		var slope_invert = settings.get("mask_slope_invert", false)
		if use_slope_mask:
			var angle_deg = settings.get("mask_slope_angle", 45.0)
			slope_angle_cos = cos(deg_to_rad(angle_deg))
			
		# Curvature Mask
		var use_curv_mask = settings.get("mask_curv_enabled", false)
		var curv_sensitivity = settings.get("mask_curv_sensitivity", 0.5)
		var curv_invert = settings.get("mask_curv_invert", false)
		
		var world_basis = mesh_instance.global_transform.basis
		
		# --- ITERATE SURFACES (via Cache) ---
		
		for surf_idx in data_node._cache_positions.keys():
			var positions = data_node.get_positions(surf_idx)
			var normals = data_node.get_normals(surf_idx)
			var vertex_count = positions.size()
			
			# Colors Init
			var colors: PackedColorArray
			if data_node.surface_data.has(surf_idx):
				colors = data_node.surface_data[surf_idx]
			else:
				colors = PackedColorArray()
				colors.resize(vertex_count)
				colors.fill(Color.BLACK)
			
			# --- C++ path (fast) ---
			if _use_cpp and _paint_core:
				var neighbor_map: Dictionary = {}
				if use_curv_mask or settings.mode == 3 or settings.mode == 4:
					var mesh_ref = mesh_instance.mesh
					if mesh_ref is ArrayMesh:
						neighbor_map = _paint_core.build_neighbor_cache(mesh_ref, surf_idx)
				var result = _paint_core.paint_surface(
					positions, normals, colors, local_hit_pos,
					radius_sq, brush_size, settings.falloff, settings.strength,
					settings.mode, settings.channels, brush_image, settings.get("brush_angle", 0.0),
					global_hit_pos, mesh_instance.global_transform, neighbor_map,
					use_slope_mask, slope_angle_cos, slope_invert,
					use_curv_mask, curv_sensitivity, curv_invert
				)
				data_node.update_surface_colors(surf_idx, result)
				continue
			
			# --- GDScript path (fallback) ---
			# FORCE NEIGHBOR CACHE
			if use_curv_mask or settings.mode == 3 or settings.mode == 4:
				if data_node.get_neighbors(surf_idx, 0).is_empty():
					data_node._build_neighbor_cache(surf_idx)
				
			var surface_modified = false
			
			# Read-Copy for Blur/Sharpen
			var colors_read: PackedColorArray
			if settings.mode == 3 or settings.mode == 4:
				colors_read = colors.duplicate()
			
			# --- VERTEX LOOP ---
			for i in range(vertex_count):
				var v_pos = positions[i]
				
				# Manhattan Pre-Check
				if abs(v_pos.x - local_hit_pos.x) > brush_size: continue
				if abs(v_pos.y - local_hit_pos.y) > brush_size: continue
				if abs(v_pos.z - local_hit_pos.z) > brush_size: continue
				
				var dist_sq = v_pos.distance_squared_to(local_hit_pos)
				
				if dist_sq < radius_sq:
					
					# --- SMART MASKS ---
					if use_slope_mask and normals.size() > i:
						var normal = normals[i]
						var world_normal = (world_basis * normal).normalized()
						var dot = world_normal.dot(Vector3.UP)
						if slope_invert:
							if dot > slope_angle_cos: continue
						else:
							if dot < slope_angle_cos: continue
					
					if use_curv_mask and normals.size() > i:
						var neighbors = data_node.get_neighbors(surf_idx, i)
						if not neighbors.is_empty():
							var avg_normal = Vector3.ZERO
							for n_idx in neighbors:
								if normals.size() > n_idx:
									avg_normal += normals[n_idx]
							avg_normal = (avg_normal / neighbors.size()).normalized()
							var my_normal = normals[i]
							var flatness = my_normal.dot(avg_normal)
							var threshold = 1.0 - (curv_sensitivity * 0.2)
							if curv_invert:
								if flatness < threshold: continue
							else:
								if flatness > threshold: continue
					
					var color = colors[i]
					var dist = sqrt(dist_sq)
					var weight = 0.0
					
					# Texture vs Falloff
					if brush_image:
						# Use Cached Image for sampling
						var normal = Vector3.UP
						if normals.size() > i: normal = normals[i]
						var world_pos = mesh_instance.to_global(v_pos)
						var world_normal = (world_basis * normal).normalized()
						
						var tex_val = _get_triplanar_sample(global_hit_pos, world_pos, world_normal, settings.size, brush_image)
						var edge_softness = 0.05
						var t = clamp((dist - (settings.size - edge_softness)) / edge_softness, 0.0, 1.0)
						weight = tex_val * (1.0 - t)
					else:
						var hard_limit = 1.0 - settings.falloff
						if dist / settings.size > hard_limit:
							var t = ((dist / settings.size) - hard_limit) / (1.0 - hard_limit)
							weight = 1.0 - t
						else:
							weight = 1.0
					
					# --- BLEND MODES ---
					if settings.mode == 3: # BLUR
						var neighbors = data_node.get_neighbors(surf_idx, i)
						if neighbors.is_empty(): continue
						var neighbor_avg = Vector4(0, 0, 0, 0)
						var count = 0.0
						for n_idx in neighbors:
							var nc = colors_read[n_idx]
							neighbor_avg.x += nc.r if settings.channels.x > 0 else color.r
							neighbor_avg.y += nc.g if settings.channels.y > 0 else color.g
							neighbor_avg.z += nc.b if settings.channels.z > 0 else color.b
							neighbor_avg.w += nc.a if settings.channels.w > 0 else color.a
							count += 1.0
						neighbor_avg /= count
						var blur_str = settings.strength * weight * 0.5
						if settings.channels.x > 0: color.r = lerp(color.r, neighbor_avg.x, blur_str)
						if settings.channels.y > 0: color.g = lerp(color.g, neighbor_avg.y, blur_str)
						if settings.channels.z > 0: color.b = lerp(color.b, neighbor_avg.z, blur_str)
						if settings.channels.w > 0: color.a = lerp(color.a, neighbor_avg.w, blur_str)
					
					elif settings.mode == 4: # SHARPEN
						var neighbors = data_node.get_neighbors(surf_idx, i)
						if neighbors.is_empty(): continue
						var neighbor_avg = Vector4(0, 0, 0, 0)
						var count = 0.0
						for n_idx in neighbors:
							var nc = colors_read[n_idx]
							neighbor_avg.x += nc.r if settings.channels.x > 0 else color.r
							neighbor_avg.y += nc.g if settings.channels.y > 0 else color.g
							neighbor_avg.z += nc.b if settings.channels.z > 0 else color.b
							neighbor_avg.w += nc.a if settings.channels.w > 0 else color.a
							count += 1.0
						neighbor_avg /= count
						var sharp_str = settings.strength * weight * 0.5
						if settings.channels.x > 0: color.r = clamp(color.r + (color.r - neighbor_avg.x) * sharp_str, 0.0, 1.0)
						if settings.channels.y > 0: color.g = clamp(color.g + (color.g - neighbor_avg.y) * sharp_str, 0.0, 1.0)
						if settings.channels.z > 0: color.b = clamp(color.b + (color.b - neighbor_avg.z) * sharp_str, 0.0, 1.0)
						if settings.channels.w > 0: color.a = clamp(color.a + (color.a - neighbor_avg.w) * sharp_str, 0.0, 1.0)
					
					elif settings.mode == 2: # SET
						var target_val = settings.strength
						if settings.channels.x > 0: color.r = lerp(color.r, target_val, weight)
						if settings.channels.y > 0: color.g = lerp(color.g, target_val, weight)
						if settings.channels.z > 0: color.b = lerp(color.b, target_val, weight)
						if settings.channels.w > 0: color.a = lerp(color.a, target_val, weight)
						
					else: # ADD/SUB
						var strength = settings.strength * weight
						var blend_op = 1.0 if settings.mode == 0 else -1.0
						if settings.channels.x > 0: color.r = clamp(color.r + (strength * blend_op), 0.0, 1.0)
						if settings.channels.y > 0: color.g = clamp(color.g + (strength * blend_op), 0.0, 1.0)
						if settings.channels.z > 0: color.b = clamp(color.b + (strength * blend_op), 0.0, 1.0)
						if settings.channels.w > 0: color.a = clamp(color.a + (strength * blend_op), 0.0, 1.0)
					
					colors[i] = color
					surface_modified = true
			
			if surface_modified:
				data_node.update_surface_colors(surf_idx, colors)

# --- PROCEDURAL LOGIC (Multi-Surface) ---

func _on_procedural_requested(type: String, settings: Dictionary):
	if selected_meshes.is_empty(): return
	
	var ur = get_undo_redo()
	ur.create_action("Procedural Paint: " + type)
	
	# 1. Save State Before
	for mesh in selected_meshes:
		var data_node = _get_or_create_data_node(mesh)
		ur.add_undo_method(data_node, "apply_data_snapshot", data_node.get_data_snapshot())
	
	# 2. Execute Logic
	for mesh_instance in selected_meshes:
		_apply_procedural_to_mesh(mesh_instance, type, settings)
	
	# 3. Save State After
	for mesh in selected_meshes:
		var data_node = _get_or_create_data_node(mesh)
		ur.add_do_method(data_node, "apply_data_snapshot", data_node.get_data_snapshot())
		
	ur.commit_action()

func _apply_procedural_to_mesh(mesh_instance: MeshInstance3D, type: String, settings: Dictionary):
	if not mesh_instance.mesh: return
	if not (mesh_instance.mesh is ArrayMesh):
		VertexPainterLog.warn("Procedural paint: Mesh '" + mesh_instance.mesh.resource_name + "' is not an ArrayMesh. Only ArrayMesh is supported.")
		return
	var data_node = _get_or_create_data_node(mesh_instance)
	var mesh = mesh_instance.mesh as ArrayMesh
	
	# Noise Setup
	var noise = FastNoiseLite.new()
	if type == "noise":
		noise.seed = randi()
		noise.frequency = 0.05 / max(settings.size, 0.01)
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	
	var min_y = 10000.0
	var max_y = -10000.0
	
	# Global Bounds Calculation
	if type == "bottom_up":
		for surf_idx in range(mesh.get_surface_count()):
			var mdt = MeshDataTool.new()
			if mdt.create_from_surface(mesh, surf_idx) == OK:
				for i in range(mdt.get_vertex_count()):
					var v = mdt.get_vertex(i)
					if v.y < min_y: min_y = v.y
					if v.y > max_y: max_y = v.y
		if is_equal_approx(min_y, max_y): max_y += 1.0

	var sharpness = settings.falloff
	
	# Iterate ALL surfaces
	for surf_idx in range(mesh.get_surface_count()):
		var mdt = MeshDataTool.new()
		if mdt.create_from_surface(mesh, surf_idx) != OK: continue
		var vertex_count = mdt.get_vertex_count()
		
		# FIX: Get colors from Dictionary
		var colors: PackedColorArray
		if data_node.surface_data.has(surf_idx):
			colors = data_node.surface_data[surf_idx]
		else:
			colors = PackedColorArray()
			colors.resize(vertex_count)
			colors.fill(Color.BLACK)
			
		if colors.size() != vertex_count: colors.resize(vertex_count)
		
		var surface_modified = false
		
		for i in range(vertex_count):
			var current_color = colors[i]
			
			var v_pos = mdt.get_vertex(i)
			var normal = mdt.get_vertex_normal(i)
			var world_normal = (mesh_instance.global_transform.basis * normal).normalized()
			var world_pos = mesh_instance.to_global(v_pos)
			
			var weight = 0.0
			
			if type == "top_down":
				var dot = world_normal.dot(Vector3.UP)
				var threshold = 1.0 - sharpness
				if dot > (threshold * 2.0 - 1.0):
					weight = (dot - (threshold * 2.0 - 1.0))
					weight = clamp(weight * 2.0, 0.0, 1.0) 
			elif type == "slope":
				var dot = abs(world_normal.dot(Vector3.UP))
				var wall_factor = 1.0 - dot
				if wall_factor > sharpness:
					weight = (wall_factor - sharpness) / (1.0 - sharpness)
			elif type == "bottom_up":
				var h = (v_pos.y - min_y) / (max_y - min_y)
				weight = 1.0 - smoothstep(sharpness - 0.1, sharpness + 0.1, h)
			elif type == "noise":
				var n = noise.get_noise_3dv(world_pos)
				weight = (n + 1.0) * 0.5
				if sharpness > 0.0:
					weight = smoothstep(0.5 - sharpness/2.0, 0.5 + sharpness/2.0, weight)
			
			weight = clamp(weight, 0.0, 1.0)
			
			if settings.mode == 2: # SET MODE
				var target_val = settings.strength
				var alpha = weight 
				if settings.channels.x > 0: current_color.r = lerp(current_color.r, target_val, alpha)
				if settings.channels.y > 0: current_color.g = lerp(current_color.g, target_val, alpha)
				if settings.channels.z > 0: current_color.b = lerp(current_color.b, target_val, alpha)
				if settings.channels.w > 0: current_color.a = lerp(current_color.a, target_val, alpha)
			else: # ADD/SUB
				var apply_amount = weight * settings.strength
				var blend_op = 1.0 if settings.mode == 0 else -1.0
				
				if settings.channels.x > 0: current_color.r = clamp(current_color.r + (apply_amount * blend_op), 0.0, 1.0)
				if settings.channels.y > 0: current_color.g = clamp(current_color.g + (apply_amount * blend_op), 0.0, 1.0)
				if settings.channels.z > 0: current_color.b = clamp(current_color.b + (apply_amount * blend_op), 0.0, 1.0)
				if settings.channels.w > 0: current_color.a = clamp(current_color.a + (apply_amount * blend_op), 0.0, 1.0)
				
			colors[i] = current_color
			surface_modified = true
		
		if surface_modified:
			data_node.update_surface_colors(surf_idx, colors)

# --- FILL / CLEAR (Multi-Surface) ---

func _on_fill_requested(channels: Vector4, value: float):
	if selected_meshes.is_empty(): return
	
	var ur = get_undo_redo()
	ur.create_action("Fill Colors")
	
	for mesh in selected_meshes:
		var data_node = _get_or_create_data_node(mesh)
		ur.add_undo_method(data_node, "apply_data_snapshot", data_node.get_data_snapshot())
	
	for mesh in selected_meshes:
		_apply_global_color(mesh, channels, value, true)
		
	for mesh in selected_meshes:
		var data_node = _get_or_create_data_node(mesh)
		ur.add_do_method(data_node, "apply_data_snapshot", data_node.get_data_snapshot())
		
	ur.commit_action()

func _on_clear_requested(channels: Vector4):
	if selected_meshes.is_empty(): return
	
	var ur = get_undo_redo()
	ur.create_action("Clear Colors")
	
	for mesh in selected_meshes:
		var data_node = _get_or_create_data_node(mesh)
		ur.add_undo_method(data_node, "apply_data_snapshot", data_node.get_data_snapshot())
	
	for mesh in selected_meshes:
		_apply_global_color(mesh, channels, 0.0, false)
		
	for mesh in selected_meshes:
		var data_node = _get_or_create_data_node(mesh)
		ur.add_do_method(data_node, "apply_data_snapshot", data_node.get_data_snapshot())
		
	ur.commit_action()

func _apply_global_color(mesh_instance: MeshInstance3D, channels: Vector4, value: float, is_fill: bool):
	if not mesh_instance.mesh: return
	if not (mesh_instance.mesh is ArrayMesh):
		VertexPainterLog.warn("Fill/Clear: Mesh '" + mesh_instance.mesh.resource_name + "' is not an ArrayMesh. Only ArrayMesh is supported.")
		return
	var data_node = _get_or_create_data_node(mesh_instance)
	data_node._prep_cache(mesh_instance.mesh)
	var mesh = mesh_instance.mesh as ArrayMesh
	
	for surf_idx in data_node._cache_positions.keys():
		var positions = data_node.get_positions(surf_idx)
		var vertex_count = positions.size()
		var colors: PackedColorArray
		if data_node.surface_data.has(surf_idx):
			colors = data_node.surface_data[surf_idx]
		else:
			colors = PackedColorArray()
			colors.resize(vertex_count)
			colors.fill(Color.BLACK)
		if colors.size() != vertex_count:
			colors.resize(vertex_count)
		
		if _use_cpp and _paint_core:
			var result = _paint_core.fill_surface(colors, channels, is_fill)
			data_node.update_surface_colors(surf_idx, result)
		else:
			var surface_modified = false
			for i in range(vertex_count):
				var color = colors[i]
				if is_fill:
					if channels.x > 0: color.r = 1.0
					if channels.y > 0: color.g = 1.0
					if channels.z > 0: color.b = 1.0
					if channels.w > 0: color.a = 1.0
				else:
					if channels.x > 0: color.r = 0.0
					if channels.y > 0: color.g = 0.0
					if channels.z > 0: color.b = 0.0
					if channels.w > 0: color.a = 0.0
				colors[i] = color
				surface_modified = true
			if surface_modified:
				data_node.update_surface_colors(surf_idx, colors)

# --- HELPERS ---

func _init_shared_brush_material():
	var shader = preload("res://addons/nexus_vertex_painter/shaders/brush_decal.gdshader")
	shared_brush_material = ShaderMaterial.new()
	shared_brush_material.shader = shader
	shared_brush_material.set_shader_parameter("color", Color(1.0, 0.5, 0.0, 0.8))
	shared_brush_material.render_priority = 100 

func _update_shader_debug_view():
	for mesh in selected_meshes:
		var mat = mesh.get_active_material(0) as ShaderMaterial
		if mat:
			mat.set_shader_parameter("active_layer_view", 0)

func _get_paint_collision_mask() -> int:
	# Retrieve setting (default to 30 if missing)
	var layer_idx = DEFAULT_COLLISION_LAYER
	if ProjectSettings.has_setting("nexus/vertex_painter/collision_layer"):
		var val = ProjectSettings.get_setting("nexus/vertex_painter/collision_layer")
		if val != null:
			layer_idx = val
	
	# Clamp for safety (Layers are 1-32)
	layer_idx = clamp(layer_idx, 1, 32)
	
	# Bitshift: Layer 1 is 1<<0, Layer 30 is 1<<29
	return 1 << (layer_idx - 1)

# --- TEXTURE SAMPLING HELPER ---

func _get_triplanar_sample(brush_pos: Vector3, vert_pos: Vector3, vert_normal: Vector3, radius: float, image: Image) -> float:
	# 1. Calculate Weights
	var blending = vert_normal.abs()
	blending = Vector3(pow(blending.x, 4.0), pow(blending.y, 4.0), pow(blending.z, 4.0))
	var dot_sum = blending.x + blending.y + blending.z
	if dot_sum > 0.00001:
		blending /= dot_sum
	else:
		blending = Vector3(0, 1, 0) 

	# 2. Relative Position & Scale
	var rel_pos = vert_pos - brush_pos
	var uv_scale = 1.0 / (radius * 2.0)
	var brush_angle_rad = dock_instance.get_settings().brush_angle
	
	# 3. Calculate UVs (Matching shader flips)
	
	# Top/Bottom (XZ Plane)
	var raw_uv_y = Vector2(rel_pos.x, rel_pos.z)
	if vert_normal.y < 0.0: raw_uv_y.x = -raw_uv_y.x
	raw_uv_y.x = -raw_uv_y.x 
	var uv_y = raw_uv_y * uv_scale + Vector2(0.5, 0.5)
	uv_y.y = 1.0 - uv_y.y 
	uv_y = _rotate_uv_cpu(uv_y, brush_angle_rad)
	
	# Front/Back (XY Plane)
	var raw_uv_z = Vector2(rel_pos.x, rel_pos.y)
	if vert_normal.z < 0.0: raw_uv_z.x = -raw_uv_z.x
	var uv_z = raw_uv_z * uv_scale + Vector2(0.5, 0.5)
	uv_z.y = 1.0 - uv_z.y
	uv_z = _rotate_uv_cpu(uv_z, brush_angle_rad)
	
	# Left/Right (ZY Plane)
	var raw_uv_x = Vector2(rel_pos.z, rel_pos.y)
	if vert_normal.x < 0.0: raw_uv_x.x = -raw_uv_x.x
	raw_uv_x.x = -raw_uv_x.x
	var uv_x = raw_uv_x * uv_scale + Vector2(0.5, 0.5)
	uv_x.y = 1.0 - uv_x.y
	uv_x = _rotate_uv_cpu(uv_x, brush_angle_rad)

	# 4. Sample Image
	var val_x = _sample_image_at_uv(image, uv_x)
	var val_y = _sample_image_at_uv(image, uv_y)
	var val_z = _sample_image_at_uv(image, uv_z)
	
	# 5. Blend
	return val_x * blending.x + val_y * blending.y + val_z * blending.z

# Helper needed for rotation
func _rotate_uv_cpu(uv: Vector2, angle: float) -> Vector2:
	var pivot = Vector2(0.5, 0.5)
	var s = sin(angle)
	var c = cos(angle)
	var centered = uv - pivot
	var rotated = Vector2(
		centered.x * c - centered.y * s,
		centered.x * s + centered.y * c
	)
	return rotated + pivot

func _sample_image_at_uv(image: Image, uv: Vector2) -> float:
	# Bounds check (Clamp to 0-1)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return 0.0
	
	# Map UV to Pixel Coordinates
	var x = int(uv.x * (image.get_width() - 1))
	var y = int(uv.y * (image.get_height() - 1))
	
	# Get Pixel Data
	var color = image.get_pixel(x, y)
	
	# Match Shader Logic: Brightness * Alpha
	return color.r * color.a

# --- BAKING LOGIC ---

func _on_bake_requested():
	if selected_meshes.is_empty():
		VertexPainterLog.warn("No mesh selected to bake. Please select a MeshInstance3D.")
		return
	
	# We only support baking one mesh at a time to avoid file naming chaos,
	# or we pick the first one if multiple are selected.
	var mesh_instance = selected_meshes[0]
	
	if not mesh_instance.mesh:
		VertexPainterLog.warn("Selected mesh has no mesh resource. Cannot bake.")
		return
	# Suggest a filename based on the original mesh name
	var original_name = mesh_instance.mesh.resource_name
	if original_name == "": original_name = "painted_mesh"
	
	file_dialog.current_file = original_name + "_painted.res"
	file_dialog.popup_centered_ratio(0.5)

func _on_bake_file_selected(path: String):
	if selected_meshes.is_empty(): return
	var mesh_instance = selected_meshes[0]
	if not mesh_instance.mesh:
		VertexPainterLog.error("Cannot bake: selected mesh has no mesh resource.")
		return
	var data_node = _get_or_create_data_node(mesh_instance)
	
	# Ensure colors are applied to the mesh instance currently
	data_node._apply_colors()
	
	var final_mesh = mesh_instance.mesh.duplicate() # Create a standalone copy
	
	# Save to disk
	var err = ResourceSaver.save(final_mesh, path)
	if err != OK:
		VertexPainterLog.error("Failed to save mesh to " + path + ". Check file permissions and path.")
		return
	
	# Load it back to ensure Godot recognizes it as a file resource
	var loaded_mesh = load(path)
	
	# Assign to instance
	mesh_instance.mesh = loaded_mesh
	
	# Cleanup: Remove the VertexColorData node as it is no longer needed
	# The mesh is now baked and permanent.
	data_node.queue_free()
	
	VertexPainterLog.debug("Baked mesh to " + path)
	
	# Refresh UI state
	_refresh_selection_and_colliders()

# --- REVERT LOGIC ---

func _on_revert_requested():
	if selected_meshes.is_empty():
		VertexPainterLog.warn("No mesh selected to revert. Please select a MeshInstance3D.")
		return
	revert_confirm_dialog.popup_centered()


func _do_revert():
	var reverted_count = 0
	
	for mesh_instance in selected_meshes:
		# 1. Try to find the original path in metadata
		if mesh_instance.has_meta("_vertex_paint_original_path"):
			var original_path = mesh_instance.get_meta("_vertex_paint_original_path")
			
			if ResourceLoader.exists(original_path):
				var original_mesh = load(original_path)
				if original_mesh:
					mesh_instance.mesh = original_mesh
					reverted_count += 1
				else:
					VertexPainterLog.error("Could not load original mesh from " + str(original_path))
			else:
				VertexPainterLog.error("Original file not found: " + str(original_path))
		
		# 2. Cleanup Data Node
		for child in mesh_instance.get_children():
			if child is VertexColorData:
				child.queue_free()
				
		# 3. Cleanup Metadata (Optional - keeps it clean)
		if mesh_instance.has_meta("_vertex_paint_original_path"):
			mesh_instance.remove_meta("_vertex_paint_original_path")
			
	if reverted_count > 0:
		VertexPainterLog.debug("Reverted " + str(reverted_count) + " meshes to original state.")
		# Refresh to rebuild colliders/visuals for the original mesh
		_refresh_selection_and_colliders()
