extends Node
class_name PartySystem

## PartySystem — active roster, benches, per-member meta/equip/sigils/affinity/effects
## Note: keep it coarse for now; refine schemas as features land.

var active: Array[String] = ["hero"]
var bench: Array[String] = []

# Minimal per-member snapshot (id -> dict)
var roster: Dictionary = {
	"hero": {
		"hp": {"cur": 30, "max": 30},
		"mp": {"cur": 10, "max": 10},
		"stats": {"BRW":1, "MND":1, "TPO":1, "VTL":1, "FCS":1},
		"equipment": {"weapon":"", "armor":"", "head":"","feet":"","bracelet":""},
		"sigils": [],                       # ["sigil_id", ...]
		"active_skills": {},                # {sigil_id: skill_id}
		"affinity": {},                     # {target_id: {"tier":0, "xp":0}}
		"effects": []                       # [{"id":"poison","t":3}, ...]
	}
}

func get_save_blob() -> Dictionary:
	return {
		"active": active.duplicate(),
		"bench": bench.duplicate(),
		"roster": roster.duplicate(true),
	}

func apply_save_blob(blob: Dictionary) -> void:
	var a_v: Variant = blob.get("active", [])
	if typeof(a_v) == TYPE_ARRAY: active = (a_v as Array).duplicate()
	var b_v: Variant = blob.get("bench", [])
	if typeof(b_v) == TYPE_ARRAY: bench = (b_v as Array).duplicate()
	var r_v: Variant = blob.get("roster", {})
	if typeof(r_v) == TYPE_DICTIONARY: roster = (r_v as Dictionary).duplicate(true)

func clear_all() -> void:
	active = ["hero"]; bench = []
	roster = {"hero": roster.get("hero", {})}
