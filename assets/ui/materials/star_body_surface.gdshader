shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(.3,.6,1.,1.);
uniform float age = 0.;
uniform float strength = 0.;
uniform float shell_width = .006;
uniform int family = 0;
uniform mat4 pose0;
uniform mat4 pose1;
uniform mat4 pose2;
uniform mat4 pose3;
uniform mat4 pose4;
uniform mat4 pose5;
uniform mat4 pose6;
uniform mat4 pose7;
uniform mat4 pose8;
uniform mat4 pose9;
uniform mat4 pose10;
uniform mat4 pose11;
uniform mat4 pose12;
uniform mat4 pose13;

varying vec3 point;
void vertex() {
 int joint=int(COLOR.r*13.+.5);
 mat4 pose=pose0;
 if (joint==1) pose=pose1;
 else if (joint==2) pose=pose2;
 else if (joint==3) pose=pose3;
 else if (joint==4) pose=pose4;
 else if (joint==5) pose=pose5;
 else if (joint==6) pose=pose6;
 else if (joint==7) pose=pose7;
 else if (joint==8) pose=pose8;
 else if (joint==9) pose=pose9;
 else if (joint==10) pose=pose10;
 else if (joint==11) pose=pose11;
 else if (joint==12) pose=pose12;
 else if (joint==13) pose=pose13;

 VERTEX=(pose*vec4(VERTEX+NORMAL*shell_width,1.)).xyz;
 NORMAL=normalize(mat3(pose)*NORMAL);
 point=VERTEX;
}
void fragment() {
 float rim=pow(1.-max(0.,dot(normalize(NORMAL),normalize(VIEW))),2.5);
 float speed=family==1 ? 1.4 : family==5 ? .6 : .85;
 float flow=sin(point.y*12.-age*speed*4.+sin(point.x*13.+point.z*7.));
 float fleck=pow(max(0.,flow),9.);
 float detail=family==3 ? step(.55,flow) : fleck;
 vec3 color=mix(tint.rgb,vec3(.9,.97,1.),detail*.35);
 ALBEDO=color;
 EMISSION=color*(.28+strength*.55);
 ALPHA=clamp((rim*.22+detail*.10)*(1.+strength*1.1),0.,.58);
}
