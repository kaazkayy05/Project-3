shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform vec3 pulse_origin = vec3(0.0);
uniform float pulse_radius = 0.0;
uniform bool pulse_active = false;
uniform float reveal_trail_distance : hint_range(0.1, 10.0) = 5.0;
uniform vec4 echo_color : source_color = vec4(0.933, 0.949, 0.969, 1.0);
uniform float grid_scale : hint_range(2.0, 24.0) = 9.0;

varying vec3 world_position;


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float behind_wave = pulse_radius - distance(world_position, pulse_origin);
	float wave_reveal = (
		float(pulse_active)
		* step(0.0, behind_wave)
		* (1.0 - smoothstep(0.0, reveal_trail_distance, behind_wave))
	);

	// Primitive UV seams plus a view-dependent rim create a sparse lidar-like
	// wireframe without requiring a finished character asset.
	vec2 grid_uv = UV * grid_scale;
	vec2 grid_distance = abs(fract(grid_uv - 0.5) - 0.5);
	vec2 grid_width = max(fwidth(grid_uv), vec2(0.001));
	vec2 grid_lines = grid_distance / grid_width;
	float wire = 1.0 - min(min(grid_lines.x, grid_lines.y), 1.0);
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float line_strength = max(0.08, max(wire, rim));
	float echo_strength = 0.12 + (line_strength * 0.88);

	ALBEDO = echo_color.rgb * echo_strength;
	EMISSION = echo_color.rgb * echo_strength;
	ALPHA = wave_reveal * (0.2 + (line_strength * 0.8));
}
