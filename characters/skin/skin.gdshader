shader_type spatial;
// Peau réaliste pour les personnages MakeHuman (compatible GL Compatibility / Android) :
// - relief de la peau (pores, rides) et brillance variable (front, nez plus brillants) ;
// - diffusion sous la peau : la lumière « déborde » dans les ombres en teinte chaude (rouge plus que bleu) ;
// - reflet spéculaire physique (GGX) et lumière qui traverse les bords (oreilles, contre-jour).
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float normal_strength = 0.9;
uniform sampler2D spec_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.56;
uniform float specular_level : hint_range(0.0, 1.0) = 0.42;
uniform vec3 scatter_color : source_color = vec3(0.62, 0.3, 0.22);
uniform float wrap : hint_range(0.0, 1.0) = 0.38;
uniform float translucency : hint_range(0.0, 2.0) = 0.4;
uniform float saturation : hint_range(0.5, 1.5) = 0.97;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint.rgb;
	// Légère saturation : les textures MakeHuman sont un peu ternes
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(l), c, saturation);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	float s = texture(spec_tex, UV).r;
	ROUGHNESS = clamp(roughness_base - (s - 0.5) * 0.35, 0.3, 0.85);
	SPECULAR = specular_level * (0.55 + s * 0.9);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Diffusion sous la peau : enveloppe plus large pour le rouge que pour le vert et le bleu
	vec3 w = vec3(wrap, wrap * 0.7, wrap * 0.6);
	vec3 diff = clamp((vec3(ndl) + w) / ((1.0 + w) * (1.0 + w)), 0.0, 1.0);
	float shadow_edge = clamp(1.0 - abs(ndl) * 2.5, 0.0, 1.0);
	diff += scatter_color * shadow_edge * wrap * 0.08;
	DIFFUSE_LIGHT += diff * ATTENUATION * LIGHT_COLOR / PI;

	// Reflet GGX (Cook-Torrance)
	float nl = max(ndl, 0.0);
	float nv = max(dot(NORMAL, VIEW), 0.001);
	vec3 h = normalize(VIEW + LIGHT);
	float nh = max(dot(NORMAL, h), 0.0);
	float r = ROUGHNESS;
	float a2 = r * r * r * r;
	float dd = nh * nh * (a2 - 1.0) + 1.0;
	float D = a2 / (PI * dd * dd);
	float k = (r + 1.0) * (r + 1.0) / 8.0;
	float G = (nl / (nl * (1.0 - k) + k)) * (nv / (nv * (1.0 - k) + k));
	float F = 0.028 + 0.972 * pow(1.0 - max(dot(VIEW, h), 0.0), 5.0);
	float spec = D * G * F / (4.0 * nl * nv + 0.0001);
	SPECULAR_LIGHT += spec * nl * ATTENUATION * LIGHT_COLOR * SPECULAR_AMOUNT;

	// Contre-jour : la lumière traverse les bords fins (oreilles, nez, doigts)
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * pow(1.0 - nv, 2.0);
	DIFFUSE_LIGHT += scatter_color * back * translucency * ATTENUATION * LIGHT_COLOR / PI;
}
