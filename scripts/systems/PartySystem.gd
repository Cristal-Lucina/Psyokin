extends Node
class_name PartySystem

signal party_changed()
signal member_added(member_name: String)
signal member_removed(member_name: String)

const DEFAULT_MAX_SIZE: int = 4

var _max_party_size: int = DEFAULT_MAX_SIZE
var _party_order: PackedStringArray = PackedStringArray()  # ordered list of member names

func _ready() -> void:
	"""
	Called when the node is added to the scene.
	No-op placeholder to keep structure consistent.
	"""
	pass


func get_party_names() -> PackedStringArray:
	"""
	Return a copy of the current party (ordered).
	"""
	return _party_order.duplicate()


func set_party(new_party: PackedStringArray) -> void:
	"""
	Replace the party with up to _max_party_size unique, non-empty names.
	Emits party_changed().
	"""
	var cleaned: PackedStringArray = PackedStringArray()
	for nm in new_party:
		var member_name: String = String(nm)
		if member_name != "" and cleaned.find(member_name) < 0:
			cleaned.append(member_name)
		if cleaned.size() >= _max_party_size:
			break
	_party_order = cleaned
	party_changed.emit()


func add_member(member_name: String) -> bool:
	"""
	Add a member to the end of the party if not present and capacity allows.
	Emits member_added() and party_changed() on success.
	"""
	if member_name == "":
		return false
	if _party_order.find(member_name) >= 0:
		return false
	if _party_order.size() >= _max_party_size:
		return false
	_party_order.append(member_name)
	member_added.emit(member_name)
	party_changed.emit()
	return true


func remove_member(member_name: String) -> bool:
	"""
	Remove a member by exact name match.
	Emits member_removed() and party_changed() on success.
	"""
	var idx: int = _party_order.find(member_name)
	if idx < 0:
		return false
	_party_order.remove_at(idx)
	member_removed.emit(member_name)
	party_changed.emit()
	return true


func clear_party() -> void:
	"""
	Remove all party members and emit party_changed().
	"""
	_party_order.clear()
	party_changed.emit()


func swap_members(a_index: int, b_index: int) -> bool:
	"""
	Swap two members by index. Emits party_changed() on success.
	"""
	if a_index < 0 or a_index >= _party_order.size():
		return false
	if b_index < 0 or b_index >= _party_order.size():
		return false
	var temp: String = _party_order[a_index]
	_party_order[a_index] = _party_order[b_index]
	_party_order[b_index] = temp
	party_changed.emit()
	return true


func set_max_party_size(new_size: int) -> void:
	"""
	Set the max party size (min 1). Truncates party if needed, emits party_changed().
	"""
	_max_party_size = max(1, new_size)
	while _party_order.size() > _max_party_size:
		_party_order.remove_at(_party_order.size() - 1)
	party_changed.emit()


func get_max_party_size() -> int:
	"""
	Return the current max party size cap.
	"""
	return _max_party_size


func index_of(member_name: String) -> int:
	"""
	Return the index of a member, or -1 if not in the party.
	"""
	return _party_order.find(member_name)
