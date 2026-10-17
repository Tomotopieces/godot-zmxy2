shader_type canvas_item;
// A will-o'-the-wisp flame (src/level/stage_lighting.gd, "sway"): it wavers like smoke - ripples run up the flame and
// bend it sideways, more and more towards its tip (its foot stays put). The quad is widened by "margin" on both sides so
// the bent flame is not cut off at the edges of its picture.

uniform float warp = 0.25;      // sideways bend at the tip, as a share of the picture's width
uniform float speed = 0.4;      // ripples per second
uniform float phase = 0.0;      // each flame at its own time
uniform float pivot_x = 0.0;    // the flame's middle, in its local px
uniform float margin = 0.5;     // extra width on each side, as a share of the picture's width

varying float ux;

void vertex() {
	float k = 1.0 + 2.0 * margin;
	VERTEX.x = pivot_x + (VERTEX.x - pivot_x) * k;
	ux = (UV.x - 0.5) * k + 0.5;   // 0..1 is the picture, outside it the margin
}

void fragment() {
	float h = 1.0 - UV.y;   // 0 at the foot of the flame, 1 at its tip
	float t = TIME * speed * 6.2832 + phase;
	// two ripples running up the flame, a slow wide one and a quicker narrow one
	float bend = sin(UV.y * 5.0 + t) * 0.65 + sin(UV.y * 11.0 + t * 1.6 + phase * 0.7) * 0.35;
	vec2 uv = vec2(ux - warp * h * h * bend, UV.y);
	vec4 c = texture(TEXTURE, uv);
	if (uv.x < 0.0 || uv.x > 1.0) {
		c = vec4(0.0);
	}
	COLOR = c * COLOR;
}
