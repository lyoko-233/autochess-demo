shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform vec4 tint : source_color=vec4(1.0);
uniform float age=0.0;
uniform float opacity=1.0;
uniform float tier=1.0;
void fragment(){
 float edge=abs(sin(UV.x*18.8496))*abs(sin(UV.y*18.8496));
 float engraving=smoothstep(.83,.94,edge);
 vec3 base=COLOR.rgb;
 ALBEDO=base*(.82+engraving*.18);
 METALLIC=.38;
 ROUGHNESS=.42;
 EMISSION=mix(base,tint.rgb,.25)*(engraving*.24+.06)*(1.0+(tier-1.0)*.12);
 ALPHA=opacity;
}
