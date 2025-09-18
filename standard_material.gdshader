shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo: source_color, filter_nearest;
uniform float scale_offset = 0.2;

void vertex() {
	float rounded_x = round(VERTEX.x / scale_offset);
	float rounded_y = round(VERTEX.y / scale_offset);
	float rounded_z = round(VERTEX.z / scale_offset);

	vec3 rounded = vec3(rounded_x * scale_offset, rounded_y * scale_offset, rounded_z * scale_offset);

	VERTEX = rounded;
}

void fragment() {
	ALBEDO = texture(albedo, UV).rgb;
}