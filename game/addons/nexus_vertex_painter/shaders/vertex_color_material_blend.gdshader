shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 5 layers, 3 textures each: ORM (R=AO, G=Roughness, B=Metallic), Albedo, Normal
group_uniforms layer1;
uniform sampler2D mat1_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat1_albedo : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat1_normal : hint_normal, filter_linear_mipmap, repeat_enable;

group_uniforms layer2;
uniform sampler2D mat2_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat2_albedo : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat2_normal : hint_normal, filter_linear_mipmap, repeat_enable;

group_uniforms layer3;
uniform sampler2D mat3_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat3_albedo : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat3_normal : hint_normal, filter_linear_mipmap, repeat_enable;

group_uniforms layer4;
uniform sampler2D mat4_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat4_albedo : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat4_normal : hint_normal, filter_linear_mipmap, repeat_enable;

group_uniforms layer5;
uniform sampler2D mat5_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat5_albedo : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mat5_normal : hint_normal, filter_linear_mipmap, repeat_enable;

group_uniforms settings;
uniform float uv_scale : hint_range(0.01, 100.0) = 1.0;
uniform float blend_softness : hint_range(0.0, 1.0) = 0.0;
uniform float normal_scale : hint_range(-2.0, 2.0) = 1.0;

void vertex() {
	// Pass through
}

void fragment() {
	vec4 vc = COLOR;
	float r = vc.r;
	float g = vc.g;
	float b = vc.b;
	float a = vc.a;

	// Optional softness: smoothstep transition instead of hard 0/1
	float soft = blend_softness * 0.5;
	if (blend_softness > 0.001) {
		r = smoothstep(soft, 1.0 - soft, r);
		g = smoothstep(soft, 1.0 - soft, g);
		b = smoothstep(soft, 1.0 - soft, b);
		a = smoothstep(soft, 1.0 - soft, a);
	}

	// Material 1: visible when RGBA all ~0
	float w1 = 1.0 - step(0.001, r + g + b + a);
	float w2 = r;
	float w3 = g;
	float w4 = b;
	float w5 = a;

	float total = w1 + w2 + w3 + w4 + w5;
	total = max(total, 0.001);
	float inv_total = 1.0 / total;

	vec2 uv = UV * uv_scale;

	// Sample all textures
	vec3 alb1 = texture(mat1_albedo, uv).rgb;
	vec3 alb2 = texture(mat2_albedo, uv).rgb;
	vec3 alb3 = texture(mat3_albedo, uv).rgb;
	vec3 alb4 = texture(mat4_albedo, uv).rgb;
	vec3 alb5 = texture(mat5_albedo, uv).rgb;

	vec3 orm1 = texture(mat1_orm, uv).rgb;
	vec3 orm2 = texture(mat2_orm, uv).rgb;
	vec3 orm3 = texture(mat3_orm, uv).rgb;
	vec3 orm4 = texture(mat4_orm, uv).rgb;
	vec3 orm5 = texture(mat5_orm, uv).rgb;

	vec3 nor1 = texture(mat1_normal, uv).rgb;
	vec3 nor2 = texture(mat2_normal, uv).rgb;
	vec3 nor3 = texture(mat3_normal, uv).rgb;
	vec3 nor4 = texture(mat4_normal, uv).rgb;
	vec3 nor5 = texture(mat5_normal, uv).rgb;

	// Blend albedo
	vec3 albedo = (alb1 * w1 + alb2 * w2 + alb3 * w3 + alb4 * w4 + alb5 * w5) * inv_total;

	// Blend ORM (AO in R, Roughness in G, Metallic in B)
	vec3 orm = (orm1 * w1 + orm2 * w2 + orm3 * w3 + orm4 * w4 + orm5 * w5) * inv_total;

	// Blend normals: decode from 0-1 to tangent space, blend, renormalize, encode back
	vec3 n1 = nor1 * 2.0 - 1.0;
	vec3 n2 = nor2 * 2.0 - 1.0;
	vec3 n3 = nor3 * 2.0 - 1.0;
	vec3 n4 = nor4 * 2.0 - 1.0;
	vec3 n5 = nor5 * 2.0 - 1.0;
	vec3 normal_blended = (n1 * w1 + n2 * w2 + n3 * w3 + n4 * w4 + n5 * w5) * inv_total;
	normal_blended = normalize(normal_blended);
	vec3 normal_map = normal_blended * 0.5 + 0.5;

	ALBEDO = albedo;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	AO = orm.r;
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = normal_scale;
}
