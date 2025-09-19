shader_type sky;

group_uniforms sky;
uniform vec3 sky_color: source_color = vec3(0.03, 0.05, 0.11);
uniform vec3 horizon_tint_color: source_color = vec3(0.1, 0.05, 0.02);
uniform float horizon_tint_strength: hint_range(0.0, 1.0) = 0.8;
uniform float horizon_offset: hint_range(-0.5, 0.5) = 0.0;
uniform float horizon_softness: hint_range(0.0, 0.1) = 0.0;
uniform float sky_time: hint_range(0.0, 1.0) = 0.0;

group_uniforms stars;
uniform vec3 star_base_color: source_color = vec3(0.8, 1.0, 0.3);
uniform float star_hue_offset: hint_range(0., 1.) = 0.6;
uniform float star_intensity: hint_range(0., 0.2) = 0.08;

group_uniforms layers;
uniform float layer_scale: hint_range(0., 60.) = 20.;
uniform float layer_scale_step: hint_range(0., 40.) = 10.;
uniform int layers_count: hint_range(0, 12) = 3;

group_uniforms day;
uniform vec3 gradient_top_color: source_color = vec3(0.45, 0.65, 0.95);
uniform vec3 gradient_bottom_color: source_color = vec3(0.95, 0.75, 0.45);
uniform float day_gradient_power: hint_range(0.1, 5.0) = 1.0;
uniform vec3 day_horizon_tint_color: source_color = vec3(0.9, 0.8, 0.7);
uniform float day_horizon_tint_strength: hint_range(0.0, 1.0) = 0.8;
uniform float day_horizon_offset: hint_range(-0.5, 0.5) = 0.0;
uniform float day_horizon_softness: hint_range(0.0, 0.1) = 0.0;

vec3 hue(vec3 input, float offset, int range_index) {
	vec4 k = vec4(0., -1./3., 2./3., -1.);
	vec4 p = mix(vec4(input.bg, k.wz), vec4(input.gb, k.xy), step(input.b, input.g));
	vec4 q = mix(vec4(p.xyw, input.r), vec4(input.r, p.yzx), step(p.x, input.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.e-10;
	vec3 hsv = vec3(abs(q.z + (q.w - q.y) / (6. * d + e)), d / (q.x + e), q.x);
	offset = (range_index == 0) ? offset / 360. : offset;
	float h = hsv.x + offset;
	if (h < 0.) hsv.x = h + 1.;
	else if (h > 1.) hsv.x = h - 1.;
	else hsv.x = h;
	vec4 k2 = vec4(1., 2./3., 1./3., 3.);
	vec3 p2 = abs(fract(hsv.xxx + k2.xyz) * 6. - k2.www);
	return hsv.z * mix(k2.xxx, clamp(p2 - k2.xxx, 0., 1.), hsv.y);
}

vec3 hash(vec3 x) {
	x = vec3(dot(x, vec3(127.1,311.7,74.7)),
			 dot(x, vec3(269.5,183.3,246.1)),
			 dot(x, vec3(113.5,271.9,124.6)));
	return fract(sin(x) * 43758.5453123);
}

vec2 voronoi(in vec3 x){
	vec3 p = floor(x);
	vec3 f = fract(x);
	float res = 100.;
	float id = 0.;
	for (float k = -1.; k <= 1.; k += 1.) {
		for (float j = -1.; j <= 1.; j += 1.) {
			for (float i = -1.; i <= 1.; i += 1.) {
				vec3 b = vec3(i, j, k);
				vec3 r = b - f + hash(p + b);
				float d = dot(r, r);
				if (d < res) {
					res = d;
					id = dot(p + b, vec3(0., 57., 113.));
				}
			}
		}
	}
	return vec2(sqrt(res), id);
}

void sky() {
	vec3 dir = vec3(EYEDIR.x, abs(EYEDIR.y), EYEDIR.z);
	vec3 col = sky_color;
	for (int i = 0; i < layers_count; i++) {
		vec3 pos = dir * (layer_scale + float(i) * layer_scale_step);
		vec2 layer = voronoi(pos);
		vec3 rand = hash(vec3(layer.y));
		float star = 1.0 - step(star_intensity, layer.x);
		vec3 star_color = star * hue((col + star_base_color), rand.y * star_hue_offset, 1);
		col += star_color;
	}
	float y_n = EYEDIR.y - horizon_offset;
	float mask_n = (horizon_softness <= 0.0) ? step(y_n, 0.0) : smoothstep(0.0, -horizon_softness, y_n);
	vec3 night_col = mix(col, horizon_tint_color, mask_n * horizon_tint_strength);
	float ay = clamp(abs(EYEDIR.y), 0.0, 1.0);
	float t = pow(ay, day_gradient_power);
	vec3 day_base = mix(gradient_bottom_color, gradient_top_color, t);
	float y_d = EYEDIR.y - day_horizon_offset;
	float mask_d = (day_horizon_softness <= 0.0) ? step(y_d, 0.0) : smoothstep(0.0, -day_horizon_softness, y_d);
	vec3 day_col = mix(day_base, day_horizon_tint_color, mask_d * day_horizon_tint_strength);
	COLOR = mix(night_col, day_col, sky_time);
}
