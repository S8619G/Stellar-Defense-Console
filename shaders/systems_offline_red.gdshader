shader_type canvas_item;
// 1.0.8: red SYSTEMS OFFLINE background: red with a soft dark edge and faint scan lines.
uniform float alpha = 1.0;
uniform vec2 px_size = vec2(1100.0, 843.0);

void fragment() {
	vec2 n = UV * 2.0 - 1.0;
	float vignette = 1.0 - 0.28 * (n.x * n.x + n.y * n.y) / 2.0;
	vec3 c = vec3(214.0, 16.0, 28.0) / 255.0 * vignette;
	if (mod(floor(UV.y * px_size.y), 3.0) < 1.0) {
		c *= 0.9;
	}
	COLOR = vec4(c, alpha);
}
