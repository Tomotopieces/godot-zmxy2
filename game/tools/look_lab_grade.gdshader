shader_type canvas_item;
// Experiment: screen grading - gentle contrast, shadows pushed to blue and highlights to warm, a vignette.
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float contrast = 1.12;
uniform float saturation = 1.1;
uniform float vignette = 0.45;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c = mix(c * vec3(0.92, 0.96, 1.08), c * vec3(1.06, 1.0, 0.92), smoothstep(0.25, 0.8, l));   // split toning
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * smoothstep(0.25, 0.85, length(d * vec2(1.25, 1.0)));
	COLOR = vec4(c, 1.0);
}
