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

## Hit/Eva clamps
const HIT_EVA_MIN: float = 5.0   # Minimum 5% hit chance
const HIT_EVA_MAX: float = 95.0  # Maximum 95% hit chance

## ═══════════════════════════════════════════════════════════════
## HIT/EVASION CHECKS (§4.3)
## ═══════════════════════════════════════════════════════════════

func check_physical_hit(attacker: Dictionary, defender: Dictionary, options: Dictionary = {}) -> Dictionary:
	"""
	Check if a physical attack hits

	Formula: Hit% = WeaponACC + 0.25·TPO + mods
	         Eva% = FootwearEVA + 0.25·VTL + mods
	         Final = clamp(Hit − Eva, 5, 95)

	Returns:
	- hit: bool (did it hit?)
	- hit_chance: float (final hit %)
	- roll: int (d100 roll)
	"""

	# Get attacker weapon stats
	var weapon = _get_weapon_stats(attacker.id)
	var base_acc = weapon.get("acc", 75)  # Default 75% base accuracy

	# Get attacker TPO
	var tpo = attacker.stats.get("TPO", 1)

	# Calculate hit%
	var hit_percent = base_acc + (0.25 * tpo)

	# Get defender footwear stats
	var footwear = _get_footwear_stats(defender.id)
	var base_eva = footwear.get("eva", 0)  # Default 0% base evasion

	# Get defender VTL (for physical evasion)
	var vtl = defender.stats.get("VTL", 1)

	# Calculate eva%
	var eva_percent = base_eva + (0.25 * vtl)

	# Final hit chance = Hit - Eva, clamped [5, 95]
	var final_hit = clamp(hit_percent - eva_percent, HIT_EVA_MIN, HIT_EVA_MAX)

	# Roll d100
	var roll = randi() % 100 + 1  # 1-100

	var did_hit = roll <= final_hit

	return {
		"hit": did_hit,
		"hit_chance": final_hit,
		"roll": roll,
		"breakdown": {
			"hit_percent": hit_percent,
			"eva_percent": eva_percent,
			"weapon_acc": base_acc,
			"tpo": tpo,
			"footwear_eva": base_eva,
			"vtl": vtl
		}
	}

func check_sigil_hit(attacker: Dictionary, defender: Dictionary, options: Dictionary = {}) -> Dictionary:
	"""
	Check if a sigil/skill hits

	Formula: Hit% = SkillACC + WeaponSkillBoost + 0.25·TPO + mods
	         Eva% = FootwearEVA + 0.25·FCS + mods
	         Final = clamp(Hit − Eva, 5, 95)

	Returns:
	- hit: bool
	- hit_chance: float
	- roll: int
	"""

	# Get skill base accuracy
	var skill_acc = options.get("skill_acc", 85)  # Default 85% for skills

	# Get weapon's skill boost
	var weapon = _get_weapon_stats(attacker.id)
	var weapon_skill_boost = weapon.get("skill_acc_bonus", 0)

	# Get attacker TPO
	var tpo = attacker.stats.get("TPO", 1)

	# Calculate hit%
	var hit_percent = skill_acc + weapon_skill_boost + (0.25 * tpo)

	# Get defender footwear stats
	var footwear = _get_footwear_stats(defender.id)
	var base_eva = footwear.get("eva", 0)

	# Get defender FCS (for sigil evasion)
	var fcs = defender.stats.get("FCS", 1)

	# Calculate eva%
	var eva_percent = base_eva + (0.25 * fcs)

	# Final hit chance
	var final_hit = clamp(hit_percent - eva_percent, HIT_EVA_MIN, HIT_EVA_MAX)

	# Roll d100
	var roll = randi() % 100 + 1

	var did_hit = roll <= final_hit

	return {
		"hit": did_hit,
		"hit_chance": final_hit,
		"roll": roll,
		"breakdown": {
			"hit_percent": hit_percent,
			"eva_percent": eva_percent,
			"skill_acc": skill_acc,
			"weapon_boost": weapon_skill_boost,
			"tpo": tpo,
			"footwear_eva": base_eva,
			"fcs": fcs
		}
	}

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
				"brw_scale": weapon.get("brw_scale", 0.5),
				"acc": weapon.get("acc", 75),
				"skill_acc_bonus": weapon.get("skill_acc_bonus", 0)
			}

	# Default weapon stats
	return {
		"watk": 10,
		"sig": 0,
		"brw_scale": 0.5,
		"acc": 75,
		"skill_acc_bonus": 0
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

func _get_footwear_stats(member_id: String) -> Dictionary:
	"""Get footwear stats for a combatant"""
	# For allies, check equipment system
	if equipment_system and equipment_system.has_method("get_equipped_item"):
		var footwear = equipment_system.call("get_equipped_item", member_id, "foot")
		if footwear:
			return {
				"eva": footwear.get("eva", 0),
				"speed": footwear.get("speed", 0)
			}

	# Default footwear stats
	return {
		"eva": 0,
		"speed": 0
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
