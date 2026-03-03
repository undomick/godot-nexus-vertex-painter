shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Standalone preview shader: displays vertex colors (grayscale mask) only.
// Used temporarily as overlay when "Preview Smart Mask" is active.
// No textures, no layers - just vertex color as albedo.
// Works with any mesh; original material is never touched.

void vertex() {
	// Pass through - vertex colors interpolate to fragment
}

void fragment() {
	vec4 vc = COLOR;
	float mask_val = vc.r;
	ALBEDO = vec3(mask_val, mask_val, mask_val);
	ROUGHNESS = 0.5;
	METALLIC = 0.0;
	AO = 1.0;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
