shader_type canvas_item;
// Rain over a stage, all in one pass (no particles, no pictures): two depth layers of drops, each falling as a thin streak
// and, where it reaches the floor, splashing: a flat ring that widens and fades plus a few droplets thrown up.
// Screen space: the camera never moves vertically, so the floor is a band of rows (land_min..land_max); a drop picks its
// landing row at random, so the splashes are spread over the depth of the floor.
uniform vec4 rain_color : source_color = vec4(0.72, 0.82, 0.96, 1.0);
uniform float amount = 0.5;          // chance that a cell has a drop in its cycle (0..1)
uniform float speed = 380.0;         // px / s, near layer (the far layer is slower)
uniform float length_px = 16.0;      // streak length, near layer
uniform float slant = 0.12;          // sideways px per px of fall (wind)
uniform float alpha = 0.5;
uniform float splash_alpha = 0.9;
uniform float land_min = 500.0;      // screen rows where the near layer's drops land
uniform float land_max = 585.0;
uniform float splash_size = 7.0;     // ring radius at its widest, near layer
uniform vec2 area = vec2(940.0, 590.0);

float h11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

// one layer. k: scale of the layer (1 = near)
vec2 layer(vec2 p, float k, float seed) {
	float cell_w = 34.0 * mix(0.7, 1.0, k);
	float sp = speed * mix(0.7, 1.0, k);
	float len = length_px * mix(0.6, 1.0, k);
	float lo = mix(land_min - 40.0, land_min, k);   // the far layer lands higher up the floor: smaller, nearer the horizon
	float hi = mix(land_min + 12.0, land_max, k);
	float fall_max = (hi + len) / sp;
	float splash_t = 0.55;
	float period = fall_max + splash_t + 0.4;
	float u = p.x - slant * p.y;
	float cell0 = floor(u / cell_w);
	float streak = 0.0;
	float splash = 0.0;
	for (int ci = -1; ci <= 1; ci++) {
		float c = cell0 + float(ci);
		float ph = h11(c * 1.37 + seed);
		float cyc = floor(TIME / period + ph);
		float t = (fract(TIME / period + ph)) * period;
		float id = c * 7.31 + mod(cyc, 997.0) * 3.17 + seed * 13.0;
		if (h11(id + 0.5) > amount) continue;
		float ux = (c + 0.1 + 0.8 * h11(id + 1.5)) * cell_w;
		float land = mix(lo, hi, h11(id + 2.5));
		float t_land = (land + len) / sp;                // the head reaches the floor
		float head = -len + t * sp;
		// the streak: between tail and head, cut off at the floor
		float du = abs(u - ux);
		float top = min(head, land);
		float tail = head - len;
		if (head > 0.0 && tail < land && p.y < top && p.y > tail) {
			float along = (p.y - tail) / len;                           // 0 tail .. 1 head: fades in towards the head
			float w = 1.0 - smoothstep(0.35, 0.9, du);
			streak = max(streak, w * (0.25 + 0.75 * along));
		}
		// the splash: from the moment the head lands
		float tt = t - t_land;
		if (tt > 0.0 && tt < splash_t) {
			float f = tt / splash_t;
			vec2 centre = vec2(ux + slant * land, land);
			vec2 d = p - centre;
			float r = splash_size * k * (0.25 + 0.75 * sqrt(f));
			float e = length(vec2(d.x, d.y / 0.32));        // a ring seen from a low angle: flat
			float ring = (1.0 - smoothstep(0.2, 1.7, abs(e - r))) * pow(1.0 - f, 0.8) * step(1.0, r);
			// droplets: three small beads on little arcs
			float beads = 0.0;
			for (int b = 0; b < 3; b++) {
				float s = float(b) - 1.0;
				vec2 bp = centre + vec2(s * (1.6 + 2.0 * h11(id + float(b))) * k * 3.0 * f, -(8.0 * k) * (f * (1.0 - f) * 4.0) * (0.6 + 0.4 * h11(id + 9.0 + float(b))));
				beads = max(beads, (1.0 - smoothstep(0.5, 1.4, length(p - bp))) * (1.0 - f));
			}
			splash = max(splash, max(ring, beads));
		}
	}
	return vec2(streak, splash);
}

void fragment() {
	vec2 p = UV * area;
	vec2 far_l = layer(p, 0.55, 1.0);
	vec2 near_l = layer(p, 1.0, 5.0);
	float streak = max(far_l.x * 0.55, near_l.x) * 0.85 * alpha;
	float splash = max(far_l.y * 0.6, near_l.y) * splash_alpha;
	COLOR = vec4(rain_color.rgb, clamp(max(streak, splash), 0.0, 1.0));
}
