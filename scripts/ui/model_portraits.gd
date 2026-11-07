extends RefCounted
# Shared one-star in-engine model portraits V6 — updated 2026-11-07.
const ATLAS = preload("res://assets/ui/model_portraits_v6/atlas.webp")
static var regions: Dictionary = {}
static var cache: Dictionary = {}

static func portrait(piece_id: String) -> Texture2D:
	if cache.has(piece_id): return cache[piece_id]
	if regions.is_empty(): regions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/model_portraits_v6/regions.json"))
	var rect: Array = regions[piece_id]
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	texture.region = Rect2(rect[0],rect[1],rect[2],rect[3])
	texture.filter_clip = true
	cache[piece_id] = texture
	return texture
