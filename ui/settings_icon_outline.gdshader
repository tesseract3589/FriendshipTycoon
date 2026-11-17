shader_type canvas_item;

// Keep the source sprite's shading and silhouette; strengthen its black contour
// in screen pixels so the small HUD icon stays readable.
uniform float outline_width : hint_range(0.0, 4.0, 0.05) = 1.25;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 step_uv = fwidth(UV) * outline_width;
	float outline_alpha = source.a;
	for (int i = 0; i < 16; i++) {
		float angle = float(i) * 6.2831853 / 16.0;
		vec2 offset = vec2(cos(angle), sin(angle)) * step_uv;
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + offset).a);
	}
	COLOR = vec4(source.rgb * source.a, outline_alpha) * item_tint;
}
