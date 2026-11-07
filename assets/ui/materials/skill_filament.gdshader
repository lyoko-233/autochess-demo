shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0);
uniform float age = 0.0;
uniform float opacity = 1.0;
uniform float seed = 0.0;
uniform int element = 0;
void fragment() {
 float edge=pow(max(0.0,1.0-abs(UV.y*2.0-1.0)),1.7);
 float stream=sin(UV.x*24.0-age*5.0+seed)*.5+.5;
 float veins=pow(stream,5.0);
 vec3 c=mix(tint.rgb,vec3(.92,.98,1.0),.28+veins*.48);
 if(element==1) c=mix(tint.rgb,vec3(1.0,.86,.40),veins);
 if(element==4) c=mix(tint.rgb,vec3(.52,1.0,.72),veins*.55);
 if(element==5) c=mix(tint.rgb*.55,vec3(.79,.72,1.0),veins*.8);
 if(element==2) {
  float ripples=sin(UV.x*46.0-age*8.0+sin(UV.y*9.0))*.5+.5;
  c=mix(tint.rgb,vec3(.73,.95,1.0),pow(ripples,7.0)*.7);
 }
 if(element==3) {
  float facet=abs(sin(UV.x*31.0+UV.y*13.0));
  c=mix(tint.rgb,vec3(.87,.98,1.0),smoothstep(.86,.98,facet));
 }
 if(element==6) {
  float forks=pow(abs(sin(UV.x*67.0+sin(UV.x*19.0)*3.0-age*13.0)),10.0);
  c=mix(tint.rgb,vec3(.93,.97,1.0),forks);
 }
 if(element==7) c=tint.rgb*(.45+.35*sin(UV.x*7.0-age*.8));
 float endfade=smoothstep(0.0,.05,UV.x)*(1.0-smoothstep(.88,1.0,UV.x));
 ALBEDO=c; EMISSION=c*(.38+veins*.40);
 ALPHA=edge*endfade*COLOR.a*opacity*(.62+stream*.38);
}
