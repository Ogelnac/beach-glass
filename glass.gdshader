shader_type spatial;
render_mode blend_mix, unshaded, cull_back;

uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
uniform sampler2D matcap_tex;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float reflect_strength : hint_range(0.0, 1.0) = 0.9;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float refract_strength : hint_range(0.0, 0.02) = 0.006;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	vec3 N = normalize(NORMAL);
	vec3 V = normalize(CAMERA_POSITION_WORLD - NODE_POSITION_WORLD);
	float f = pow(1.0 - max(dot(N, V), 0.0), fresnel_power);

	vec3 N_view = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);
	vec2 mc_uv = N_view.xy * 0.5 + 0.5;
	vec3 matcap_col = texture(matcap_tex, mc_uv).rgb;

	vec2 refr_uv = SCREEN_UV + N.xy * refract_strength;
	vec3 refr_col = texture(SCREEN_TEXTURE, refr_uv).rgb;

	vec3 base_col = refr_col * tint;
	vec3 refl_col = matcap_col;
	vec3 col = mix(base_col, refl_col, f * reflect_strength);

	ALBEDO = col;
	ALPHA = opacity;
}
