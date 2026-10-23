shader_type canvas_item;
// 1.0.8: screen scramble over the inner console (picture tearing, colour split, static,
// scan lines, flicker). Reads what is already drawn under it; draws only inside its own
// rectangle. intensity 0..1; seed changes the pattern (about 30 times a second).
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float intensity = 1.0;
uniform float seed = 0.0;
uniform float flicker = 1.0;
uniform vec2 px_size = vec2(1100.0, 843.0);

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030) + seed * vec2(0.0973, 0.1099));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	float I = intensity;
	// Where this rectangle sits on the screen (no uniforms needed).
	vec2 rs = vec2(dFdx(SCREEN_UV.x) / dFdx(UV.x), dFdy(SCREEN_UV.y) / dFdy(UV.y));
	vec2 ro = SCREEN_UV - UV * rs;
	vec2 uv = UV;
	vec2 px = UV * px_size;
	// Whole picture jumps up or down now and then.
	if (hash(vec2(1.7, 7.3)) < 0.45 * I) {
		float dir = hash(vec2(2.1, 3.9)) < 0.5 ? -1.0 : 1.0;
		uv.y = fract(uv.y + dir * (8.0 + 34.0 * I) / px_size.y);
	}
	// Torn horizontal bands, three layers of different band heights.
	float dx = 0.0;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float bh = mix(4.0, 10.0 + 46.0 * I, hash(vec2(fk, 9.1)));
		float band = floor(uv.y * px_size.y / bh + hash(vec2(fk, 2.2)));
		if (hash(vec2(band, fk + 0.5)) < 0.05 + 0.22 * I) {
			dx += (hash(vec2(band, fk + 1.5)) * 2.0 - 1.0) * 110.0 * I;
		}
	}
	uv.x = fract(uv.x + dx / px_size.x);
	// Block corruption: a few rectangles copied from somewhere else.
	vec2 cell = floor(uv * px_size / vec2(110.0, 32.0));
	if (hash(cell + vec2(3.3, 5.1)) < 0.02 * I) {
		uv = fract(uv + vec2(hash(cell + 1.1), hash(cell + 2.2)) * 0.7);
	}
	// Colour split.
	float s = (3.0 + 12.0 * I) / px_size.x;
	vec3 col;
	col.r = texture(screen_tex, ro + vec2(fract(uv.x - s), uv.y) * rs).r;
	col.g = texture(screen_tex, ro + uv * rs).g;
	col.b = texture(screen_tex, ro + vec2(fract(uv.x + s), uv.y) * rs).b;
	// Static grain.
	float grain = hash(floor(px) + vec2(17.0, 31.0));
	col = col * (1.0 - 0.24 * I) + vec3(grain) * 0.24 * I;
	// Bands of pure static.
	float sband = floor(px.y / 14.0);
	if (hash(vec2(sband, 41.0)) < 0.025 * I) {
		col = vec3(hash(floor(px) + vec2(5.0, 9.0))) * (0.6 + 0.4 * hash(vec2(sband, 43.0)));
	}
	// Tinted bands (magenta or cyan).
	float tband = floor(px.y / 22.0);
	if (hash(vec2(tband, 61.0)) < 0.03 * I) {
		vec3 tint = hash(vec2(tband, 63.0)) < 0.5 ? vec3(1.0, 0.235, 0.55) : vec3(0.275, 0.86, 1.0);
		col = col * 0.6 + tint * 0.4;
	}
	// Scan lines and flicker.
	if (mod(floor(px.y), 3.0) < 1.0) {
		col *= 1.0 - 0.4 * I;
	}
	col *= flicker;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
