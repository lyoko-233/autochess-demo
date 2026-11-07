shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	float distance_from_center=length((UV-vec2(0.5))*vec2(1.0,1.20));
	ALBEDO=vec3(0.025,0.035,0.05);
	ALPHA=(1.0-smoothstep(0.10,0.50,distance_from_center))*0.44;
}
