shader_type canvas_item;
// A will-o'-the-wisp flame (src/level/stage_lighting.gd, "sway"): it wavers like smoke - the picture is bent sideways by
// slow ripples that grow towards its top (the bottom stays put) - and breathes a little wider and narrower.

uniform float warp = 0.08;      // sideways bend at the top, as a share of the picture's width
uniform float stretch = 0.06;   // how much wider / narrower it breathes (share of its width)
uniform float speed = 0.4;      // ripples per second
uniform float phase = 0.0;      // each flame at its own time
uniform float pivot_x = 0.0;    // the flame's middle, in its local px (the breathing is about it)

void vertex() {
	float s = 1.0 + stretch * sin(TIME * speed * 6.2832 * 0.7 + phase * 1.7);
	VERTEX.x = pivot_x + (VERTEX.x - pivot_x) * s;
}

void fragment() {
	float h = 1.0 - UV.y;   // 0 at the foot of the flame, 1 at its tip
	float t = TIME * speed * 6.2832;
	float bend = sin(UV.y * 9.0 - t + phase) * 0.6 + sin(UV.y * 19.0 + t * 0.73 + phase * 2.1) * 0.4;
	vec2 uv = vec2(UV.x + warp * h * h * bend, UV.y);
	vec4 c = texture(TEXTURE, uv);
	if (uv.x < 0.0 || uv.x > 1.0) {
		c.a = 0.0;
	}
	COLOR = c * COLOR;
}
