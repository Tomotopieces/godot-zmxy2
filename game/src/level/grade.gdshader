shader_type canvas_item;
// Screen grading of a stage: colour balance with cool shadows and slightly warm highlights, a touch less colour, and a
// vignette. Drawn over the world, under the HUD.
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform vec3 tint = vec3(0.94, 0.98, 1.06);       // multiplies everything
uniform vec3 shadow_tone = vec3(0.90, 0.96, 1.10);
uniform vec3 light_tone = vec3(1.05, 1.02, 0.96);
uniform float saturation = 0.92;
uniform float contrast = 1.06;
uniform float vignette = 0.4;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= mix(shadow_tone, light_tone, smoothstep(0.2, 0.75, l)) * tint;
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * smoothstep(0.28, 0.88, length(d * vec2(1.2, 1.0)));
	COLOR = vec4(c, 1.0);
}
