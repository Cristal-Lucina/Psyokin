extends Node
class_name MindTypeSystem

## MindTypeSystem - Mind Type Weaknesses and Resistances
## Handles type matchup calculations for combat

# Optionally define special allowances here (e.g., cross-school rules).
# Example format: "Fire": ["Lava","Light"], etc.
var _allow_map: Dictionary = {
	# "Fire": ["Lava"],
}

## Type effectiveness multipliers
const WEAKNESS_MULT: float = 1.25     # x1.25 damage when hitting weakness
const RESISTANCE_MULT: float = 0.75   # x0.75 damage when hitting resistance
const NEUTRAL_MULT: float = 1.0       # x1.0 damage for neutral matchup

## Type weakness chart
## Format: "AttackType": ["WeakAgainst1", "WeakAgainst2"]
var _weakness_chart: Dictionary = {
	"fire": ["water"],      # Fire is weak to Water
	"water": ["earth"],     # Water is weak to Earth
	"earth": ["air"],       # Earth is weak to Air
	"air": ["fire"],        # Air is weak to Fire
	"void": ["data"],       # Void is weak to Data
	"data": ["void"]        # Data is weak to Void
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

## Calculate type effectiveness multiplier
## Returns 1.25 for weakness, 0.75 for resistance, 1.0 for neutral
func get_type_effectiveness(attacker_type: String, defender_type: String) -> float:
	var atk_type = String(attacker_type).strip_edges().to_lower()
	var def_type = String(defender_type).strip_edges().to_lower()

	# No type or same type = neutral
	if atk_type == "" or def_type == "" or atk_type == "none" or def_type == "none":
		return NEUTRAL_MULT

	# Check if attacker type is weak against defender type
	# (i.e., defender resists the attack)
	if _weakness_chart.has(atk_type):
		var weaknesses: Array = _weakness_chart[atk_type]
		for weak_against in weaknesses:
			if String(weak_against).to_lower() == def_type:
				# Attacker is weak to defender = defender resists
				return RESISTANCE_MULT

	# Check if defender type is weak against attacker type
	# (i.e., it's super effective)
	if _weakness_chart.has(def_type):
		var weaknesses: Array = _weakness_chart[def_type]
		for weak_against in weaknesses:
			if String(weak_against).to_lower() == atk_type:
				# Defender is weak to attacker = super effective
				return WEAKNESS_MULT

	# Neither weak nor resistant = neutral
	return NEUTRAL_MULT

## Check if an attack is super effective (weakness hit)
func is_weakness_hit(attacker_type: String, defender_type: String) -> bool:
	return get_type_effectiveness(attacker_type, defender_type) == WEAKNESS_MULT

## Check if an attack is resisted
func is_resisted_hit(attacker_type: String, defender_type: String) -> bool:
	return get_type_effectiveness(attacker_type, defender_type) == RESISTANCE_MULT
