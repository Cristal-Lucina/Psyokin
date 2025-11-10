extends Node
class_name CombatResolver

## CombatResolver - Damage Calculation Engine
## Implements combat formulas from Chapter 4 design doc

## References to autoloads
@onready var equipment_system = get_node_or_null("/root/aEquipmentSystem")
@onready var mind_type_system = get_node_or_null("/root/aMindTypeSystem")
@onready var weapon_type_system = get_node_or_null("/root/aWeaponTypeSystem")

## Damage floor percentages (§4.4a)
const DMG_FLOOR_ENEMY_TO_PLAYER: float = 0.15  # 15% minimum
const DMG_FLOOR_PLAYER_TO_ENEMY: float = 0.20  # 20% minimum

## Enemy damage reduction for balancing
const ENEMY_DAMAGE_MULT: float = 0.7  # Enemies deal 70% damage (30% reduction)

## Defend multiplier
const DEFEND_MULT: float = 0.7  # -30% damage when defending

## Crit multiplier
const CRIT_MULT: float = 2.0  # x2 damage on crit

## Stumble bonus
const STUMBLE_MULT: float = 1.25  # +25% damage on weakness

## Hit/Eva clamps
const HIT_EVA_MIN: float = 5.0   # Minimum 5% hit chance
const HIT_EVA_MAX: float = 95.0  # Maximum 95% hit chance

## Crit chance constants
const BASE_CRIT_CHANCE: float = 5.0   # Base 5% crit chance
const BRW_CRIT_MODIFIER: float = 0.5  # +0.5% per BRW point
const BRW_CRIT_DAMAGE_BONUS: float = 0.1  # +0.1× per BRW point (base 1.5×)
const CRIT_MIN: float = 5.0           # Minimum 5% crit chance
const CRIT_MAX: float = 50.0          # Maximum 50% crit chance

## ═══════════════════════════════════════════════════════════════
## BUFF/DEBUFF HELPERS
## ═══════════════════════════════════════════════════════════════

func _get_buff_modifier(combatant: Dictionary, buff_type: String) -> float:
	"""Get the total modifier for a specific buff type from combatant's buffs"""
	if not combatant.has("buffs"):
		return 0.0

	var total_mod = 0.0
	for buff in combatant.buffs:
		if buff.type == buff_type:
			total_mod += buff.value

	return total_mod

## ═══════════════════════════════════════════════════════════════
## MIND TYPE EFFECTIVENESS
## ═══════════════════════════════════════════════════════════════

func get_mind_type_bonus(attacker: Dictionary, defender: Dictionary, attack_type: String = "") -> float:
	"""
	Calculate mind type effectiveness bonus

	Args:
	- attacker: Attacker combatant dictionary
	- defender: Defender combatant dictionary
	- attack_type: Optional override for attack type (for skills with specific types)

	Returns:
	- 0.25 for weakness (x1.25 damage multiplier becomes 1.0 + 0.25)
	- -0.25 for resistance (x0.75 multiplier becomes 1.0 - 0.25)
	- 0.0 for neutral (x1.0 multiplier)
	"""
	if not mind_type_system:
		return 0.0

	# Use override type if provided (e.g., from a skill), otherwise use attacker's mind type
	var atk_type = attack_type if attack_type != "" else String(attacker.get("mind_type", "none"))
	var def_type = String(defender.get("mind_type", "none"))

	# Get effectiveness multiplier (1.25, 0.75, or 1.0)
	var effectiveness = mind_type_system.get_type_effectiveness(atk_type, def_type)

	# Convert multiplier to bonus
	# 1.25 -> +0.25, 0.75 -> -0.25, 1.0 -> 0.0
	return effectiveness - 1.0

func is_type_weakness(attacker: Dictionary, defender: Dictionary, attack_type: String = "") -> bool:
	"""Check if attack hits a type weakness"""
	return get_mind_type_bonus(attacker, defender, attack_type) > 0.0

## ═══════════════════════════════════════════════════════════════
## WEAPON TYPE EFFECTIVENESS (Triangle System)
## ═══════════════════════════════════════════════════════════════

func check_weapon_weakness(attacker: Dictionary, defender: Dictionary) -> bool:
	"""
	Check if attacker's weapon type beats defender's weapon type

	Returns:
		true if weapon triangle advantage (Pierce > Slash > Blunt > Pierce)
	"""
	if not weapon_type_system or attacker == null or defender == null:
		return false

	return weapon_type_system.is_weapon_weakness(
		weapon_type_system.get_weapon_type_from_equipment(attacker),
		weapon_type_system.get_weapon_type_from_equipment(defender)
	)

func get_weapon_type_description(attacker: Dictionary, defender: Dictionary) -> String:
	"""Get description of weapon type matchup"""
	if not weapon_type_system or attacker == null or defender == null:
		return ""

	var atk_type = weapon_type_system.get_weapon_type_from_equipment(attacker)
	var def_type = weapon_type_system.get_weapon_type_from_equipment(defender)

	return weapon_type_system.get_weakness_description(atk_type, def_type)

## ═══════════════════════════════════════════════════════════════
## HIT/EVASION CHECKS (§4.3)
## ═══════════════════════════════════════════════════════════════

func check_physical_hit(attacker: Dictionary, defender: Dictionary, _options: Dictionary = {}) -> Dictionary:
	"""
	Check if a physical attack hits

	Formula: Hit% = WeaponACC + 0.25·TPO + mods
			 Eva% = FootwearEVA + 0.15·VTL + mods
			 Final = clamp(Hit − Eva, 5, 95)
			 (Base accuracy increased to 90%, evasion scaling reduced for better hit rates)

	Returns:
	- hit: bool (did it hit?)
	- hit_chance: float (final hit %)
	- roll: int (d100 roll)
	"""

	# Get attacker weapon stats
	var weapon = _get_weapon_stats(attacker.id)
	var base_acc = weapon.get("acc", 90)  # Default 90% base accuracy

	# Get attacker TPO
	var tpo = attacker.stats.get("TPO", 1)

	# Calculate hit%
	var hit_percent = base_acc + (0.20 * tpo)

	# Apply physical accuracy buffs (Eye Drops, etc.)
	var acc_buff = _get_buff_modifier(attacker, "phys_acc")
	hit_percent += (acc_buff * 100.0)  # Convert 0.10 to 10%

	# Get defender footwear stats
	var footwear = _get_footwear_stats(defender.id)
	var base_eva = footwear.get("eva", 0)  # Default 0% base evasion

	# Get defender VTL (for physical evasion)
	var vtl = defender.stats.get("VTL", 1)

	# Calculate eva%
	var eva_percent = base_eva + (0.20 * vtl)

	# Apply evasion buffs (Hyper Chews, etc.)
	var eva_buff = _get_buff_modifier(defender, "evasion")
	eva_percent += (eva_buff * 100.0)  # Convert 0.10 to 10%

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
			 Eva% = FootwearEVA + 0.15·FCS + mods
			 Final = clamp(Hit − Eva, 5, 95)
			 (Base skill accuracy increased to 95%, evasion scaling reduced for better hit rates)

	Returns:
	- hit: bool
	- hit_chance: float
	- roll: int
	"""

	# Get skill base accuracy
	var skill_acc = options.get("skill_acc", 95)  # Default 95% for skills

	# Get weapon's skill boost
	var weapon = _get_weapon_stats(attacker.id)
	var weapon_skill_boost = weapon.get("skill_acc_bonus", 0)

	# Get attacker TPO
	var tpo = attacker.stats.get("TPO", 1)

	# Calculate hit%
	var hit_percent = skill_acc + weapon_skill_boost + (0.20 * tpo)

	# Apply mind/skill accuracy buffs (Focus Tonic, etc.)
	var mind_acc_buff = _get_buff_modifier(attacker, "mind_acc")
	hit_percent += (mind_acc_buff * 100.0)  # Convert 0.10 to 10%

	# Get defender footwear stats
	var footwear = _get_footwear_stats(defender.id)
	var base_eva = footwear.get("eva", 0)

	# Get defender FCS (for sigil evasion)
	var fcs = defender.stats.get("FCS", 1)

	# Calculate eva%
	var eva_percent = base_eva + (0.20 * fcs)

	# Apply evasion buffs (Hyper Chews, etc.)
	var eva_buff = _get_buff_modifier(defender, "evasion")
	eva_percent += (eva_buff * 100.0)  # Convert 0.10 to 10%

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
## CRITICAL HIT CHECKS
## ═══════════════════════════════════════════════════════════════

func check_critical_hit(attacker: Dictionary, options: Dictionary = {}) -> Dictionary:
	"""
	Check if an attack should critically hit

	Formula:
	  CritChance = Base(5%) + BRW×0.5% + WeaponCritBonus% + SkillCritBonus% + WandVuln%
	  Clamped to [5%, 50%]

	Args:
	  - attacker: Combatant dictionary with id and stats
	  - options:
		- weapon_crit_bonus: int = 0 (weapon crit bonus %)
		- skill_crit_bonus: int = 0 (skill crit bonus %)
		- defender: Dictionary = {} (defender combatant, for wand vulnerability check)

	Returns:
	  - crit: bool (whether it's a critical hit)
	  - crit_chance: float (final crit chance %)
	  - crit_multiplier: float (damage multiplier on crit, 1.5 + BRW×0.1)
	  - roll: int (d100 roll)
	  - breakdown: Dictionary (for debugging)
	"""

	# Get BRW stat
	var brw: int = attacker.stats.get("BRW", 1)

	# Get crit bonuses from options
	var weapon_crit_bonus: int = options.get("weapon_crit_bonus", 0)
	var skill_crit_bonus: int = options.get("skill_crit_bonus", 0)

	# Get defender for wand vulnerability check
	var defender: Dictionary = options.get("defender", {})

	# Calculate crit chance
	var base_crit: float = BASE_CRIT_CHANCE
	var brw_bonus: float = brw * BRW_CRIT_MODIFIER
	var total_bonus: float = weapon_crit_bonus + skill_crit_bonus

	# Apply wand vulnerability (10% more crit chance if defender uses wand)
	var wand_crit_bonus: float = 0.0
	if weapon_type_system and not defender.is_empty():
		wand_crit_bonus = weapon_type_system.get_wand_crit_bonus(defender)

	var final_crit: float = clamp(base_crit + brw_bonus + total_bonus + wand_crit_bonus, CRIT_MIN, CRIT_MAX)

	# Calculate crit damage multiplier based on BRW
	var crit_multiplier: float = 1.5 + (brw * BRW_CRIT_DAMAGE_BONUS)

	# Roll d100
	var roll: int = randi() % 100 + 1
	var is_crit: bool = roll <= final_crit

	return {
		"crit": is_crit,
		"crit_chance": final_crit,
		"crit_multiplier": crit_multiplier,
		"roll": roll,
		"breakdown": {
			"base": base_crit,
			"brw_bonus": brw_bonus,
			"brw": brw,
			"weapon_bonus": weapon_crit_bonus,
			"skill_bonus": skill_crit_bonus,
			"wand_vuln_bonus": wand_crit_bonus,
			"total": final_crit,
			"crit_mult": crit_multiplier
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
	var brw_scale: float = attacker_weapon.get("brw_scale", 1.0)

	# Get defender defense
	var defender_armor = _get_armor_stats(defender.id)
	var base_pdef: int = defender_armor.get("pdef", 0)

	# Step 1: Pre-mitigation damage
	# Pre = (BaseWATK + BRW×Scale_BRW) × POT/100
	var pre_mit: float = (base_watk + brw * brw_scale) * (potency / 100.0)

	# Step 2: Apply TYPE, Crit, and buffs
	# ATK_Power = Pre × (1+TYPE) × (Crit?(1.5+BRW×0.1):1) × (1+ATK_buffs−ATK_debuffs) × WandVuln
	var type_mult: float = 1.0 + type_bonus
	# Variable crit multiplier based on BRW
	var crit_mult: float = (1.5 + (brw * BRW_CRIT_DAMAGE_BONUS)) if is_crit else 1.0

	# Get ATK buffs/debuffs from attacker
	var atk_buff = _get_buff_modifier(attacker, "atk_up")
	var atk_debuff = _get_buff_modifier(attacker, "atk_down")
	var buff_mult: float = 1.0 + atk_buff + atk_debuff  # debuffs are negative

	# Apply wand vulnerability (10% more damage if defender uses wand)
	var wand_mult: float = 1.0
	if weapon_type_system:
		wand_mult = weapon_type_system.get_wand_damage_modifier(defender)

	var atk_power: float = pre_mit * type_mult * crit_mult * buff_mult * wand_mult

	# Step 3: Apply defense mitigation
	# For multi-hit: PDEF_perHit = PDEF / √H
	var pdef_per_hit: float = base_pdef
	if multi_hit > 1:
		pdef_per_hit = base_pdef / sqrt(float(multi_hit))

	# Raw = max(ATK_Power − PDEF_perHit, 0)
	var raw_damage: float = max(atk_power - pdef_per_hit, 0.0)

	# Step 4: Apply defensive modifiers (Defend, Shield/DEF Up, etc)
	var defend_mult: float = DEFEND_MULT if defender.get("is_defending", false) else 1.0

	# Get DEF buffs (Shield Orb / DEF Up reduces damage taken)
	var def_buff = _get_buff_modifier(defender, "def_up")
	var def_debuff = _get_buff_modifier(defender, "def_down")
	var shield_mult: float = 1.0 - (def_buff + def_debuff)  # def_up reduces damage, def_down increases it

	var dmg_after_mods: float = raw_damage * defend_mult * shield_mult

	# Step 5: Apply enemy damage reduction (for balancing)
	var enemy_mult: float = ENEMY_DAMAGE_MULT if not attacker.get("is_ally", false) else 1.0
	dmg_after_mods = dmg_after_mods * enemy_mult

	# Step 6: Apply mitigation floor
	# DMG = max(DMG, ceil(ATK_Power × DMG_FLOOR))
	var dmg_floor: float = DMG_FLOOR_PLAYER_TO_ENEMY if attacker.get("is_ally", false) else DMG_FLOOR_ENEMY_TO_PLAYER
	var min_damage: int = int(ceil(atk_power * dmg_floor * enemy_mult))

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
	var base_sig: int = options.get("base_sig", 40)
	var mnd_scale: float = options.get("mnd_scale", 1.5)

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
	# Variable crit multiplier based on BRW (applies to skills too)
	var brw: int = attacker.stats.get("BRW", 1)
	var crit_mult: float = (1.5 + (brw * BRW_CRIT_DAMAGE_BONUS)) if is_crit else 1.0

	# Get SKL buffs/debuffs from attacker (skills use SKL/MND buffs)
	var skl_buff = _get_buff_modifier(attacker, "skl_up")
	var skl_debuff = _get_buff_modifier(attacker, "skl_down")
	var buff_mult: float = 1.0 + skl_buff + skl_debuff  # debuffs are negative

	var skill_power: float = pre_mit * type_mult * crit_mult * buff_mult

	# Step 3: Apply defense mitigation
	var mdef_per_hit: float = base_mdef
	if multi_hit > 1:
		mdef_per_hit = base_mdef / sqrt(float(multi_hit))

	var raw_damage: float = max(skill_power - mdef_per_hit, 0.0)

	# Step 4: Apply defensive modifiers
	var defend_mult: float = DEFEND_MULT if defender.get("is_defending", false) else 1.0

	# Get DEF buffs (Shield Orb / DEF Up reduces damage taken)
	var def_buff = _get_buff_modifier(defender, "def_up")
	var def_debuff = _get_buff_modifier(defender, "def_down")
	var shield_mult: float = 1.0 - (def_buff + def_debuff)  # def_up reduces damage, def_down increases it

	var dmg_after_mods: float = raw_damage * defend_mult * shield_mult

	# Step 5: Apply enemy damage reduction (for balancing)
	var enemy_mult: float = ENEMY_DAMAGE_MULT if not attacker.get("is_ally", false) else 1.0
	dmg_after_mods = dmg_after_mods * enemy_mult

	# Step 6: Apply mitigation floor
	var dmg_floor: float = DMG_FLOOR_PLAYER_TO_ENEMY if attacker.get("is_ally", false) else DMG_FLOOR_ENEMY_TO_PLAYER
	var min_damage: int = int(ceil(skill_power * dmg_floor * enemy_mult))

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
				"watk": weapon.get("watk", 15),
				"sig": weapon.get("sig", 0),
				"brw_scale": weapon.get("brw_scale", 1.0),
				"acc": weapon.get("acc", 90),
				"skill_acc_bonus": weapon.get("skill_acc_bonus", 0),
				"crit_bonus": weapon.get("crit_bonus_pct", 0)
			}

	# Default weapon stats
	return {
		"watk": 15,
		"sig": 0,
		"brw_scale": 1.0,
		"acc": 90,
		"skill_acc_bonus": 0,
		"crit_bonus": 0
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

func get_type_modifier(_attacker_element: String, _defender_element: String) -> float:
	"""
	Get TYPE modifier based on elemental matchup
	Returns: -0.5 (resist), 0.0 (neutral), 0.25 (weakness), etc.
	"""
	if not mind_type_system:
		return 0.0

	# TODO: Implement type system lookup using attacker_element and defender_element
	# For now, return neutral
	return 0.0

## ═══════════════════════════════════════════════════════════════
## AILMENT APPLICATION (MND-based)
## ═══════════════════════════════════════════════════════════════

func calculate_ailment_chance(attacker: Dictionary, skill_base_rate: float) -> float:
	"""
	Calculate the chance for an ailment to be applied

	Formula:
	  Ailment_Rate% = Skill_Base_Rate + (MND × 2%)
	  Clamped to [5%, 95%]

	Args:
	  - attacker: Attacker combatant dictionary with stats
	  - skill_base_rate: Base ailment rate from skill data (e.g., 30.0 for 30%)

	Returns:
	  - float: Final ailment application chance (5-95%)
	"""
	var mnd: int = attacker.stats.get("MND", 1)
	var mnd_bonus: float = mnd * 2.0  # +2% per MND point

	var final_rate: float = clamp(skill_base_rate + mnd_bonus, HIT_EVA_MIN, HIT_EVA_MAX)

	return final_rate

func attempt_ailment(ailment_chance: float) -> bool:
	"""
	Roll to see if ailment is applied

	Args:
	  - ailment_chance: Chance % (0-100)

	Returns:
	  - bool: true if ailment applied
	"""
	var roll: float = randf() * 100.0  # 0.0 - 100.0
	return roll <= ailment_chance

## ═══════════════════════════════════════════════════════════════
## CAPTURE MECHANICS (§4.8)
## ═══════════════════════════════════════════════════════════════

const CAPTURE_HP_COEFFICIENT: float = 0.15  # k value for HP% penalty (reduced from 0.4 to make captures more viable)
const STATE_BONUS_HIGH: int = 15  # Sleep, Freeze, Bound
const STATE_BONUS_MED: int = 10   # Stunned, Fallen

func calculate_capture_chance(enemy: Dictionary, options: Dictionary = {}) -> Dictionary:
	"""
	Calculate chance to capture an enemy

	Formula (§4.8):
	  Catch% = clamp(Base + ItemMod − EnemyResist − k·HP% + StateBonus, 0, 100)

	Where:
	  - Base = 35 (encounter default)
	  - ItemMod = bind item modifier (+10/+25/+40/+60/+100)
	  - EnemyResist = enemy's capture_resist value (0-60)
	  - k = 0.4
	  - HP% = enemy's current HP as percentage (0-100)
	  - StateBonus = +15 for Sleep/Freeze/Bound, +10 for Stunned/Fallen

	Args:
	  - enemy: Enemy combatant dictionary
	  - options:
		- item_mod: int = 0 (bind item's capture modifier)

	Returns:
	  - chance: float (final capture chance, 0-100)
	  - breakdown: Dictionary (for display/debugging)
	"""

	# Base capture chance
	var base_chance: int = aMoralitySystem.BASE_CAPTURE_CHANCE if aMoralitySystem else 35

	# Item modifier from bind
	var item_mod: int = options.get("item_mod", 0)
	print("[CombatResolver] Capture calculation - options: %s" % options)
	print("[CombatResolver] Item mod from options: %d" % item_mod)

	# Enemy resistance
	var enemy_resist: int = enemy.get("capture_resist", 25)

	# Calculate HP percentage
	var current_hp: int = enemy.get("hp", 1)
	var max_hp: int = enemy.get("hp_max", 1)  # Fixed: field is "hp_max" not "max_hp"
	var hp_percent: float = (float(current_hp) / float(max_hp)) * 100.0

	# HP penalty (lower HP = better capture chance)
	var hp_penalty: float = CAPTURE_HP_COEFFICIENT * hp_percent

	# State bonus
	var state_bonus: int = 0
	var status: String = enemy.get("status", "")

	# High bonus states (+15)
	if status in ["Sleep", "Freeze", "Bound"]:
		state_bonus = STATE_BONUS_HIGH
	# Medium bonus states (+10)
	elif status in ["Stunned", "Fallen"]:
		state_bonus = STATE_BONUS_MED

	# Calculate final chance
	var raw_chance: float = float(base_chance) + float(item_mod) - float(enemy_resist) - hp_penalty + float(state_bonus)
	var final_chance: float = clamp(raw_chance, 0.0, 100.0)

	print("[CombatResolver] Capture breakdown: base=%d, item_mod=%d, enemy_resist=%d, hp_percent=%.1f, hp_penalty=%.1f, state_bonus=%d" % [base_chance, item_mod, enemy_resist, hp_percent, hp_penalty, state_bonus])
	print("[CombatResolver] Raw chance: %.1f, Final chance: %.1f" % [raw_chance, final_chance])

	return {
		"chance": final_chance,
		"breakdown": {
			"base": base_chance,
			"item_mod": item_mod,
			"enemy_resist": enemy_resist,
			"hp_percent": hp_percent,
			"hp_penalty": hp_penalty,
			"state_bonus": state_bonus,
			"status": status,
			"raw_chance": raw_chance
		}
	}

func attempt_capture(_enemy: Dictionary, capture_chance: float) -> bool:
	"""
	Roll to see if capture succeeds

	Args:
	  - _enemy: Enemy combatant dictionary (reserved for future use)
	  - capture_chance: Capture chance % (0-100)

	Returns:
	  - bool: true if capture succeeded
	"""
	var roll: float = randf() * 100.0  # 0.0 - 100.0
	return roll <= capture_chance
