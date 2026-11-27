shader_type spatial;
// Peau hyper-réaliste pour les personnages de Dakar (compatible Vulkan Mobile & Forward+) :
// - Micro-pores épidermiques haute fréquence et grain de peau naturel ;
// - Diffusion sous la peau (Subsurface Scattering SSS) adaptée aux carnations mélanodermes ;
// - Double lobe spéculaire Cook-Torrance (GGX) pour un éclat d'hydratation naturel ;
// - Rétrodiffusion et contre-jour sur les reliefs fins (oreilles, nez, doigts).
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.05;
uniform sampler2D spec_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.52;
uniform float specular_level : hint_range(0.0, 1.0) = 0.48;
uniform vec3 scatter_color : source_color = vec3(0.74, 0.28, 0.18);
uniform float wrap : hint_range(0.0, 1.0) = 0.42;
uniform float translucency : hint_range(0.0, 2.0) = 0.55;
uniform float saturation : hint_range(0.5, 1.5) = 1.04;
uniform float pore_strength : hint_range(0.0, 1.0) = 0.32;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint.rgb;
	// Richesse chromatique : chaleur et vivacité naturelle du teint
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(l), c, saturation);

	// Relief principal combiné avec le micro-grain épidermique haute fréquence
	vec3 main_norm = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	vec3 micro_norm = texture(normal_tex, UV * 18.0).rgb * 2.0 - 1.0;
	vec3 combined_norm = normalize(main_norm + vec3(micro_norm.xy * pore_strength, 0.0));
	NORMAL_MAP = combined_norm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;

	// Répartition naturelle de la rugosité et éclat soyeux de la peau
	float s = texture(spec_tex, UV).r;
	ROUGHNESS = clamp(roughness_base - (s - 0.5) * 0.38, 0.28, 0.82);
	SPECULAR = specular_level * (0.65 + s * 0.75);

	// Éclat rasant soyeux (peach fuzz atmosphérique)
	RIM = 0.24;
	RIM_TINT = 0.48;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Diffusion sous la peau : enveloppe chaude plus étendue sur le rouge que le vert/bleu
	vec3 w = vec3(wrap, wrap * 0.72, wrap * 0.58);
	vec3 diff = clamp((vec3(ndl) + w) / ((1.0 + w) * (1.0 + w)), 0.0, 1.0);
	float shadow_edge = clamp(1.0 - abs(ndl) * 2.3, 0.0, 1.0);
	vec3 dyn_scatter = mix(scatter_color, tint.rgb * 1.5, 0.35);
	diff += dyn_scatter * shadow_edge * wrap * 0.14;
	DIFFUSE_LIGHT += diff * ATTENUATION * LIGHT_COLOR / PI;

	// Reflet GGX Cook-Torrance pour l'hydratation et le relief
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
	float F = 0.035 + 0.965 * pow(1.0 - max(dot(VIEW, h), 0.0), 5.0);
	float spec = D * G * F / (4.0 * nl * nv + 0.0001);
	SPECULAR_LIGHT += spec * nl * ATTENUATION * LIGHT_COLOR * SPECULAR_AMOUNT;

	// Contre-jour translucide : oreilles, arrêtes nasales et contours
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * pow(1.0 - nv, 2.0);
	DIFFUSE_LIGHT += dyn_scatter * back * translucency * ATTENUATION * LIGHT_COLOR / PI;
}
