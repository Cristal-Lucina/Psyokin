extends Node

## MoralitySystem - Tracks player morality from Pacifist to Bloodlust
## Based on Chapter 14 design doc

## Signals
signal morality_changed(old_value: int, new_value: int, delta: int, reason: String)
signal tier_changed(old_tier: String, new_tier: String)

## Morality Meter
## Range: [-100, +100]
## +100 = Paragon Pacifist
## -100 = Infamous Bloodlust
var morality_meter: int = 0

## Constants
const DIMINISH_ALPHA: float = 0.5  # Diminishing returns factor
const DAILY_CAP: int = 30  # Maximum |delta| per calendar day
const BASE_CAPTURE_CHANCE: int = 35  # Base capture percentage

## Event deltas (raw points before diminishing)
const DELTA_REGULAR_LETHAL: int = -1
const DELTA_REGULAR_NONLETHAL: int = 1
const DELTA_ELITE_LETHAL: int = -3
const DELTA_ELITE_NONLETHAL: int = 3
const DELTA_BOSS_LETHAL: int = -15
const DELTA_BOSS_NONLETHAL: int = 15

## Tier thresholds
enum MoralityTier {
	P3,  # Paragon Pacifist [+80, +100]
	P2,  # Recognized Pacifist [+40, +79]
	N,   # Neutral [-39, +39]
	B2,  # Feared [-79, -40]
	B3   # Infamous Bloodlust [-100, -80]
}

## Tier data (based on §14.3)
const TIER_DATA = {
	MoralityTier.P3: {
		"name": "Paragon Pacifist",
		"min": 80,
		"max": 100,
		"surrender_bonus": 10,
		"bind_ease": 15,
		"color": Color(0.3, 0.7, 1.0)  # Light blue
	},
	MoralityTier.P2: {
		"name": "Recognized Pacifist",
		"min": 40,
		"max": 79,
		"surrender_bonus": 5,
		"bind_ease": 8,
		"color": Color(0.5, 0.8, 1.0)  # Pale blue
	},
	MoralityTier.N: {
		"name": "Neutral",
		"min": -39,
		"max": 39,
		"surrender_bonus": 0,
		"bind_ease": 0,
		"color": Color(0.7, 0.7, 0.7)  # Gray
	},
	MoralityTier.B2: {
		"name": "Feared",
		"min": -79,
		"max": -40,
		"surrender_bonus": -5,
		"bind_ease": 0,
		"color": Color(1.0, 0.7, 0.3)  # Orange
	},
	MoralityTier.B3: {
		"name": "Infamous Bloodlust",
		"min": -100,
		"max": -80,
		"surrender_bonus": -10,
		"bind_ease": 0,
		"color": Color(1.0, 0.3, 0.2)  # Red
	}
}

## Daily tracking
var _daily_delta_total: int = 0
var _current_date: String = ""  # Format: "month/day" (e.g., "5/5")

## References
@onready var gs = get_node_or_null("/root/aGameState")

func _ready() -> void:
	print("[MoralitySystem] Initialized")
	_load_from_game_state()

## ═══════════════════════════════════════════════════════════════
## CORE METER MANAGEMENT
## ═══════════════════════════════════════════════════════════════

func _load_from_game_state() -> void:
	"""Load morality data from GameState metadata"""
	if not gs:
		return

	if gs.has_meta("morality_meter"):
		morality_meter = gs.get_meta("morality_meter")
	else:
		morality_meter = 0
		gs.set_meta("morality_meter", 0)

	if gs.has_meta("morality_daily_delta"):
		_daily_delta_total = gs.get_meta("morality_daily_delta")
	else:
		_daily_delta_total = 0
		gs.set_meta("morality_daily_delta", 0)

	if gs.has_meta("morality_date"):
		_current_date = gs.get_meta("morality_date")
	else:
		_current_date = _get_current_date()
		gs.set_meta("morality_date", _current_date)

	print("[MoralitySystem] Loaded: M=%d, Tier=%s, DailyDelta=%d/%d" % [
		morality_meter,
		get_tier_name(),
		abs(_daily_delta_total),
		DAILY_CAP
	])

func _save_to_game_state() -> void:
	"""Save morality data to GameState metadata"""
	if not gs:
		return

	gs.set_meta("morality_meter", morality_meter)
	gs.set_meta("morality_daily_delta", _daily_delta_total)
	gs.set_meta("morality_date", _current_date)

func _get_current_date() -> String:
	"""Get current calendar date from GameState as 'month/day'"""
	if not gs:
		return "5/1"  # Default

	var month = gs.get_meta("month", 5)
	var day = gs.get_meta("day", 1)
	return "%d/%d" % [month, day]

func check_date_reset() -> void:
	"""Check if calendar date changed and reset daily counter"""
	var current = _get_current_date()

	if current != _current_date:
		print("[MoralitySystem] Date changed from %s to %s - resetting daily cap" % [_current_date, current])
		_current_date = current
		_daily_delta_total = 0
		_save_to_game_state()

## ═══════════════════════════════════════════════════════════════
## EVENT PROCESSING
## ═══════════════════════════════════════════════════════════════

func record_enemy_defeat(env_tag: String, is_lethal: bool, is_vr: bool = false) -> void:
	"""
	Record an enemy defeat for morality tracking

	Args:
		env_tag: "Regular", "Elite", or "Boss"
		is_lethal: true for kill, false for capture/pacify
		is_vr: true if this is a VR battle (morality not tracked)

	NOTE: VR battles do NOT affect morality. This will be integrated when we
	implement the VR system. For now, assume all battles are LIVE.
	"""
	if is_vr:
		print("[MoralitySystem] Skipping VR battle - no morality change")
		return

	# Get raw delta based on enemy type and outcome
	var raw_delta: int = 0

	match env_tag.to_lower():
		"regular":
			raw_delta = DELTA_REGULAR_NONLETHAL if not is_lethal else DELTA_REGULAR_LETHAL
		"elite":
			raw_delta = DELTA_ELITE_NONLETHAL if not is_lethal else DELTA_ELITE_LETHAL
		"boss":
			raw_delta = DELTA_BOSS_NONLETHAL if not is_lethal else DELTA_BOSS_LETHAL
		_:
			push_warning("[MoralitySystem] Unknown env_tag: %s" % env_tag)
			return

	var reason = "%s %s" % [env_tag, "pacified" if not is_lethal else "defeated"]
	apply_delta(raw_delta, reason)

func apply_delta(raw_delta: int, reason: String = "Unknown") -> void:
	"""
	Apply a morality delta with diminishing returns and daily cap

	Formula (§14.2):
	p_applied = sign(p) × floor(|p| × (1 - α × |M|/100) + 0.5)

	Args:
		raw_delta: Raw points before diminishing
		reason: Description for logging/UI
	"""
	# Check date reset first
	check_date_reset()

	# Apply diminishing returns (half-away-from-zero rounding)
	var factor: float = 1.0 - DIMINISH_ALPHA * abs(morality_meter) / 100.0
	var diminished: float = abs(raw_delta) * factor
	var applied_delta: int = sign(raw_delta) * int(floor(diminished + 0.5))

	# Check daily cap
	var new_daily_total = abs(_daily_delta_total + applied_delta)
	if new_daily_total > DAILY_CAP:
		var remaining = DAILY_CAP - abs(_daily_delta_total)
		applied_delta = sign(applied_delta) * remaining
		print("[MoralitySystem] Daily cap reached! Clamping delta from %d to %d" % [
			sign(raw_delta) * int(floor(diminished + 0.5)),
			applied_delta
		])

	if applied_delta == 0:
		print("[MoralitySystem] Delta too small or daily cap reached - no change")
		return

	# Store old values
	var old_meter = morality_meter
	var old_tier = get_current_tier()

	# Apply delta and clamp
	morality_meter = clamp(morality_meter + applied_delta, -100, 100)
	_daily_delta_total += applied_delta

	# Save to GameState
	_save_to_game_state()

	# Emit signals
	morality_changed.emit(old_meter, morality_meter, applied_delta, reason)

	var new_tier = get_current_tier()
	if new_tier != old_tier:
		var old_name = TIER_DATA[old_tier]["name"]
		var new_name = TIER_DATA[new_tier]["name"]
		tier_changed.emit(old_name, new_name)
		print("[MoralitySystem] TIER CHANGED: %s → %s" % [old_name, new_name])

	print("[MoralitySystem] %s: raw=%+d, applied=%+d, M=%d→%d (%s), daily=%d/%d" % [
		reason,
		raw_delta,
		applied_delta,
		old_meter,
		morality_meter,
		get_tier_name(),
		abs(_daily_delta_total),
		DAILY_CAP
	])

## ═══════════════════════════════════════════════════════════════
## TIER CALCULATION
## ═══════════════════════════════════════════════════════════════

func get_current_tier() -> MoralityTier:
	"""Get current morality tier based on meter value"""
	for tier in TIER_DATA:
		var data = TIER_DATA[tier]
		if morality_meter >= data["min"] and morality_meter <= data["max"]:
			return tier

	# Fallback (should never happen)
	return MoralityTier.N

func get_tier_name() -> String:
	"""Get current tier name as string"""
	return TIER_DATA[get_current_tier()]["name"]

func get_tier_color() -> Color:
	"""Get current tier color for UI"""
	return TIER_DATA[get_current_tier()]["color"]

## ═══════════════════════════════════════════════════════════════
## GAMEPLAY EFFECTS
## ═══════════════════════════════════════════════════════════════

func get_bind_ease_bonus() -> int:
	"""Get flat bonus to capture ItemMod from morality tier"""
	return TIER_DATA[get_current_tier()].get("bind_ease", 0)

func get_surrender_bonus() -> int:
	"""Get percentage bonus to enemy surrender chance"""
	return TIER_DATA[get_current_tier()].get("surrender_bonus", 0)

## ═══════════════════════════════════════════════════════════════
## DEBUGGING / TESTING
## ═══════════════════════════════════════════════════════════════

func debug_set_morality(value: int) -> void:
	"""DEBUG: Directly set morality value (for testing)"""
	var old_meter = morality_meter
	var old_tier = get_current_tier()

	morality_meter = clamp(value, -100, 100)
	_save_to_game_state()

	morality_changed.emit(old_meter, morality_meter, morality_meter - old_meter, "DEBUG")

	var new_tier = get_current_tier()
	if new_tier != old_tier:
		tier_changed.emit(TIER_DATA[old_tier]["name"], TIER_DATA[new_tier]["name"])

	print("[MoralitySystem] DEBUG: Set M to %d (%s)" % [morality_meter, get_tier_name()])

func debug_reset_daily_cap() -> void:
	"""DEBUG: Reset daily cap (for testing)"""
	_daily_delta_total = 0
	_save_to_game_state()
	print("[MoralitySystem] DEBUG: Reset daily cap")
