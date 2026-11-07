shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0);
uniform float age=0.0;
uniform float opacity=1.0;
uniform float radius=.4;
uniform float height=.6;
uniform float seed=0.0;
uniform int element=0;
uniform bool flight=false;
varying float life;
void vertex() {
 float id=INSTANCE_CUSTOM.r;
 float phase=fract(age*.75+id*.618033+seed*.071);
 float a=id*53.0+age*.45;
 vec3 center=vec3(sin(a)*radius*sqrt(id),phase*height,cos(a)*radius*sqrt(id));
 if(flight) center=vec3(sin(a)*.10,cos(a)*.10,phase*.85);
 mat3 camera=mat3(INV_VIEW_MATRIX[0].xyz,INV_VIEW_MATRIX[1].xyz,INV_VIEW_MATRIX[2].xyz);
 VERTEX=center+inverse(mat3(MODEL_MATRIX))*camera*VERTEX;
 life=sin(phase*3.14159265);
}
void fragment() {
 vec2 p=UV*2.0-1.0;
 float d=length(p);
 float mask=pow(max(0.0,1.0-d),2.4);
 if(element==3) mask=pow(max(0.0,1.0-abs(p.x)-abs(p.y)),1.2);
 if(element==7) mask=pow(max(0.0,1.0-d),.7)*.22;
 if(element==4) mask=(1.0-smoothstep(.70,1.0,length(vec2(p.x*1.8,p.y))))*(1.0-smoothstep(.04,.16,abs(p.x)*.3+abs(p.y*.7-p.x*.2))*.22);
 if(element==0) mask=1.0-smoothstep(.50,.8,max(abs(p.x),abs(p.y)));
 if(element==6) mask=pow(max(0.0,1.0-abs(p.x)*3.0-abs(p.y)*.55),1.2);
 if(element==5) mask=pow(max(0.0,1.0-d),1.4)*(1.0-smoothstep(.18,.27,d)*.25);
 vec3 c=mix(tint.rgb,vec3(.91,.98,1.0),mask*.7);
 ALBEDO=c; EMISSION=c*.7; ALPHA=mask*life*opacity;
}
