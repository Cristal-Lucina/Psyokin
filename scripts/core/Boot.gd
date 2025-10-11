extends Control
class_name Boot

const ROUTER_PATH: String = "/root/aSceneRouter"
const TITLE_SCENE: String = "res://scenes/main_menu/Title.tscn"

## Boot
## Minimal bootstrap node.
##
## Responsibility
## - Hands off to the SceneRouter (if autoloaded) to open the Title scene.
## - Falls back to `get_tree().change_scene_to_file()` if the router is missing.
##
## Why `call_deferred()`?
## - Switching scenes inside `_ready()` can mutate the scene tree while it’s
##   still being set up. Deferring lets autoloads/children finish initializing.

## Called when the node enters the scene tree.
## Defers main startup to `_go()` to avoid mutating the tree during `_ready()`.
func _ready() -> void:
	# Defer to next idle frame so autoloads are guaranteed ready.
	call_deferred("_go")

## Performs the actual handoff to the Title scene.
## Prefers the SceneRouter autoload if present; otherwise changes scene directly.
func _go() -> void:
	var router: Node = get_node_or_null(ROUTER_PATH)
	if router != null:
		# Use the autoloaded router (recommended path).
		aSceneRouter.goto_title()
	else:
		# Fallback: change scene directly.
		var err: int = get_tree().change_scene_to_file(TITLE_SCENE)
		if err != OK:
			push_error("Boot: failed to change scene to '%s' (code %d)" % [TITLE_SCENE, err])
