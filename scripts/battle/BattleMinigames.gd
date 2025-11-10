extends Node
class_name BattleMinigames

## BattleMinigames - Utility class and constants for all battle minigames
## Provides stat-based calculations, grade evaluation, and helper functions
##
## Minigame lifecycle is managed by MinigameManager
## This class provides the formulas and constants used by all minigames
##
## Updated for new stat system:
## - BRW: Drives crit rate/damage (not TPO)
## - TPO: Still affects initiative, less impactful on accuracy (0.20 not 0.25)
## - FCS: Drives skill charge speed and evasion
## - MND: Drives skill damage and ailment rates (+2% per point)
## - VTL: Drives HP and physical defense

## ═══════════════════════════════════════════════════════════════
## MINIGAME TYPE ENUM
## ═══════════════════════════════════════════════════════════════

enum Type {
	ATTACK,  ## Physical attack minigame (BRW-based damage, TPO for attempts)
	SKILL,   ## Skill/Sigil minigame (FCS-based charge speed)
	RUN,     ## Escape minigame (run chance-based)
	CAPTURE, ## Capture minigame
	BURST    ## Burst/Psyokin minigame
}

## ═══════════════════════════════════════════════════════════════
## HELPER FUNCTIONS
## ═══════════════════════════════════════════════════════════════

static func get_minigame_type_name(type: Type) -> String:
	"""Get human-readable name for minigame type"""
	match type:
		Type.ATTACK: return "Attack"
		Type.SKILL: return "Skill"
		Type.RUN: return "Run"
		_: return "Unknown"

static func calculate_attack_damage_modifier(grade: String) -> float:
	"""
	Calculate damage modifier from attack minigame grade

	Grades:
		- red: 0.9× (-10%)
		- yellow: 1.0× (normal)
		- green: 1.1× (+10%)
		- blue: 1.1× (+10% + crit)
	"""
	match grade:
		"red": return 0.9
		"yellow": return 1.0
		"green": return 1.1
		"blue": return 1.1  # Same as green, but with is_crit flag
		_: return 1.0

static func calculate_skill_bonuses(focus_level: int) -> Dictionary:
	"""
	Calculate bonuses from skill minigame focus level

	Returns:
		{
			"damage_modifier": float,
			"mp_modifier": float
		}

	Focus Levels:
		- 0: 1.0× damage, 1.0× MP
		- 1: 1.05× damage, 1.0× MP
		- 2: 1.1× damage, 1.0× MP
		- 3: 1.1× damage, 0.9× MP (save 10% MP)
	"""
	match focus_level:
		0: return {"damage_modifier": 1.0, "mp_modifier": 1.0}
		1: return {"damage_modifier": 1.05, "mp_modifier": 1.0}
		2: return {"damage_modifier": 1.1, "mp_modifier": 1.0}
		3: return {"damage_modifier": 1.1, "mp_modifier": 0.9}
		_: return {"damage_modifier": 1.0, "mp_modifier": 1.0}
