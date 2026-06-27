shader_type spatial;
render_mode unshaded, cull_back;

// Brick photo (read as sRGB) composited with the accumulated paint buffer.
uniform sampler2D brick_tex : source_color, filter_linear_mipmap;
uniform sampler2D paint_tex : source_color, filter_linear;

// Vignette: darkens the brick toward the edges, *under* the paint so painted
// marks stay vivid. strength 0 = off.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_extent : hint_range(0.0, 1.5) = 0.7;
uniform float vignette_softness : hint_range(0.01, 1.0) = 0.4;

void fragment() {
	vec4 brick = texture(brick_tex, UV);
	vec4 paint = texture(paint_tex, UV);

	// Radial darkening: 0 at centre, ~1 at the corners.
	float dist = distance(UV, vec2(0.5)) * 1.41421356;
	float vig = smoothstep(vignette_extent, vignette_extent + vignette_softness, dist);
	vec3 brick_rgb = brick.rgb * (1.0 - vig * vignette_strength);

	// Alpha-over: paint sits on top of the (vignetted) brick by its alpha.
	ALBEDO = mix(brick_rgb, paint.rgb, paint.a);
}
