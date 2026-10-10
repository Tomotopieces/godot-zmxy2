// Flash display-object filters (blur / glow / color matrix) for a CanvasGroup.
// The group renders its children off-screen; this samples that buffer (premultiplied) and filters it.
// Sizes are in game pixels; flash_px_scale converts them to screen pixels (window stretch).
shader_type canvas_item;
render_mode unshaded;

// No mipmaps: the canvas back buffer's mip chain is unreliable at the group's edges at non-integer window
// scales (stray lines / blocks of glow). The blur takes more taps on the full-resolution buffer instead.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
global uniform float flash_px_scale;

uniform vec2 blur = vec2(0.0);                  // box blur size
uniform bool glow_on = false;
uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.0, 1.0);
uniform vec2 glow_blur = vec2(0.0);
uniform float glow_strength = 1.0;
uniform bool glow_gauss = false;               // glow of quality HIGH: three box passes, which add up to a bell (sigma = blur / 2)
uniform bool glow_inner = false;
uniform bool glow_knockout = false;
uniform bool matrix_on = false;
uniform mat4 color_matrix = mat4(1.0);          // rgba' = color_matrix * rgba + color_offset
uniform vec4 color_offset = vec4(0.0);

// Box average over `size` (game px) around uv: an up to 11x11 grid of bilinear taps.
vec4 box(vec2 uv, vec2 size, vec2 pixel) {
	vec2 s = size * max(flash_px_scale, 0.0001);
	if (s.x < 1.0 && s.y < 1.0) {
		return textureLod(screen_texture, uv, 0.0);
	}
	int n = clamp(int(ceil(max(s.x, s.y) / 3.0)), 2, 10);
	vec4 acc = vec4(0.0);
	for (int i = 0; i <= n; i++) {
		for (int j = 0; j <= n; j++) {
			vec2 o = (vec2(float(i), float(j)) / float(n) - 0.5) * s;
			acc += textureLod(screen_texture, uv + o * pixel, 0.0);
		}
	}
	return acc / float((n + 1) * (n + 1));
}

// Alpha of the three-pass blur of size `size` (game px), as a Gaussian of sigma size / 2 (a grid of 11 x 11 weighted taps).
float gauss_alpha(vec2 uv, vec2 size, vec2 pixel) {
	vec2 sigma = max(size * 0.5 * max(flash_px_scale, 0.0001), vec2(0.5));
	vec2 reach = sigma * 2.5;
	float acc = 0.0;
	float wsum = 0.0;
	for (int i = 0; i <= 10; i++) {
		for (int j = 0; j <= 10; j++) {
			vec2 o = (vec2(float(i), float(j)) / 10.0 - 0.5) * 2.0 * reach;
			vec2 q = o / sigma;
			float w = exp(-0.5 * dot(q, q));
			acc += w * textureLod(screen_texture, uv + o * pixel, 0.0).a;
			wsum += w;
		}
	}
	return acc / wsum;
}

void fragment() {
	vec4 c = box(SCREEN_UV, blur, SCREEN_PIXEL_SIZE);
	if (glow_on) {
		float a = glow_gauss ? gauss_alpha(SCREEN_UV, glow_blur, SCREEN_PIXEL_SIZE) : box(SCREEN_UV, glow_blur, SCREEN_PIXEL_SIZE).a;
		if (glow_inner) {
			float g = clamp((1.0 - a) * glow_strength, 0.0, 1.0) * glow_color.a;
			c.rgb = mix(c.rgb, glow_color.rgb * c.a, g);
		} else {
			float g = clamp(a * glow_strength, 0.0, 1.0) * glow_color.a;
			vec4 gl = vec4(glow_color.rgb * g, g);
			c = glow_knockout ? gl * (1.0 - c.a) : c + gl * (1.0 - c.a);
		}
	}
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	if (matrix_on) {
		c = clamp(color_matrix * c + color_offset, 0.0, 1.0);
	}
	COLOR *= c;
}
