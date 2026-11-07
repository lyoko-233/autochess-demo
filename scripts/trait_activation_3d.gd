extends "res://scripts/hero_skill_effect_3d.gd"

# Each tag has its own silhouette, hue and movement. Short placement feedback only.
const DESIGNS := {
	"兽人":["taunt_armor","d98b4b"], "野兽":["call_of_the_wild","d2aa70"],
	"精灵":["treants","89e8b0"], "地精":["magic_pulse","d7ee65"],
	"巨魔":["fervor","ee9164"], "人类":["disarm","e8dcab"],
	"亡灵":["death_pulse","aedcac"], "恶魔":["doom","fb725e"],
	"娜迦":["waveform","6bdddf"], "元素":["refraction","98c2f5"],
	"龙":["dragon_form","eaa879"], "矮人":["assassinate","eacb95"],
	"食人魔":["multicast","e99ace"], "神":["purification","fff0ae"],
	"虫族":["spiked_carapace","b4d478"], "萨特":["smoke_screen","b48ccc"],
	"战士":["gods_strength","efc07a"], "德鲁伊":["spirit_bear","9bce81"],
	"法师":["line_orb","aeabfb"], "猎人":["powershot","bbdd83"],
	"刺客":["critical","d5bcfa"], "萨满":["hex","cfa0ea"],
	"恶魔猎手":["mana_burn","9ba6ff"], "骑士":["shield","f5df9d"],
	"工匠":["aoe_burst","ffd587"], "术士":["leech_seed","d1b0ed"],
	"牧师":["shallow_grave","f3b5ea"], "巫师":["spell_steal","b1eece"]}

func configure_tag(tag: String) -> void:
	assert(DESIGNS.has(tag),"Missing activation design: "+tag)
	var recipe: Array = DESIGNS[tag]
	configure(str(recipe[0]),Color(str(recipe[1])),{"radius":.45,"line_length":.55,"distance":.3,"line_half_width":.2},"release")
	kind = "trait_"+tag
	sustain = false
	lifetime = .85
	if tag in ["神","精灵","德鲁伊","牧师"]: motion = "rise"

func sample(age: float) -> void:
	super.sample(age)
	scale *= .72
	position.y += .10
	material.albedo_color.a *= .60
	if surface != null: surface.set_shader_parameter("opacity",material.albedo_color.a)
