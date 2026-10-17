shader_type canvas_item;
// The scenery under a stage's light (src/level/stage_lighting.gd): a thin highlight along the edges facing the moon
// (upper left: a rim of backlight) and, for the decoration standing on the ground, a fade to dark towards the floor so
// its feet sink into it.
uniform vec3 rim_color : source_color = vec3(0.72, 0.86, 1.0);
uniform float rim_strength = 0.7;
uniform float rim_width = 2.0;                     // game px
uniform vec2 light_dir = vec2(-0.6, -0.8);         // towards the light, in the world
uniform float ground_y = 497.0;
uniform float fade_height = 0.0;                   // px above the floor where the fade starts (0 = none)
uniform float fade_dark = 0.3;                     // brightness at the floor
uniform float blur = 0.0;
uniform bool rim_sides = false;                   // backlight on the left, top and right edges instead of towards light_dir                          // depth of field: soft focus, game px

varying vec4 modc;
varying vec2 uvdir;
varying vec2 uvl;
varying vec2 uvu;
varying vec2 uvr;
varying float wy;
varying float sc;

void vertex() {
	modc = COLOR;
	mat2 m = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	uvdir = inverse(m) * normalize(light_dir) * rim_width * TEXTURE_PIXEL_SIZE;
	uvl = inverse(m) * vec2(-1.0, 0.0) * rim_width * TEXTURE_PIXEL_SIZE;
	uvu = inverse(m) * vec2(0.0, -1.0) * rim_width * TEXTURE_PIXEL_SIZE;
	uvr = inverse(m) * vec2(1.0, 0.0) * rim_width * TEXTURE_PIXEL_SIZE;
	wy = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
	sc = max(length(MODEL_MATRIX[0].xy), 0.0001);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	if (blur > 0.0) {   // a ring of taps (premultiplied, so a soft edge does not pick up the colour of nothing)
		vec2 px = TEXTURE_PIXEL_SIZE * (blur / sc);
		vec4 acc = vec4(t.rgb * t.a, t.a) * 2.0;
		float wsum = 2.0;
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.7854;
			vec4 q = texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px);
			acc += vec4(q.rgb * q.a, q.a);
			wsum += 1.0;
		}
		acc /= wsum;
		t = vec4(acc.a > 0.001 ? acc.rgb / acc.a : t.rgb, acc.a);
	}
	vec3 c = t.rgb * modc.rgb;
	float a = t.a * modc.a;
	if (rim_strength > 0.0) {
		float edge;
		if (rim_sides) {   // the strongest of the left, top and right edges (a hall lit from all around, not the floor)
			float el = t.a - 0.5 * (texture(TEXTURE, UV + uvl).a + texture(TEXTURE, UV + uvl * 2.0).a);
			float eu = t.a - 0.5 * (texture(TEXTURE, UV + uvu).a + texture(TEXTURE, UV + uvu * 2.0).a);
			float er = t.a - 0.5 * (texture(TEXTURE, UV + uvr).a + texture(TEXTURE, UV + uvr * 2.0).a);
			edge = clamp(max(el, max(eu, er)), 0.0, 1.0);
		} else {
			float toward = 0.5 * (texture(TEXTURE, UV + uvdir).a + texture(TEXTURE, UV + uvdir * 2.0).a);
			edge = clamp(t.a - toward, 0.0, 1.0);
		}
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		c += rim_color * edge * rim_strength * (0.5 + 0.5 * clamp(lum * 2.5, 0.0, 1.0));
	}
	if (fade_height > 0.0) {
		float k = smoothstep(ground_y - fade_height, ground_y, wy);
		c *= mix(1.0, fade_dark, k);
	}
	COLOR = vec4(c, a);
}
