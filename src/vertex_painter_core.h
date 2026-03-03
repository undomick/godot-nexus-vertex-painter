#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class VertexPainterCore : public RefCounted {
	GDCLASS(VertexPainterCore, RefCounted)

protected:
	static void _bind_methods();

public:
	VertexPainterCore() = default;
	~VertexPainterCore() override = default;

	// Phase 2: Main paint loop - returns modified colors for one surface
	PackedColorArray paint_surface(
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
			bool p_curv_invert);

	// Phase 3: Build neighbor cache for one surface (MeshDataTool requires ArrayMesh)
	Dictionary build_neighbor_cache(const Ref<ArrayMesh> &p_mesh, int p_surface_idx);

	// Phase 5 (optional): Fill/Clear - simple channel set
	PackedColorArray fill_surface(const PackedColorArray &p_colors, const Vector4 &p_channels, bool p_is_fill);

	// Phase 2+3: Mesh rebuild with vertex colors - uses add_surface_from_arrays + USE_DYNAMIC_UPDATE
	// for Phase 3: surface_update_attribute_region can then be used for fast color-only updates
	Ref<ArrayMesh> apply_colors_to_mesh(
			const Ref<Mesh> &p_source_mesh,
			const Dictionary &p_surface_colors,
			const Dictionary &p_surface_materials);

	// Phase 3: Convert PackedColorArray to PackedByteArray for surface_update_attribute_region.
	// Godot's internal attribute buffer uses RGBA8 (4 bytes per vertex).
	PackedByteArray pack_colors_to_rgba8(const PackedColorArray &p_colors);
};

}
