shader_type spatial;
render_mode unshaded;
uniform vec3 pulse_origin = vec3(0.0);
uniform float pulse_radius = 0.0;
uniform bool pulse_active = false;
uniform float fade = 1.0;
uniform vec4 echo_color : source_color = vec4(0.933, 0.949, 0.969, 1.0);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float behind = pulse_radius - distance(world_position, pulse_origin);
	float reveal = float(pulse_active) * step(0.0, behind) * (1.0 - smoothstep(0.0, 8.0, behind));
	vec2 edge = min(UV, vec2(1.0) - UV);
	float outline = 1.0 - smoothstep(0.005, 0.025, min(edge.x, edge.y));
	ALBEDO = echo_color.rgb * reveal * fade * (0.045 + 0.955 * outline);
}
