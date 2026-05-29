class_name VertexPaintStroke
extends RefCounted

const LARGE_MESH_VERTEX_WARN := 500000


func paint_mesh(
		plugin: EditorPlugin,
		colliders: VertexPaintColliders,
		preview: VertexPaintPreview,
		mesh_instances: Array[MeshInstance3D],
		global_hit_pos: Vector3,
		settings: Dictionary,
		hit_mesh: MeshInstance3D = null) -> void:
	var targets: Array[MeshInstance3D] = mesh_instances
	if hit_mesh and hit_mesh in mesh_instances:
		targets = [hit_mesh]

	var defer_gpu: bool = plugin.is_painting

	for mesh_instance in targets:
		if not mesh_instance.mesh:
			continue
		if not (mesh_instance.mesh is ArrayMesh):
			VertexPainterLog.warn(
					"Mesh '" + mesh_instance.mesh.resource_name + "' is not an ArrayMesh. Only ArrayMesh is supported for painting.")
			continue

		var data_node = colliders.get_or_create_data_node(plugin, mesh_instance)
		if not data_node._color_mesh_normalized and data_node.mesh_needs_color_normalize(mesh_instance.mesh):
			data_node.ensure_paintable_color_mesh()
		if data_node._mesh_needs_paintable_rebuild(mesh_instance.mesh):
			data_node.ensure_paintable_runtime_mesh()
		elif data_node._runtime_mesh == null:
			data_node.ensure_paintable_runtime_mesh()
		var diag_id: int = mesh_instance.get_instance_id()
		if not plugin._logged_paint_diagnostics.get(diag_id, false):
			plugin._logged_paint_diagnostics[diag_id] = true
			data_node.log_paint_diagnostics()

		if data_node._cache_positions.is_empty():
			data_node._prep_cache(mesh_instance.mesh)
			if data_node._cache_positions.is_empty():
				VertexPainterLog.debug("Cache still empty after _prep_cache for mesh: %s" % mesh_instance.mesh.resource_name)

		var vert_count := 0
		for k in data_node._cache_positions:
			vert_count += data_node._cache_positions[k].size()
		if vert_count >= LARGE_MESH_VERTEX_WARN and not plugin._warned_large_meshes.get(mesh_instance.get_instance_id(), false):
			plugin._warned_large_meshes[mesh_instance.get_instance_id()] = true
			VertexPainterLog.warn(
					"Mesh has " + str(vert_count) + " vertices. Painting may be slow. Consider the C++ extension for better performance.")

		if plugin.is_painting:
			plugin._ensure_undo_snapshot_for_mesh(data_node)

		var local_hit_pos = mesh_instance.to_local(global_hit_pos)
		var radius_sq = settings.size * settings.size
		var brush_size = settings.size
		var brush_image = plugin._cached_brush_image
		var mask_settings = VertexPaintBrushSampling.get_mask_settings(settings)
		var use_slope_mask = mask_settings.use_slope_mask
		var slope_angle_cos = mask_settings.slope_angle_cos
		var slope_invert = mask_settings.slope_invert
		var use_curv_mask = mask_settings.use_curv_mask
		var curv_sensitivity = mask_settings.curv_sensitivity
		var curv_invert = mask_settings.curv_invert
		var front_face_only: bool = settings.get(
				"projection_mode", VertexPaintBrushSampling.PROJECTION_BOTH_SIDES) == VertexPaintBrushSampling.PROJECTION_FRONT_ONLY
		var hit_normal_world: Vector3 = settings.get("brush_hit_normal", Vector3.ZERO)
		var world_basis = mesh_instance.global_transform.basis

		for surf_idx in data_node._cache_positions.keys():
			if not data_node.surface_intersects_brush(surf_idx, local_hit_pos, brush_size):
				continue

			var positions = data_node.get_positions(surf_idx)
			var normals = data_node.get_normals(surf_idx)
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

			if plugin._use_cpp and plugin._paint_core:
				var neighbor_map: Dictionary = {}
				if use_curv_mask or settings.mode == 3 or settings.mode == 4:
					neighbor_map = data_node.get_neighbor_map(surf_idx)
				var painted: PackedColorArray = _paint_surface_cpp(
						plugin, positions, normals, colors, local_hit_pos,
						radius_sq, brush_size, settings.falloff, settings.strength,
						settings.mode, settings.channels, brush_image, settings.get("brush_angle", 0.0),
						global_hit_pos, mesh_instance.global_transform, neighbor_map,
						use_slope_mask, slope_angle_cos, slope_invert,
						use_curv_mask, curv_sensitivity, curv_invert,
						front_face_only, hit_normal_world
				)
				data_node.update_surface_colors(surf_idx, painted, defer_gpu)
				continue

			if use_curv_mask or settings.mode == 3 or settings.mode == 4:
				if data_node.get_neighbors(surf_idx, 0).is_empty():
					data_node._build_neighbor_cache(surf_idx)

			var surface_modified = false
			var colors_read: PackedColorArray
			if settings.mode == 3 or settings.mode == 4:
				colors_read = colors.duplicate()

			for i in range(vertex_count):
				var v_pos = positions[i]
				if abs(v_pos.x - local_hit_pos.x) > brush_size:
					continue
				if abs(v_pos.y - local_hit_pos.y) > brush_size:
					continue
				if abs(v_pos.z - local_hit_pos.z) > brush_size:
					continue

				var dist_sq = v_pos.distance_squared_to(local_hit_pos)
				if dist_sq < radius_sq:
					if normals.size() > i:
						var world_normal := (world_basis * normals[i]).normalized()
						if not VertexPaintBrushSampling.vertex_passes_projection(world_normal, settings):
							continue

					if use_slope_mask and normals.size() > i:
						var normal = normals[i]
						var world_normal = (world_basis * normal).normalized()
						var dot = world_normal.dot(Vector3.UP)
						if slope_invert:
							if dot > slope_angle_cos:
								continue
						else:
							if dot < slope_angle_cos:
								continue

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
								if flatness < threshold:
									continue
							else:
								if flatness > threshold:
									continue

					var color = colors[i]
					var dist = sqrt(dist_sq)
					var weight = 0.0

					if brush_image:
						var normal = Vector3.UP
						if normals.size() > i:
							normal = normals[i]
						var world_pos = mesh_instance.to_global(v_pos)
						var world_normal = (world_basis * normal).normalized()
						var tex_val = VertexPaintBrushSampling.get_triplanar_sample(
								global_hit_pos, world_pos, world_normal, settings.size, brush_image,
								settings.get("brush_angle", 0.0))
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

					if settings.mode == 3:
						var neighbors = data_node.get_neighbors(surf_idx, i)
						if neighbors.is_empty():
							continue
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
						if settings.channels.x > 0:
							color.r = lerp(color.r, neighbor_avg.x, blur_str)
						if settings.channels.y > 0:
							color.g = lerp(color.g, neighbor_avg.y, blur_str)
						if settings.channels.z > 0:
							color.b = lerp(color.b, neighbor_avg.z, blur_str)
						if settings.channels.w > 0:
							color.a = lerp(color.a, neighbor_avg.w, blur_str)

					elif settings.mode == 4:
						var neighbors = data_node.get_neighbors(surf_idx, i)
						if neighbors.is_empty():
							continue
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
						if settings.channels.x > 0:
							color.r = clamp(color.r + (color.r - neighbor_avg.x) * sharp_str, 0.0, 1.0)
						if settings.channels.y > 0:
							color.g = clamp(color.g + (color.g - neighbor_avg.y) * sharp_str, 0.0, 1.0)
						if settings.channels.z > 0:
							color.b = clamp(color.b + (color.b - neighbor_avg.z) * sharp_str, 0.0, 1.0)
						if settings.channels.w > 0:
							color.a = clamp(color.a + (color.a - neighbor_avg.w) * sharp_str, 0.0, 1.0)

					elif settings.mode == 2:
						var target_val = settings.strength
						if settings.channels.x > 0:
							color.r = lerp(color.r, target_val, weight)
						if settings.channels.y > 0:
							color.g = lerp(color.g, target_val, weight)
						if settings.channels.z > 0:
							color.b = lerp(color.b, target_val, weight)
						if settings.channels.w > 0:
							color.a = lerp(color.a, target_val, weight)

					else:
						var strength = settings.strength * weight
						var blend_op = 1.0 if settings.mode == 0 else -1.0
						if settings.channels.x > 0:
							color.r = clamp(color.r + (strength * blend_op), 0.0, 1.0)
						if settings.channels.y > 0:
							color.g = clamp(color.g + (strength * blend_op), 0.0, 1.0)
						if settings.channels.z > 0:
							color.b = clamp(color.b + (strength * blend_op), 0.0, 1.0)
						if settings.channels.w > 0:
							color.a = clamp(color.a + (strength * blend_op), 0.0, 1.0)

					colors[i] = color
					surface_modified = true

			if surface_modified:
				data_node.update_surface_colors(surf_idx, colors, defer_gpu)

	preview.refresh_vertex_color_preview(plugin, colliders, targets)


func apply_procedural_to_mesh(
		plugin: EditorPlugin,
		colliders: VertexPaintColliders,
		mesh_instance: MeshInstance3D,
		type: String,
		settings: Dictionary) -> void:
	if not mesh_instance.mesh:
		return
	if not (mesh_instance.mesh is ArrayMesh):
		VertexPainterLog.warn(
				"Procedural paint: Mesh '" + mesh_instance.mesh.resource_name + "' is not an ArrayMesh. Only ArrayMesh is supported.")
		return
	var data_node = colliders.get_or_create_data_node(plugin, mesh_instance)
	var mesh = mesh_instance.mesh as ArrayMesh

	var noise = FastNoiseLite.new()
	if type == "noise":
		noise.seed = randi()
		noise.frequency = 0.05 / max(settings.size, 0.01)
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM

	var min_y = 10000.0
	var max_y = -10000.0

	if type == "bottom_up":
		for surf_idx in range(mesh.get_surface_count()):
			var mdt = MeshDataTool.new()
			if mdt.create_from_surface(mesh, surf_idx) == OK:
				for i in range(mdt.get_vertex_count()):
					var v = mdt.get_vertex(i)
					if v.y < min_y:
						min_y = v.y
					if v.y > max_y:
						max_y = v.y
		if is_equal_approx(min_y, max_y):
			max_y += 1.0
		elif max_y < min_y:
			max_y = min_y + 1.0

	var sharpness = settings.falloff
	if is_equal_approx(sharpness, 1.0):
		sharpness = 0.99

	for surf_idx in range(mesh.get_surface_count()):
		var mdt = MeshDataTool.new()
		if mdt.create_from_surface(mesh, surf_idx) != OK:
			continue
		var vertex_count = mdt.get_vertex_count()

		var colors: PackedColorArray
		if data_node.surface_data.has(surf_idx):
			colors = data_node.surface_data[surf_idx]
		else:
			colors = PackedColorArray()
			colors.resize(vertex_count)
			colors.fill(Color.BLACK)

		if colors.size() != vertex_count:
			colors.resize(vertex_count)

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
					weight = smoothstep(0.5 - sharpness / 2.0, 0.5 + sharpness / 2.0, weight)

			weight = clamp(weight, 0.0, 1.0)

			if settings.mode == 2:
				var target_val = settings.strength
				var alpha = weight
				if settings.channels.x > 0:
					current_color.r = lerp(current_color.r, target_val, alpha)
				if settings.channels.y > 0:
					current_color.g = lerp(current_color.g, target_val, alpha)
				if settings.channels.z > 0:
					current_color.b = lerp(current_color.b, target_val, alpha)
				if settings.channels.w > 0:
					current_color.a = lerp(current_color.a, target_val, alpha)
			else:
				var apply_amount = weight * settings.strength
				var blend_op = 1.0 if settings.mode == 0 else -1.0
				if settings.channels.x > 0:
					current_color.r = clamp(current_color.r + (apply_amount * blend_op), 0.0, 1.0)
				if settings.channels.y > 0:
					current_color.g = clamp(current_color.g + (apply_amount * blend_op), 0.0, 1.0)
				if settings.channels.z > 0:
					current_color.b = clamp(current_color.b + (apply_amount * blend_op), 0.0, 1.0)
				if settings.channels.w > 0:
					current_color.a = clamp(current_color.a + (apply_amount * blend_op), 0.0, 1.0)

			colors[i] = current_color
			surface_modified = true

		if surface_modified:
			data_node.update_surface_colors(surf_idx, colors)


func apply_global_color(
		plugin: EditorPlugin,
		colliders: VertexPaintColliders,
		mesh_instance: MeshInstance3D,
		channels: Vector4,
		_value: float,
		is_fill: bool) -> void:
	if channels.x == 0 and channels.y == 0 and channels.z == 0 and channels.w == 0:
		return
	if not mesh_instance.mesh:
		return
	if not (mesh_instance.mesh is ArrayMesh):
		VertexPainterLog.warn(
				"Fill/Clear: Mesh '" + mesh_instance.mesh.resource_name + "' is not an ArrayMesh. Only ArrayMesh is supported.")
		return
	var data_node = colliders.get_or_create_data_node(plugin, mesh_instance)
	data_node._prep_cache(mesh_instance.mesh)

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

		if plugin._use_cpp and plugin._paint_core:
			var result = plugin._paint_core.fill_surface(colors, channels, is_fill)
			data_node.update_surface_colors(surf_idx, result)
		else:
			var surface_modified = false
			for i in range(vertex_count):
				var color = colors[i]
				if is_fill:
					if channels.x > 0:
						color.r = 1.0
					if channels.y > 0:
						color.g = 1.0
					if channels.z > 0:
						color.b = 1.0
					if channels.w > 0:
						color.a = 1.0
				else:
					if channels.x > 0:
						color.r = 0.0
					if channels.y > 0:
						color.g = 0.0
					if channels.z > 0:
						color.b = 0.0
					if channels.w > 0:
						color.a = 0.0
				colors[i] = color
				surface_modified = true
			if surface_modified:
				data_node.update_surface_colors(surf_idx, colors)


static func detect_cpp_paint_surface_projection() -> bool:
	if not ClassDB.class_exists("VertexPainterCore"):
		return false
	for method in ClassDB.class_get_method_list(&"VertexPainterCore", true):
		if method.get("name", "") == "paint_surface":
			return true
	return false


func _paint_surface_cpp(
		plugin: EditorPlugin,
		positions: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray,
		local_hit: Vector3,
		radius_sq: float,
		brush_size: float,
		falloff: float,
		strength: float,
		mode: int,
		channels: Vector4,
		brush_image: Image,
		brush_angle: float,
		brush_pos_global: Vector3,
		mesh_transform: Transform3D,
		neighbor_map: Dictionary,
		use_slope_mask: bool,
		slope_angle_cos: float,
		slope_invert: bool,
		use_curv_mask: bool,
		curv_sensitivity: float,
		curv_invert: bool,
		front_face_only: bool,
		hit_normal_world: Vector3) -> PackedColorArray:
	var args: Array = [
		positions, normals, colors, local_hit,
		radius_sq, brush_size, falloff, strength,
		mode, channels, brush_image, brush_angle,
		brush_pos_global, mesh_transform, neighbor_map,
		use_slope_mask, slope_angle_cos, slope_invert,
		use_curv_mask, curv_sensitivity, curv_invert,
	]
	if plugin._cpp_paint_surface_has_projection:
		args.append(front_face_only)
		args.append(hit_normal_world)
	elif front_face_only:
		VertexPainterLog.warn(
				"Projection mode needs a rebuilt GDExtension (run scons in src/). Using both sides in C++ path.")
	return plugin._paint_core.callv("paint_surface", args)
