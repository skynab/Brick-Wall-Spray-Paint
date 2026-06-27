shader_type canvas_item;

// Projective (keystone) warp of the already-rendered frame. The full-screen
// scene is the "source" (screen UV 0..1); inv_homography maps each output screen
// pixel back to the source it should sample. Outside the source square -> black.
uniform mat3 inv_homography;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment() {
	vec3 p = inv_homography * vec3(SCREEN_UV, 1.0);
	vec2 src = p.xy / p.z;
	if (src.x < 0.0 || src.x > 1.0 || src.y < 0.0 || src.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = vec4(texture(screen_tex, src).rgb, 1.0);
	}
}
