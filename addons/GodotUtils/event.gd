extends RefCounted
class_name GameEvent

## An event object carrying an event name and associated data.
## Used with GameEventCenter for event dispatching.

var name: StringName:
	set(v):
		pass
	get:
		return _name

var data:
	set(v):
		pass
	get:
		return _data

var event_center: GameEventCenter:
	set(v):
		pass
	get:
		return _event_center.get_ref()

var _name: StringName
var _data: Variant
var _event_center: WeakRef

## Creates a new GameEvent with the specified name and data.
## @param n: The StringName identifier for this event.
## @param d: The optional data payload for this event.
func _init(n: StringName, d: Variant) -> void:
	_name = n
	_data = d

## Returns a string representation of this event.
## @return: String in format "GameEvent("<name>", <data>)".
func _to_string() -> String:
	return "GameEvent(\"%s\", %s)" % [_name, _data]
