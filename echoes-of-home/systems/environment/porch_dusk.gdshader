shader_type spatial;
render_mode unshaded;

uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float warm_glow = 0.0;
uniform vec3 pulse_origin = vec3(0.0);
uniform float pulse_radius = 0.0;
uniform bool pulse_active = false;
uniform float fade = 1.0;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// Dusk and porch-lantern shading affects only exterior meshes, never the interior.
	float moon = 0.24 + 0.36 * max(dot(normalize(world_normal), normalize(vec3(-0.4, 0.8, 0.2))), 0.0);
	float lantern = exp(-distance(world_position, vec3(-2.4, 2.3, 8.3)) * 0.22) * 0.4;
	vec3 dusk = base_color.rgb * (vec3(0.65, 0.78, 1.0) * moon + vec3(1.0, 0.76, 0.45) * lantern + warm_glow);
	float behind = pulse_radius - distance(world_position, pulse_origin);
	float wave = float(pulse_active) * step(0.0, behind) * (1.0 - smoothstep(0.0, 16.0, behind)) * fade;
	vec2 edge = min(UV, vec2(1.0) - UV);
	float outline = 1.0 - smoothstep(0.005, 0.025, min(edge.x, edge.y));
	dusk += base_color.rgb * wave * (0.08 + outline * 0.3);
	float fog = smoothstep(28.0, 70.0, distance(world_position, vec3(0.0, 1.6, 10.0)));
	ALBEDO = mix(dusk, vec3(0.018, 0.026, 0.042), fog * 0.85);
}
