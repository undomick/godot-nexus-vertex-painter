shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_mix;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

// --- TEXTURE SETTINGS ---
uniform sampler2D brush_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_texture = false;

uniform vec4 channel_mask = vec4(1.0, 0.0, 0.0, 0.0); 
uniform float brush_radius = 1.0; 
uniform float falloff_range : hint_range(0.0, 1.0) = 0.5;
uniform float brush_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 brush_pos; 

// Rotation angle in radians
uniform float brush_angle = 0.0;

// Pass the hit normal explicitly
uniform vec3 brush_normal = vec3(0.0, 1.0, 0.0); 

// Visual settings
uniform float width_outer = 0.008; 
uniform float width_inner = 0.002; 
uniform float softness = 0.002;
uniform float thickness_scale = 0.015;
uniform float min_thickness = 0.002;

// Varyings
varying vec3 world_pos;
varying vec3 v_normal; 

void vertex() {
	// Physical Overlay
	VERTEX += NORMAL * 0.005;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Normal for Triplanar Blending
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// --- HELPER: ROTATE UV ---
vec2 rotate_uv(vec2 uv, float angle) {
	vec2 pivot = vec2(0.5);
	float s = sin(angle);
	float c = cos(angle);
	mat2 rotation_mat = mat2(vec2(c, s), vec2(-s, c));
	return pivot + rotation_mat * (uv - pivot);
}

void fragment() {
	float dist = distance(world_pos, brush_pos);
	
	// Dynamic Widths
	float w_outer = max(min_thickness, brush_radius * thickness_scale);
	float w_inner = max(min_thickness * 0.5, w_outer * 0.25);
	float dyn_softness = w_outer * 0.5;
	
	// Color Logic
	vec3 final_color = vec3(0.0);
	if (channel_mask.r > 0.5) final_color.r += 1.0;
	if (channel_mask.g > 0.5) final_color.g += 1.0;
	if (channel_mask.b > 0.5) final_color.b += 1.0;
	
	if (length(final_color) < 0.1) final_color = vec3(0.5); 
	final_color = normalize(final_color + vec3(0.001));
	
	// --- TRIPLANAR TEXTURE LOGIC (FIXED MIRRORING) ---
	float tex_alpha = 0.0;
	
	if (use_texture) {
		// 1. Triplanar Weights
		vec3 blending = abs(v_normal);
		blending = pow(blending, vec3(4.0)); 
		blending /= dot(blending, vec3(1.0));
		
		// 2. Relative Position (Centered at Brush)
		vec3 rel_pos = world_pos - brush_pos;
		float uv_scale = 1.0 / (brush_radius * 2.0);
		
		// 3. Calculate Projections & Apply Rotation & Fix Mirroring
		
		// --- Y-Plane (Top/Bottom) ---
		// Map XZ to UV.
		vec2 raw_uv_y = rel_pos.xz;
		// FIX: If normal points down (-Y), flip X to prevent mirroring looking from below
		if (v_normal.y < 0.0) raw_uv_y.x = -raw_uv_y.x;
		// Standard Flip for Y-Projection usually requires inverting X relative to Z for readable text
		raw_uv_y.x = -raw_uv_y.x; 
		
		vec2 uv_y = raw_uv_y * uv_scale + 0.5;
		uv_y.y = 1.0 - uv_y.y; // Standard Vertical Flip
		uv_y = rotate_uv(uv_y, brush_angle);

		// --- Z-Plane (Front/Back) ---
		// Map XY to UV.
		vec2 raw_uv_z = rel_pos.xy;
		// FIX: If normal points Back (-Z), flip X to prevent mirroring
		if (v_normal.z < 0.0) raw_uv_z.x = -raw_uv_z.x;
		
		vec2 uv_z = raw_uv_z * uv_scale + 0.5;
		uv_z.y = 1.0 - uv_z.y; 
		uv_z = rotate_uv(uv_z, brush_angle);
		
		// --- X-Plane (Left/Right) ---
		// Map ZY to UV.
		vec2 raw_uv_x = rel_pos.zy;
		// FIX: If normal points Left (-X), flip horizontal axis (Z in this case)
		if (v_normal.x < 0.0) raw_uv_x.x = -raw_uv_x.x;
		// Correction for side mapping direction
		raw_uv_x.x = -raw_uv_x.x; 
		
		vec2 uv_x = raw_uv_x * uv_scale + 0.5;
		uv_x.y = 1.0 - uv_x.y;
		uv_x = rotate_uv(uv_x, brush_angle);
		
		// 4. Sampling with bounds check
		float col_y = 0.0;
		if(uv_y.x >= 0.0 && uv_y.x <= 1.0 && uv_y.y >= 0.0 && uv_y.y <= 1.0) {
			vec4 s = texture(brush_texture, uv_y);
			col_y = s.r * s.a;
		}
		
		float col_z = 0.0;
		if(uv_z.x >= 0.0 && uv_z.x <= 1.0 && uv_z.y >= 0.0 && uv_z.y <= 1.0) {
			vec4 s = texture(brush_texture, uv_z);
			col_z = s.r * s.a;
		}
		
		float col_x = 0.0;
		if(uv_x.x >= 0.0 && uv_x.x <= 1.0 && uv_x.y >= 0.0 && uv_x.y <= 1.0) {
			vec4 s = texture(brush_texture, uv_x);
			col_x = s.r * s.a;
		}
		
		// 5. Blending
		tex_alpha = col_x * blending.x + col_y * blending.y + col_z * blending.z;
		
		// Soft circular crop
		float circle_mask = 1.0 - smoothstep(brush_radius - 0.05, brush_radius, dist);
		tex_alpha *= circle_mask;
	}
	
	// --- RING LOGIC (Unchanged) ---
	
	float dist_delta_outer = abs(dist - brush_radius);
	float outer_ring = 1.0 - smoothstep(w_outer, w_outer + dyn_softness, dist_delta_outer);
	
	float inner_ring = 0.0;
	if (!use_texture) {
		float inner_r = brush_radius * (1.0 - falloff_range);
		float dist_delta_inner = abs(dist - inner_r);
		inner_ring = 1.0 - smoothstep(w_inner, w_inner + dyn_softness, dist_delta_inner);
	}
	
	// Meter
	float meter_radius = brush_radius + w_outer + (brush_radius * 0.05) + 0.02;
	float meter_track = 1.0 - smoothstep(w_inner, w_inner + dyn_softness, abs(dist - meter_radius));
	vec3 dir = world_pos - brush_pos;
	float angle = atan(dir.x, dir.z); 
	float meter_pct = (angle / 3.14159) * 0.5 + 0.5;
	float meter_fill = (meter_pct < brush_strength) ? meter_track : 0.0;
	
	// --- COMPOSITION ---
	
	float final_alpha = 0.0;
	vec3 final_rgb = final_color;
	
	if (use_texture) {
		if (tex_alpha > 0.0) final_alpha = tex_alpha; 
	}
	
	if (outer_ring > final_alpha) final_alpha = outer_ring;
	
	if (inner_ring > final_alpha) {
		final_alpha = inner_ring;
		if (channel_mask.a > 0.5) final_rgb = vec3(1.0);
	}
	
	if (meter_track > 0.0) {
		float m_vis = max(meter_track * 0.2, meter_fill);
		if (m_vis > final_alpha) {
			final_alpha = m_vis;
			final_rgb = final_color;
		}
	}

	if (dist > meter_radius + w_outer + 0.1) {
		final_alpha = 0.0;
		discard;
	}

	ALBEDO = final_rgb;
	ALPHA = final_alpha;
}