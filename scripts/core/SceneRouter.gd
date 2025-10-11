extends Node
class_name SceneRouter

## SceneRouter
## Small helper for switching between core scenes and opening popup scenes.
## Intended to be an autoload (e.g., `/root/aSceneRouter`) so any script can call:
## - `aSceneRouter.goto_title()`
## - `aSceneRouter.goto_main()`
## - `aSceneRouter.open_popup("res://path/to/Popup.tscn", optional_parent)`
##
## Notes
## - `goto_*` report errors if `change_scene_to_file` fails.
## - `open_popup` loads a PackedScene, instantiates it, and attaches it to
##   `parent` if provided, otherwise to the current scene. Logs failures.

## Switch to the Title scene.
## Logs an error if the scene change fails.
func goto_title() -> void:
	var err: int = get_tree().change_scene_to_file("res://scenes/main_menu/Title.tscn")
	if err != OK:
		push_error("SceneRouter: failed to change to Title.tscn (code %d)" % err)

## Switch to the Main game scene.
## Logs an error if the scene change fails.
func goto_main() -> void:
	var err: int = get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	if err != OK:
		push_error("SceneRouter: failed to change to Main.tscn (code %d)" % err)

## Load and attach a popup/control scene at runtime.
##
## @param scene_path: String — path to a `.tscn` that is a PackedScene.
## @param parent: Node (optional) — node to attach to; if null, uses current scene.
## @return Node — the instantiated node, or null if the PackedScene failed to load.
func open_popup(scene_path: String, parent: Node = null) -> Node:
	var ps: PackedScene = load(scene_path) as PackedScene
	if ps == null:
		push_error("SceneRouter: '%s' is not a PackedScene or failed to load." % scene_path)
		return null

	var inst: Node = ps.instantiate()
	var host: Node = parent if parent != null else get_tree().current_scene
	if host == null:
		push_error("SceneRouter: no valid parent to attach popup.")
		return inst

	host.add_child(inst)
	return inst
