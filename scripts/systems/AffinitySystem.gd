## ═══════════════════════════════════════════════════════════════════════════
## AffinitySystem - Social Relationship & Affinity XP Tracker
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Tracks social relationships between party members through Affinity XP (AXP).
##   AXP is earned through combat co-presence and synergy moments, converted weekly
##   to Affinity Tiers (AT0-AT3) that provide combat bonuses.
##
## RESPONSIBILITIES:
##   • Track weekly AXP for each character pair
##   • Apply daily caps (+6 co-presence per pair)
##   • Apply per-battle synergy caps (+3 best events)
##   • Weekly conversion (Sunday): floor → cap 30 → add to lifetime → compute tier
##   • Provide tier-based combat auras (AT1: +5% stats, AT2: +10%, AT3: +15%)
##   • Track co-presence (+2 both active, +1 if one KO'd)
##   • Track synergy moments (weakness chains, Burst usage, interrupts)
##
## AXP SOURCES (Weekly):
##   • Co-presence: Fighting together in battles (daily cap: +6 per pair)
##   • Synergy: Weakness chains, Burst participation, interrupts (per-battle cap: +3)
##   • Social: Dates, gifts, dorm adjacency (not implemented yet)
##
## AFFINITY TIERS & THRESHOLDS:
##   • AT0: 0+ lifetime AXP (no bonus)
##   • AT1: 20+ lifetime AXP (+5% BRW/VTL/MND when both active)
##   • AT2: 60+ lifetime AXP (+10% BRW/VTL/MND when both active)
##   • AT3: 120+ lifetime AXP (+15% BRW/VTL/MND when both active)
##
## CONNECTED SYSTEMS:
##   • BattleManager - Awards AXP for co-presence and synergy
##   • GameState - Save/load coordination, weekly Sunday conversion
##   • CombatResolver - Applies tier-based stat bonuses
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name AffinitySystem

## Weekly AXP tracking (pair_key -> axp_data)
## pair_key format: "memberA|memberB" (alphabetically sorted)
var weekly_axp: Dictionary = {}

## Lifetime AXP totals (pair_key -> total_lifetime_axp)
var lifetime_axp: Dictionary = {}

## Daily co-presence tracking (pair_key -> daily_copresence)
var daily_copresence: Dictionary = {}

## Constants
const DAILY_COPRESENCE_CAP: int = 6
const PER_BATTLE_SYNERGY_CAP: int = 3
const WEEKLY_AXP_CAP: int = 30

## Tier thresholds
const AT1_THRESHOLD: int = 20
const AT2_THRESHOLD: int = 60
const AT3_THRESHOLD: int = 120

## Tier bonuses (stat multipliers when both members active)
const AT1_BONUS: float = 0.05  # +5%
const AT2_BONUS: float = 0.10  # +10%
const AT3_BONUS: float = 0.15  # +15%

func _ready() -> void:
	print("[AffinitySystem] Initialized - Social Affinity Tracker")

## ═══════════════════════════════════════════════════════════════
## PAIR KEY HELPERS
## ═══════════════════════════════════════════════════════════════

func _make_pair_key(member_a: String, member_b: String) -> String:
	"""Create a sorted pair key (A|B) to avoid duplicates"""
	var sorted_pair = [member_a, member_b]
	sorted_pair.sort()
	return "%s|%s" % [sorted_pair[0], sorted_pair[1]]

func _get_pair_members(pair_key: String) -> Array:
	"""Split pair key back into [memberA, memberB]"""
	return pair_key.split("|")

## ═══════════════════════════════════════════════════════════════
## AXP TRACKING
## ═══════════════════════════════════════════════════════════════

func add_copresence_axp(member_a: String, member_b: String, amount: int) -> int:
	"""
	Add co-presence AXP to a pair (caps at +6 daily)

	Returns: actual amount added (may be less than requested due to cap)
	"""
	if member_a == member_b:
		return 0  # Can't earn AXP with yourself

	var pair_key = _make_pair_key(member_a, member_b)

	# Initialize daily tracking if needed
	if not daily_copresence.has(pair_key):
		daily_copresence[pair_key] = 0

	# Check daily cap
	var current_daily = daily_copresence[pair_key]
	if current_daily >= DAILY_COPRESENCE_CAP:
		print("[AffinitySystem] Daily co-presence cap reached for %s (%d/%d)" % [pair_key, current_daily, DAILY_COPRESENCE_CAP])
		return 0

	# Cap the amount we can add
	var allowed = mini(amount, DAILY_COPRESENCE_CAP - current_daily)

	# Add to daily tracking
	daily_copresence[pair_key] = current_daily + allowed

	# Add to weekly AXP
	_add_weekly_axp(pair_key, allowed)

	print("[AffinitySystem] Co-presence AXP: %s +%d (daily: %d/%d)" % [
		pair_key, allowed, daily_copresence[pair_key], DAILY_COPRESENCE_CAP
	])

	return allowed

func add_synergy_axp(member_a: String, member_b: String, amount: int, reason: String = "") -> int:
	"""
	Add synergy AXP to a pair (per-battle cap handled by caller)

	Returns: actual amount added
	"""
	if member_a == member_b:
		return 0  # Can't earn AXP with yourself

	var pair_key = _make_pair_key(member_a, member_b)

	# Add to weekly AXP
	_add_weekly_axp(pair_key, amount)

	var reason_text = (" (%s)" % reason) if reason != "" else ""
	print("[AffinitySystem] Synergy AXP: %s +%d%s" % [pair_key, amount, reason_text])

	return amount

func _add_weekly_axp(pair_key: String, amount: int) -> void:
	"""Internal: Add to weekly AXP tracking"""
	if not weekly_axp.has(pair_key):
		weekly_axp[pair_key] = 0

	weekly_axp[pair_key] += amount

## ═══════════════════════════════════════════════════════════════
## DAILY & WEEKLY RESET
## ═══════════════════════════════════════════════════════════════

func reset_daily_caps() -> void:
	"""Reset daily co-presence caps (called at start of each new day)"""
	daily_copresence.clear()
	print("[AffinitySystem] Daily co-presence caps reset")

func convert_weekly_axp() -> Dictionary:
	"""
	Convert weekly AXP to lifetime AXP (called every Sunday)

	Process: floor → cap at 30 → add to lifetime → compute tier

	Returns: Dictionary of pair_key -> {added, new_total, tier}
	"""
	var conversion_results: Dictionary = {}

	for pair_key in weekly_axp.keys():
		var weekly = int(floor(weekly_axp[pair_key]))

		# Cap at 30
		var capped = mini(weekly, WEEKLY_AXP_CAP)

		# Add to lifetime
		if not lifetime_axp.has(pair_key):
			lifetime_axp[pair_key] = 0

		var old_lifetime = lifetime_axp[pair_key]
		lifetime_axp[pair_key] += capped
		var new_lifetime = lifetime_axp[pair_key]

		# Compute tier
		var tier = get_affinity_tier_for_pair(pair_key)

		conversion_results[pair_key] = {
			"weekly_earned": weekly,
			"capped_at": capped,
			"old_lifetime": old_lifetime,
			"new_lifetime": new_lifetime,
			"tier": tier
		}

		print("[AffinitySystem] Weekly conversion: %s earned %d (capped %d) → lifetime %d (Tier %d)" % [
			pair_key, weekly, capped, new_lifetime, tier
		])

	# Clear weekly tracking
	weekly_axp.clear()

	print("[AffinitySystem] Weekly AXP conversion complete")

	return conversion_results

## ═══════════════════════════════════════════════════════════════
## TIER CALCULATION
## ═══════════════════════════════════════════════════════════════

func get_affinity_tier_for_pair(pair_key: String) -> int:
	"""Get current affinity tier (0-3) for a pair"""
	var total = lifetime_axp.get(pair_key, 0)

	if total >= AT3_THRESHOLD:
		return 3
	elif total >= AT2_THRESHOLD:
		return 2
	elif total >= AT1_THRESHOLD:
		return 1
	else:
		return 0

func get_affinity_tier(member_a: String, member_b: String) -> int:
	"""Get current affinity tier (0-3) between two members"""
	if member_a == member_b:
		return 0

	var pair_key = _make_pair_key(member_a, member_b)
	return get_affinity_tier_for_pair(pair_key)

func get_tier_bonus_multiplier(tier: int) -> float:
	"""Get stat bonus multiplier for a tier"""
	match tier:
		1: return AT1_BONUS
		2: return AT2_BONUS
		3: return AT3_BONUS
		_: return 0.0

func get_affinity_bonus(member_a: String, member_b: String) -> float:
	"""Get stat bonus multiplier when both members are active together"""
	var tier = get_affinity_tier(member_a, member_b)
	return get_tier_bonus_multiplier(tier)

## ═══════════════════════════════════════════════════════════════
## QUERY METHODS
## ═══════════════════════════════════════════════════════════════

func get_weekly_axp(member_a: String, member_b: String) -> int:
	"""Get current weekly AXP for a pair"""
	var pair_key = _make_pair_key(member_a, member_b)
	return weekly_axp.get(pair_key, 0)

func get_lifetime_axp(member_a: String, member_b: String) -> int:
	"""Get lifetime AXP total for a pair"""
	var pair_key = _make_pair_key(member_a, member_b)
	return lifetime_axp.get(pair_key, 0)

func get_daily_copresence(member_a: String, member_b: String) -> int:
	"""Get daily co-presence AXP earned today for a pair"""
	var pair_key = _make_pair_key(member_a, member_b)
	return daily_copresence.get(pair_key, 0)

func get_all_pair_data() -> Array:
	"""Get all pair data for UI display"""
	var pairs: Array = []

	# Collect all unique pairs from lifetime and weekly tracking
	var all_keys: Dictionary = {}
	for key in lifetime_axp.keys():
		all_keys[key] = true
	for key in weekly_axp.keys():
		all_keys[key] = true

	for pair_key in all_keys.keys():
		var members = _get_pair_members(pair_key)
		pairs.append({
			"pair_key": pair_key,
			"member_a": members[0],
			"member_b": members[1],
			"weekly_axp": weekly_axp.get(pair_key, 0),
			"lifetime_axp": lifetime_axp.get(pair_key, 0),
			"tier": get_affinity_tier_for_pair(pair_key),
			"daily_copresence": daily_copresence.get(pair_key, 0)
		})

	return pairs

## ═══════════════════════════════════════════════════════════════
## SAVE / LOAD
## ═══════════════════════════════════════════════════════════════

func get_save_blob() -> Dictionary:
	"""Serialize affinity data for save system"""
	return {
		"weekly_axp": weekly_axp.duplicate(),
		"lifetime_axp": lifetime_axp.duplicate(),
		"daily_copresence": daily_copresence.duplicate()
	}

func apply_save_blob(blob: Dictionary) -> void:
	"""Restore affinity data from save system"""
	if blob.has("weekly_axp"):
		weekly_axp = blob.weekly_axp.duplicate()
	if blob.has("lifetime_axp"):
		lifetime_axp = blob.lifetime_axp.duplicate()
	if blob.has("daily_copresence"):
		daily_copresence = blob.daily_copresence.duplicate()

	print("[AffinitySystem] Loaded affinity data: %d pairs tracked" % lifetime_axp.size())

func clear_all() -> void:
	"""Reset all affinity tracking (for new game)"""
	weekly_axp.clear()
	lifetime_axp.clear()
	daily_copresence.clear()
	print("[AffinitySystem] All affinity data cleared")
