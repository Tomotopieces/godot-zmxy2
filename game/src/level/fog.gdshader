shader_type canvas_item;
// Drifting mist: patches of fractal noise that slide sideways, swell and thin out on their own (no picture, nothing that
// repeats), denser near the ground, never opaque. `scroll` ties the mist loosely to the camera.
uniform vec4 fog_color : source_color = vec4(0.62, 0.72, 0.9, 1.0);
uniform float density = 0.5;        // peak opacity of a patch
uniform float ground_bias = 0.6;    // 0 = even over the screen, 1 = only near the ground
uniform float speed = 14.0;         // px / s
uniform float seed = 0.0;
uniform vec2 scroll = vec2(0.0);
uniform vec2 area = vec2(940.0, 590.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 px = UV * area;
	vec2 p = vec2((px.x + scroll.x) / 300.0, px.y / 170.0) + vec2(seed * 13.7, seed * 5.3);
	float t = TIME;
	float n1 = fbm(p + vec2(t * speed / 300.0, t * 0.004));
	float n2 = fbm(p * 1.6 + vec2(-t * speed * 0.6 / 300.0, t * 0.006) + 11.7);
	float n = n1 * 0.6 + n2 * 0.4;
	float breathe = 0.5 + 0.5 * sin(t * 0.17 + p.x * 0.9 + n2 * 3.0 + seed * 4.0);   // patches come and go
	float f = smoothstep(0.38, 0.74, n) * mix(0.3, 1.0, breathe);
	float low = smoothstep(0.15, 0.95, UV.y);
	float h = mix(1.0, low, ground_bias);
	COLOR = vec4(fog_color.rgb, clamp(f * h * density, 0.0, 0.42));
}
