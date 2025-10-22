## ═══════════════════════════════════════════════════════════════════════════
## BurstSystem - Burst Meter Manager (PLACEHOLDER)
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   (PLACEHOLDER) Will manage the Burst meter system for combat, tracking
##   accumulation and spending of Burst points for special attacks/abilities.
##
## PLANNED RESPONSIBILITIES:
##   • Burst meter tracking (0-100 or similar scale)
##   • Burst point accumulation from attacks/crits/damage taken
##   • Burst skill/finisher activation
##   • Burst point spending mechanics
##   • Save/load burst state
##
## CONNECTED SYSTEMS (Planned):
##   • CombatSystem - Burst point generation during combat
##   • PerkSystem - Perks that affect Burst gain (e.g., Opportunist)
##   • GameState - Save/load coordination
##
## STATUS: Not yet implemented
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name BurstSystem

func get_save_blob() -> Dictionary:
	return {}   # fill later

func apply_save_blob(_blob: Dictionary) -> void:
	# no-op for now
	pass

func clear_all() -> void:
	# reset local state when you add some
	pass
