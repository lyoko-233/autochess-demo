extends RefCounted

static func measure(source: Node3D, posed: bool = false) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree(): continue
		if mesh.skin == null:
			var box := (source.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
			result=box if first else result.merge(box)
			first=false
			continue
		var skeleton: Skeleton3D=mesh.get_node(mesh.skeleton)
		var binds: Array[Transform3D]=[]
		for i in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(i)
			if bone<0:bone=skeleton.find_bone(mesh.skin.get_bind_name(i))
			assert(bone>=0)
			binds.append(source.global_transform.affine_inverse()*skeleton.global_transform*(skeleton.get_bone_global_pose(bone) if posed else skeleton.get_bone_global_rest(bone))*mesh.skin.get_bind_pose(i))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			var stride: int=bones.size()/vertices.size()
			for v in vertices.size():
				var point := Vector3.ZERO
				for j in stride:
					var index := v*stride+j
					if weights[index]>0:point+=(binds[bones[index]]*vertices[v])*weights[index]
				result=AABB(point,Vector3.ZERO) if first else result.expand(point)
				first=false
	return result

