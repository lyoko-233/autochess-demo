extends RefCounted


static func beveled_box(dimensions: Vector3, bevel: float) -> ArrayMesh:
	var h := dimensions * 0.5
	var b := minf(bevel,minf(h.x,h.z)*0.45)
	var points := [Vector2(-h.x+b,-h.z),Vector2(h.x-b,-h.z),Vector2(h.x,-h.z+b),Vector2(h.x,h.z-b),
		Vector2(h.x-b,h.z),Vector2(-h.x+b,h.z),Vector2(-h.x,h.z-b),Vector2(-h.x,-h.z+b)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		for i in range(8):
			var a: Vector2=points[i]
			var c: Vector2=points[(i+1)%8]
			_triangle(surface,Vector3(0,side*h.y,0),Vector3(a.x,side*h.y,a.y),Vector3(c.x,side*h.y,c.y),Vector3(0,side,0))
	for i in range(8):
		var a: Vector2=points[i]
		var c: Vector2=points[(i+1)%8]
		var n:=Vector3(c.y-a.y,0,a.x-c.x).normalized()
		_triangle(surface,Vector3(a.x,-h.y,a.y),Vector3(c.x,-h.y,c.y),Vector3(c.x,h.y,c.y),n)
		_triangle(surface,Vector3(a.x,-h.y,a.y),Vector3(c.x,h.y,c.y),Vector3(a.x,h.y,a.y),n)
	return surface.commit()


static func _triangle(surface: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,normal: Vector3) -> void:
	for p in [a,c,b] if (b-a).cross(c-a).dot(normal)>0 else [a,b,c]:
		surface.set_normal(normal)
		surface.add_vertex(p)
