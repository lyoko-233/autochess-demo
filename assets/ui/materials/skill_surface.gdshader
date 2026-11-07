shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float age = 0.0;
uniform float opacity = 1.0;
uniform int family = 0;
varying vec3 point;
float grain(vec3 p) { return fract(sin(dot(p,vec3(12.9898,78.233,37.719)))*43758.5453); }
void vertex() { point = VERTEX; }
void fragment() {
 vec3 p=point;
 float streak=sin(p.y*19.0+p.x*7.0+p.z*5.0-age*4.0)*.5+.5;
 float detail=.78+.22*streak;
 vec3 color=COLOR.rgb;
 if (family==1) { detail=.62+.38*sin(p.y*22.0-age*7.0+sin(p.x*12.0)); color=mix(color,vec3(1.0,.87,.43),pow(streak,5.0)*.5); }
 else if (family==2) { float caustic=pow(abs(sin(p.x*15.0+age*2.0)*cos(p.z*15.0-age*1.4)),7.0); color=mix(color,vec3(.78,.96,1.0),caustic*.55); detail=.80+caustic*.20; }
 else if (family==3) { float facets=step(.7,fract(p.x*8.0+p.y*5.0+p.z*9.0)); color=mix(color,vec3(.86,.97,1.0),facets*.35); detail=.83+.17*streak; }
 else if (family==4) { detail=.77+.23*sin(p.y*9.0+age*1.5+p.z*12.0); }
 else if (family==5) { detail=.68+.32*sin(length(p.xz)*19.0-p.y*5.0-age*3.0); }
 else if (family==6) { detail=.80+.20*sin(p.y*28.0+age*13.0); color=mix(color,vec3(.83,.94,1.0),streak*.30); }
 else if (family==7) { detail=.42+.30*sin(p.x*9.0+p.z*7.0+age*.9)*sin(p.y*8.0+age*.7); }
 else { color=mix(color,vec3(1.0),pow(streak,10.0)*.22); }
 ALBEDO=color;
 EMISSION=color*.16;
 ALPHA=COLOR.a*opacity*clamp(detail,.15,1.0);
}
