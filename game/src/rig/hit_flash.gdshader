shader_type canvas_item;
// The rig's own look, drawn over every part that has no material of its own (they take this one through
// use_parent_material):
//  - a hit flashes the whole rig (the colour mixed in over the part's picture, keeping its silhouette);
//  - a stage's light (src/level/stage_lighting.gd): a body is lit from above (the moon) and shaded below. The height
//    is measured from the rig's feet (feet_y, in world px), so all parts of one body get one smooth gradient.
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform bool look_on = false;
uniform vec4 shade : source_color = vec4(1.0);   // multiplier at the feet
uniform vec4 lit : source_color = vec4(1.0);     // multiplier at the top
uniform float feet_y = 0.0;
uniform float body_height = 120.0;

varying vec4 modc;
varying float wy;

void vertex() {
	modc = COLOR;
	wy = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 tint = vec3(1.0);
	if (look_on) {
		float f = clamp((feet_y - wy) / body_height, 0.0, 1.0);
		tint = mix(shade.rgb, lit.rgb, smoothstep(0.0, 1.0, f));
	}
	COLOR = vec4(mix(t.rgb * modc.rgb * tint, flash_color.rgb, flash), t.a * modc.a);
}
