shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 brush_pos;
uniform float brush_radius = 0.0;
uniform float marker_size = 7.0;

varying vec3 world_pos;

void vertex() {
	if (COLOR.a > 0.5) {
		VERTEX += NORMAL * 0.01;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POINT_SIZE = marker_size;
}

void fragment() {
	if (distance(world_pos, brush_pos) > brush_radius) {
		discard;
	}
	if (length(POINT_COORD - vec2(0.5)) > 0.5) {
		discard;
	}
	ALBEDO = vec3(1.0, 0.85, 0.15);
}
