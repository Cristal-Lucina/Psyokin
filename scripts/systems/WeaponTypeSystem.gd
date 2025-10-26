extends Node
class_name WeaponTypeSystem

## Weapon Type Triangle System
##
## Handles weapon type effectiveness for initiative/turn order manipulation
## Triangle: Pierce > Slash > Blunt > Pierce
##
## When hit by a weapon weakness:
## - Initiative penalty applied (turn pushed back)
## - Weakness hit tracked
## - 2 weakness hits in one round = lose next turn

## Weapon type triangle
## Pierce beats Slash (piercing finds gaps in slashing defenses)
## Slash beats Blunt (cutting through blunt weapon users)
## Blunt beats Pierce (crushing through piercing defenses)
var _weakness_chart: Dictionary = {
	"pierce": ["slash"],   # Pierce is strong against Slash
	"slash": ["blunt"],    # Slash is strong against Blunt
	"blunt": ["pierce"]    # Blunt is strong against Pierce
}

## Initiative penalty when hit by weapon weakness
const WEAKNESS_INITIATIVE_PENALTY: int = 2  # TPO points lost when hit by weakness

func get_weapon_type_from_equipment(combatant: Dictionary) -> String:
	"""Extract weapon type from combatant's equipment"""
	if combatant == null or combatant.is_empty() or not combatant.has("equipment"):
		return "none"

	var equipment = combatant.get("equipment")
	if equipment == null or typeof(equipment) != TYPE_DICTIONARY:
		return "none"

	var equipment_dict: Dictionary = equipment as Dictionary
	var weapon = equipment_dict.get("weapon", "")
	if weapon == null or weapon == "":
		return "unarmed"  # No weapon equipped

	var weapon_id: String = String(weapon)

	# Get weapon data from items CSV via autoload
	if has_node("/root/aCSVLoader"):
		var csv_loader = get_node("/root/aCSVLoader")
		var items_data = csv_loader.load_csv("res://data/items/items.csv", "item_id")

		if items_data and items_data.has(weapon_id):
			var weapon_data: Dictionary = items_data[weapon_id]
			var weapon_type: String = String(weapon_data.get("watk_type_tag", "none")).strip_edges().to_lower()
			return weapon_type

	return "none"

func is_weapon_weakness(attacker_weapon_type: String, defender_weapon_type: String) -> bool:
	"""
	Check if attacker's weapon type has advantage over defender's weapon type

	Args:
		attacker_weapon_type: Type of weapon attacking (pierce, slash, blunt)
		defender_weapon_type: Type of weapon defending (pierce, slash, blunt)

	Returns:
		true if attacker type beats defender type
	"""
	var atk_type = String(attacker_weapon_type).strip_edges().to_lower()
	var def_type = String(defender_weapon_type).strip_edges().to_lower()

	# No advantage if either has no type or special types
	if atk_type in ["none", "unarmed", "wand", ""] or def_type in ["none", "unarmed", "wand", ""]:
		return false

	# Check if attacker type beats defender type
	if _weakness_chart.has(atk_type):
		var beats_types: Array = _weakness_chart[atk_type]
		for beats in beats_types:
			if String(beats).to_lower() == def_type:
				return true

	return false

func get_initiative_penalty(attacker: Dictionary, defender: Dictionary) -> int:
	"""
	Calculate initiative penalty for defender if hit by weapon weakness

	Returns:
		Initiative penalty (TPO points) to apply to defender
	"""
	var atk_weapon_type = get_weapon_type_from_equipment(attacker)
	var def_weapon_type = get_weapon_type_from_equipment(defender)

	if is_weapon_weakness(atk_weapon_type, def_weapon_type):
		return WEAKNESS_INITIATIVE_PENALTY

	return 0

func get_weakness_description(attacker_type: String, defender_type: String) -> String:
	"""Get a description of the weapon triangle matchup"""
	if is_weapon_weakness(attacker_type, defender_type):
		return "%s beats %s!" % [attacker_type.capitalize(), defender_type.capitalize()]
	return ""
