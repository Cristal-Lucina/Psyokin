extends Node
class_name CBXPSystem

## CBXPSystem
## Lightweight Circle-Bond XP tracker.
## - Tracks total Circle Bond XP per circle (`cbxp`).
## - Tracks weekly action counts per circle (`weekly_actions`) for diminishing returns.
## - Emits `week_reset` when weekly counters are cleared.
##
## Typical use:
## ```
## var total := aCBXPSystem.add_cbxp("study_club", 5)  # returns new total for that circle
## ```

## Emitted when weekly action counters are cleared (e.g., at start of a new in-game week).
signal week_reset

## Total CBXP per circle_id.
var cbxp: Dictionary = {}

## Weekly action count per circle_id (drives diminishing returns).
var weekly_actions: Dictionary = {}

## After this many actions in a week for a given circle, gains are halved (min 1).
const WEEKLY_HALF_AFTER: int = 7

## Adds CBXP to a circle, applying weekly diminishing returns.
##
## After `WEEKLY_HALF_AFTER` actions in the same week for that circle,
## additional gains are halved (rounded down, minimum of 1).
##
## @param circle_id: String — Identifier for the circle (e.g., "art_club").
## @param base_amount: int — Raw CBXP to add (negative values are treated as 0).
## @return int — The new **total** CBXP for that circle.
func add_cbxp(circle_id: String, base_amount: int) -> int:
	var amt: int = base_amount
	if amt < 0:
		amt = 0

	var acts: int = int(weekly_actions.get(circle_id, 0))
	if acts >= WEEKLY_HALF_AFTER:
		# Halve the gain with floor, but never below 1.
		var halved: int = int(floor(float(amt) * 0.5))
		if halved < 1:
			halved = 1
		amt = halved

	weekly_actions[circle_id] = acts + 1

	var prev: int = int(cbxp.get(circle_id, 0))
	var total: int = prev + amt
	cbxp[circle_id] = total
	return total

## Returns the **total** CBXP for a circle.
##
## @param circle_id: String
## @return int — Total CBXP accumulated for this circle (0 if none).
func get_cbxp(circle_id: String) -> int:
	return int(cbxp.get(circle_id, 0))

## Clears all weekly action counters and emits `week_reset`.
func reset_week() -> void:
	weekly_actions.clear()
	emit_signal("week_reset")
