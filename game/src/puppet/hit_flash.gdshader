shader_type canvas_item;
// The puppet's own look, drawn over every part that has no material of its own (they take this one through
// use_parent_material):
//  - a hit flashes the whole puppet (the colour mixed in over the part's picture, keeping its silhouette);
//  - a stage's light (src/level/stage_lighting.gd): a body is lit from above (the moon) and shaded below (the height is
//    measured from the puppet's feet, in world px, so all parts of one body get one smooth gradient), and its upper-left
//    edges catch a thin rim of backlight.
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform bool look_on = false;
uniform vec4 shade : source_color = vec4(1.0);   // multiplier at the feet
uniform vec4 lit : source_color = vec4(1.0);     // multiplier at the top
uniform float feet_y = 0.0;
uniform float body_height = 120.0;
uniform vec3 rim_color : source_color = vec3(0.72, 0.86, 1.0);
uniform float rim_strength = 0.0;
uniform float rim_width = 1.6;
uniform vec2 light_dir = vec2(-0.6, -0.8);

varying vec4 modc;
varying float wy;
varying vec2 uvdir;

void vertex() {
	modc = COLOR;
	wy = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
	mat2 m = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	uvdir = inverse(m) * normalize(light_dir) * rim_width * TEXTURE_PIXEL_SIZE;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 c = t.rgb * modc.rgb;
	if (look_on) {
		float f = clamp((feet_y - wy) / body_height, 0.0, 1.0);
		c *= mix(shade.rgb, lit.rgb, smoothstep(0.0, 1.0, f));
		if (rim_strength > 0.0) {
			float toward = 0.5 * (texture(TEXTURE, UV + uvdir).a + texture(TEXTURE, UV + uvdir * 2.0).a);
			c += rim_color * clamp(t.a - toward, 0.0, 1.0) * rim_strength;
		}
	}
	COLOR = vec4(mix(c, flash_color.rgb, flash), t.a * modc.a);
}
