shader_type spatial;
render_mode cull_disabled;
uniform vec4 stone_color : source_color = vec4(0.43,0.49,0.49,1.0);
uniform sampler2D painted_stone : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); vec2 u=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),u.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x),u.y);
}
void vertex() {
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
 vec2 p=world_position.xz;
 vec2 local=fract(p);
 float edge=min(min(local.x,1.0-local.x),min(local.y,1.0-local.y));
 // World mapping survives static mesh batching and continues onto the bench.
 vec2 texcoord=p*.13;
 if(abs(world_normal.y)<.5) {
  texcoord=(abs(world_normal.x)>.5 ? world_position.zy : world_position.xy)*.30;
 }
 vec3 painted=texture(painted_stone,texcoord).rgb;
 // Compatibility renderer supplies this sampler in display space.
 vec3 detail=pow(painted,vec3(2.2))*2.0*(stone_color.rgb/vec3(.43,.49,.49));
 vec3 stone=mix(pow(stone_color.rgb,vec3(2.2))*1.2,detail,.45);
 float seam=1.0-smoothstep(.004,.023,edge);
 stone*=1.0-seam*.18;
 float erosion=smoothstep(.52,.74,noise(p*13.0))* (1.0-smoothstep(.025,.14,edge));
 float moss=erosion*.24;
 stone=mix(stone,vec3(.075,.11,.045),moss);
 float wear=smoothstep(.02,.055,edge)*(1.0-smoothstep(.055,.085,edge));
 stone+=wear*.013;
 ALBEDO=stone;
 ROUGHNESS=.94;
}
