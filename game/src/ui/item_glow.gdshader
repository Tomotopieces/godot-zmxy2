shader_type canvas_item;
// The quality glow of an item picture (src/ui/item_icon.gd): a thin soft light hugging the outline of the picture,
// in the colour of the item's quality. Inside the picture nothing changes.

uniform vec4 glow_color : source_color = vec4(1.0, 0.4, 0.0, 0.6);
uniform float width = 2.5;   // reach of the glow, in texels of the picture

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5235988;   // 12 directions
		vec2 dir = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE;
		for (int k = 1; k <= 3; k++) {
			float r = width * float(k) / 3.0;
			float fall = 1.0 - float(k - 1) / 3.0;   // nearer samples count more: a soft edge
			m = max(m, texture(TEXTURE, UV + dir * r).a * fall);
		}
	}
	float g = clamp(m - c.a, 0.0, 1.0) * glow_color.a;
	float a = c.a + g * (1.0 - c.a);
	vec3 rgb = a > 0.0 ? (c.rgb * c.a + glow_color.rgb * g * (1.0 - c.a)) / a : vec3(0.0);
	COLOR = vec4(rgb, a) * COLOR;
}
