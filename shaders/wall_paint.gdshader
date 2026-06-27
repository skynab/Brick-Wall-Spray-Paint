shader_type spatial;
render_mode unshaded, cull_back;

// Brick photo (read as sRGB) composited with the accumulated paint buffer.
uniform sampler2D brick_tex : source_color, filter_linear_mipmap;
uniform sampler2D paint_tex : source_color, filter_linear;

void fragment() {
	vec4 brick = texture(brick_tex, UV);
	vec4 paint = texture(paint_tex, UV);
	// Alpha-over: paint sits on top of the brick by its accumulated alpha.
	ALBEDO = mix(brick.rgb, paint.rgb, paint.a);
}
