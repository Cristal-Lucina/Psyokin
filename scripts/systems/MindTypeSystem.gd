extends Node
class_name MindTypeSystem

# Minimal compatibility logic used by SigilSystem.is_school_allowed_for_member()

# Optionally define special allowances here (e.g., cross-school rules).
# Example format: "Fire": ["Lava","Light"], etc.
var _allow_map: Dictionary = {
	# "Fire": ["Lava"],
}

func normalize(tag: String) -> String:
	return String(tag).strip_edges().capitalize()

func is_school_allowed(member_base: String, sigil_school: String) -> bool:
	var base: String = normalize(member_base)
	var school: String = normalize(sigil_school)
	if base == "" or school == "":
		return true
	if base == "Omega":
		return true
	if base == school:
		return true
	# Optional cross-allowances
	if _allow_map.has(base):
		var arr: Array = _allow_map[base]
		for s in arr:
			if normalize(String(s)) == school:
				return true
	return false
