extends Node
class_name MinigameManager

## MinigameManager - Coordinates all battle minigames
## Handles launching minigames and returning results to the battle system

## Signals emitted when minigames complete
signal minigame_completed(result: Dictionary)

## Minigame result structure:
## {
##   "success": bool,           # Did the minigame complete successfully?
##   "grade": String,           # "perfect", "good", "miss", etc.
##   "damage_modifier": float,  # Damage multiplier (e.g., 1.1 for +10%)
##   "is_crit": bool,          # Force critical hit?
##   "mp_modifier": float,      # MP cost modifier for skills
##   "tier_downgrade": int,     # Skill tier reduction (0 = no change)
##   "focus_level": int,        # Achieved focus level for skills
## }

## Current minigame scene
var current_minigame: Node = null

## Minigame scene paths
const ATTACK_MINIGAME = preload("res://scenes/minigames/AttackMinigame.tscn")
const SKILL_MINIGAME = preload("res://scenes/minigames/SkillMinigame.tscn")
const RUN_MINIGAME = preload("res://scenes/minigames/RunMinigame.tscn")
const CAPTURE_MINIGAME = preload("res://scenes/minigames/CaptureMinigame.tscn")
const BURST_MINIGAME = preload("res://scenes/minigames/BurstMinigame.tscn")

func _ready() -> void:
	print("[MinigameManager] Initialized")

## Launch attack minigame
## tempo: Number of attempts (1-4) based on TPO stat
## brawn: Brawn stat (affects reticle size)
## status_effects: Array of active status effect names
func launch_attack_minigame(tempo: int, brawn: int, status_effects: Array = []) -> Dictionary:
	print("[MinigameManager] Launching attack minigame (tempo: %d, brawn: %d)" % [tempo, brawn])

	var minigame = ATTACK_MINIGAME.instantiate()
	minigame.tempo = tempo
	minigame.brawn = brawn
	minigame.status_effects = status_effects

	var result = await _run_minigame(minigame)
	return result

## Launch skill minigame
## focus_stat: Focus stat value (affects charge speed)
## skill_sequence: Array of button inputs ["A", "B", "X", "Y"]
## skill_tier: Skill tier (1-3)
## status_effects: Array of active status effect names
func launch_skill_minigame(focus_stat: int, skill_sequence: Array, skill_tier: int, status_effects: Array = []) -> Dictionary:
	print("[MinigameManager] Launching skill minigame (focus: %d, tier: %d)" % [focus_stat, skill_tier])

	var minigame = SKILL_MINIGAME.instantiate()
	minigame.focus_stat = focus_stat
	minigame.skill_sequence = skill_sequence
	minigame.skill_tier = skill_tier
	minigame.status_effects = status_effects

	var result = await _run_minigame(minigame)
	return result

## Launch run minigame
## run_chance: Base run percentage (0-100)
## tempo_diff: Party tempo - enemy tempo
## focus: Party focus stat
## status_effects: Array of active status effect names
func launch_run_minigame(run_chance: float, tempo_diff: int, focus: int, status_effects: Array = []) -> Dictionary:
	print("[MinigameManager] Launching run minigame (chance: %.1f%%)" % run_chance)

	var minigame = RUN_MINIGAME.instantiate()
	minigame.run_chance = run_chance
	minigame.tempo_diff = tempo_diff
	minigame.focus = focus
	minigame.status_effects = status_effects

	var result = await _run_minigame(minigame)
	return result

## Launch capture minigame
## binds: Array of bind types ["basic", "standard", "advanced"]
## enemy_data: Dictionary with enemy stats
## party_member_data: Dictionary with party member stats
## status_effects: Array of active status effect names
func launch_capture_minigame(binds: Array, enemy_data: Dictionary, party_member_data: Dictionary, status_effects: Array = []) -> Dictionary:
	print("[MinigameManager] Launching capture minigame")

	var minigame = CAPTURE_MINIGAME.instantiate()
	minigame.binds = binds
	minigame.enemy_data = enemy_data
	minigame.party_member_data = party_member_data
	minigame.status_effects = status_effects

	var result = await _run_minigame(minigame)
	return result

## Launch burst minigame
## affinity: Combined affinity of burst participants
## status_effects: Array of active status effect names
func launch_burst_minigame(affinity: int, status_effects: Array = []) -> Dictionary:
	print("[MinigameManager] Launching burst minigame (affinity: %d)" % affinity)

	var minigame = BURST_MINIGAME.instantiate()
	minigame.affinity = affinity
	minigame.status_effects = status_effects

	var result = await _run_minigame(minigame)
	return result

## Internal: Run a minigame and wait for completion
func _run_minigame(minigame: Node) -> Dictionary:
	current_minigame = minigame
	get_tree().root.add_child(minigame)

	# Wait for minigame to complete
	var result = await minigame.completed

	# Cleanup
	minigame.queue_free()
	current_minigame = null

	print("[MinigameManager] Minigame completed: %s" % str(result))
	minigame_completed.emit(result)

	return result
