extends RefCounted

const JOINTS := ["", "LeftArmPivot", "RightArmPivot", "LeftLegPivot", "RightLegPivot", "WeaponPivot", "HeadPivot", "HeadPivot/JawPivot", "LeftWingPivot", "RightWingPivot", "GoblinRider", "Rider", "Rider/LeftArmPivot", "Rider/RightArmPivot"]

static func build(rig: Node3D) -> ArrayMesh:
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	# Copy the actual visible surface into one render pass. Vertex color encodes
	# the animation joint, so the shell follows limbs and weapons on replay.
	for mesh in rig.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree(): continue
		var joint_index:=0
		for j in range(JOINTS.size()-1,0,-1):
			if rig.has_node(JOINTS[j]) and rig.get_node(JOINTS[j]).is_ancestor_of(mesh): joint_index=j; break
		var joint: Node3D=rig if joint_index==0 else rig.get_node(JOINTS[joint_index])
		var local: Transform3D=joint.global_transform.affine_inverse()*mesh.global_transform
		var normal_basis:=local.basis.inverse().transposed()
		for surface in mesh.mesh.get_surface_count():
			if mesh.mesh is ArrayMesh and mesh.mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays: Array=mesh.mesh.surface_get_arrays(surface)
			var offset:=vertices.size()
			for i in arrays[Mesh.ARRAY_VERTEX].size():
				vertices.append(local*arrays[Mesh.ARRAY_VERTEX][i])
				var normal: Vector3=arrays[Mesh.ARRAY_NORMAL][i] if arrays[Mesh.ARRAY_NORMAL]!=null else Vector3.UP
				normals.append((normal_basis*normal).normalized())
				colors.append(Color(float(joint_index)/(JOINTS.size()-1),0,0,1))
			if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty():
				for index in arrays[Mesh.ARRAY_INDEX]: indices.append(offset+index)
			else:
				for index in arrays[Mesh.ARRAY_VERTEX].size(): indices.append(offset+index)
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
