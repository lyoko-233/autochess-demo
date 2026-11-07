extends RefCounted

# Keep editable source meshes and joint nodes; only their render submissions change.
static var cache: Dictionary = {}

static func apply(rig: Node3D, variant: String) -> Dictionary:
	var groups := {}
	var before := 0
	for mesh in rig.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null or mesh.mesh.get_surface_count() != 1: continue
		var material: Material = mesh.material_override if mesh.material_override != null else mesh.mesh.surface_get_material(0)
		if material == null: continue
		var material_key := material.resource_path if not material.resource_path.is_empty() else str(material.get_instance_id())
		var key := "%s:%s:%s"%[variant,rig.get_path_to(mesh.get_parent()),material_key]
		if mesh.skin!=null: key += ":skin:"+str(mesh.skin.get_instance_id())
		if not groups.has(key): groups[key] = {"parent":mesh.get_parent(),"material":material,"items":[]}
		groups[key].items.append(mesh)
		before += 1
	var after := 0
	for key in groups:
		var group: Dictionary = groups[key]
		if group.items.size() < 2:
			after += 1
			continue
		if not cache.has(key): cache[key] = _combine(group.items)
		var combined := MeshInstance3D.new()
		combined.name = "RenderBatch"
		combined.set_meta("render_proxy",true)
		combined.mesh = cache[key]
		combined.material_override = group.material
		if group.items[0].skin!=null:
			combined.skin=group.items[0].skin
			combined.skeleton=group.items[0].skeleton
		group.parent.add_child(combined,true)
		for item in group.items:
			item.hide()
			item.set_meta("render_batched",true)
		after += 1
	return {"before":before,"after":after}

static func _combine(items: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	var bones:=PackedInt32Array()
	var weights:=PackedFloat32Array()
	for item: MeshInstance3D in items:
		var arrays := item.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offset := vertices.size()
		if arrays[Mesh.ARRAY_BONES]!=null:
			bones.append_array(arrays[Mesh.ARRAY_BONES])
			weights.append_array(arrays[Mesh.ARRAY_WEIGHTS])
		var normal_basis := item.basis.inverse().transposed()
		for i in points.size():
			vertices.append(item.transform*points[i])
			normals.append((normal_basis*arrays[Mesh.ARRAY_NORMAL][i]).normalized() if arrays[Mesh.ARRAY_NORMAL] != null else Vector3.UP)
			colors.append(arrays[Mesh.ARRAY_COLOR][i] if arrays[Mesh.ARRAY_COLOR] != null else Color.WHITE)
			uvs.append(arrays[Mesh.ARRAY_TEX_UV][i] if arrays[Mesh.ARRAY_TEX_UV] != null else Vector2.ZERO)
			var tangent := Vector3.RIGHT
			var sign_value := 1.0
			if arrays[Mesh.ARRAY_TANGENT] != null:
				tangent = (item.basis*Vector3(arrays[Mesh.ARRAY_TANGENT][i*4],arrays[Mesh.ARRAY_TANGENT][i*4+1],arrays[Mesh.ARRAY_TANGENT][i*4+2])).normalized()
				sign_value = arrays[Mesh.ARRAY_TANGENT][i*4+3]
			tangents.append_array(PackedFloat32Array([tangent.x,tangent.y,tangent.z,sign_value]))
		if arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() > 0:
			for index in arrays[Mesh.ARRAY_INDEX]: indices.append(offset+index)
		else:
			for i in points.size(): indices.append(offset+i)
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_COLOR] = colors
	result[Mesh.ARRAY_TEX_UV] = uvs
	result[Mesh.ARRAY_TANGENT] = tangents
	result[Mesh.ARRAY_INDEX] = indices
	if not bones.is_empty():
		result[Mesh.ARRAY_BONES]=bones
		result[Mesh.ARRAY_WEIGHTS]=weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,result)
	return mesh
