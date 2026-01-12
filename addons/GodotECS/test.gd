extends RefCounted
class_name ECSTest

var _world := ECSWorld.new("ECSWorld_test")
var _entity: ECSEntity

func _init() -> void:
	_world.debug_print = true
	_test_entity()
	_test_component()
	_test_system()
	_test_remove_component()
	_test_remove_entity()
	_test_remove_system()
	_mixed_test()
	_test_snapshot()
	_test_event()
	_test_update()
	
	ECSSchedulerCommandsTest.new().run()
	
func queue_free() -> void:
	_entity = null
	_world.clear()
	
func _test_entity() -> void:
	_entity = _world.create_entity()
	
	var e: ECSEntity = _world.get_entity(_entity.id())
	printt("entity id is equality:", e.id() == _entity.id())
	
	print("")
	
func _test_component() -> void:
	_entity.add_component("c1", ECSComponent.new())
	_entity.add_component("c2", ECSComponent.new())
	_entity.add_component("c3", ECSComponent.new())
	_entity.add_component("c4", ECSDataComponent.new(11))
	_entity.add_component("c5", ECSViewComponent.new(null))
	print("")
	
func _test_system() -> void:
	_world.add_system("s1", ECSSystem.new())
	_world.add_system("s2", ECSSystem.new())
	_world.add_system("s2", ECSSystem.new())
	_world.add_system("s3", ECSSystem.new())
	print("")
	
func _test_remove_component() -> void:
	_entity.remove_component("c1")
	_entity.remove_component("c3")
	
	var list: Array = _entity.get_components()
	print("entity component list:")
	for c: ECSComponent in list:
		print("component [%s]" % c)
	print("")
	
func _test_remove_entity() -> void:
	_entity.destroy()
	
	var entity_id_list: Array = _world.get_entity_keys()
	print("entity id list:")
	if entity_id_list.is_empty():
		print("entity id list is empty.")
	else:
		for entity_id: int in entity_id_list:
			print("entity id [%d]" % entity_id)
	var component_list: Array = _world.view("c2")
	print("component list:")
	if component_list.is_empty():
		print("component list is empty.")
	else:
		for c: ECSComponent in component_list:
			print("component [%s]" % c)
	print("")
	
func _test_remove_system() -> void:
	_world.remove_system("s1")
	_world.remove_system("s3")
	printt("system list:", _world.get_system_keys())
	print("")
	
func _mixed_test() -> void:
	var e: ECSEntity = _world.create_entity()
	e.add_component("c1", ECSComponent.new())
	e.add_component("c2", ECSComponent.new())
	e.add_component("c3", ECSComponent.new())
	
	_entity = _world.create_entity()
	_entity.add_component("c1", ECSComponent.new())
	_entity.add_component("c2", ECSComponent.new())
	_entity.add_component("c3", ECSComponent.new())
	_world.add_system("s1", ECSSystem.new())
	
	var component_list: Array = _world.view("c1")
	print("mixed test component list:")
	for c: ECSComponent in component_list:
		print("component [%s] entity [%d]" % [c.name(), c.entity().id()])
	
	component_list = _world.view("c1", func(c: ECSComponent) -> bool:
		return false)
	printt("view component list with filter:", component_list)
	
	printt("mixed test system list:", _world.get_system_keys())
	printt("multi view list:", _world.multi_view(["c1", "c2"]))
	printt("multi view list with filter:", _world.multi_view(["c1", "c2"], func(dict: Dictionary) -> bool:
		return false))
	
func _test_snapshot() -> void:
	var packer := ECSWorldPacker.new(_world)
	var pack := packer.pack()
	print("\nworld snapshot:")
	print(pack.data())
	
	print("\nworld snapshot with filter:")
	var empty_packer := ECSWorldPacker.new(_world, ["must_saved"])
	print(empty_packer.pack().data())
	
	print("\nworld restore:")
	print(packer.unpack(pack))
	
	print("")
	
class _event_tester extends ECSSystem:
	func _on_enter(w: ECSWorld) -> void:
		w.add_callable("test", _on_event)
	func _on_exit(w: ECSWorld) -> void:
		w.remove_callable("test", _on_event)
	func _on_event(e: GameEvent) -> void:
		printt("system [%s] on event [%s] with param [%s]" % [self.name(), e.name, e.data])
	
class _callable_event_tester extends  ECSSystem:
	func _on_enter(w: ECSWorld) -> void:
		w.add_callable("test", _on_event)
	func _on_exit(w: ECSWorld) -> void:
		w.remove_callable("test", _on_event)
	func _on_event(e: GameEvent) -> void:
		printt("system [%s] on event [%s] with param [%s]" % [self.name(), e.name, e.data])
	
func _test_event() -> void:
	print("begin test add_listener for event:")
	_world.add_system("test_event_system", _event_tester.new())
	_world.notify("test", "hello test event.")
	_world.remove_system("test_event_system")
	_world.notify("test", "hello test event.")
	
	print("\nbegin test add_callable for event:")
	_world.add_system("test_event_system", _callable_event_tester.new())
	_world.notify("test", "hello test event.")
	_world.remove_system("test_event_system")
	_world.notify("test", "hello test event.")
	
	print("")
	
class _system_update extends ECSSystem:
	func _on_update(delta: float) -> void:
		print("system on update.")
	
func _test_update() -> void:
	_world.add_system("update_system", _system_update.new())
	_world.update(1/60.0)
	_world.set_system_update("update_system", false)
	_world.update(1/60.0)
	_world.remove_system("update_system")
	
