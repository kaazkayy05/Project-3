shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 shadow_color : source_color = vec4(0.012, 0.014, 0.022, 1.0);
uniform vec4 rim_color : source_color = vec4(0.18, 0.24, 0.29, 1.0);
uniform float threat : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.94;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.14;

varying vec3 world_position;


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.6);
	float grain = fract(sin(dot(floor(world_position * 18.0).xz, vec2(12.9898, 78.233))) * 43758.5453);
	float slow_flicker = 0.9 + sin(TIME * 5.3 + world_position.y * 7.0) * flicker_amount * 0.1;
	float broken_band = step(0.90, fract(world_position.y * 3.1 - TIME * 0.7));
	float silhouette = mix(0.76, 1.0, grain * 0.18) * slow_flicker;
	vec3 threat_tint = mix(rim_color.rgb, vec3(0.52, 0.055, 0.035), threat);

	ALBEDO = shadow_color.rgb * silhouette;
	EMISSION = threat_tint * (rim * (0.34 + threat * 0.22) + broken_band * 0.025);
	ALPHA = opacity;
}
