shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo: source_color, filter_nearest;
uniform vec2 ratio_adjustment = vec2(1.0, 1.0);
uniform vec3 colour: source_color = vec3(1.0, 1.0, 1.0);
uniform bool use_colour = false;
uniform float mix_amount = 0.5;

uniform float scale_multiplier = 0.2;

void vertex() {
	float rounded_x = round(VERTEX.x * scale_multiplier);
	float rounded_y = round(VERTEX.y * scale_multiplier);
	float rounded_z = round(VERTEX.z * scale_multiplier);

	VERTEX = vec3(rounded_x / scale_multiplier, rounded_y / scale_multiplier, rounded_z / scale_multiplier);
}

void fragment() {
	vec2 uv_adjusted = UV * ratio_adjustment;

	vec3 blend = mix(colour, texture(albedo, uv_adjusted).rgb, mix_amount);
	if (use_colour)
		ALBEDO = blend;
	else
		ALBEDO = texture(albedo, uv_adjusted).rgb;
}