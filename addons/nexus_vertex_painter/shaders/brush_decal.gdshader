shader_type spatial;

// unshaded: Lighting calculation not needed for a UI element.
// depth_draw_never: This object should not write to the depth buffer (it's a ghost overlay).
// cull_back: Standard culling.
// blend_mix: Standard alpha blending.
render_mode unshaded, depth_draw_never, cull_back, blend_mix;

// Active color channels mask (1.0 = active, 0.0 = inactive)
uniform vec4 channel_mask = vec4(1.0, 0.0, 0.0, 0.0); 

// Brush settings passed from the plugin
uniform float brush_radius = 1.0; 
uniform float falloff_range : hint_range(0.0, 1.0) = 0.5;
uniform vec3 brush_pos; 

// Visual settings for the ring lines
uniform float width_outer = 0.008; 
uniform float width_inner = 0.002; 
uniform float softness = 0.002;
uniform float thickness_scale = 0.015;
uniform float min_thickness = 0.002;

// Varying to pass the world position from Vertex to Fragment stage
varying vec3 world_pos;

void vertex() {
	// 1. "Physical Overlay": Push vertices out along their normals.
	// This guarantees the ring floats slightly ABOVE the original mesh, preventing Z-fighting.
	VERTEX += NORMAL * 0.005; // 5mm offset
	
	// 2. Calculate world position for distance checks in the fragment shader
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 3. Calculate 3D distance from the brush center
	float dist = distance(world_pos, brush_pos);
	
	// --- DYNAMIC WIDTH CALCULATION ---
	// Scale thickness based on brush size, but clamp to a minimum visibility
	float w_outer = max(min_thickness, brush_radius * thickness_scale);
	float w_inner = max(min_thickness * 0.5, w_outer * 0.25);
	float dyn_softness = w_outer * 0.5;
	
	// --- COLOR LOGIC ---
	// Mix color based on active channels
	vec3 final_color = vec3(0.0);
	if (channel_mask.r > 0.5) final_color.r += 1.0;
	if (channel_mask.g > 0.5) final_color.g += 1.0;
	if (channel_mask.b > 0.5) final_color.b += 1.0;
	
	// Fallback to gray if no channel is selected
	if (length(final_color) < 0.1) final_color = vec3(0.5); 
	
	// Normalize to prevent mixed colors (like yellow) from being brighter than single colors
	final_color = normalize(final_color + vec3(0.001));
	
	// --- RING LOGIC ---
	float alpha = 0.0;
	
	// A. Outer Ring (Brush Boundary)
	float dist_delta_outer = abs(dist - brush_radius);
	float outer_ring = 1.0 - smoothstep(w_outer, w_outer + dyn_softness, dist_delta_outer);
	
	// B. Inner Ring (Falloff Start)
	float inner_radius_val = brush_radius * (1.0 - falloff_range);
	float dist_delta_inner = abs(dist - inner_radius_val);
	float inner_ring = 1.0 - smoothstep(w_inner, w_inner + dyn_softness, dist_delta_inner);
	
	// --- VISUAL ASSEMBLY ---
	
	// If Alpha channel is active, color the inner ring white
	vec3 inner_color_visual = final_color;
	if (channel_mask.a > 0.5) inner_color_visual = vec3(1.0); 
	
	vec3 out_rgb = vec3(0.0);
	
	// Compose rings
	if (outer_ring > 0.0) {
		out_rgb = final_color;
		alpha = outer_ring;
	} 
	if (inner_ring > 0.0) {
		out_rgb = inner_color_visual;
		alpha = max(alpha, inner_ring);
	}
	
	// Clipping: Discard pixels far outside the brush radius for performance
	if (dist > brush_radius + w_outer + 0.1) {
		alpha = 0.0;
		discard;
	}

	ALBEDO = out_rgb;
	ALPHA = alpha; 
}