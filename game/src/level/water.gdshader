shader_type canvas_item;
// The water surface of a stage (3-1, the 忘川河): one rectangle, no pictures. The rectangle's top edge is the water line;
// it is displaced by a sum of sines of the world x, so the surface keeps its shape while the camera scrolls (and it never
// depends on the camera's y, which is fixed). Everything above the displaced line is transparent: the world shows through.
// Below it the colour runs from the surface colour at the water line to the deep colour at the bottom, with a light foam
// band just under the line and faint horizontal streaks drifting with the flow.
uniform vec2 size = vec2(940.0, 200.0);                  // the rectangle's px size
uniform vec4 surface_color : source_color = vec4(0.32, 0.6, 0.68, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.1, 0.16, 1.0);
uniform vec4 foam_color : source_color = vec4(0.8, 0.94, 0.96, 1.0);
uniform float alpha = 0.9;               // overall opacity
uniform float wave_height = 8.0;         // px the water line moves up and down
uniform float wave_length = 180.0;       // px of the longest wave
uniform float wave_speed = 0.8;          // waves per second (rad / s of the phase)
uniform float flow_speed = 30.0;         // px / s the streaks drift right

varying vec2 world_pos;

float h11(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// one dimension of value noise: cell index + the row it is read on
float noise1(float x, float row) {
	float i = floor(x);
	float f = fract(x);
	return mix(h11(vec2(i, row)), h11(vec2(i + 1.0, row)), f * f * (3.0 - 2.0 * f));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 px = UV * size;                  // px from the rectangle's top-left corner
	float wx = world_pos.x;               // the world x of this pixel

	// the water line, from the top edge of the rectangle
	float w = sin(wx / wave_length * TAU + TIME * wave_speed) * 0.5
		+ sin(wx / (wave_length * 0.43) * TAU - TIME * wave_speed * 1.7) * 0.3
		+ sin(wx / (wave_length * 0.27) * TAU + TIME * wave_speed * 2.4) * 0.2;
	float line = wave_height * w;
	float d = px.y - line;                // px below the water line
	if (d < 0.0) {
		discard;
	}

	// surface -> deep
	float depth = clamp(d / max(size.y, 1.0), 0.0, 1.0);
	vec3 col = mix(surface_color.rgb, deep_color.rgb, pow(depth, 0.55));

	// a lighter foam band just under the water line
	float foam = 1.0 - smoothstep(2.0, 26.0, d);
	foam *= 0.75 + 0.25 * sin(wx / 46.0 + TIME * 2.0);
	col = mix(col, foam_color.rgb, foam * 0.75);

	// faint horizontal streaks drifting with the flow
	float scroll = TIME * flow_speed;
	float light = noise1(px.x / 120.0 + scroll / 120.0, floor(px.y / 9.0));
	col += (light - 0.5) * 0.22 * smoothstep(0.0, 30.0, d) * (1.0 - depth);

	COLOR = vec4(col, alpha);
}
