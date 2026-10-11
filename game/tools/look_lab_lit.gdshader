shader_type canvas_item;
// Experiment: a normal map made from the sprite itself (brightness bumps + a rounded silhouette), so the 2D lights of
// Godot shade flat Flash art; optional rim light on the edge facing the light.
uniform float bump : hint_range(0.0, 8.0) = 2.5;
uniform float round_edge : hint_range(0.0, 4.0) = 1.5;
uniform float rim = 0.0;

float lum(vec4 c) {
	return dot(c.rgb, vec3(0.299, 0.587, 0.114)) * c.a;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * 1.5;
	vec4 c = texture(TEXTURE, UV);
	float lx = lum(texture(TEXTURE, UV + vec2(px.x, 0.0))) - lum(texture(TEXTURE, UV - vec2(px.x, 0.0)));
	float ly = lum(texture(TEXTURE, UV + vec2(0.0, px.y))) - lum(texture(TEXTURE, UV - vec2(0.0, px.y)));
	float ax = texture(TEXTURE, UV + vec2(px.x, 0.0)).a - texture(TEXTURE, UV - vec2(px.x, 0.0)).a;
	float ay = texture(TEXTURE, UV + vec2(0.0, px.y)).a - texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	vec3 n = normalize(vec3(-(lx * bump + ax * round_edge), -(ly * bump + ay * round_edge), 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	if (rim > 0.0) {
		float edge = clamp(-(ax * -0.7 + ay * -0.7), 0.0, 1.0);   // the silhouette edge that faces up-left
		c.rgb += vec3(1.0, 0.92, 0.75) * edge * 0.6 * c.a;
	}
	COLOR = c;
}
