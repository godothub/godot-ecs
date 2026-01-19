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
	
	# 执行各个测试模块
	_run_test("Entity & Component CRUD", _test_entity_component_crud)
	_run_test("Query System (With/Without/AnyOf)", _test_query_system)
	_run_test("Event System", _test_events)
	_run_test("Command Buffer", _test_commands)
	_run_test("Command Buffer Defer", _test_commands_defer)
	_run_test("Scheduler & Parallel Systems", _test_scheduler_dependency)
	_run_test("Serialization (Pack/Unpack)", _test_serialization)
	
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
	# 关闭内部 Debug 打印以保持测试输出整洁，除非你需要调试框架本身
	_world.debug_print = false 

func _teardown() -> void:
	if _world:
		_world.clear()
		_world = null

func _run_test(test_name: String, test_func: Callable) -> void:
	print_rich("[color=cyan]> Running: %s...[/color]" % test_name)
	_setup()
	test_func.call()
	# 显式清理，防止状态污染
	_teardown() 

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		# 成功时不打印，减少刷屏，或者只打印简略信息
		# print("  [OK] %s" % msg) 
	else:
		_fail_count += 1
		print_rich("  [b][color=red][FAIL] %s[/color][/b]" % msg)
		print_stack()

# ==============================================================================
# Mock Data (Inner Classes)
# ==============================================================================

# 定义一些测试用的组件
class CompHealth extends ECSDataComponent: pass
class CompMana extends ECSDataComponent: pass
class CompPos extends ECSComponent: 
	var x: int = 0
	var y: int = 0
	# 为了序列化测试，必须重写 pack/unpack
	func _on_pack(ar: Serializer.Archive) -> void:
		ar.set_var("x", x)
		ar.set_var("y", y)
	func _on_unpack(ar: Serializer.Archive) -> void:
		x = ar.get_var("x", 0)
		y = ar.get_var("y", 0)

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
	# 逻辑预期：flush 时会先执行 OP_DESTROY，然后执行 OP_DEFER
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
# 模拟一个产生数据的系统
class SysProducer extends ECSParallel:
	func _init(): super._init("Producer")
	func _list_components() -> Dictionary:
		return {"Val": ECSParallel.READ_WRITE}
	func _view_components(view: Dictionary, cmds: ECSSchedulerCommands) -> void:
		# 给所有有 Val 组件的实体加 1
		var c = view["Val"] as ECSDataComponent
		c.data += 1

# 模拟一个消费数据的系统，必须在 Producer 后运行
class SysConsumer extends ECSParallel:
	var total_sum = 0
	func _init(): super._init("Consumer")
	func _list_components() -> Dictionary:
		return {"Val": ECSParallel.READ_ONLY}
	func _parallel() -> bool: return false # 为了累加测试方便，设为单线程
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
	
	# 设置依赖：Consumer 必须在 Producer 之后
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
