shader_type spatial;
// Flaque d'eau sur la chaussée : forme irrégulière, bords doux, surface lisse qui reflète le ciel.
// « wet » (0 à 1) la fait apparaître pendant la pluie et sécher ensuite.
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform float wet : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sky_color : source_color = vec3(0.6, 0.65, 0.7);
varying float seed;

void vertex() {
	seed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	// Contour bosselé, différent pour chaque flaque
	float r = 0.72 + 0.12 * sin(a * 3.0 + seed * 6.28) + 0.07 * sin(a * 5.0 + seed * 17.0) + 0.04 * sin(a * 9.0 + seed * 3.0);
	float d = length(p);
	float mask = 1.0 - smoothstep(r * 0.75, r, d);
	// Reflet du ciel plus fort en regardant de biais (effet de Fresnel)
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(vec3(0.03, 0.032, 0.036), sky_color * 0.75, 0.25 + fres * 0.7);
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ALPHA = mask * wet * 0.85;
}
