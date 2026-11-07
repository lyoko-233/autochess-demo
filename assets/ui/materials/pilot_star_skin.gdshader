shader_type spatial;
render_mode blend_add,unshaded,cull_back,depth_draw_never;
uniform vec4 tint : source_color=vec4(1.0,0.4,0.08,1.0);
uniform int family=0;
uniform float age=0.0;
uniform float strength=0.0;
varying vec3 local_at;
void vertex(){ local_at=VERTEX; VERTEX+=NORMAL*0.003; }
void fragment(){
 float pattern=0.0;
 if(family==0){ pattern=pow(max(0.0,sin(local_at.y*24.0-age*3.0+sin(local_at.x*20.0))),10.0); }
 else if(family==1){ pattern=pow(max(0.0,sin((local_at.x+local_at.y)*28.0-age*1.4)),22.0); }
 else if(family==2){ pattern=pow(max(0.0,sin(local_at.y*17.0+sin(local_at.x*9.0-age)*2.0)),9.0); }
 else if(family==3){ pattern=pow(max(0.0,sin(local_at.z*35.0-age*2.0)),25.0); }
 else { pattern=pow(max(0.0,sin(local_at.x*32.0)*sin(local_at.y*32.0)),8.0); }
 ALBEDO=tint.rgb;
 EMISSION=tint.rgb*(0.10+strength*0.55)*pattern;
 ALPHA=(0.025+strength*0.15)*pattern;
}
