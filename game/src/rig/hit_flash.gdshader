shader_type canvas_item;
// A hit flashes the whole rig: every part without a material of its own takes this one (use_parent_material), and
// the colour is mixed in over the part's own picture, keeping its silhouette.
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

varying vec4 modc;

void vertex() {
	modc = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(mix(t.rgb * modc.rgb, flash_color.rgb, flash), t.a * modc.a);
}
