shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform bool lungs_empty = false;
uniform vec4 edge_color : source_color = vec4(
	0.360784314, 0.078431373, 0.078431373, 1.0
);
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.94;
uniform float clear_center : hint_range(0.1, 0.6) = 0.32;
uniform float edge_softness : hint_range(0.1, 0.6) = 0.5;

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float mask = smoothstep(clear_center, clear_center + edge_softness, radius);
	float alpha = lungs_empty ? mask * edge_opacity : 0.0;
	COLOR = vec4(edge_color.rgb, alpha);
}
