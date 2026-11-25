// Lumière des lampadaires (sodium orangé) calculée dans les shaders du sol et des façades, sans vraies lumières :
// scripts/world/street_lamps.gd écrit dans city_lamps les lampadaires les plus proches de la caméra
// (un texel RGBA32F par lampadaire : x, y, z de la tête, w = intensité ; w = 0 marque la fin de la liste).
// city_lamp_count : nombre de lampadaires lus (selon le profil graphique) ; city_lamp_night : 0 le jour → 1 la nuit.
// Coût : rien le jour (branche uniforme), une boucle courte la nuit, aucune ombre.

global uniform sampler2D city_lamps : filter_nearest;
global uniform float city_lamp_night;
global uniform float city_lamp_count;

const vec3 LAMP_TINT = vec3(1.0, 0.6, 0.28);

// Éclairement reçu en wp (monde) par une surface de normale n (monde)
vec3 lamp_light(vec3 wp, vec3 n) {
	vec3 sum = vec3(0.0);
	int count = int(city_lamp_count);
	for (int i = 0; i < 32; i++) {
		if (i >= count) {
			break;
		}
		vec4 L = texelFetch(city_lamps, ivec2(i, 0), 0);
		if (L.w <= 0.0) {
			break;
		}
		vec3 v = L.xyz - wp;
		float hz2 = dot(v.xz, v.xz);
		if (hz2 > 324.0) { // au-delà de 18 m à l'horizontale : rien
			continue;
		}
		float d2 = dot(v, v);
		vec3 l = v * inversesqrt(d2);
		float ndl = max(dot(n, l), 0.0);
		// Flaque de lumière : forte sous la tête, bord doux vers 8-15 m (le luminaire éclaire vers le bas)
		float pool = 1.0 - smoothstep(16.0, 225.0, hz2);
		sum += vec3(ndl * pool * L.w * 150.0 / (d2 + 6.0));
	}
	return sum * LAMP_TINT;
}
