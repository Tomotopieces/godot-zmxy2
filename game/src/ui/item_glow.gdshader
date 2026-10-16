shader_type canvas_item;
// The quality glow behind an item in a cell (src/ui/item_icon.gd): a soft round light, strongest in the middle.

uniform vec4 glow_color : source_color = vec4(1.0, 0.4, 0.0, 0.75);

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;     // 0 in the middle, 1 at the cell's edge
	float a = smoothstep(1.0, 0.15, d);
	COLOR = vec4(glow_color.rgb, glow_color.a * a * a);
}
