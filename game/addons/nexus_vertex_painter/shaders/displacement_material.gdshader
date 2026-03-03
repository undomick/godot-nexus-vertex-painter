shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Texture inputs
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D displacement_texture : hint_default_black, filter_linear_mipmap, repeat_enable;

// Settings
uniform float uv_scale : hint_range(0.01, 100.0) = 1.0;
uniform float displacement_scale : hint_range(0.0, 2.0) = 0.1;
uniform float displacement_midpoint : hint_range(0.0, 1.0) = 0.5;
uniform float normal_scale : hint_range(-2.0, 2.0) = 1.0;

void vertex() {
	vec2 uv = UV * uv_scale;

	// Sample displacement (R channel), subtract midpoint for 0.5-centered maps
	float height = texture(displacement_texture, uv).r - displacement_midpoint;

	// Offset vertex along normal
	VERTEX += NORMAL * height * displacement_scale;
}

void fragment() {
	vec2 uv = UV * uv_scale;

	vec3 albedo = texture(albedo_texture, uv).rgb;
	vec3 orm = texture(orm_texture, uv).rgb;
	vec3 normal_map = texture(normal_texture, uv).rgb;

	ALBEDO = albedo;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	AO = orm.r;
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = normal_scale;
}
