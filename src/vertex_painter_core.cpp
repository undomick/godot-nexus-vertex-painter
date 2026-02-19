#include "vertex_painter_core.h"
#include <godot_cpp/classes/mesh_data_tool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cmath>

namespace godot {

// Blend modes: 0=ADD, 1=SUB, 2=SET, 3=BLUR, 4=SHARPEN

void VertexPainterCore::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("paint_surface",
					"positions", "normals", "colors", "local_hit",
					"radius_sq", "brush_size", "falloff", "strength", "mode", "channels",
					"brush_image", "brush_angle", "brush_pos_global", "mesh_global_transform",
					"neighbor_map", "use_slope_mask", "slope_angle_cos", "slope_invert",
					"use_curv_mask", "curv_sensitivity", "curv_invert"),
			&VertexPainterCore::paint_surface);

	ClassDB::bind_method(
			D_METHOD("build_neighbor_cache", "mesh", "surface_idx"),
			&VertexPainterCore::build_neighbor_cache);

	ClassDB::bind_method(
			D_METHOD("fill_surface", "colors", "channels", "is_fill"),
			&VertexPainterCore::fill_surface);
}

static inline double sample_image_at_uv(Image *img, double u, double v) {
	if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) {
		return 0.0;
	}
	int w = img->get_width();
	int h = img->get_height();
	if (w <= 0 || h <= 0) return 0.0;
	int x = (int)(u * (w - 1));
	int y = (int)(v * (h - 1));
	Color c = img->get_pixel(x, y);
	return c.r * c.a;
}

static inline Vector2 rotate_uv(const Vector2 &uv, double angle) {
	Vector2 pivot(0.5, 0.5);
	double s = std::sin(angle);
	double c = std::cos(angle);
	Vector2 centered = uv - pivot;
	Vector2 rotated(centered.x * c - centered.y * s, centered.x * s + centered.y * c);
	return rotated + pivot;
}

static double get_triplanar_sample(
		const Vector3 &brush_pos,
		const Vector3 &vert_pos,
		const Vector3 &vert_normal,
		double radius,
		double brush_angle,
		Image *img) {
	Vector3 blending = vert_normal.abs();
	blending.x = blending.x * blending.x * blending.x * blending.x;
	blending.y = blending.y * blending.y * blending.y * blending.y;
	blending.z = blending.z * blending.z * blending.z * blending.z;
	double dot_sum = blending.x + blending.y + blending.z;
	if (dot_sum > 0.00001) {
		blending /= dot_sum;
	} else {
		blending = Vector3(0, 1, 0);
	}

	Vector3 rel_pos = vert_pos - brush_pos;
	double uv_scale = 1.0 / (radius * 2.0);

	// Top/Bottom (XZ plane)
	Vector2 raw_uv_y(rel_pos.x, rel_pos.z);
	if (vert_normal.y < 0.0) raw_uv_y.x = -raw_uv_y.x;
	raw_uv_y.x = -raw_uv_y.x;
	Vector2 uv_y = raw_uv_y * uv_scale + Vector2(0.5, 0.5);
	uv_y.y = 1.0 - uv_y.y;
	uv_y = rotate_uv(uv_y, brush_angle);

	// Front/Back (XY plane)
	Vector2 raw_uv_z(rel_pos.x, rel_pos.y);
	if (vert_normal.z < 0.0) raw_uv_z.x = -raw_uv_z.x;
	Vector2 uv_z = raw_uv_z * uv_scale + Vector2(0.5, 0.5);
	uv_z.y = 1.0 - uv_z.y;
	uv_z = rotate_uv(uv_z, brush_angle);

	// Left/Right (ZY plane)
	Vector2 raw_uv_x(rel_pos.z, rel_pos.y);
	if (vert_normal.x < 0.0) raw_uv_x.x = -raw_uv_x.x;
	raw_uv_x.x = -raw_uv_x.x;
	Vector2 uv_x = raw_uv_x * uv_scale + Vector2(0.5, 0.5);
	uv_x.y = 1.0 - uv_x.y;
	uv_x = rotate_uv(uv_x, brush_angle);

	double val_x = sample_image_at_uv(img, uv_x.x, uv_x.y);
	double val_y = sample_image_at_uv(img, uv_y.x, uv_y.y);
	double val_z = sample_image_at_uv(img, uv_z.x, uv_z.y);

	return val_x * blending.x + val_y * blending.y + val_z * blending.z;
}

PackedColorArray VertexPainterCore::paint_surface(
		const PackedVector3Array &p_positions,
		const PackedVector3Array &p_normals,
		const PackedColorArray &p_colors,
		const Vector3 &p_local_hit,
		double p_radius_sq,
		double p_brush_size,
		double p_falloff,
		double p_strength,
		int p_mode,
		const Vector4 &p_channels,
		const Ref<Image> &p_brush_image,
		double p_brush_angle,
		const Vector3 &p_brush_pos_global,
		const Transform3D &p_mesh_global_transform,
		const Dictionary &p_neighbor_map,
		bool p_use_slope_mask,
		double p_slope_angle_cos,
		bool p_slope_invert,
		bool p_use_curv_mask,
		double p_curv_sensitivity,
		bool p_curv_invert) {

	PackedColorArray colors = p_colors;
	int vertex_count = p_positions.size();
	PackedColorArray colors_read;
	if (p_mode == 3 || p_mode == 4) {
		colors_read.resize(vertex_count);
		for (int k = 0; k < vertex_count; k++) {
			colors_read[k] = p_colors[k];
		}
	}

	const Basis &world_basis = p_mesh_global_transform.basis;

	for (int i = 0; i < vertex_count; i++) {
		Vector3 v_pos = p_positions[i];

		// Manhattan pre-check
		if (std::abs(v_pos.x - p_local_hit.x) > p_brush_size) continue;
		if (std::abs(v_pos.y - p_local_hit.y) > p_brush_size) continue;
		if (std::abs(v_pos.z - p_local_hit.z) > p_brush_size) continue;

		double dist_sq = v_pos.distance_squared_to(p_local_hit);
		if (dist_sq >= p_radius_sq) continue;

		// Slope mask
		if (p_use_slope_mask && i < p_normals.size()) {
			Vector3 normal = p_normals[i];
			Vector3 world_normal = world_basis.xform(normal).normalized();
			double dot = world_normal.dot(Vector3(0, 1, 0));
			if (p_slope_invert) {
				if (dot > p_slope_angle_cos) continue;
			} else {
				if (dot < p_slope_angle_cos) continue;
			}
		}

		// Curvature mask
		if (p_use_curv_mask && i < p_normals.size()) {
			Variant key = i;
			if (p_neighbor_map.has(key)) {
				Array neighbors = p_neighbor_map[key];
				if (!neighbors.is_empty()) {
					Vector3 avg_normal = Vector3(0, 0, 0);
					for (int j = 0; j < neighbors.size(); j++) {
						int n_idx = neighbors[j];
						if (n_idx < p_normals.size()) {
							avg_normal += p_normals[n_idx];
						}
					}
					avg_normal = (avg_normal / (double)neighbors.size()).normalized();
					Vector3 my_normal = p_normals[i];
					double flatness = my_normal.dot(avg_normal);
					double threshold = 1.0 - (p_curv_sensitivity * 0.2);
					if (p_curv_invert) {
						if (flatness < threshold) continue;
					} else {
						if (flatness > threshold) continue;
					}
				}
			}
		}

		Color color = colors[i];
		double dist = std::sqrt(dist_sq);
		double weight = 0.0;

		Image *brush_img = p_brush_image.ptr();
		if (brush_img && brush_img->get_width() > 0 && brush_img->get_height() > 0) {
			Vector3 world_pos = p_mesh_global_transform.xform(v_pos);
			Vector3 world_normal = i < p_normals.size()
					? world_basis.xform(p_normals[i]).normalized()
					: Vector3(0, 1, 0);
			double tex_val = get_triplanar_sample(
					p_brush_pos_global, world_pos, world_normal,
					p_brush_size, p_brush_angle, brush_img);
			double edge_softness = 0.05;
			double t = (dist - (p_brush_size - edge_softness)) / edge_softness;
			if (t < 0.0) t = 0.0;
			if (t > 1.0) t = 1.0;
			weight = tex_val * (1.0 - t);
		} else {
			double hard_limit = 1.0 - p_falloff;
			if (dist / p_brush_size > hard_limit) {
				double t = ((dist / p_brush_size) - hard_limit) / (1.0 - hard_limit);
				weight = 1.0 - t;
			} else {
				weight = 1.0;
			}
		}

		if (p_mode == 3) { // BLUR
			Variant key = i;
			if (!p_neighbor_map.has(key)) continue;
			Array neighbors = p_neighbor_map[key];
			if (neighbors.is_empty()) continue;

			Vector4 neighbor_avg(0, 0, 0, 0);
			double count = 0.0;
			for (int j = 0; j < neighbors.size(); j++) {
				int n_idx = neighbors[j];
				Color nc = colors_read[n_idx];
				neighbor_avg.x += (p_channels.x > 0) ? nc.r : color.r;
				neighbor_avg.y += (p_channels.y > 0) ? nc.g : color.g;
				neighbor_avg.z += (p_channels.z > 0) ? nc.b : color.b;
				neighbor_avg.w += (p_channels.w > 0) ? nc.a : color.a;
				count += 1.0;
			}
			neighbor_avg /= count;
			double blur_str = p_strength * weight * 0.5;
			if (p_channels.x > 0) color.r = (float)Math::lerp((double)color.r, (double)neighbor_avg.x, blur_str);
			if (p_channels.y > 0) color.g = (float)Math::lerp((double)color.g, (double)neighbor_avg.y, blur_str);
			if (p_channels.z > 0) color.b = (float)Math::lerp((double)color.b, (double)neighbor_avg.z, blur_str);
			if (p_channels.w > 0) color.a = (float)Math::lerp((double)color.a, (double)neighbor_avg.w, blur_str);
		} else if (p_mode == 4) { // SHARPEN
			Variant key = i;
			if (!p_neighbor_map.has(key)) continue;
			Array neighbors = p_neighbor_map[key];
			if (neighbors.is_empty()) continue;

			Vector4 neighbor_avg(0, 0, 0, 0);
			double count = 0.0;
			for (int j = 0; j < neighbors.size(); j++) {
				int n_idx = neighbors[j];
				Color nc = colors_read[n_idx];
				neighbor_avg.x += (p_channels.x > 0) ? nc.r : color.r;
				neighbor_avg.y += (p_channels.y > 0) ? nc.g : color.g;
				neighbor_avg.z += (p_channels.z > 0) ? nc.b : color.b;
				neighbor_avg.w += (p_channels.w > 0) ? nc.a : color.a;
				count += 1.0;
			}
			neighbor_avg /= count;
			double sharp_str = p_strength * weight * 0.5;
			if (p_channels.x > 0) color.r = CLAMP(color.r + (color.r - neighbor_avg.x) * sharp_str, 0.0, 1.0);
			if (p_channels.y > 0) color.g = CLAMP(color.g + (color.g - neighbor_avg.y) * sharp_str, 0.0, 1.0);
			if (p_channels.z > 0) color.b = CLAMP(color.b + (color.b - neighbor_avg.z) * sharp_str, 0.0, 1.0);
			if (p_channels.w > 0) color.a = CLAMP(color.a + (color.a - neighbor_avg.w) * sharp_str, 0.0, 1.0);
		} else if (p_mode == 2) { // SET
			double target_val = p_strength;
			if (p_channels.x > 0) color.r = (float)Math::lerp((double)color.r, target_val, weight);
			if (p_channels.y > 0) color.g = (float)Math::lerp((double)color.g, target_val, weight);
			if (p_channels.z > 0) color.b = (float)Math::lerp((double)color.b, target_val, weight);
			if (p_channels.w > 0) color.a = (float)Math::lerp((double)color.a, target_val, weight);
		} else { // ADD (0) or SUB (1)
			double strength = p_strength * weight;
			double blend_op = (p_mode == 0) ? 1.0 : -1.0;
			if (p_channels.x > 0) color.r = CLAMP(color.r + strength * blend_op, 0.0, 1.0);
			if (p_channels.y > 0) color.g = CLAMP(color.g + strength * blend_op, 0.0, 1.0);
			if (p_channels.z > 0) color.b = CLAMP(color.b + strength * blend_op, 0.0, 1.0);
			if (p_channels.w > 0) color.a = CLAMP(color.a + strength * blend_op, 0.0, 1.0);
		}

		colors[i] = color;
	}

	return colors;
}

Dictionary VertexPainterCore::build_neighbor_cache(const Ref<ArrayMesh> &p_mesh, int p_surface_idx) {
	Dictionary result;
	if (p_mesh.is_null()) return result;

	Ref<MeshDataTool> mdt;
	mdt.instantiate();
	if (mdt->create_from_surface(p_mesh, p_surface_idx) != OK) {
		return result;
	}

	int vert_count = mdt->get_vertex_count();
	for (int v = 0; v < vert_count; v++) {
		PackedInt32Array n_list;
		PackedInt32Array edge_indices = mdt->get_vertex_edges(v);
		for (int j = 0; j < edge_indices.size(); j++) {
			int edge_idx = edge_indices[j];
			int v1 = mdt->get_edge_vertex(edge_idx, 0);
			int v2 = mdt->get_edge_vertex(edge_idx, 1);
			int other = (v1 == v) ? v2 : v1;
			n_list.append(other);
		}
		result[v] = n_list;
	}
	return result;
}

PackedColorArray VertexPainterCore::fill_surface(
		const PackedColorArray &p_colors,
		const Vector4 &p_channels,
		bool p_is_fill) {
	PackedColorArray colors = p_colors;
	double value = p_is_fill ? 1.0 : 0.0;
	for (int i = 0; i < colors.size(); i++) {
		Color c = colors[i];
		if (p_channels.x > 0) c.r = value;
		if (p_channels.y > 0) c.g = value;
		if (p_channels.z > 0) c.b = value;
		if (p_channels.w > 0) c.a = value;
		colors[i] = c;
	}
	return colors;
}

}
