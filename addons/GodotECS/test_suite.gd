extends RefCounted
class_name ECSTestSuite

# ==============================================================================
# Test Runner & Helpers
# ==============================================================================

const ECSSchedulerCommands = ECSParallel.Commands

var _world: ECSWorld
var _fail_count: int = 0
var _pass_count: int = 0

func run() -> void:
	print_rich("[b][color=yellow]=== Starting ECS Framework Full Test Suite ===[/color][/b]")
	_fail_count = 0
	_pass_count = 0
	
	# Execute each test module
	_run_test("Entity & Component CRUD", _test_entity_component_crud)
	_run_test("Query System (With/Without/AnyOf)", _test_query_system)
	_run_test("Query Cache Reactive", _test_query_cache_reactive)
	_run_test("Event System", _test_events)
	_run_test("Command Buffer", _test_commands)
	_run_test("Command Buffer Defer", _test_commands_defer)
	_run_test("Scheduler & Parallel Systems", _test_scheduler_dependency)
	_run_test("Serialization (Pack/Unpack)", _test_serialization)
	_run_test("ECSRunner System Management", _test_runner_system_management)
	_run_test("ECSRunner Update Control", _test_runner_update_control)
	_run_test("ECSRunner Lifecycle", _test_runner_lifecycle)
	_run_test("ECSRunner Edge Cases", _test_runner_edge_cases)
	
	print_rich("[b]--------------------------------------------------[/b]")
	if _fail_count == 0:
		print_rich("[b][color=green]ALL TESTS PASSED! (%d/%d)[/color][/b]" % [_pass_count, _pass_count])
	else:
		print_rich("[b][color=red]SOME TESTS FAILED! (Passed: %d, Failed: %d)[/color][/b]" % [_pass_count, _fail_count + _pass_count])
	
	_teardown()

func _setup() -> void:
	if _world:
		_world.clear()
	_world = ECSWorld.new("TestWorld")
	# Disable internal debug print to keep test output clean, unless you need to debug the framework itself
	_world.debug_print = false 

func _teardown() -> void:
	if _world:
		_world.clear()
		_world = null

func _run_test(test_name: String, test_func: Callable) -> void:
	print_rich("[color=cyan]> Running: %s...[/color]" % test_name)
	_setup()
	test_func.call()
	# Explicit cleanup to prevent state pollution
	_teardown() 

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		# Don't print on success to reduce clutter
		# print("  [OK] %s" % msg) 
	else:
		_fail_count += 1
		print_rich("  [b][color=red][FAIL] %s[/color][/b]" % msg)
		print_stack()

# ==============================================================================
# Mock Data (Inner Classes)
# ==============================================================================

# Define some test components
class CompHealth extends ECSDataComponent: pass
class CompMana extends ECSDataComponent: pass
class CompPos extends ECSComponent: 
	var x: int = 0
	var y: int = 0
	# Must override pack/unpack for serialization tests
	func _on_pack(ar: Serializer.Archive) -> void:
		ar.set_var("x", x)
		ar.set_var("y", y)
	func _on_unpack(ar: Serializer.Archive) -> void:
		x = ar.get_var("x", 0)
		y = ar.get_var("y", 0)

# Mock system for testing ECSRunner
class MockSystem extends ECSSystem:
	var update_count: int = 0
	var enter_called: bool = false
	var exit_called: bool = false
	var test_data: Dictionary = {}
	
	func _on_enter(w: ECSWorld) -> void:
		enter_called = true
	
	func _on_exit(w: ECSWorld) -> void:
		exit_called = true
	
	func _on_update(delta: float) -> void:
		update_count += 1

# Mock system without _on_update for edge case testing
class SystemNoUpdate extends ECSSystem:
	pass

# ==============================================================================
# Test Cases
# ==============================================================================

func _test_entity_component_crud() -> void:
	var e = _world.create_entity()
	var eid = e.id()
	
	_assert(_world.has_entity(eid), "Entity should exist in world")
	
	# Add Components
	e.add_component("Health", CompHealth.new(100))
	e.add_component("Pos", CompPos.new())
	
	_assert(e.has_component("Health"), "Entity should have Health")
	_assert(e.has_component("Pos"), "Entity should have Pos")
	_assert(not e.has_component("Mana"), "Entity should not have Mana")
	
	# Check Data
	var hp = e.get_component("Health") as CompHealth
	_assert(hp.data == 100, "Health data value check")
	
	# Update Data
	hp.set_data(50)
	_assert((e.get_component("Health") as CompHealth).data == 50, "Health data update check")
	
	# Remove Component
	e.remove_component("Health")
	_assert(not e.has_component("Health"), "Health component should be removed")
	_assert(e.has_component("Pos"), "Pos component should remain")
	
	# Destroy Entity
	e.destroy()
	_assert(not _world.has_entity(eid), "Entity should be removed from world")
	_assert(not e.valid(), "Entity wrapper should report invalid")

func _test_query_system() -> void:
	# Setup Data:
	# E1: [Health, Pos]
	# E2: [Health, Mana]
	# E3: [Pos, Mana]
	# E4: [Health]
	
	var e1 = _world.create_entity()
	e1.add_component("Health", CompHealth.new(10)); e1.add_component("Pos", CompPos.new())
	
	var e2 = _world.create_entity()
	e2.add_component("Health", CompHealth.new(20)); e2.add_component("Mana", CompMana.new(20))
	
	var e3 = _world.create_entity()
	e3.add_component("Pos", CompPos.new()); e3.add_component("Mana", CompMana.new(30))
	
	var e4 = _world.create_entity()
	e4.add_component("Health", CompHealth.new(40))
	
	# 1. Test View (Single Component)
	var healths = _world.view("Health")
	_assert(healths.size() == 3, "View('Health') should return 3 components")
	
	# 2. Test Multi View (AND logic - Cache check)
	var health_pos = _world.multi_view(["Health", "Pos"])
	_assert(health_pos.size() == 1, "MultiView(['Health', 'Pos']) should return 1 result (E1)")
	if not health_pos.is_empty():
		_assert(health_pos[0].entity.id() == e1.id(), "MultiView result validation")
		
	# 3. Test Complex Query (With + Without)
	# Find entities with Health but WITHOUT Pos -> E2, E4
	var res_without = _world.query().with(["Health"]).without(["Pos"]).exec()
	_assert(res_without.size() == 2, "Query With(Health) Without(Pos) count check")
	
	# 4. Test AnyOf (OR logic)
	# Find entities with Pos OR Mana -> E1, E2, E3
	var res_any = _world.query().any_of(["Pos", "Mana"]).exec()
	_assert(res_any.size() == 3, "Query AnyOf(Pos, Mana) count check")
	
	# 5. Test Filter
	# Find Health > 15 -> E2 (20), E4 (40)
	var res_filter = _world.query().with(["Health"]).filter(func(data):
		return data["Health"].data > 15
	).exec()
	_assert(res_filter.size() == 2, "Query Filter check")

func _test_query_cache_reactive() -> void:
	# --- 1. Initialize environment ---
	var e = _world.create_entity()
	e.add_component("Health", CompHealth.new(10))
	# At this point e only has Health

	# --- 2. Build cache (Cache Miss -> Build) ---
	# We query entities with both [Health, Pos]
	# Result should be empty at this point
	var cache_view = _world.multi_view(["Health", "Pos"])
	_assert(cache_view.is_empty(), "Cache should be empty initially")

	# --- 3. Test: Dynamic component addition (Add -> Cache Update) ---
	# Add Pos to e so it satisfies [Health, Pos] condition
	e.add_component("Pos", CompPos.new())

	# Get cache result again (note: multi_view returns same Array reference)
	# Key point: We should NOT recreate query, check if previous view updated
	var cache_view_after_add = _world.multi_view(["Health", "Pos"])

	_assert(cache_view_after_add.size() == 1, "Cache should update after adding component")
	_assert(cache_view_after_add[0].entity.id() == e.id(), "Entity should appear in cache")

	# --- 4. Test: Dynamic component removal (Remove -> Cache Update) ---
	# Remove Pos, e no longer satisfies condition
	e.remove_component("Pos")

	_assert(cache_view_after_add.is_empty(), "Cache should clear after removing component")

	# --- 5. Test: Entity destruction (Destroy -> Cache Update) ---
	# Add it back first so it enters cache again
	e.add_component("Pos", CompPos.new())
	_assert(cache_view_after_add.size() == 1, "Entity re-added")

	# Destroy entity
	e.destroy()

	_assert(cache_view_after_add.is_empty(), "Cache should clear after destroying entity")

func _test_events() -> void:
	var test_data := {
		"received_count": 0,
		"last_msg": "",
	}
	
	var callback = func(e: GameEvent):
		test_data.received_count += 1
		test_data.last_msg = e.data
		
	_world.add_callable("test_event", callback)
	
	_world.notify("test_event", "hello")
	_world.notify("test_event", "world")
	_world.notify("other_event", "ignore")
	
	_assert(test_data.received_count == 2, "Should receive 2 test_events")
	_assert(test_data.last_msg == "world", "Order of events check")
	
	_world.remove_callable("test_event", callback)
	_world.notify("test_event", "again")
	_assert(test_data.received_count == 2, "Should stop receiving after remove")

func _test_commands() -> void:
	var cmds = ECSSchedulerCommands.new()
	
	# Queue operations
	cmds.spawn()\
		.add_component("Health", CompHealth.new(999))
	
	var e = _world.create_entity()
	var eid = e.id()
	cmds.entity(eid).add_component("Pos", CompPos.new())
	
	_assert(_world.get_entity_keys().size() == 1, "Before flush: Only 1 entity exists")
	_assert(not e.has_component("Pos"), "Before flush: Pos not added yet")
	
	# Execute
	cmds.flush(_world)
	
	# Verify
	_assert(_world.get_entity_keys().size() == 2, "After flush: 2 entities exist")
	_assert(e.has_component("Pos"), "After flush: Pos added")
	
	var entities = _world.get_entity_keys()
	var new_entity_found = false
	for id in entities:
		if id != eid:
			if _world.has_component(id, "Health"):
				new_entity_found = true
	_assert(new_entity_found, "After flush: Spawned entity has Health")

func _test_commands_defer() -> void:
	var cmds = ECSSchedulerCommands.new()
	
	# --- Case 1: Basic Defer Execution ---
	
	# Prepare capture context (simulate side effects)
	var context = { "count": 0, "text": "" }
	
	# Queue operations
	cmds.defer(func():
		context.count += 1
		context.text = "deferred"
	)
	
	# Verify BEFORE flush
	_assert(context.count == 0, "Before flush: Callback should NOT execute yet")
	_assert(context.text == "", "Before flush: Text remains default")
	
	# Execute
	cmds.flush(_world)
	
	# Verify AFTER flush
	_assert(context.count == 1, "After flush: Callback executed exactly once")
	_assert(context.text == "deferred", "After flush: Text updated")
	
	
	# --- Case 2: Mixed Order (Command Stream Sequence) ---
	
	var cmds_mixed = ECSSchedulerCommands.new()
	var e = _world.create_entity()
	var eid = e.id()
	
	# Context to capture world state inside the deferred call
	var check_state = { "has_entity_inside_defer": true }
	
	# Queue: Destroy Entity -> Then Defer Logic
	# Logic expectation: flush will execute OP_DESTROY first, then OP_DEFER
	cmds_mixed.entity(eid).destroy()
	cmds_mixed.defer(func():
		# Check if the entity still exists at this specific moment in the stream
		check_state.has_entity_inside_defer = _world.has_entity(eid)
	)
	
	_assert(_world.has_entity(eid), "Before flush: Entity still exists")
	
	# Execute
	cmds_mixed.flush(_world)
	
	# Verify
	_assert(not _world.has_entity(eid), "After flush: Entity is destroyed")
	_assert(check_state.has_entity_inside_defer == false, "Inside defer: Should perceive the entity as already destroyed (Sequential consistency)")

# --- Scheduler Mock Systems ---
# Simulate a system that produces data
class SysProducer extends ECSParallel:
	func _init(): super._init("Producer")
	func _list_components() -> Dictionary:
		return {"Val": ECSParallel.READ_WRITE}
	func _view_components(view: Dictionary, cmds: ECSSchedulerCommands) -> void:
		# Add 1 to all entities with Val component
		var c = view["Val"] as ECSDataComponent
		c.data += 1

# Simulate a system that consumes data, must run after Producer
class SysConsumer extends ECSParallel:
	var total_sum = 0
	func _init(): super._init("Consumer")
	func _list_components() -> Dictionary:
		return {"Val": ECSParallel.READ_ONLY}
	func _parallel() -> bool: return false # Set to single-threaded for easier accumulation testing
	func thread_function(delta: float) -> void:
		total_sum = 0 # Reset per frame
		super.thread_function(delta)
		
	func _view_components(view: Dictionary, cmds: ECSSchedulerCommands) -> void:
		var c = view["Val"] as ECSDataComponent
		total_sum += c.data

func _test_scheduler_dependency() -> void:
	var scheduler = _world.create_scheduler("MainLoop")
	
	# Setup entities
	for i in range(10):
		var e = _world.create_entity()
		e.add_component("Val", CompHealth.new(0)) # Reuse Health as general data wrapper
	
	# Setup Systems
	var sys_prod = SysProducer.new()
	var sys_cons = SysConsumer.new()
	
	# Set dependency: Consumer must run after Producer
	sys_cons.after(["Producer"])
	
	scheduler.add_systems([sys_prod, sys_cons])
	scheduler.build()
	
	# Run Frame 1
	scheduler.run(0.016)
	# Producer runs: 0 -> 1
	# Consumer runs: sums 1 * 10 = 10
	_assert(sys_cons.total_sum == 10, "Frame 1: Dependency order check (Sum 10)")
	
	# Run Frame 2
	scheduler.run(0.016)
	# Producer runs: 1 -> 2
	# Consumer runs: sums 2 * 10 = 20
	_assert(sys_cons.total_sum == 20, "Frame 2: State persistence check (Sum 20)")
	
	_world.destroy_scheduler("MainLoop")

func _test_serialization() -> void:
	# 1. Setup World State
	var e1 = _world.create_entity()
	var pos = CompPos.new()
	pos.x = 100
	pos.y = 200
	e1.add_component("Pos", pos)
	e1.add_component("Health", CompHealth.new(50))
	
	# 2. Pack
	var packer = ECSWorldPacker.new(_world)
	var data_pack = packer.pack()
	
	# 3. Destroy World
	_world.clear()
	_assert(_world.get_entity_keys().is_empty(), "World cleared")
	
	# 3.1 register inner class help test success
	packer.factory().register(CompPos)
	packer.factory().register(CompHealth, [0])
	
	# 4. Unpack
	var success = packer.unpack(data_pack)
	_assert(success, "Unpack operation successful")
	
	# 5. Verify
	var keys = _world.get_entity_keys()
	_assert(keys.size() == 1, "Entity restored count")
	
	if keys.size() > 0:
		var eid = keys[0]
		var e_restored = _world.get_entity(eid)
		
		_assert(e_restored.has_component("Pos"), "Component Pos restored")
		_assert(e_restored.has_component("Health"), "Component Health restored")
		
		if e_restored.has_component("Pos"):
			var p = e_restored.get_component("Pos") as CompPos
			_assert(p.x == 100 and p.y == 200, "Component custom data restored correct")
			
		if e_restored.has_component("Health"):
			var h = e_restored.get_component("Health") as CompHealth
			_assert(h.data == 50, "Component standard data restored correct")

func _test_runner_system_management() -> void:
	var runner = _world.create_runner("TestRunner")
	
	# Test: Add single system
	var sys1 = MockSystem.new()
	runner.add_system("Sys1", sys1)
	_assert(runner.get_system("Sys1") == sys1, "Add single system - system retrieved correctly")
	_assert(runner.get_systems().size() == 1, "Add single system - count correct")
	
	# Test: Add multiple systems
	var sys2 = MockSystem.new()
	var sys3 = MockSystem.new()
	runner.add_systems({"Sys2": sys2, "Sys3": sys3})
	_assert(runner.get_systems().size() == 3, "Add multiple systems - count correct")
	_assert(runner.get_system("Sys2") == sys2, "Add multiple systems - Sys2 retrieved")
	_assert(runner.get_system("Sys3") == sys3, "Add multiple systems - Sys3 retrieved")
	
	# Test: Replace system with same name
	var sys1_new = MockSystem.new()
	runner.add_system("Sys1", sys1_new)
	_assert(runner.get_system("Sys1") == sys1_new, "Replace system - new system retrieved")
	_assert(sys1.exit_called, "Replace system - old system exit called")
	_assert(sys1_new.enter_called, "Replace system - new system enter called")
	
	# Test: Remove system
	runner.remove_system("Sys2")
	_assert(runner.get_system("Sys2") == null, "Remove system - system is null")
	_assert(runner.get_systems().size() == 2, "Remove system - count reduced")
	_assert(sys2.exit_called, "Remove system - exit called")
	
	# Test: Clear all systems
	runner.clear()
	_assert(runner.get_systems().is_empty(), "Clear all systems - pool empty")
	_assert(sys1_new.exit_called, "Clear all systems - systems exit called")
	_assert(sys3.exit_called, "Clear all systems - systems exit called")
	
	_world.destroy_runner("TestRunner")

func _test_runner_update_control() -> void:
	var runner = _world.create_runner("TestRunner")
	
	# Test: Run one frame
	var sys1 = MockSystem.new()
	var sys2 = MockSystem.new()
	runner.add_systems({"Sys1": sys1, "Sys2": sys2})
	runner.run(0.016)
	_assert(sys1.update_count == 1, "Run frame - Sys1 update called once")
	_assert(sys2.update_count == 1, "Run frame - Sys2 update called once")
	
	# Test: Disable single system
	runner.set_system_update("Sys1", false)
	_assert(not runner.is_system_updating("Sys1"), "Disable system - is_system_updating returns false")
	_assert(runner.is_system_updating("Sys2"), "Disable system - other system still updating")
	
	runner.run(0.016)
	_assert(sys1.update_count == 1, "Disable system - Sys1 not updated")
	_assert(sys2.update_count == 2, "Disable system - Sys2 updated")
	
	# Test: Enable system again
	runner.set_system_update("Sys1", true)
	_assert(runner.is_system_updating("Sys1"), "Enable system - is_system_updating returns true")
	
	runner.run(0.016)
	_assert(sys1.update_count == 2, "Enable system - Sys1 updated again")
	_assert(sys2.update_count == 3, "Enable system - Sys2 continues updating")
	
	# Test: Disable all systems
	runner.set_systems_update(false)
	_assert(not runner.is_system_updating("Sys1"), "Disable all - Sys1 not updating")
	_assert(not runner.is_system_updating("Sys2"), "Disable all - Sys2 not updating")
	
	runner.run(0.016)
	_assert(sys1.update_count == 2, "Disable all - Sys1 not updated")
	_assert(sys2.update_count == 3, "Disable all - Sys2 not updated")
	
	# Test: Enable all systems
	runner.set_systems_update(true)
	_assert(runner.is_system_updating("Sys1"), "Enable all - Sys1 updating")
	_assert(runner.is_system_updating("Sys2"), "Enable all - Sys2 updating")
	
	runner.run(0.016)
	_assert(sys1.update_count == 3, "Enable all - Sys1 updated")
	_assert(sys2.update_count == 4, "Enable all - Sys2 updated")
	
	_world.destroy_runner("TestRunner")

func _test_runner_lifecycle() -> void:
	var runner = _world.create_runner("TestRunner")
	
	# Test: _on_enter is called when adding system
	var sys = MockSystem.new()
	_assert(not sys.enter_called, "Before add - enter not called")
	runner.add_system("TestSys", sys)
	_assert(sys.enter_called, "After add - enter called")
	
	# Test: System name and world reference are set
	_assert(sys.name() == "TestSys", "System name set correctly")
	_assert(sys.world() == _world, "System world reference set correctly")
	
	# Test: _on_exit is called when removing system
	var sys2 = MockSystem.new()
	runner.add_system("TestSys2", sys2)
	_assert(not sys2.exit_called, "Before remove - exit not called")
	runner.remove_system("TestSys2")
	_assert(sys2.exit_called, "After remove - exit called")
	
	_world.destroy_runner("TestRunner")

func _test_runner_edge_cases() -> void:
	var runner = _world.create_runner("TestRunner")
	
	# Test: Remove non-existent system
	var result = runner.remove_system("NonExistent")
	_assert(not result, "Remove non-existent system returns false")
	
	# Test: Get non-existent system
	var sys = runner.get_system("NonExistent")
	_assert(sys == null, "Get non-existent system returns null")
	
	# Test: Enable/disable non-existent system (should not crash)
	runner.set_system_update("NonExistent", true)
	runner.set_system_update("NonExistent", false)
	_assert(true, "Enable/disable non-existent system does not crash")
	
	# Test: Check update status of non-existent system
	var updating = runner.is_system_updating("NonExistent")
	_assert(not updating, "is_system_updating for non-existent returns false")
	
	# Test: System without _on_update method
	var sys_no_update = SystemNoUpdate.new()
	runner.add_system("NoUpdate", sys_no_update)
	_assert(runner.is_system_updating("NoUpdate") == false, "System without _on_update not connected")
	runner.run(0.016) # Should not crash
	_assert(true, "Running with system without _on_update does not crash")
	
	_world.destroy_runner("TestRunner")
