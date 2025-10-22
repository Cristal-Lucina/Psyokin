## ═══════════════════════════════════════════════════════════════════════════
## AffinitySystem - Elemental/Type Affinity Manager (PLACEHOLDER)
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   (PLACEHOLDER) Will manage elemental/type affinities for characters,
##   tracking weaknesses, resistances, and immunities for combat calculations.
##
## PLANNED RESPONSIBILITIES:
##   • Affinity tracking (Fire, Water, Earth, Air, Data, Void, etc.)
##   • Weakness/resistance calculations (e.g., Fire deals 1.5x to Earth)
##   • Immunity system (e.g., Fire immune to Burn)
##   • Dynamic affinity changes (buffs/debuffs/equipment)
##   • Save/load affinity state
##
## CONNECTED SYSTEMS (Planned):
##   • CombatSystem - Damage calculation multipliers
##   • MindTypeSystem - Character mind type affinities
##   • EquipmentSystem - Equipment-granted resistances
##   • GameState - Save/load coordination
##
## STATUS: Not yet implemented
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name AffinitySystem

func get_save_blob() -> Dictionary:
	return {}   # fill later

func apply_save_blob(_blob: Dictionary) -> void:
	# no-op for now
	pass

func clear_all() -> void:
	# reset local state when you add some
	pass
