## ═══════════════════════════════════════════════════════════════════════════
## RomanceSystem - Romance Progression Manager (PLACEHOLDER)
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   (PLACEHOLDER) Will manage romantic relationships, confession tracking,
##   dating progression, and romance-specific events. Currently a stub for
##   future implementation.
##
## PLANNED RESPONSIBILITIES:
##   • Romance state tracking (confessed, dating, committed, etc.)
##   • Confession acceptance/rejection handling
##   • Date event scheduling
##   • Jealousy and poly relationship management
##   • Romance-specific dialogue unlocks
##   • Save/load romance state
##
## CONNECTED SYSTEMS (Planned):
##   • CircleBondSystem - Love interest identification
##   • GameState - Save/load coordination
##   • EventRunner - Romance event scenes
##
## STATUS: Not yet implemented
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name RomanceSystem

func get_save_blob() -> Dictionary:
	return {}   # fill later

func apply_save_blob(_blob: Dictionary) -> void:
	# no-op for now
	pass

func clear_all() -> void:
	# reset local state when you add some
	pass
