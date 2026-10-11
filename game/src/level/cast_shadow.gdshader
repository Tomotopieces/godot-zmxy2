shader_type canvas_item;
// A cast shadow: the body's own silhouette in one dark colour, with a soft edge (a ring of taps of its alpha).
uniform vec4 shadow_color : source_color = vec4(0.02, 0.03, 0.08, 0.4);
uniform float blur = 3.0;   // game px

varying float fade;
varying float sc;

void vertex() {
	fade = COLOR.a;
	sc = max(length(MODEL_MATRIX[0].xy), 0.0001);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * (blur / sc);
	float a = texture(TEXTURE, UV).a * 2.0;
	float w = 2.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5236;
		float r = (i % 2 == 0) ? 1.0 : 0.55;
		a += texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px * r).a;
		w += 1.0;
	}
	COLOR = vec4(shadow_color.rgb, (a / w) * shadow_color.a * fade);
}
