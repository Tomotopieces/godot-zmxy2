shader_type canvas_item;
// A cast shadow: the body's own silhouette in one dark colour (fading with the body's own modulate).
uniform vec4 shadow_color : source_color = vec4(0.02, 0.03, 0.08, 0.4);

varying float fade;

void vertex() {
	fade = COLOR.a;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(shadow_color.rgb, a * shadow_color.a * fade);
}
