shader_type spatial;
// render_mode unshaded;

group_uniforms heightBlend;

uniform bool invertHeight = false;
uniform int vertexColor : hint_enum("Red", "Green", "Blue", "Alpha");
uniform float heightBlendOffset : hint_range(0.0, 1.0) = 0.3;
uniform float heightBlendContrast : hint_range(0.0, 1.0) = 0.2;

group_uniforms materialA;
group_uniforms materialA.textures;
uniform sampler2D albedoTex_A : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D heightTex_A : hint_default_black, filter_linear_mipmap_anisotropic;
uniform sampler2D normalTex_A : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughnessTex_A : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D aoTex_A : hint_default_white, filter_linear_mipmap_anisotropic;

group_uniforms materialA.UVControls;
uniform float UVScale_A = 1.0;
uniform vec2 UVOffset_A = vec2(0.0, 0.0);
uniform float UVRot_A : hint_range(0.0, 360.0) = 0.0;
uniform vec2 pivot_A = vec2(0.0, 0.0);

group_uniforms materialA.albedo;
uniform vec3 tint_A : source_color = vec3(1.0, 1.0, 1.0);
uniform float albedoBrightness_A : hint_range(-1.0, 1.0) = 0.0;
uniform float albedoContrast_A : hint_range(-1.0, 1.0) = 0.0;

group_uniforms materialA.roughness;
uniform float roughnessLevel_A : hint_range(-1.0, 1.0) = 0.0;
uniform float roughnessContrast_A : hint_range(-1.0, 2.0) = 0.0;

group_uniforms materialA.normal;
uniform float normalIntensity_A : hint_range(0.0, 5.0) = 1.0;

group_uniforms materialA.ao;
uniform float aoLevel_A : hint_range(-1.0, 1.0) = 0.0;


group_uniforms materialB;
group_uniforms materialB.textures;
uniform sampler2D albedoTex_B : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D heightTex_B : hint_default_black, filter_linear_mipmap_anisotropic;
uniform sampler2D normalTex_B : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughnessTex_B : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D aoTex_B : hint_default_white, filter_linear_mipmap_anisotropic;

group_uniforms materialB.UVControls;
uniform float UVScale_B = 1.0;
uniform vec2 UVOffset_B = vec2(0.0, 0.0);
uniform float UVRot_B : hint_range(0.0, 360.0) = 0.0;
uniform vec2 pivot_B = vec2(0.0, 0.0);

group_uniforms materialB.albedo;
uniform vec3 tint_B : source_color = vec3(1.0, 1.0, 1.0);
uniform float albedoBrightness_B : hint_range(-1.0, 1.0) = 0.0;
uniform float albedoContrast_B : hint_range(-1.0, 1.0) = 0.0;

group_uniforms materialB.roughness;
uniform float roughnessLevel_B : hint_range(-1.0, 1.0) = 0.0;
uniform float roughnessContrast_B : hint_range(-1.0, 2.0) = 0.0;

group_uniforms materialB.normal;
uniform float normalIntensity_B : hint_range(0.0, 5.0) = 1.0;

group_uniforms materialB.ao;
uniform float aoLevel_B : hint_range(-1.0, 1.0) = 0.0;


vec3 normalStrength(vec3 normal_A, float strength){
	vec3 unpacked = normal_A * 2.0 - 1.0;
	return vec3(unpacked.xy * strength, unpacked.z) * 0.5 + 0.5;
}
vec2 rotateUV(vec2 uv, float angle, vec2 pivot_A_in) {

    float angle_rad = radians(angle);
    vec2 pivot_A_internal = clamp(pivot_A_in, 0.0, 1.0);

    mat2 rotate = mat2(
    vec2(cos(angle_rad), -sin(angle_rad)),
    vec2(sin(angle_rad), cos(angle_rad))
	);

		uv -= pivot_A_internal;
		uv = rotate * uv;
		uv += pivot_A_internal;
		return uv;
}
vec2 uvManip(vec2 uv, vec2 scale, float rotation, vec2 pivot_A_in, vec2 offset){
    vec2 pivot_A_internal = clamp(pivot_A_in, 0.0, 1.0);
	uv -= pivot_A_internal;
    uv *= scale;
	uv = rotateUV(uv, rotation, vec2(0.0));
	uv += pivot_A_internal;
    uv += offset;
    return uv;
}
float heightBlend(float h1, float h2, float height_offset, float contrast, float mask){
	height_offset = 1.0 - height_offset;
    float add1 = h1 + height_offset;
	float subtract1 = h2 - height_offset;
    float add2 = subtract1 + mask;
	float max1 = max(add1, add2);
	float subtract2 = max1 - add1;
	float multiply1 = subtract2 * (contrast * 100.0);
    float result = clamp(multiply1, 0.0, 1.0);
	return result;
}
float getChannel(vec4 tex, int ch) {
	if (ch == 0) return tex.r;
	if (ch == 1) return tex.g;
	if (ch == 2) return tex.b;
	if (ch == 3) return tex.a;
	return 1.0;
}
void vertex() {

}

void fragment() {

    vec2 uv = UV;
    vec2 uv_A = uvManip(uv, vec2(UVScale_A), UVRot_A, pivot_A, UVOffset_A);
    vec2 uv_B = uvManip(uv, vec2(UVScale_B), UVRot_B, pivot_B, UVOffset_B);

    float mask = getChannel(COLOR, vertexColor);

    // Material A

	vec3 albedo_A = texture(albedoTex_A, uv_A).rgb;
	vec3 normal_A = texture(normalTex_A, uv_A).rgb;
	float roughness_A = texture(roughnessTex_A, uv_A).r;
	float ao_A = texture(aoTex_A, uv_A).r;
	float height_A = texture(heightTex_A, uv_A).r;

	albedo_A = albedo_A * tint_A;
	albedo_A = albedo_A * (albedoBrightness_A + 1.0);
	albedo_A = (albedo_A - 0.5) * max(albedoContrast_A + 1.0, 0.0) + 0.5;
	albedo_A = clamp(albedo_A, 0.0, 1.0);

	roughness_A = roughness_A + roughnessLevel_A;
	roughness_A = (roughness_A - 0.5) * max(roughnessContrast_A + 1.0, 0.0) + 0.5;

	normal_A = normalStrength(normal_A, normalIntensity_A);

	ao_A += aoLevel_A;
	ao_A = clamp(ao_A, 0.0, 1.0);

    // Material B

	vec3 albedo_B = texture(albedoTex_B, uv_B).rgb;
	vec3 normal_B = texture(normalTex_B, uv_B).rgb;
	float roughness_B = texture(roughnessTex_B, uv_B).r;
	float ao_B = texture(aoTex_B, uv_B).r;
	float height_B = texture(heightTex_B, uv_B).r;

	albedo_B = albedo_B * tint_B;
	albedo_B = albedo_B * (albedoBrightness_B + 1.0);
	albedo_B = (albedo_B - 0.5) * max(albedoContrast_B + 1.0, 0.0) + 0.5;
	albedo_B = clamp(albedo_B, 0.0, 1.0);

	roughness_B = roughness_B + roughnessLevel_B;
	roughness_B = (roughness_B - 0.5) * max(roughnessContrast_B + 1.0, 0.0) + 0.5;

	normal_B = normalStrength(normal_B, normalIntensity_B);

	ao_B += aoLevel_B;
	ao_B = clamp(ao_B, 0.0, 1.0);

    // Material Blending

    float height_blend = heightBlend(mix(height_A, 1.0 - height_A, float(invertHeight)), height_B, heightBlendOffset, heightBlendContrast, mask);

    vec3 albedo_blend = mix(albedo_A, albedo_B, height_blend);
    vec3 normal_blend = mix(normal_A, normal_B, height_blend);
    float roughness_blend = mix(roughness_A, roughness_B, height_blend);
    float ao_blend = mix(ao_A, ao_B, height_blend);

	ALBEDO = vec3(albedo_blend);
	NORMAL_MAP = normal_blend;
	ROUGHNESS = roughness_blend;
	AO = ao_blend;
}
