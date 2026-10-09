shader_type spatial;
render_mode unshaded;

uniform vec3 pulse_origin = vec3(0.0);
uniform float pulse_radius = 0.0;
uniform bool pulse_active = false;
uniform float fade = 1.0;
uniform vec4 echo_color : source_color = vec4(0.933, 0.949, 0.969, 1.0);

// Visibility tuning controls
uniform float ambient_floor : hint_range(0.0, 0.2) = 0.04;      // Faint persistent baseline
uniform float wave_trail_distance : hint_range(4.0, 30.0) = 16.0; // How far back the wave illuminates (was 8.0)
uniform float surface_fill_boost : hint_range(0.0, 1.0) = 0.22;   // Wall/floor visibility (was 0.045)
uniform float edge_glow_boost : hint_range(1.0, 3.0) = 1.6;       // Edge pop strength

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist_from_origin = distance(world_position, pulse_origin);
	float behind = pulse_radius - dist_from_origin;
	
	// Broader, softer falloff so the illuminated area lingers much longer
	float wave_reveal = float(pulse_active) * step(0.0, behind) * (1.0 - smoothstep(0.0, wave_trail_distance, behind));
	
	// Edge detection for wireframe highlights
	vec2 edge = min(UV, vec2(1.0) - UV);
	float outline = 1.0 - smoothstep(0.005, 0.035, min(edge.x, edge.y));
	
	// Combines boosted face brightness with enhanced edge brightness
	float brightness_profile = surface_fill_boost + (edge_glow_boost * outline);
	
	// Calculates total visibility, maintaining a subtle ambient floor so geometry never goes 100% blind
	float total_light = max(ambient_floor, wave_reveal * fade * brightness_profile);
	
	ALBEDO = echo_color.rgb * total_light;
}