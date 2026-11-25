shader_type spatial;
// Façades des immeubles et maisons de Dakar : enduit (texture photo × couleur des sommets, bas sali),
// fenêtres dessinées au pixel près : cadre, appui, vitre qui reflète, persiennes en bois peintes,
// grilles en fer forgé aux étages bas, climatiseurs, coulures sous les appuis, dalle à chaque étage.
// La nuit, une partie des fenêtres s'allume (lumière chaude).
// L'alpha de la couleur des sommets choisit le rendu :
//   1.0 mur avec fenêtres   0.5 enduit sans fenêtre (acrotères, balcons)
//   0.4 rideau de fer (tôle)   0.3 peinture unie (portes, réservoirs)   0.2 vitrage (bandeaux vitrés)
//   0.75 mur-rideau des tours (verre teinté, montants alu, allèges)   0.85 immeuble de bureaux à bandeaux vitrés

render_mode cull_back;

#include "res://world/shaders/city_lamps.gdshaderinc"

uniform sampler2DArray detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;

global uniform float city_wet;
global uniform float city_detail;
global uniform float city_night;   // 0 jour → 1 nuit (0 si les fenêtres allumées sont désactivées)

const float FLOOR_H = 3.2;
const float BAY = 3.1;
const float L_TIN = 4.0;
const float L_PLASTER = 5.0;
const float L_CONCRETE = 2.0;
const float L_WOOD = 6.0;

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 1 à l'intérieur de [lo, hi], bords adoucis selon la taille du pixel (anti-crénelage)
float band(float x, float lo, float hi) {
	float fw = max(fwidth(x), 1e-4);
	return clamp((x - lo) / fw + 0.5, 0.0, 1.0) * clamp((hi - x) / fw + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 n = normalize(v_wn);
	float a = COLOR.a;
	vec3 base = COLOR.rgb;
	vec2 uv;
	vec3 T;
	vec3 B = vec3(0.0, 1.0, 0.0);
	if (abs(n.y) > 0.5) {
		uv = v_wp.xz;
		T = vec3(1.0, 0.0, 0.0);
		B = vec3(0.0, 0.0, -1.0);
	} else {
		T = normalize(vec3(-n.z, 0.0, n.x));
		uv = vec2(dot(v_wp, T), -v_wp.y);
	}
	float u = uv.x;
	float y = v_wp.y;

	vec3 col = base;
	float rough = 0.9;
	float metal = 0.0;
	float spec = 0.4;
	vec3 emit = vec3(0.0);
	float layer = L_PLASTER;
	float tscale = 3.0;
	float nstrength = 1.0;
	float porous = 0.6;

	bool curtain = a > 0.7 && a < 0.8;
	bool ribbon = a > 0.8 && a < 0.9;
	if (curtain) {
		layer = -1.0;
		porous = 0.0;
	} else if (a < 0.25) {
		// Bandeau vitré : verre sombre qui reflète le ciel
		col = base * 0.6;
		rough = 0.06;
		spec = 0.9;
		layer = -1.0;
		porous = 0.0;
	} else if (a < 0.35) {
		// Peinture unie (portes métalliques, réservoirs)
		layer = L_CONCRETE;
		tscale = 2.0;
		nstrength = 0.3;
		rough = 0.6;
		porous = 0.2;
	} else if (a < 0.45) {
		// Rideau de fer des boutiques : tôle ondulée horizontale
		layer = L_TIN;
		uv = vec2(-uv.y, uv.x);
		tscale = 1.6;
		metal = 0.4;
		rough = 0.55;
		porous = 0.0;
	}

	vec3 nw = n;
	if (layer >= 0.0) {
		vec4 d = texture(detail_tex, vec3(uv / tscale, layer));
		vec4 big = texture(detail_tex, vec3(uv / 37.0 + vec2(0.21, 0.63), L_PLASTER));
		col *= mix(vec3(1.0), d.rgb * 2.0, layer == L_PLASTER ? 0.3 : 0.8);
		if (layer == L_PLASTER) {
			// Taches et enduit refait par endroits
			col *= mix(0.86, 1.1, big.r);
			rough = mix(0.8, 1.0, d.a);
		}
		if (city_detail > 0.5) {
			vec3 tn = texture(normal_tex, vec3(uv / tscale, layer)).xyz * 2.0 - 1.0;
			tn.xy *= layer == L_PLASTER ? 0.45 : nstrength;
			nw = normalize(T * tn.x + B * tn.y + n * max(tn.z, 0.2));
		}
	}

	// --- Tours : mur-rideau (trame de 1,55 m, allège opaque à chaque dalle) ---
	if (curtain && abs(n.y) < 0.5) {
		float fl = floor(y / FLOOR_H);
		float fy = y - fl * FLOOR_H;
		float mu = u / 1.55;
		vec2 cell = vec2(floor(mu), fl) + floor(n.xz * 6.0 + 0.5) * 3.0;
		float h1 = hash(cell);
		float h2 = hash(cell + 7.1);
		float mf = fract(mu);
		// Verre : teinte de la tour, reflet du ciel plus clair vers le haut, panneaux légèrement différents
		vec3 glass = base * mix(0.7, 0.95, h1) + vec3(0.04, 0.06, 0.08) * clamp(y / 50.0, 0.0, 1.0);
		float spandrel = band(fy, 0.0, 0.8);
		float far = clamp(fwidth(mu) * 3.0, 0.0, 1.0);
		float mull = (band(mf, 0.0, 0.04) + band(mf, 0.96, 1.0) + band(fy, 0.8, 0.88)) * (1.0 - far * 0.7);
		col = mix(glass, base * 0.45 + vec3(0.04), spandrel * 0.85);
		col = mix(col, vec3(0.62, 0.64, 0.66), clamp(mull, 0.0, 1.0));
		rough = mix(0.04, 0.4, clamp(spandrel + mull, 0.0, 1.0));
		spec = 0.9;
		metal = mix(0.35, 0.8, clamp(mull, 0.0, 1.0));
		// Bureaux allumés la nuit (lumière froide), étages entiers parfois
		float lit = step(0.72, h2) + step(0.9, hash(vec2(fl, floor(dot(v_wp.xz, n.xz) / 9.0))));
		emit = vec3(1.0, 0.9, 0.72) * 0.22 * clamp(lit, 0.0, 1.0) * (1.0 - spandrel) * (1.0 - clamp(mull, 0.0, 1.0)) * city_night * (0.4 + 0.6 * h1) * mix(0.6, 1.0, clamp((fy - 0.8) / 2.4, 0.0, 1.0));
	}
	// --- Bureaux : bandeau vitré continu à chaque étage, montants tous les 1,8 m ---
	if (ribbon && abs(n.y) < 0.5) {
		float fl = floor(y / FLOOR_H);
		float fy = y - fl * FLOOR_H;
		float mu = u / 1.8;
		vec2 cell = vec2(floor(mu), fl) + floor(n.xz * 6.0 + 0.5) * 3.0;
		float h1 = hash(cell);
		float rib = band(fy, 0.95, 2.55) * step(0.5, fl);
		float mull = band(fract(mu), 0.0, 0.05) * (1.0 - clamp(fwidth(mu) * 3.0, 0.0, 0.7));
		vec3 glass = mix(vec3(0.12, 0.16, 0.2), vec3(0.32, 0.4, 0.48), clamp((fy - 0.95) / 1.6, 0.0, 1.0)) * (0.85 + 0.3 * h1);
		col = mix(col, glass, rib);
		col = mix(col, vec3(0.2, 0.21, 0.22), rib * mull);
		col *= 1.0 - band(fy, 0.0, 0.18) * 0.12 * step(0.5, fl);
		rough = mix(rough, 0.05, rib * (1.0 - mull));
		spec = mix(spec, 0.9, rib);
		emit = vec3(1.0, 0.9, 0.72) * 0.22 * step(0.72, h1) * rib * (1.0 - mull) * city_night * mix(0.6, 1.0, clamp((fy - 0.95) / 1.6, 0.0, 1.0));
	}

	// --- Fenêtres (murs principaux seulement) ---
	if (a > 0.95 && abs(n.y) < 0.5) {
		float fl = floor(y / FLOOR_H);
		float fy = y - fl * FLOOR_H;
		float bay = floor(u / BAY);
		float fu = u - bay * BAY - BAY * 0.5;      // -BAY/2 .. BAY/2
		vec2 cell = vec2(bay, fl) + floor(n.xz * 6.0 + 0.5) * 3.0;
		float h1 = hash(cell);
		float h2 = hash(cell + 17.3);
		float h3 = hash(cell + 41.9);
		float hb = hash(vec2(fl, floor(dot(v_wp.xz, n.xz)))); // une teinte par façade et par étage

		// Dalle d'étage : fine bande plus sombre
		float slab = band(fy, 0.0, 0.14) * step(0.5, fl);
		col *= 1.0 - slab * 0.18;
		// Soubassement peint au pied du mur (plus sombre, souvent d'une autre teinte) et son liseré
		if (fl < 0.5) {
			float hp = hash(vec2(floor(dot(v_wp.xz, n.xz)), 3.7));
			vec3 plinth = hp < 0.5 ? col * 0.6 : mix(col * 0.55, vec3(0.42, 0.3, 0.22), 0.5);
			col = mix(col, plinth, band(fy, -1.0, 0.6) * step(0.25, hp));
			col *= 1.0 - 0.25 * band(fy, 0.6, 0.66) * step(0.25, hp);
		}

		bool has_win = h1 > 0.1 && !(fl < 0.5 && h1 < 0.55);
		if (has_win) {
			float hw = 0.62;     // demi-largeur
			float y0 = 0.95;
			float y1 = 2.4;
			float frame = 0.07;
			float outer = band(fu, -hw, hw) * band(fy, y0, y1);
			float inner = band(fu, -hw + frame, hw - frame) * band(fy, y0 + frame, y1 - frame);
			// Appui de fenêtre en béton, plus large
			float sill = band(fu, -hw - 0.1, hw + 0.1) * band(fy, y0 - 0.1, y0);
			// Coulures noires sous l'appui
			float drip = band(fu, -hw - 0.05, hw + 0.05) * clamp(1.0 - (y0 - 0.1 - fy) / 1.4, 0.0, 1.0) * step(fy, y0 - 0.1);
			float streak = texture(detail_tex, vec3(vec2(u * 2.3, y * 0.05), L_CONCRETE)).g;
			col *= 1.0 - drip * 0.3 * smoothstep(0.42, 0.62, streak) * (1.0 - abs(fu) / (hw + 0.05));

			vec3 frame_col = h3 < 0.6 ? vec3(0.9, 0.9, 0.87) : vec3(0.32, 0.22, 0.15);
			// Linteau en béton au-dessus, ombre portée sous l'appui (la fenêtre est en retrait dans le mur)
			float lintel = band(fu, -hw - 0.08, hw + 0.08) * band(fy, y1, y1 + 0.16);
			col = mix(col, vec3(0.8, 0.78, 0.74) * (base.r + base.g + base.b) / 2.3, lintel * 0.7);
			col *= 1.0 - 0.28 * band(fu, -hw - 0.1, hw + 0.1) * band(fy, y0 - 0.24, y0 - 0.1) * smoothstep(y0 - 0.26, y0 - 0.1, fy);
			col = mix(col, frame_col, (outer - inner));
			col = mix(col, vec3(0.78, 0.76, 0.72) * (base.r + base.g + base.b) / 2.2, sill);

			if (inner > 0.0) {
				float ix = (fu + hw - frame) / (2.0 * (hw - frame)); // 0..1 dans la fenêtre
				float iy = (fy - y0 - frame) / (y1 - y0 - 2.0 * frame);
				vec3 inside;
				float in_rough;
				float in_spec;
				float in_metal = 0.0;
				bool lit = h3 > 0.62 && city_night > 0.01;
				float louver_side = h2 < 0.35 ? 1.0 : (h2 < 0.5 ? step(0.5, ix) : 0.0);
				if (louver_side > 0.5) {
					// Persiennes en bois peintes (vert, brun, bleu, crème)
					vec3 pc = hb < 0.3 ? vec3(0.18, 0.36, 0.25) : (hb < 0.55 ? vec3(0.42, 0.27, 0.16) : (hb < 0.8 ? vec3(0.16, 0.3, 0.5) : vec3(0.85, 0.82, 0.74)));
					float slat = fract(iy * 11.0);
					// Au loin, les lames se fondent (pas de moiré)
					float far = smoothstep(0.08, 0.3, fwidth(iy * 11.0));
					float sh = mix(mix(0.62, 1.0, smoothstep(0.0, 0.85, slat)), 0.86, far);
					float mid = band(ix, 0.485, 0.515); // jonction des deux battants
					vec3 wood = texture(detail_tex, vec3(vec2(ix * 1.3, iy * 0.5), L_WOOD)).rgb * 2.0;
					inside = pc * sh * mix(vec3(1.0), wood, 0.12 * (1.0 - far)) * (1.0 - mid * 0.4);
					in_rough = 0.75;
					in_spec = 0.3;
					if (lit) {
						emit = vec3(1.0, 0.62, 0.3) * 0.5 * smoothstep(0.85, 1.0, slat);
					}
				} else {
					// Vitre : intérieur sombre + reflet du ciel en haut, rideau parfois
					float curtain = step(0.7, h2) * band(ix, 0.0, 0.35 + h1 * 0.3);
					inside = mix(vec3(0.05, 0.06, 0.07), vec3(0.22, 0.27, 0.32), iy * 0.8);
					inside = mix(inside, vec3(0.75, 0.68, 0.55) * (0.5 + h2 * 0.5), curtain * 0.8);
					// Croisillon (fenêtre à deux battants)
					float mull = band(ix, 0.48, 0.52) + band(iy, 0.62, 0.66);
					inside = mix(inside, frame_col, clamp(mull, 0.0, 1.0));
					in_rough = mix(0.05, 0.7, clamp(mull + curtain, 0.0, 1.0));
					in_spec = 0.9;
					if (lit) {
						vec3 warm = h1 > 0.5 ? vec3(1.0, 0.66, 0.34) : vec3(0.85, 0.9, 1.0);
						emit = warm * (1.0 - clamp(mull, 0.0, 1.0)) * (curtain > 0.0 ? 0.7 : 1.4);
					}
				}
				// Grille en fer forgé (rez-de-chaussée et 1er étage)
				if (fl < 1.5 && h2 > 0.2) {
					float bars = band(fract(ix * 7.0), 0.45, 0.55) + band(fract(iy * 3.0), 0.47, 0.53);
					float b = clamp(bars, 0.0, 1.0) * (1.0 - clamp(fwidth(ix * 7.0) * 2.0 - 0.4, 0.0, 0.7));
					inside = mix(inside, vec3(0.06, 0.06, 0.06), b);
					in_rough = mix(in_rough, 0.5, b);
					emit *= 1.0 - b;
				}
				// Profondeur : ombre du linteau en haut de l'ouverture et des tableaux sur les côtés
				float reveal = mix(0.5, 1.0, 1.0 - smoothstep(0.8, 1.0, iy)) * mix(0.72, 1.0, smoothstep(0.0, 0.07, min(ix, 1.0 - ix)));
				inside *= reveal;
				col = mix(col, inside, inner);
				rough = mix(rough, in_rough, inner);
				spec = mix(spec, in_spec, inner);
				nw = normalize(mix(nw, n, inner));
				emit *= inner * city_night;
			}
			// Climatiseur sous la fenêtre (immeubles)
			if (h1 > 0.82 && fl > 0.5) {
				float ac = band(fu, hw - 0.1, hw + 0.75) * band(fy, 0.25, 0.85);
				float grille = 0.85 + 0.15 * step(0.5, fract(fy * 22.0));
				col = mix(col, vec3(0.82, 0.83, 0.82) * grille, ac);
				rough = mix(rough, 0.5, ac);
			}
		}
	}

	col = clamp(col, 0.0, 1.0);
	vec3 alb = to_linear(col);
	// Pluie : façades plus sombres, surtout en bas (éclaboussures)
	float w = clamp(city_wet, 0.0, 1.0);
	alb *= mix(1.0, 0.75, w * porous * mix(1.0, 0.5, clamp(y / 6.0, 0.0, 1.0)));
	rough = mix(rough, rough * 0.6, w);

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	// Lampadaires : les murs proches reçoivent la lumière orangée
	if (city_lamp_night > 0.0) {
		emit += alb * lamp_light(v_wp, nw) * city_lamp_night;
	}
	EMISSION = emit;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
