// 棋盘与出售交互 V2 · 2026-11-06
shader_type canvas_item;
varying vec4 modulation;

void vertex() { modulation = COLOR; }

void fragment() {
	vec2 pixel = UV * vec2(1536.0, 1024.0);
	float t = (pixel.y - 226.0) / 516.0;
	float left = mix(415.0, 300.0, t);
	float width = mix(705.0, 932.0, t);
	float u = (pixel.x - left) / width;
	vec2 sample_uv = UV;
	float grout = 0.0;
	float bevel = 0.0;
	if (t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0) {
		float ratio = 932.0 / 705.0;
		// Undo perspective: equal world rows have different screen heights.
		float v = t * ratio / (1.0 + t * (ratio - 1.0));
		vec2 grid = clamp(vec2(u, v), vec2(0.0), vec2(0.999999)) * 8.0;
		vec2 cell = floor(grid);
		vec2 local = fract(grid);
		// Reuse the painted stone interiors, excluding the original seven-row seams.
		vec2 inset = mix(vec2(0.13), vec2(0.87), local);
		// The added eighth row reuses row seven with opposite checker parity.
		float source_col = cell.y > 6.5 ? mod(cell.x + 1.0, 8.0) : cell.x;
		float source_u = (source_col + inset.x) / 8.0;
		float source_v = (min(cell.y, 6.0) + inset.y) / 7.0;
		float source_t = source_v / (ratio - (ratio - 1.0) * source_v);
		sample_uv = vec2(mix(415.0, 300.0, source_t) + source_u * mix(705.0, 932.0, source_t), 226.0 + source_t * 516.0) / vec2(1536.0, 1024.0);
		float edge = min(min(local.x, 1.0-local.x), min(local.y, 1.0-local.y));
		grout = 1.0 - smoothstep(0.009, 0.020, edge);
		bevel = smoothstep(0.020, 0.035, edge) * (1.0 - smoothstep(0.035, 0.055, edge));
	}
	vec4 painted = texture(TEXTURE, sample_uv);
	painted.rgb = painted.rgb * (1.0 - grout * 0.40) + vec3(bevel * 0.018);
	COLOR = painted * modulation;
}
