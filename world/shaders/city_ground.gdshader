shader_type spatial;
// Sol, chaussées, trottoirs et toits de la ville (couleur des sommets × texture photo).
// Le matériau est choisi par l'alpha de la couleur des sommets (posé par tools/bake_dakar.gd) :
//   1.0 couleur unie (terrains)   0.97 peinture routière (usée)   0.9 asphalte   0.8 pavés   0.7 béton (bordures, quais)
//   0.6 sable/terre   0.5 toit-terrasse en béton   0.45 tôle ondulée
// Textures : ambientCG (CC0), voir world/textures/CREDITS.md.

render_mode cull_back;

#include "res://world/shaders/city_lamps.gdshaderinc"

uniform sampler2DArray detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;

global uniform float city_wet;     // 0 sec → 1 trempé (pluie)
global uniform float city_detail;  // 0 profil Faible (sans relief), 1 sinon

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.37 + 3.3) * 0.15;
}

// Distance (en m) à la frontière la plus proche d'un réseau de Voronoï déformé : plaques de 1 à 2 m.
// Vraie distance à la médiatrice entre plaques voisines (deux passes) : la fente garde la même largeur
// partout (l'ancienne approximation f2 - f1 l'élargissait beaucoup le long de certains bords).
float cracks(vec2 p) {
	vec2 q = p / 1.5 + (vec2(vnoise(p * 0.9), vnoise(p * 0.9 + 5.0)) - 0.5) * 0.3;
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 mr = vec2(0.0);
	vec2 mg = vec2(0.0);
	float md = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + vec2(hash21(i + g), hash21(i + g + 19.3)) - f;
			float dd = dot(r, r);
			if (dd < md) {
				md = dd;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = mg + vec2(float(x), float(y));
			vec2 r = g + vec2(hash21(i + g), hash21(i + g + 19.3)) - f;
			vec2 dr = r - mr;
			if (dot(dr, dr) > 1e-5) {
				md = min(md, dot(0.5 * (mr + r), normalize(dr)));
			}
		}
	}
	// En mètres (une cellule fait 1,5 m), bords à peine déchiquetés
	return md * 1.5 + (vnoise(p * 14.0) - 0.5) * 0.006;
}

// Asphalte de Dakar : gris chaud délavé par le soleil, rustines plus sombres, traces de roues
// lustrées, taches d'huile au milieu des voies, sable apporté par le vent le long des trottoirs.
// edge_m : distance au bord (m), half_m : demi-largeur ; road = false hors chaussée (parkings, ponts).
void asphalt(vec2 p, float edge_m, float half_m, bool road, vec4 d, inout vec3 col, inout float rough, inout float wet_mask) {
	float lum = dot(d.rgb, vec3(0.299, 0.587, 0.114)) * 2.0; // grain photo sans sa teinte bleue
	float big = fbm(p * 0.045);
	float mid = fbm(p * 0.35 + 11.0);
	// Gris chaud blanchi par le soleil (l'ancien gris 0.37 paraissait presque noir en plein jour),
	// grandes plaques plus ou moins délavées
	col = vec3(0.5, 0.48, 0.45) * mix(1.0, lum, 0.55) * mix(0.8, 1.12, big);
	// Gravillons : points clairs et sombres de quelques centimètres, effacés au loin (pas de scintillement)
	float fade = 1.0 - smoothstep(0.015, 0.05, length(fwidth(p)));
	if (fade > 0.0) {
		float g = vnoise(p * 22.0 + vec2(vnoise(p * 5.0) * 3.0));
		col *= 1.0 + (smoothstep(0.72, 0.9, g) * 0.14 - smoothstep(0.28, 0.1, g) * 0.12) * fade;
	}
	rough = mix(0.82, 0.97, d.a);
	// Rustines : rectangles d'asphalte plus récent (plus sombre, plus lisse)
	vec2 cell = floor(p / 5.0);
	float h = hash21(cell);
	if (h > 0.86) {
		// Bords un peu irréguliers (découpe à la main) et teinte qui se fond dans l'asphalte usé
		vec2 lp = fract(p / 5.0) + (vec2(vnoise(p * 3.0), vnoise(p * 3.0 + 9.0)) - 0.5) * 0.03;
		vec2 c0 = vec2(hash21(cell + 3.1), hash21(cell + 7.7)) * 0.4 + 0.1;
		vec2 c1 = c0 + vec2(hash21(cell + 1.3), hash21(cell + 5.9)) * 0.45 + 0.15;
		if (all(greaterThan(lp, c0)) && all(lessThan(lp, c1))) {
			col *= mix(0.72, 0.86, big);
			rough -= 0.1;
		}
	}
	if (road) {
		// Traces de roues : deux bandes par voie (voies de ~3 m depuis chaque bord)
		float lane = mod(edge_m, 3.2);
		float track = smoothstep(0.55, 0.15, abs(lane - 0.85)) + smoothstep(0.55, 0.15, abs(lane - 2.55));
		// Plus ou moins marquées le long de la rue (pas de rayures régulières)
		track *= step(0.6, edge_m) * smoothstep(0.25, 0.75, mid);
		col *= 1.0 - 0.18 * track;
		rough -= 0.1 * track;
		// Taches d'huile au centre des voies (là où s'arrêtent les cars rapides)
		float oil = smoothstep(0.72, 0.85, fbm(p * 0.6 + 31.0)) * smoothstep(0.7, 0.0, abs(lane - 1.7));
		col *= 1.0 - 0.35 * oil;
		rough -= 0.25 * oil;
		// Sable et poussière le long des bordures, plus ou moins étalés
		float reach = 0.35 + 0.9 * fbm(p * 0.25 + 5.0);
		float dust = smoothstep(reach, 0.0, edge_m) * (0.55 + 0.45 * mid);
		col = mix(col, vec3(0.66, 0.58, 0.45) * mix(0.85, 1.1, lum * 0.5), dust * 0.85);
		rough = mix(rough, 1.0, dust);
		wet_mask = 1.0 - 0.6 * dust;
		// Caniveau : bande sombre au pied de la bordure
		col *= 1.0 - 0.3 * smoothstep(0.35, 0.05, edge_m) * (1.0 - 0.5 * dust);
	}
	// Fissures longues : creux du bruit (lignes sombres irrégulières)
	// Largeur constante (~1 cm) : distance au creux = valeur / pente du bruit (sinon traits épais là où il varie peu)
	float cr = abs(fbm(p * 0.9 + 17.0) - 0.5);
	float pw = max(length(fwidth(p)), 1e-5);
	float cd = cr / max(fwidth(cr) / pw, 1e-3);
	col *= 1.0 - 0.4 * smoothstep(0.012 + pw * 0.6, 0.0, cd) * smoothstep(0.55, 0.8, big) * (0.3 + 0.7 * fade);
	// Faïençage : réseau de fissures en plaques, par zones (asphalte vieilli), seulement de près
	if (fade > 0.0) {
		float zone = smoothstep(0.5, 0.68, fbm(p * 0.11 + 3.0));
		if (zone > 0.0) {
			float e = cracks(p);
			// Fente d'environ 1 cm, élargie à un pixel au loin (sinon elle clignote)
			col *= 1.0 - 0.5 * smoothstep(0.006 + pw * 0.5, 0.0, e) * zone * fade;
		}
	}
	rough = clamp(rough, 0.45, 1.0);
}

// Trottoirs : dalles rectangulaires (24 × 12 cm) posées en quinconce le long de la rue (u = direction),
// teintes grises variées, joints sombres remplis de sable. Au loin, joints et variations s'estompent.
void pavers(vec2 p, vec2 u, vec4 d, inout vec3 col, inout float rough) {
	vec2 s = vec2(dot(p, u), dot(p, vec2(-u.y, u.x)));
	float row = floor(s.y / 0.12);
	s.x += mod(row, 2.0) * 0.12;
	vec2 cell = vec2(floor(s.x / 0.24), row);
	vec2 f = vec2(fract(s.x / 0.24), fract(s.y / 0.12));
	float e = min(min(f.x, 1.0 - f.x) * 0.24, min(f.y, 1.0 - f.y) * 0.12);
	float h = hash21(cell);
	float h2 = hash21(cell + 13.7);
	vec3 base = vec3(0.78, 0.765, 0.735);
	vec3 brick = base * mix(0.8, 1.06, h);
	brick = mix(brick, vec3(0.8, 0.73, 0.62) * mix(0.88, 1.03, h), step(0.85, h2)); // quelques dalles ocre
	brick *= mix(0.9, 1.0, smoothstep(0.0, 0.025, e)); // arêtes usées, un peu plus sombres
	float lum = dot(d.rgb, vec3(0.299, 0.587, 0.114)) * 2.0;
	brick *= mix(1.0, lum, 0.35);
	vec3 joint = vec3(0.45, 0.41, 0.35); // sable tassé
	float pw = length(fwidth(p));
	float jfade = 1.0 - smoothstep(0.008, 0.035, pw); // joints
	float tfade = 1.0 - smoothstep(0.08, 0.25, pw); // teintes des dalles, visibles plus loin
	vec3 near = mix(joint, brick, smoothstep(0.002, 0.007, e));
	vec3 far = base * 0.9 * mix(1.0, lum, 0.35);
	col = mix(mix(far, brick * 0.97, tfade), near, jfade);
	rough = mix(0.85, 1.0, d.a);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float a = COLOR.a;
	float layer = -1.0;
	float scale = 3.0; // mètres par répétition
	float porous = 1.0;
	float contrast = 1.0; // force du détail photo
	float bright = 1.0;
	if (a > 0.95) { layer = -1.0; }
	else if (a > 0.85) { layer = 0.0; scale = 3.5; porous = 0.8; }   // asphalte (voir asphalt())
	else if (a > 0.75) { layer = 1.0; scale = 1.5; porous = 0.6; contrast = 0.6; }   // pavés
	else if (a > 0.65) { layer = 2.0; scale = 3.0; porous = 0.7; }     // béton
	else if (a > 0.55) { layer = 3.0; scale = 5.0; porous = 1.0; contrast = 0.55; }   // sable
	else if (a > 0.475) { layer = 2.0; scale = 6.0; porous = 0.7; }    // toit en béton
	else { layer = 4.0; scale = 2.4; porous = 0.0; }                   // tôle

	vec3 n = normalize(v_wn);
	bool flat_face = abs(n.y) > 0.5;
	vec2 uv;
	vec3 T;
	vec3 B;
	if (flat_face) {
		uv = v_wp.xz;
		T = vec3(1.0, 0.0, 0.0);
		B = vec3(0.0, 0.0, -1.0);
	} else {
		vec3 t = normalize(vec3(-n.z, 0.0, n.x));
		uv = vec2(dot(v_wp, t), -v_wp.y);
		T = t;
		B = vec3(0.0, 1.0, 0.0);
	}

	vec3 col = COLOR.rgb;
	float rough = 0.92;
	vec3 nw = n;
	float wet_mask = 1.0;
	if (a > 0.95 && a < 0.99) {
		// Peinture routière : effacée par les pneus et la poussière, l'asphalte reparaît par endroits
		vec4 d = texture(detail_tex, vec3(uv / 3.5, 0.0));
		vec3 asph = col;
		float dummy = 1.0;
		asphalt(v_wp.xz, 99.0, 0.0, false, d, asph, rough, dummy);
		float wear = smoothstep(0.35, 0.75, fbm(v_wp.xz * 1.7 + 41.0)) * 0.75 + 0.15 * fbm(v_wp.xz * 9.0);
		col = mix(col * vec3(0.93, 0.92, 0.88), asph, clamp(wear, 0.0, 0.85));
		rough = mix(0.65, rough, wear);
	}
	if (layer == 0.0 && flat_face) {
		vec4 d = texture(detail_tex, vec3(uv / scale, layer));
		bool road = COLOR.b > 0.9;
		asphalt(v_wp.xz, road ? COLOR.r * 8.0 : 99.0, COLOR.g * 8.0, road, d, col, rough, wet_mask);
		if (city_detail > 0.5) {
			vec3 tn = texture(normal_tex, vec3(uv / scale, layer)).xyz * 2.0 - 1.0;
			nw = normalize(T * tn.x * 0.7 + B * tn.y * 0.7 + n * max(tn.z, 0.2));
		}
	} else if (layer == 1.0 && flat_face && COLOR.b < 0.02) {
		// Trottoir dallé (direction de la rue dans la couleur, voir tools/bake_dakar.gd)
		vec2 u = normalize(vec2(COLOR.r * 2.0 - 1.0, COLOR.g) + vec2(1e-4, 0.0));
		vec4 d = texture(detail_tex, vec3(uv / 1.2, 2.0)); // grain du béton
		pavers(v_wp.xz, u, d, col, rough);
	} else if (layer >= 0.0) {
		vec4 d = texture(detail_tex, vec3(uv / scale, layer));
		// Grande variation (casse la répétition) : la même texture, beaucoup plus grande
		vec4 big = texture(detail_tex, vec3(uv / (scale * 13.7) + vec2(0.37, 0.71), layer));
		col *= bright * mix(vec3(1.0), d.rgb * 2.0, contrast) * mix(1.0, big.g * 2.0, 0.3);
		rough = mix(0.75, 1.0, d.a);
		if (city_detail > 0.5) {
			vec3 tn = texture(normal_tex, vec3(uv / scale, layer)).xyz * 2.0 - 1.0;
			nw = normalize(T * tn.x + B * tn.y + n * max(tn.z, 0.2));
		}
		if (layer == 4.0) {
			rough = mix(0.45, 0.8, d.a);
			METALLIC = 0.35;
		}
	} else {
		rough = 0.85;
	}
	if (layer == 3.0) {
		// Sable un peu moins jaune (poussière grise des rues)
		col = mix(col, vec3(dot(col, vec3(0.33))), 0.25);
		// Gravillons et cailloux clairs ou sombres, seulement de près
		float gf = 1.0 - smoothstep(0.015, 0.05, length(fwidth(v_wp.xz)));
		if (gf > 0.0 && flat_face) {
			float g = vnoise(v_wp.xz * 16.0 + vec2(vnoise(v_wp.xz * 4.0) * 2.0));
			col *= 1.0 + (smoothstep(0.76, 0.92, g) * 0.08 - smoothstep(0.24, 0.08, g) * 0.08) * gf;
		}
	}
	col = clamp(col, 0.0, 1.0);
	vec3 alb = to_linear(col);

	// Pluie : le sol fonce et devient brillant (les creux d'abord)
	float w = clamp(city_wet, 0.0, 1.0) * (flat_face ? 1.0 : 0.5) * wet_mask;
	alb *= mix(1.0, 0.55, w * porous);
	rough = mix(rough, 0.12, w * (flat_face ? 0.9 : 0.5));
	nw = normalize(mix(nw, n, w * 0.6));

	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = mix(0.35, 0.6, w);
	// Lampadaires : flaques de lumière orangée (plus brillantes sur le sol mouillé)
	if (city_lamp_night > 0.0) {
		EMISSION = alb * lamp_light(v_wp, nw) * city_lamp_night * (1.0 + 1.2 * w);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
