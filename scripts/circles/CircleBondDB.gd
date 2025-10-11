extends Node
class_name CircleBondDB

## CircleBondDB
## Loads Circle/Bond related CSV tables into in-memory dictionaries at startup.
## Expected to live as an autoload (e.g., `/root/aCircleBondDB`) so other systems
## can query characters, events, rewards, gifts, and flags quickly (O(1) lookups).
##
## CSV assumptions:
## - Files live under `res://data/circles/`
## - Each file has a header row and a primary-key column:
##   - characters → key: `circle_id`
##   - events     → key: `event_id`
##   - rewards    → key: `reward_id`
##   - gifts      → key: `gift_id`
##   - flags      → key: `flag_id`
## - `aCSVLoader.load_csv(path, key_field)` returns a Dictionary keyed by `key_field`.

## Character rows keyed by `circle_id`. Each row is a Dictionary of CSV columns.
var chars: Dictionary = {}     # id -> row

## Event rows keyed by `event_id`.
var events: Dictionary = {}    # event_id -> row

## Reward rows keyed by `reward_id`.
var rewards: Dictionary = {}   # id -> row

## Gift rows keyed by `gift_id`.
var gifts: Dictionary = {}     # id -> row

## Story/state flag rows keyed by `flag_id`.
var flags: Dictionary = {}     # id -> row

## On ready, load any circle-related CSVs that exist, using aCSVLoader.
## Missing files are silently skipped so development isn’t blocked.
func _ready() -> void:
	var loader := get_node_or_null("/root/aCSVLoader")
	if loader == null: return
	if FileAccess.file_exists("res://data/circles/circles_characters.csv"):
		chars = loader.load_csv("res://data/circles/circles_characters.csv", "circle_id")
	if FileAccess.file_exists("res://data/circles/circles_events.csv"):
		events = loader.load_csv("res://data/circles/circles_events.csv", "event_id")
	if FileAccess.file_exists("res://data/circles/circles_rewards.csv"):
		rewards = loader.load_csv("res://data/circles/circles_rewards.csv", "reward_id")
	if FileAccess.file_exists("res://data/circles/circles_gifts.csv"):
		gifts = loader.load_csv("res://data/circles/circles_gifts.csv", "gift_id")
	if FileAccess.file_exists("res://data/circles/circles_flags.csv"):
		flags = loader.load_csv("res://data/circles/circles_flags.csv", "flag_id")
