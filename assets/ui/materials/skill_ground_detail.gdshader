shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color=vec4(1.0);
uniform float age=0.0;
uniform float opacity=1.0;
uniform float seed=0.0;
uniform int element=0;
void fragment() {
 vec2 p=UV*2.0-1.0;
 float d=length(p);
 float a=atan(p.y,p.x);
 float edge=1.0-smoothstep(.72,1.0,d);
 float n=sin(p.x*15.0+sin(p.y*9.0+age))*cos(p.y*13.0-age*.8);
 float bands=pow(abs(sin(d*27.0-age*5.0+sin(a*5.0+seed))),5.0);
 vec3 c=tint.rgb;
 float alpha=(.03+bands*.12)*edge;
 if(element==2) {
  float foam=pow(abs(sin(p.x*17.0+age)*sin(p.y*19.0-age*1.1)),6.0);
  c=mix(tint.rgb*.55,vec3(.75,.96,1.0),foam);
  alpha=(.05+foam*.32+bands*.12)*edge;
 } else if(element==5) {
  c=mix(tint.rgb*.18,tint.rgb,clamp(n*.5+.5,0.0,1.0));
  alpha=(.12+max(0.0,n)*.18+bands*.10)*edge;
 } else if(element==6) {
  float forks=pow(abs(sin(a*12.0+sin(d*18.0-age*3.0))),18.0);
  c=mix(tint.rgb*.6,vec3(.84,.96,1.0),forks);
  alpha=(.03+forks*.17+bands*.12)*edge;
 } else if(element==4) {
  c=mix(tint.rgb*.45,vec3(.74,1.0,.42),bands);
  alpha=(.04+max(0.0,n)*.12+bands*.13)*edge;
 } else if(element==7) {
  c=tint.rgb*.3; alpha=(.14+n*.06)*edge;
 } else if(element==1) {
  c=mix(tint.rgb*.4,vec3(1.0,.80,.26),bands);
  alpha=(.03+bands*.19)*edge;
 }
 ALBEDO=c; EMISSION=c*.2; ALPHA=alpha*opacity;
}
