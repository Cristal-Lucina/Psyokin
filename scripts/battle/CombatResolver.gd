extends Node
class_name CombatResolver

## CombatResolver - Damage Calculation Engine
## Implements combat formulas from Chapter 4 design doc

## References to autoloads
@onready var equipment_system = get_node("/root/aEquipmentSystem")
@onready var mind_type_system = get_node("/root/aMindTypeSystem")

## Damage floor percentages (§4.4a)
const DMG_FLOOR_ENEMY_TO_PLAYER: float = 0.15  # 15% minimum
const DMG_FLOOR_PLAYER_TO_ENEMY: float = 0.20  # 20% minimum

## Defend multiplier
const DEFEND_MULT: float = 0.7  # -30% damage when defending

## Crit multiplier
const CRIT_MULT: float = 2.0  # x2 damage on crit

## Stumble bonus
const STUMBLE_MULT: float = 1.25  # +25% damage on weakness

## ═══════════════════════════════════════════════════════════════
## PHYSICAL DAMAGE (Attack)
## ═══════════════════════════════════════════════════════════════

func calculate_physical_damage(attacker: Dictionary, defender: Dictionary, options: Dictionary = {}) -> Dictionary:
	"""
	Calculate physical attack damage

	Options:
	- potency: int = 100 (base potency %)
	- multi_hit: int = 1 (number of hits)
	- is_crit: bool = false
	- type_bonus: float = 0.0 (TYPE modifier, e.g., 0.25 for weakness)

	Returns:
	- damage: int (final damage)
	- is_crit: bool
	- is_stumble: bool
	- breakdown: Dictionary (for debugging)
	"""

	# Get parameters
	var potency: int = options.get("potency", 100)
	var multi_hit: int = options.get("multi_hit", 1)
	var is_crit: bool = options.get("is_crit", false)
	var type_bonus: float = options.get("type_bonus", 0.0)

	# Get attacker stats
	var brw: int = attacker.stats.get("BRW", 1)

	# Get equipment stats
	var attacker_weapon = _get_weapon_stats(attacker.id)
	var base_watk: int = attacker_weapon.get("watk", 0)
	var brw_scale: float = attacker_weapon.get("brw_scale", 0.5)

	# Get defender defense
	var defender_armor = _get_armor_stats(defender.id)
	var base_pdef: int = defender_armor.get("pdef", 0)

	# Step 1: Pre-mitigation damage
	# Pre = (BaseWATK + BRW×Scale_BRW) × POT/100
	var pre_mit: float = (base_watk + brw * brw_scale) * (potency / 100.0)

	# Step 2: Apply TYPE, Crit, and buffs
	# ATK_Power = Pre × (1+TYPE) × (Crit?2:1) × (1+buffs−debuffs)
	var type_mult: float = 1.0 + type_bonus
	var crit_mult: float = CRIT_MULT if is_crit else 1.0
	var buff_mult: float = 1.0  # TODO: Add buff/debuff system

	var atk_power: float = pre_mit * type_mult * crit_mult * buff_mult

	# Step 3: Apply defense mitigation
	# For multi-hit: PDEF_perHit = PDEF / √H
	var pdef_per_hit: float = base_pdef
	if multi_hit > 1:
		pdef_per_hit = base_pdef / sqrt(float(multi_hit))

	# Raw = max(ATK_Power − PDEF_perHit, 0)
	var raw_damage: float = max(atk_power - pdef_per_hit, 0.0)

	# Step 4: Apply defensive modifiers (Defend, Shield, etc)
	var defend_mult: float = DEFEND_MULT if defender.get("is_defending", false) else 1.0
	var shield_mult: float = 1.0  # TODO: Add shield orb system

	var dmg_after_mods: float = raw_damage * defend_mult * shield_mult

	# Step 5: Apply mitigation floor
	# DMG = max(DMG, ceil(ATK_Power × DMG_FLOOR))
	var dmg_floor: float = DMG_FLOOR_PLAYER_TO_ENEMY if attacker.get("is_ally", false) else DMG_FLOOR_ENEMY_TO_PLAYER
	var min_damage: int = int(ceil(atk_power * dmg_floor))

	var final_damage: int = int(floor(dmg_after_mods))
	final_damage = max(final_damage, min_damage)

	# Check for stumble (weakness hit)
	var is_stumble: bool = type_bonus > 0.0

	return {
		"damage": final_damage,
		"is_crit": is_crit,
		"is_stumble": is_stumble,
		"breakdown": {
			"pre_mit": pre_mit,
			"atk_power": atk_power,
			"raw": raw_damage,
			"after_mods": dmg_after_mods,
			"min_damage": min_damage,
			"brw": brw,
			"watk": base_watk,
			"pdef": base_pdef
		}
	}

## ═══════════════════════════════════════════════════════════════
## SIGIL DAMAGE (Skills)
## ═══════════════════════════════════════════════════════════════

func calculate_sigil_damage(attacker: Dictionary, defender: Dictionary, options: Dictionary = {}) -> Dictionary:
	"""
	Calculate sigil/skill damage

	Options:
	- potency: int = 100 (base potency %)
	- multi_hit: int = 1 (number of hits)
	- is_crit: bool = false
	- type_bonus: float = 0.0 (TYPE modifier)
	- base_sig: int = 0 (skill's base SIG power)
	- mnd_scale: float = 1.0 (skill's MND scaling)

	Returns:
	- damage: int (final damage)
	- is_crit: bool
	- is_stumble: bool
	- breakdown: Dictionary
	"""

	# Get parameters
	var potency: int = options.get("potency", 100)
	var multi_hit: int = options.get("multi_hit", 1)
	var is_crit: bool = options.get("is_crit", false)
	var type_bonus: float = options.get("type_bonus", 0.0)
	var base_sig: int = options.get("base_sig", 30)
	var mnd_scale: float = options.get("mnd_scale", 1.0)

	# Get attacker stats
	var mnd: int = attacker.stats.get("MND", 1)

	# Get equipment stats
	var attacker_weapon = _get_weapon_stats(attacker.id)
	var sig_bonus: int = attacker_weapon.get("sig", 0)

	# Get defender defense
	var defender_armor = _get_armor_stats(defender.id)
	var base_mdef: int = defender_armor.get("mdef", 0)

	# Step 1: Pre-mitigation damage
	# PreM = (SIG + MND×S_MND) × POT/100
	var total_sig: float = base_sig + sig_bonus
	var pre_mit: float = (total_sig + mnd * mnd_scale) * (potency / 100.0)

	# Step 2: Apply TYPE, Crit, and buffs
	var type_mult: float = 1.0 + type_bonus
	var crit_mult: float = CRIT_MULT if is_crit else 1.0
	var buff_mult: float = 1.0  # TODO: Add buff/debuff system

	var skill_power: float = pre_mit * type_mult * crit_mult * buff_mult

	# Step 3: Apply defense mitigation
	var mdef_per_hit: float = base_mdef
	if multi_hit > 1:
		mdef_per_hit = base_mdef / sqrt(float(multi_hit))

	var raw_damage: float = max(skill_power - mdef_per_hit, 0.0)

	# Step 4: Apply defensive modifiers
	var defend_mult: float = DEFEND_MULT if defender.get("is_defending", false) else 1.0
	var shield_mult: float = 1.0

	var dmg_after_mods: float = raw_damage * defend_mult * shield_mult

	# Step 5: Apply mitigation floor
	var dmg_floor: float = DMG_FLOOR_PLAYER_TO_ENEMY if attacker.get("is_ally", false) else DMG_FLOOR_ENEMY_TO_PLAYER
	var min_damage: int = int(ceil(skill_power * dmg_floor))

	var final_damage: int = int(floor(dmg_after_mods))
	final_damage = max(final_damage, min_damage)

	var is_stumble: bool = type_bonus > 0.0

	return {
		"damage": final_damage,
		"is_crit": is_crit,
		"is_stumble": is_stumble,
		"breakdown": {
			"pre_mit": pre_mit,
			"skill_power": skill_power,
			"raw": raw_damage,
			"after_mods": dmg_after_mods,
			"min_damage": min_damage,
			"mnd": mnd,
			"sig": total_sig,
			"mdef": base_mdef
		}
	}

## ═══════════════════════════════════════════════════════════════
## EQUIPMENT HELPERS
## ═══════════════════════════════════════════════════════════════

func _get_weapon_stats(member_id: String) -> Dictionary:
	"""Get weapon stats for a combatant"""
	# For allies, check equipment system
	if equipment_system and equipment_system.has_method("get_equipped_item"):
		var weapon = equipment_system.call("get_equipped_item", member_id, "weapon")
		if weapon:
			return {
				"watk": weapon.get("watk", 10),
				"sig": weapon.get("sig", 0),
				"brw_scale": weapon.get("brw_scale", 0.5)
			}

	# Default weapon stats
	return {
		"watk": 10,
		"sig": 0,
		"brw_scale": 0.5
	}

func _get_armor_stats(member_id: String) -> Dictionary:
	"""Get armor stats for a combatant"""
	# For allies, check equipment system
	if equipment_system and equipment_system.has_method("get_equipped_item"):
		var armor = equipment_system.call("get_equipped_item", member_id, "armor")
		if armor:
			return {
				"pdef": armor.get("pdef", 0),
				"mdef": armor.get("mdef", 0)
			}

	# Default armor stats (or enemy base defense)
	return {
		"pdef": 5,
		"mdef": 5
	}

## ═══════════════════════════════════════════════════════════════
## TYPE SYSTEM
## ═══════════════════════════════════════════════════════════════

func get_type_modifier(attacker_element: String, defender_element: String) -> float:
	"""
	Get TYPE modifier based on elemental matchup
	Returns: -0.5 (resist), 0.0 (neutral), 0.25 (weakness), etc.
	"""
	if not mind_type_system:
		return 0.0

	# TODO: Implement type system lookup
	# For now, return neutral
	return 0.0
