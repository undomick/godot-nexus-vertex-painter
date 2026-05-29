class_name VertexPaintBrushSampling
extends RefCounted

const PROJECTION_BOTH_SIDES := 0
const PROJECTION_FRONT_ONLY := 1


static func vertex_passes_projection(world_normal: Vector3, settings: Dictionary) -> bool:
	if settings.get("projection_mode", PROJECTION_BOTH_SIDES) != PROJECTION_FRONT_ONLY:
		return true
	var hit_normal: Variant = settings.get("brush_hit_normal")
	if hit_normal == null or not hit_normal is Vector3:
		return true
	var n: Vector3 = hit_normal as Vector3
	if n.length_squared() < 0.0001:
		return true
	return world_normal.dot(n) > 0.0


static func get_mask_settings(settings: Dictionary) -> Dictionary:
	var use_slope = settings.get("mask_slope_enabled", false)
	var slope_cos = 0.0
	if use_slope:
		var angle_deg = settings.get("mask_slope_angle", 45.0)
		slope_cos = cos(deg_to_rad(angle_deg))
	return {
		"use_slope_mask": use_slope,
		"slope_angle_cos": slope_cos,
		"slope_invert": settings.get("mask_slope_invert", false),
		"use_curv_mask": settings.get("mask_curv_enabled", false),
		"curv_sensitivity": settings.get("mask_curv_sensitivity", 0.5),
		"curv_invert": settings.get("mask_curv_invert", false),
	}


static func get_triplanar_sample(
		brush_pos: Vector3,
		vert_pos: Vector3,
		vert_normal: Vector3,
		radius: float,
		image: Image,
		brush_angle_rad: float) -> float:
	if radius <= 0.0:
		return 0.0
	var blending = vert_normal.abs()
	blending = Vector3(pow(blending.x, 4.0), pow(blending.y, 4.0), pow(blending.z, 4.0))
	var dot_sum = blending.x + blending.y + blending.z
	if dot_sum > 0.00001:
		blending /= dot_sum
	else:
		blending = Vector3(0, 1, 0)

	var rel_pos = vert_pos - brush_pos
	var uv_scale = 1.0 / (radius * 2.0)

	var raw_uv_y = Vector2(rel_pos.x, rel_pos.z)
	if vert_normal.y < 0.0:
		raw_uv_y.x = -raw_uv_y.x
	raw_uv_y.x = -raw_uv_y.x
	var uv_y = raw_uv_y * uv_scale + Vector2(0.5, 0.5)
	uv_y.y = 1.0 - uv_y.y
	uv_y = _rotate_uv_cpu(uv_y, brush_angle_rad)

	var raw_uv_z = Vector2(rel_pos.x, rel_pos.y)
	if vert_normal.z < 0.0:
		raw_uv_z.x = -raw_uv_z.x
	var uv_z = raw_uv_z * uv_scale + Vector2(0.5, 0.5)
	uv_z.y = 1.0 - uv_z.y
	uv_z = _rotate_uv_cpu(uv_z, brush_angle_rad)

	var raw_uv_x = Vector2(rel_pos.z, rel_pos.y)
	if vert_normal.x < 0.0:
		raw_uv_x.x = -raw_uv_x.x
	raw_uv_x.x = -raw_uv_x.x
	var uv_x = raw_uv_x * uv_scale + Vector2(0.5, 0.5)
	uv_x.y = 1.0 - uv_x.y
	uv_x = _rotate_uv_cpu(uv_x, brush_angle_rad)

	var val_x = _sample_image_at_uv(image, uv_x)
	var val_y = _sample_image_at_uv(image, uv_y)
	var val_z = _sample_image_at_uv(image, uv_z)
	return val_x * blending.x + val_y * blending.y + val_z * blending.z


static func _rotate_uv_cpu(uv: Vector2, angle: float) -> Vector2:
	var pivot = Vector2(0.5, 0.5)
	var s = sin(angle)
	var c = cos(angle)
	var centered = uv - pivot
	var rotated = Vector2(
			centered.x * c - centered.y * s,
			centered.x * s + centered.y * c
	)
	return rotated + pivot


static func _sample_image_at_uv(image: Image, uv: Vector2) -> float:
	if image.get_width() <= 0 or image.get_height() <= 0:
		return 0.0
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return 0.0
	var x = int(uv.x * (image.get_width() - 1))
	var y = int(uv.y * (image.get_height() - 1))
	var color = image.get_pixel(x, y)
	return color.r * color.a
