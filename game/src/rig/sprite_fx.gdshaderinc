// Per-sprite visual effects (no CanvasGroup, no screen texture, nothing nests): the soft glow around fire and
// energy, a tint matrix, a soft blur. Each sprite grows its own quad to make room for the halo and reads only its
// own texture, so it works on any sprite, in any renderer, inside any other effect.
// Sizes are in game pixels (sprite scale is taken from the node's transform).
uniform bool matrix_on = false;
uniform mat4 color_matrix = mat4(1.0);   // rgba' = color_matrix * rgba + color_offset
uniform vec4 color_offset = vec4(0.0);
uniform float blur = 0.0;                // soft blur radius
uniform bool glow_on = false;
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow_blur = 0.0;           // halo reach
uniform float glow_strength = 1.0;
uniform bool solid = false;              // only the halo colour: a silhouette to draw behind a character
uniform float extend = 0.0;              // room the quad needs around the sprite

varying float sc;
varying vec4 modc;

void vertex() {
	sc = max(length(MODEL_MATRIX[0].xy), 0.0001);
	modc = COLOR;
	if (extend > 0.0) {
		vec2 dir = sign(UV - 0.5);
		float pad = extend / sc;
		VERTEX += dir * pad;
		UV += dir * pad * TEXTURE_PIXEL_SIZE;
	}
}

// A texel of this sprite; outside the picture it is transparent (the quad was grown for the halo).
#define TEXEL(uv) (texture(TEXTURE, (uv)) * (step(0.0, (uv).x) * step((uv).x, 1.0) * step(0.0, (uv).y) * step((uv).y, 1.0)))

// Gaussian-weighted average of premultiplied colour within `reach` game px (sigma = reach / 2: Flash's blur of that size).
// One call per effect; the taps lie on three rings of twelve around the pixel.
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 t = TEXEL(UV);
	vec4 c = vec4(t.rgb * modc.rgb, t.a * modc.a);
	float reach[2] = float[2](blur, glow_on ? glow_blur : 0.0);
	vec4 avg[2] = vec4[2](vec4(0.0), vec4(0.0));
	for (int k = 0; k < 2; k++) {
		if (reach[k] <= 0.0) {
			continue;
		}
		float r = reach[k] / sc;
		vec4 acc = vec4(t.rgb * t.a, t.a);
		float ws = 1.0;
		for (int ring = 1; ring <= 3; ring++) {
			float d = float(ring) / 3.0;
			float w = exp(-2.0 * d * d);
			for (int i = 0; i < 12; i++) {
				float ang = 6.2831853 * (float(i) + 0.5 * float(ring)) / 12.0;
				vec2 q = UV + vec2(cos(ang), sin(ang)) * r * d * px;
				vec4 s = TEXEL(q);
				acc += vec4(s.rgb * s.a, s.a) * w;
				ws += w;
			}
		}
		avg[k] = acc / ws;
	}
	if (blur > 0.0) {
		c = vec4(avg[0].a > 0.0001 ? avg[0].rgb / avg[0].a : vec3(0.0), avg[0].a) * vec4(modc.rgb, modc.a);
	}
	if (matrix_on) {
		c = clamp(color_matrix * c + color_offset, 0.0, 1.0);
	}
	if (glow_on) {
		float g = clamp(avg[1].a * modc.a * glow_strength, 0.0, 1.0) * glow_color.a;
		if (solid) {
			COLOR = vec4(glow_color.rgb, max(g, c.a));
		} else {
			float oa = c.a + g * (1.0 - c.a);
			vec3 rgb = c.rgb * c.a + glow_color.rgb * g * (1.0 - c.a);
			COLOR = vec4(oa > 0.0001 ? rgb / oa : vec3(0.0), oa);
		}
	} else {
		COLOR = c;
	}
}
