extends RefCounted
class_name ECSSchedulerCommandsTest

const Commands = preload("scheduler_commands.gd")

var _world: ECSWorld
var _commands: Commands

func run() -> void:
	print_rich("[b][color=yellow]--- Starting ECSSchedulerCommands Test ---[/color][/b]")
	
	_setup()
	_test_spawn_chain()
	
	_setup()
	_test_entity_modification()
	
	_setup()
	_test_destroy_entity()
	
	_setup()
	_test_event_batching()
	
	_setup()
	_test_command_merge()
	
	print_rich("[b][color=green]--- All Tests Passed Successfully! ---[/color][/b]")
	print("")

# ==============================================================================
# Setup & Helpers
# ==============================================================================

func _setup() -> void:
	if _world:
		_world.clear()
	_world = ECSWorld.new("TestWorld")
	# 确保关闭 debug_print，除非你需要调试
	_world.debug_print = false 
	_commands = Commands.new()

func _assert(condition: bool, msg: String) -> void:
	if not condition:
		print_rich("[b][color=red][FAIL] %s[/color][/b]" % msg)
		# 打印堆栈以便定位
		print_stack()
		# 可以在这里暂停或抛出错误
		assert(condition, msg)
	else:
		print("[PASS] %s" % msg)

# ==============================================================================
# Test Cases
# ==============================================================================

func _test_spawn_chain() -> void:
	print_rich("[color=cyan]> Testing Spawn Chain (OP_SPAWN + OP_ADD_TO_NEW)[/color]")
	
	_commands.spawn()\
		.add_component("Health", ECSDataComponent.new(100))\
		.add_component("Position", ECSComponent.new())
	
	_assert(_commands.is_empty() == false, "Commands stream should not be empty")
	_commands.flush(_world)
	
	var entities = _world.get_entity_keys()
	_assert(entities.size() == 1, "World should have exactly 1 entity")
	if entities.size() > 0:
		var eid = entities[0]
		var e = _world.get_entity(eid)
		_assert(e.has_component("Health"), "Entity should have 'Health' component")
		_assert(e.has_component("Position"), "Entity should have 'Position' component")
		if e.has_component("Health"):
			var hp_comp = e.get_component("Health") as ECSDataComponent
			_assert(hp_comp.data == 100, "Health data should be 100")
	
	_assert(_commands.is_empty() == true, "Commands should be empty after flush")

func _test_entity_modification() -> void:
	print_rich("[color=cyan]> Testing Entity Modification (OP_ADD_COMP / OP_RM_COMP)[/color]")
	
	var e = _world.create_entity()
	e.add_component("OldComp", ECSComponent.new())
	var eid = e.id()
	
	_commands.entity(eid)\
		.add_component("NewComp", ECSDataComponent.new("new_data"))\
		.remove_component("OldComp")
		
	_commands.flush(_world)
	
	_assert(e.has_component("NewComp"), "Entity should have 'NewComp'")
	_assert(not e.has_component("OldComp"), "Entity should NOT have 'OldComp'")
	
	if e.has_component("NewComp"):
		var new_comp = e.get_component("NewComp") as ECSDataComponent
		_assert(new_comp.data == "new_data", "NewComp data verification")

func _test_destroy_entity() -> void:
	print_rich("[color=cyan]> Testing Destroy Entity (OP_DESTROY)[/color]")
	
	var e1 = _world.create_entity()
	var e2 = _world.create_entity()
	
	_commands.entity(e1.id()).destroy()
	_commands.flush(_world)
	
	_assert(not _world.has_entity(e1.id()), "Entity 1 should be destroyed")
	_assert(_world.has_entity(e2.id()), "Entity 2 should still exist")

func _test_event_batching() -> void:
	print_rich("[color=cyan]> Testing Event Batching & Notification[/color]")
	
	# 使用字典或数组包装计数器，避免 Lambda 捕获基础类型的潜在问题
	var context = {
		"count": 0,
		"values": []
	}
	
	var callback = func(e: GameEvent):
		context.count += 1
		context.values.append(e.data)
		# print("Callback fired! Data: ", e.data) # Debug print
		
	_world.add_callable("test_event", callback)
	
	_commands.notify("test_event", 10)
	_commands.notify("other_event", "ignore me")
	_commands.notify("test_event", 20)
	_commands.notify("test_event", 30)
	
	_assert(context.count == 0, "Events should not fire before flush")
	
	_commands.flush(_world)
	
	# 如果这里失败，打印实际值
	if context.count != 3:
		print_rich("[color=red]Actual count: %d, Values: %s[/color]" % [context.count, str(context.values)])
	
	_assert(context.count == 3, "Should receive exactly 3 'test_event' callbacks")
	_assert(context.values == [10, 20, 30], "Event values should preserve order")
	
	_world.remove_callable("test_event", callback)

func _test_command_merge() -> void:
	print_rich("[color=cyan]> Testing Command Merge (Thread Simulation)[/color]")
	
	var cmd_thread_a = Commands.new()
	cmd_thread_a.spawn().add_component("ThreadA", ECSComponent.new())
	cmd_thread_a.notify("thread_event", "A")
	
	var cmd_thread_b = Commands.new()
	cmd_thread_b.spawn().add_component("ThreadB", ECSComponent.new())
	cmd_thread_b.notify("thread_event", "B")
	
	_commands.merge(cmd_thread_a)
	_commands.merge(cmd_thread_b)
	
	# 同样使用 context 包装
	var context = { "events": [] }
	_world.add_callable("thread_event", func(e): context.events.append(e.data))
	
	_commands.flush(_world)
	
	var entities = _world.get_entity_keys()
	_assert(entities.size() == 2, "Should have 2 entities from merged commands")
	
	var found_a = false
	var found_b = false
	for eid in entities:
		if _world.has_component(eid, "ThreadA"): found_a = true
		if _world.has_component(eid, "ThreadB"): found_b = true
	
	_assert(found_a and found_b, "Should find components from both threads")
	_assert(context.events.size() == 2, "Should receive 2 merged events")
	# 合并顺序通常是 A 然后 B，但也取决于 merge 调用的顺序
	if context.events.size() >= 2:
		_assert(context.events[0] == "A" and context.events[1] == "B", "Merged events order check")
