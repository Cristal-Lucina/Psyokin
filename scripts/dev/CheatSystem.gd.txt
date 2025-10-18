extends Node
class_name CheatSystem

## CheatSystem (LXP/SXP/BPP)
## - Non-invasive debug helpers that call your existing autoloads if available.
## - Works even if some systems are missing (defensive "has_method" checks).
## - Recalculates HP/MP from doc formulas when level changes.
##
## Optional hotkeys (define in Project Settings → Input Map):
##   cheat_level_up_1      → +1 Level
##   cheat_level_up_5      → +5 Levels
##   cheat_add_bpp_1       → +1 Perk Point
##   cheat_add_sxp_brw_20  → +20 SXP to BRW  (similarly for vtl/tpo/fcs/mnd)
##
## You can also call functions directly from your dev console or UI:
##   aCheatSystem.cheat_add_lxp(600)               # inject LXP bucket
##   aCheatSystem.cheat_set_level(12)              # hard set level
##   aCheatSystem.cheat_add_sxp("MND", 50)         # stat XP
##   aCheatSystem.cheat_set_stat_level("TPO", 6)   # hard set stat level
##   aCheatSystem.cheat_add_bpp(3)                 # perk points

const HERO_PATH  := "/root/aHeroSystem"
const STATS_PATH := "/root/aStatsSystem"
const PERK_PATH  := "/root/aPerkSystem"
const GS_PATH    := "/root/aGameState"

# Persist the "fake LXP pool" in GameState.flags so it survives a save/load.
const FLAG_LXP_POOL := "CHEAT_LXP_POOL"

# --- lifecycle ---------------------------------------------------------------
func _ready() -> void:
	set_process_unhandled_input(true)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_echo(): return
	if Input.is_action_just_pressed("cheat_level_up_1"):
		cheat_set_level(_get_level() + 1)
	if Input.is_action_just_pressed("cheat_level_up_5"):
		cheat_set_level(_get_level() + 5)
	if Input.is_action_just_pressed("cheat_add_bpp_1"):
		cheat_add_bpp(1)
	# Example SXP hotkeys if you add them to InputMap:
	if Input.is_action_just_pressed("cheat_add_sxp_brw_20"):
		cheat_add_sxp("BRW", 20)
	if Input.is_action_just_pressed("cheat_add_sxp_vtl_20"):
		cheat_add_sxp("VTL", 20)
	if Input.is_action_just_pressed("cheat_add_sxp_tpo_20"):
		cheat_add_sxp("TPO", 20)
	if Input.is_action_just_pressed("cheat_add_sxp_fcs_20"):
		cheat_add_sxp("FCS", 20)
	if Input.is_action_just_pressed("cheat_add_sxp_mnd_20"):
		cheat_add_sxp("MND", 20)

# --- public API --------------------------------------------------------------
## Inject LXP using the doc formula XP_NEXT(L) = 120 + 30·L + 6·L²
## This keeps a small pool so partial injections carry over.
func cheat_add_lxp(amount: int, grant_perk_milestones: bool = true) -> void:
	if amount <= 0: return
	var pool := _get_lxp_pool() + amount
	var lvl  := _get_level()
	var gained_bpp := 0

	# Spend pool by crossing thresholds upward
	while pool >= _xp_next(lvl) and lvl < 99:
		pool -= _xp_next(lvl)
		var old := lvl
		lvl += 1
		if grant_perk_milestones:
			gained_bpp += int(floor(lvl / 3.0)) - int(floor(old / 3.0))
	_set_lxp_pool(pool)
	_set_level_and_recalc(lvl)

	if gained_bpp > 0:
		cheat_add_bpp(gained_bpp)

## Hard set level (awards any missed milestone perks automatically).
func cheat_set_level(new_level: int, grant_perk_milestones: bool = true) -> void:
	var cur := _get_level()
	new_level = clamp(new_level, 1, 99)
	_set_level_and_recalc(new_level)

	if grant_perk_milestones and new_level > cur:
		var gained_bpp := int(floor(new_level / 3.0)) - int(floor(cur / 3.0))
		if gained_bpp > 0:
			cheat_add_bpp(gained_bpp)

## Add SXP for a stat (BRW/VTL/TPO/FCS/MND). Uses your StatsSystem if present.
func cheat_add_sxp(stat: String, amount: int) -> void:
	var s := _stats()
	if s == null or amount == 0:
		return
	stat = stat.strip_edges().to_upper()
	# Common method names, try in order
	var calls := [
		"add_sxp", "grant_sxp", "add_stat_xp", "give_sxp", "debug_add_sxp", "cheat_add_sxp"
	]
	for m in calls:
		if s.has_method(m):
			s.call(m, stat, amount)
			return
	# Fallback: if there is a set_stat_level & get_stat_level path, approximate by level bumps
	if s.has_method("get_stat_level") and s.has_method("set_stat_level"):
		var before := int(s.call("get_stat_level", stat))
		var after  := before
		# crude: +amount // 50 as a default pace to move levels without knowing costs
		after = max(1, before + int(floor(amount / 50.0)))
		if after != before:
			s.call("set_stat_level", stat, after)

## Hard set a stat level.
func cheat_set_stat_level(stat: String, new_level: int) -> void:
	var s := _stats()
	if s == null: return
	stat = stat.strip_edges().to_upper()
	new_level = clamp(new_level, 1, 11)
	if s.has_method("set_stat_level"):
		s.call("set_stat_level", stat, new_level)
	elif s.has_method("debug_set_stat_level"):
		s.call("debug_set_stat_level", stat, new_level)

## Perk points (BPP)
func cheat_add_bpp(amount: int) -> void:
	if amount == 0: return
	var p := _perk()
	if p and p.has_method("add_points"):
		p.call("add_points", amount)
		return
	if p and p.has_method("add_perk_points"):
		p.call("add_perk_points", amount)
		return
	# Fallback: write into GameState.perk_points
	var gs := _gs()
	if gs != null:
		var cur_pp := 0
		if gs.has_method("get"): cur_pp = int(gs.get("perk_points"))
		gs.set("perk_points", max(0, cur_pp + amount))

# --- helpers -----------------------------------------------------------------
func _xp_next(level: int) -> int:
	return 120 + 30 * level + 6 * level * level

func _get_level() -> int:
	var h := _hero()
	if h == null:
		return 1
	var v: Variant = h.get("level")  # explicit Variant
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return int(v)
	return 1


func _set_level_and_recalc(level: int) -> void:
	var h := _hero()
	if h == null: return
	h.set("level", level)
	_recalc_hp_mp(h)
	# Nudge any UIs that listen to hero creation_applied
	if h.has_signal("creation_applied"):
		h.emit_signal("creation_applied")

func _recalc_hp_mp(h: Node) -> void:
	# MaxHP = 150 + (VTL × Level × 6)
	# MaxMP = 20  + (FCS × Level × 1.5)
	var lvl := int(h.get("level"))
	var vtl := _read_stat_level("VTL")
	var fcs := _read_stat_level("FCS")

	var hp_max := 150 + (vtl * lvl * 6)
	var mp_max := int(round(20.0 + float(fcs) * float(lvl) * 1.5))

	var hp_cur := int(h.get("hp"))
	var mp_cur := int(h.get("mp"))

	h.set("hp_max", hp_max)
	h.set("mp_max", mp_max)
	h.set("hp", clamp(hp_cur, 0, hp_max))
	h.set("mp", clamp(mp_cur, 0, mp_max))

func _read_stat_level(stat: String) -> int:
	var s := _stats()
	if s == null: return 1
	# Preferred: get_stat_level()
	if s.has_method("get_stat_level"):
		return int(s.call("get_stat_level", stat))
	# Fallback: get_stats_dict() / to_dict()
	var blob: Dictionary = {}
	if s.has_method("get_stats_dict"):
		var v1: Variant = s.call("get_stats_dict")
		if typeof(v1) == TYPE_DICTIONARY: blob = v1
	elif s.has_method("to_dict"):
		var v2: Variant = s.call("to_dict")
		if typeof(v2) == TYPE_DICTIONARY: blob = v2
	if not blob.is_empty():
		var rec_v: Variant = blob.get(stat, {})
		if typeof(rec_v) == TYPE_DICTIONARY:
			return int((rec_v as Dictionary).get("level", 1))
	return 1

func _get_lxp_pool() -> int:
	var gs := _gs()
	if gs == null:
		return 0
	var f_v: Variant = gs.get("flags") if gs.has("flags") else {}  # explicit Variant
	if typeof(f_v) == TYPE_DICTIONARY:
		var f: Dictionary = f_v
		return int(f.get(FLAG_LXP_POOL, 0))
	return 0


func _set_lxp_pool(v: int) -> void:
	var gs := _gs()
	if gs == null: return
	var f: Dictionary = {}
	if gs.has("flags") and typeof(gs.get("flags")) == TYPE_DICTIONARY:
		f = (gs.get("flags") as Dictionary).duplicate(true)
	f[FLAG_LXP_POOL] = max(0, v)
	gs.set("flags", f)

# --- autoload getters ---------------------------------------------------------
func _hero()  -> Node: return get_node_or_null(HERO_PATH)
func _stats() -> Node: return get_node_or_null(STATS_PATH)
func _perk()  -> Node: return get_node_or_null(PERK_PATH)
func _gs()    -> Node: return get_node_or_null(GS_PATH)
