shader_type canvas_item;
// Quiet stone-board stage behind the actual model portrait. Updated 2026-11-07.
void fragment() {
	vec3 stone = texture(TEXTURE, UV * vec2(0.65, 0.42)).rgb;
	float grain = dot(stone, vec3(0.2126, 0.7152, 0.0722));
	vec2 tile = vec2((UV.x - 0.5) / mix(0.55, 1.0, UV.y) * 3.0 + 1.5, sqrt(UV.y + 0.05) * 3.0);
	vec2 edge = min(fract(tile), 1.0 - fract(tile));
	float seam = 1.0 - smoothstep(0.008, 0.025, min(edge.x, edge.y));
	float alternate = mod(floor(tile.x) + floor(tile.y), 2.0);
	vec3 slate = vec3(0.29, 0.34, 0.36) + (grain - 0.35) * 0.10;
	slate += alternate * 0.012;
	slate *= 1.0 - seam * 0.14;
	COLOR = vec4(slate, 1.0);
}
