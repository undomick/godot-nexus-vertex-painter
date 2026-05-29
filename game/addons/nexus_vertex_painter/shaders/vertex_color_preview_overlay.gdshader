shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, unshaded;

// Semi-transparent vertex-color layer on a child MeshInstance3D.
// The base mesh keeps its materials; this only tints the framebuffer behind it.

uniform float overlay_strength : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float normal_offset : hint_range(0.0, 0.01, 0.00001) = 0.0008;

void vertex() {
	VERTEX += NORMAL * normal_offset;
}

void fragment() {
	vec3 vc = COLOR.rgb;
	float coverage = max(max(vc.r, vc.g), max(vc.b, COLOR.a));
	ALBEDO = vc;
	ALPHA = overlay_strength * max(coverage, 0.02);
}
