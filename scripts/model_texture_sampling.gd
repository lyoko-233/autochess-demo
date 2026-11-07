extends RefCounted

static func prepare(source: Node3D, max_size: int = 0) -> void:
	var textures := {}
	var packing := {"textures":0,"source_bytes":0,"gpu_bytes":0,"max_size":max_size}
	for mesh: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if mat==null:continue
			for slot in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","emission_texture","ao_texture"]:
				var tex=mat.get(slot) as Texture2D
				if tex==null:continue
				var key := "%d:%s"%[tex.get_instance_id(),slot=="normal_texture"]
				if not textures.has(key):
					var image := tex.get_image()
					if image.is_compressed():assert(image.decompress()==OK)
					if not image.has_mipmaps():assert(image.generate_mipmaps(slot=="normal_texture")==OK)
					if max_size>0:
						packing.source_bytes+=image.get_data_size()
						var longest := maxi(image.get_width(),image.get_height())
						if longest>max_size:
							# Sample the already normalized normal-map mip chain.
							image.resize(maxi(1,image.get_width()*max_size/longest),maxi(1,image.get_height()*max_size/longest),Image.INTERPOLATE_TRILINEAR)
							if not image.has_mipmaps():assert(image.generate_mipmaps(slot=="normal_texture")==OK)
						packing.gpu_bytes+=image.get_data_size()
						packing.textures+=1
					textures[key]=ImageTexture.create_from_image(image)
				mat.set(slot,textures[key])
			mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if max_size>0:source.set_meta("gpu_texture_packing",packing)

