extends RefCounted
class_name ECSWorld

const VERSION = "1.0.0"

var debug_print: bool		# ecs logging
var debug_entity: bool:		# for entity debugging
	set(v):
		debug_entity = v
		_create_entity_callback = _create_debug_entity if v else _create_common_entity

var ignore_notify_log: Dictionary # ignore notify log

signal on_system_viewed(name: StringName, components: Array)
signal on_update(delta: float)

var _name: StringName

var _entity_id: int = 0xFFFFFFFF
var _entity_pool: Dictionary
var _system_pool: Dictionary
var _event_pool := GameEventCenter.new()

var _type_component_dict: Dictionary
var _entity_component_dict: Dictionary

func _init(name := "ECSWorld") -> void:
	_name = name
	debug_entity = false
	
# ==============================================================================
# public
func name() -> StringName:
	return _name
	
func clear() -> void:
	remove_all_systems()
	remove_all_entities()
	
# user valid entity id (0x1 ~ 0xFFFFFFFF)
func create_entity(id: int = 0) -> ECSEntity:
	assert(id >= 0 and id <= 0xFFFFFFFF, "create_entity invalid id!")
	var eid: int = id if id >= 1 else _entity_id + 1
	if id == 0:
		_entity_id += 1
	remove_entity(eid)
	return _create_entity(eid)
	
func remove_entity(entity_id: int) -> bool:
	if not remove_all_components(entity_id):
		return false
	if debug_print:
		print("entity <%s:%d> destroyed." % [_name, entity_id])
	_entity_component_dict.erase(entity_id)
	return _entity_pool.erase(entity_id)
	
func remove_all_entities() -> bool:
	for entity_id: int in _entity_pool.keys():
		remove_entity(entity_id)
	_entity_id = 0xFFFFFFFF
	return true
	
func get_entity(id: int) -> ECSEntity:
	return _entity_pool.get(id)
	
func get_entity_keys() -> Array:
	return _entity_pool.keys()
	
func has_entity(id: int) -> bool:
	return _entity_pool.has(id)
	
func add_component(entity_id: int, name: StringName, component := ECSComponent.new()) -> bool:
	assert(component._world == null)
	if not _add_entity_component(entity_id, name, component):
		return false
	component._name = name
	component._entity = get_entity(entity_id)
	component._set_world(self)
	if debug_print:
		print("component <%s:%s> add to entity <%d>." % [_name, name, entity_id])
	# 实体组件添加信号
	var entity: ECSEntity = component._entity
	entity.on_component_added.emit(entity, component)
	return true
	
func remove_component(entity_id: int, name: StringName) -> bool:
	var c: ECSComponent = get_component(entity_id, name)
	if not c or not _remove_entity_component(entity_id, name):
		return false
	if debug_print:
		print("component <%s:%s> remove from entity <%d>." % [_name, name, entity_id])
	# 实体组件移除信号
	var entity: ECSEntity = c._entity
	entity.on_component_removed.emit(entity, c)
	return true
	
func remove_all_components(entity_id: int) -> bool:
	if not has_entity(entity_id):
		return false
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	for key: StringName in entity_dict.keys():
		remove_component(entity_id, key)
	return true
	
func get_component(entity_id: int, name: StringName) -> ECSComponent:
	if not has_entity(entity_id):
		return null
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	if entity_dict.has(name):
		return entity_dict[name]
	return null
	
func get_components(entity_id: int) -> Array:
	if not has_entity(entity_id):
		return []
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	return entity_dict.values()
	
func get_component_keys() -> Array:
	return _type_component_dict.keys()
	
func has_component(entity_id: int, name: StringName) -> bool:
	if not has_entity(entity_id):
		return false
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	return entity_dict.has(name)
	
func view(name: StringName, filter := Callable()) -> Array:
	if not _type_component_dict.has(name):
		return []
	var values: Array = _type_component_dict[name].values()
	return values.filter(filter) if filter.is_valid() else values
	
func multi_view(names: Array, filter := Callable()) -> Array:
	var views: Array = view(names.front())
	if views.is_empty():
		return []
	views = views.filter(func(c: ECSComponent):
		return names.all(func(key: StringName):
			return has_component(c.entity().id(), key)
		)
	)
	views = views.map(func(c: ECSComponent):
		return _get_satisfy_components(c.entity(), names)
	)
	return views.filter(filter) if filter.is_valid() else views
	
func add_system(name: StringName, system: ECSSystem) -> bool:
	remove_system(name)
	_system_pool[name] = system
	system._set_name(name)
	system._set_world(self)
	set_system_update(name, true)
	system.on_enter(self)
	return true
	
func remove_system(name: StringName) -> bool:
	if not _system_pool.has(name):
		return false
	set_system_update(name, false)
	_system_pool[name].on_exit(self)
	return _system_pool.erase(name)
	
func remove_all_systems() -> bool:
	for name: StringName in _system_pool.keys():
		remove_system(name)
	return true
	
func get_system(name: StringName) -> ECSSystem:
	if not _system_pool.has(name):
		return null
	return _system_pool[name]
	
func get_system_keys() -> Array:
	return _system_pool.keys()
	
func has_system(name: StringName) -> bool:
	return _system_pool.has(name)
	
func add_callable(name: StringName, c: Callable) -> void:
	_event_pool.add_callable(name, c)
	
func remove_callable(name: StringName, c: Callable) -> void:
	_event_pool.remove_callable(name, c)
	
func notify(event_name: StringName, value: Variant = null) -> void:
	if debug_print and not ignore_notify_log.has(event_name):
		print('notify <%s> "%s", %s.' % [_name, event_name, value])
	_event_pool.notify(event_name, value)
	
func send(e: GameEvent) -> void:
	if debug_print and not ignore_notify_log.has(e.name):
		print('send <%s> "%s", %s.' % [_name, e.name, e.data])
	_event_pool.send(e)
	
func update(delta: float) -> void:
	on_update.emit(delta)
	
func set_system_update(name: StringName, enable: bool) -> void:
	var system := get_system(name)
	if system == null or not system.has_method("_on_update"):
		return
	if enable:
		if not on_update.is_connected(system._on_update):
			on_update.connect(system._on_update)
	else:
		if on_update.is_connected(system._on_update):
			on_update.disconnect(system._on_update)
	
func is_system_updating(name: StringName) -> bool:
	var system := get_system(name)
	if system == null or not system.has_method("_on_update"):
		return false
	return on_update.is_connected(system._on_update)
	
# ==============================================================================
# private
func _get_type_list(name: StringName) -> Dictionary:
	if not _type_component_dict.has(name):
		_type_component_dict[name] = {}
	return _type_component_dict[name]
	
func _get_satisfy_components(e: ECSEntity, names: Array) -> Dictionary:
	var result := {
		"entity": e,
	}
	for c: ECSComponent in names.map(func(key: StringName):
		return get_component(e.id(), key)
	):
		result.set(c.name(), c)
	return result
	
func _add_entity_component(entity_id: int, name: StringName, component: ECSComponent) -> bool:
	if not has_entity(entity_id):
		return false
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	entity_dict[name] = component
	var type_list: Dictionary = _get_type_list(name)
	type_list[entity_id] = component
	return true
	
func _remove_entity_component(entity_id: int, name: StringName) -> bool:
	if not has_entity(entity_id):
		return false
	var type_list: Dictionary = _type_component_dict[name]
	type_list.erase(entity_id)
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	return entity_dict.erase(name)
	
func _create_entity(eid: int) -> ECSEntity:
	var e := _create_entity_callback.call(eid)
	_entity_pool[eid] = e
	_entity_component_dict[eid] = {}
	if debug_print:
		print("entity <%s:%d> created." % [_name, eid])
	return e
	
var _create_entity_callback: Callable
	
func _create_common_entity(id: int) -> ECSEntity:
	return ECSEntity.new(id, self)
	
func _create_debug_entity(id: int) -> ECSEntity:
	return DebugEntity.new(id, self)
	
# ==============================================================================
func create_scheduler(name: StringName, threads_size: int = -1) -> ECSScheduler:
	assert(not _scheduler_pool.has(name))
	var result := ECSScheduler.new(self, threads_size)
	_scheduler_pool[name] = result
	return result
	
func destroy_scheduler(name: StringName) -> bool:
	if not _scheduler_pool.has(name):
		return false
	var scheduler := _scheduler_pool[name]
	scheduler.clear()
	scheduler._world = null
	_scheduler_pool.erase(name)
	return true
	
func get_scheduler(name: StringName) -> ECSScheduler:
	return _scheduler_pool.get(name)
	
var _scheduler_pool: Dictionary[StringName, ECSScheduler]
	
