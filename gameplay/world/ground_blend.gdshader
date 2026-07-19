shader_type canvas_item;
render_mode unshaded;

uniform sampler2D dirt_base : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt_sandy : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt_tracks : source_color, repeat_enable, filter_linear_mipmap;
uniform vec2 tile_scale = vec2(3.2, 2.15);
uniform float contrast = 1.03;
uniform float saturation = 1.04;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		value += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

vec3 adjust_color(vec3 color) {
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luminance), color, saturation);
	return (color - 0.5) * contrast + 0.5;
}

void fragment() {
	vec2 base_uv = UV * tile_scale;
	vec2 sandy_uv = base_uv * 0.91 + vec2(0.27, 0.13);
	vec2 tracks_uv = vec2(-base_uv.y, base_uv.x) * vec2(0.88, 0.92) + vec2(0.41, 0.22);

	vec4 base_color = texture(dirt_base, base_uv);
	vec4 sandy_color = texture(dirt_sandy, sandy_uv);
	vec4 tracks_color = texture(dirt_tracks, tracks_uv);

	float large_noise = fbm(UV * vec2(5.0, 3.4));
	float detail_noise = fbm(UV * vec2(12.0, 8.0) + vec2(4.7, 8.2));
	float sandy_weight = smoothstep(0.42, 0.70, large_noise);
	float tracks_weight = smoothstep(0.60, 0.82, detail_noise) * (1.0 - sandy_weight * 0.55);

	vec4 blended = mix(base_color, sandy_color, sandy_weight * 0.48);
	blended = mix(blended, tracks_color, tracks_weight * 0.28);
	blended.rgb = adjust_color(blended.rgb);
	COLOR = vec4(blended.rgb, 1.0);
}
