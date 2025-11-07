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
## Slash beats Blunt/Impact (cutting through blunt weapon users)
## Blunt/Impact beats Pierce (crushing through piercing defenses)
var _weakness_chart: Dictionary = {
	"pierce": ["slash"],   # Pierce is strong against Slash
	"slash": ["blunt", "impact"],    # Slash is strong against Blunt/Impact
	"blunt": ["pierce"],    # Blunt is strong against Pierce
	"impact": ["pierce"]    # Impact (alias for Blunt) is strong against Pierce
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
		attacker_weapon_type: Type of weapon attacking (pierce, slash, blunt/impact)
		defender_weapon_type: Type of weapon defending (pierce, slash, blunt/impact)

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

## ═══════════════════════════════════════════════════════════════
## WAND VULNERABILITY SYSTEM
## ═══════════════════════════════════════════════════════════════
## Wands are not part of the weapon triangle but have a general
## vulnerability to physical attacks:
## - Take 10% more damage from all physical attacks
## - 10% higher chance to be critically hit by physical attacks

const WAND_DAMAGE_VULNERABILITY: float = 0.10  # 10% more damage
const WAND_CRIT_VULNERABILITY: float = 10.0    # +10% crit chance

func is_defender_using_wand(defender: Dictionary) -> bool:
	"""
	Check if defender is using a wand

	Args:
		defender: Combatant dictionary with equipment

	Returns:
		true if defender has a wand equipped
	"""
	var weapon_type = get_weapon_type_from_equipment(defender)
	return weapon_type == "wand"

func get_wand_damage_modifier(defender: Dictionary) -> float:
	"""
	Get damage modifier for attacking a wand user

	Args:
		defender: Combatant dictionary

	Returns:
		Damage multiplier (1.1 if wand user, 1.0 otherwise)
	"""
	if is_defender_using_wand(defender):
		return 1.0 + WAND_DAMAGE_VULNERABILITY
	return 1.0

func get_wand_crit_bonus(defender: Dictionary) -> float:
	"""
	Get critical hit chance bonus for attacking a wand user

	Args:
		defender: Combatant dictionary

	Returns:
		Crit chance bonus (+10.0 if wand user, 0.0 otherwise)
	"""
	if is_defender_using_wand(defender):
		return WAND_CRIT_VULNERABILITY
	return 0.0
