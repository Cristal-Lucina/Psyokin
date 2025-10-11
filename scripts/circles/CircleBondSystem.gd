extends Node
class_name CircleBondSystem

## CircleBondSystem
## Minimal Circle-Bond progression store.
## - `cbxp`: total Circle-Bond XP per circle (e.g., "art_club" → 42).
## - `levels`: derived levels per circle (hook up your thresholds later).
## 
## This system is intentionally dumb on purpose: it just stores numbers.
## Award logic (diminishing returns, bonuses) should happen elsewhere, then
## call `add_cbxp()` with the final amount.

## Total CBXP per circle_id (e.g., "art_club" → 42).
var cbxp: Dictionary = {}   # circle_id -> int

## Current level per circle_id (computed elsewhere, stored here).
var levels: Dictionary = {} # circle_id -> int (derived thresholds later)

## Adds CBXP to a circle (clamps negatives to 0) and returns the new total.
## 
## @param circle_id: String — which circle to modify.
## @param amount: int — amount to add (if negative, treated as 0).
## @return int — new total CBXP for this circle.
func add_cbxp(circle_id: String, amount: int) -> int:
	var base: int = int(cbxp.get(circle_id, 0))
	var delta: int = max(0, amount)
	var v: int = base + delta
	cbxp[circle_id] = v
	return v

## Reads the total CBXP for a circle.
##
## @param circle_id: String
## @return int — total CBXP (0 if none).
func get_cbxp(circle_id: String) -> int:
	return int(cbxp.get(circle_id, 0))

## Reads the current level for a circle (if you’re tracking levels).
##
## @param circle_id: String
## @return int — current level (0 if unset).
func get_level(circle_id: String) -> int:
	return int(levels.get(circle_id, 0))

## Placeholder for gating logic: determines if an event is available today.
## 
## @param _event_row: Dictionary — row from your events table (unused here).
## @param _ctx: Dictionary — caller context (stats/items/flags/etc., unused here).
## @return bool — always true (stub). Replace with real checks later.
func can_meet_today(_event_row: Dictionary, _ctx: Dictionary) -> bool:
	# Placeholder for gating logic; underscore params silence "unused" warnings.
	return true
