extends RefCounted
# Legacy timing and weapon tracks remain authoritative; body deforms on bones.
static func build(rig: Node3D, original: AnimationLibrary, id: String) -> AnimationLibrary:
	var skeleton: Skeleton3D=rig.get_node(rig.get_meta("skeleton_path"))
	var library:=AnimationLibrary.new()
	var mapped: Dictionary={"LeftArmPivot":"UpperArmL","RightArmPivot":"UpperArmR","LeftLegPivot":"ThighL","RightLegPivot":"ThighR"}
	for clip in original.get_animation_list():
		var animation: Animation=original.get_animation(clip).duplicate(true)
		var motion: Dictionary={}
		for t in animation.get_track_count():
			var path:=str(animation.track_get_path(t))
			for node in mapped:
				if path.ends_with("/"+node+":rotation"):
					var keys:=[]
					for k in animation.track_get_key_count(t): keys.append([animation.track_get_key_time(t,k),animation.track_get_key_value(t,k)])
					motion[mapped[node]]=keys
		for b in skeleton.get_bone_count():
			var name:=skeleton.get_bone_name(b)
			var rest:=skeleton.get_bone_global_rest(b).basis.orthonormalized()
			var keys: Array=motion.get(name,[[0.0,Vector3.ZERO],[animation.length,Vector3.ZERO]])
			if name in ["ForearmL","ForearmR","Chest","Cape","ShinL","ShinR","Head"]:
				var peak:=Vector3.ZERO
				if name.begins_with("Forearm") and clip in ["attack","cast"]:
					peak.x=(.20 if id=="Sniper" else .35) if clip=="attack" else .45
				if name=="Chest" and clip in ["attack","cast","hit"]: peak.z=.10 if clip=="attack" else -.06
				if name=="Cape": peak.x=.07 if clip=="idle" else .16
				if name.begins_with("Shin") and clip=="walk": peak.x=.30
				if name=="Head" and clip=="hit": peak.x=-.12
				keys=[[0.0,Vector3.ZERO],[animation.length*.42,peak],[animation.length,Vector3.ZERO]]
			var track:=animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track,NodePath("Rig/"+str(rig.get_path_to(skeleton))+":"+name))
			for key in keys:
				var rotation: Basis=skeleton.get_bone_rest(b).basis*rest.inverse()*Basis.from_euler(key[1])*rest
				animation.rotation_track_insert_key(track,key[0],rotation.get_rotation_quaternion())
		library.add_animation(clip,animation)
	return library
