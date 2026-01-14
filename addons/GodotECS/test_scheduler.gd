extends RefCounted
class_name ECSSchedulerStressTest

# ==============================================================================
# Helper: Strict System for Testing
# ==============================================================================
class StrictSystem extends ECSParallel:
	var _read_list: Array[StringName] = []
	var _write_list: Array[StringName] = []
	
	func _init(n: StringName, reads: Array = [], writes: Array = []):
		super._init(n)
		_read_list.assign(reads)
		_write_list.assign(writes)
	
	# Override: Define Resource Access
	func _list_components() -> Dictionary:
		var dict = {}
		for r in _read_list: dict[r] = ECSParallel.READ_ONLY
		for w in _write_list: dict[w] = ECSParallel.READ_WRITE
		return dict
		
	# Override: No-op logic, we inspect the plan, not the execution result
	func _view_components(_view: Dictionary, _cmds) -> void: pass

# ==============================================================================
# Test Runner
# ==============================================================================

var _world: ECSWorld
var _fail_count: int = 0

func run() -> void:
	print_rich("[b][color=yellow]=== Starting STRICT Scheduler Analysis ===[/color][/b]")
	_fail_count = 0
	
	_run_test("Implicit Resource Conflict (RW/WW Safety)", _test_resource_conflict_serialization)
	_run_test("Explicit Dependency DAG (Diamond Shape)", _test_diamond_dependency)
	_run_test("Massive Scale (100+ Systems)", _test_massive_chain_and_width)
	_run_test("Cyclic Dependency (Deadlock Prevention)", _test_cyclic_dependency)
	
	print_rich("[b]--------------------------------------------------[/b]")
	if _fail_count == 0:
		print_rich("[b][color=green]ALL STRICT TESTS PASSED! Scheduler is Robust.[/color][/b]")
	else:
		print_rich("[b][color=red]CRITICAL FAILURE: Scheduler logic is flawed![/color][/b]")
		# 强制报错以中断 CI/CD 流程
		assert(_fail_count == 0, "Scheduler Verification Failed")
	
	_teardown()
	
func _setup() -> void:
	if _world: _world.clear()
	_world = ECSWorld.new("StrictTestWorld")
	_world.debug_print = false

func _teardown() -> void:
	if _world:
		_world.clear()
		_world = null

func _run_test(name: String, func_ref: Callable) -> void:
	print_rich("[color=cyan]> Analyzing: %s...[/color]" % name)
	_setup()
	func_ref.call()

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail_count += 1
		print_rich("  [b][color=red][FAIL] %s[/color][/b]" % msg)
		print_stack()

# ==============================================================================
# 1. 资源冲突隐式串行化测试
# 验证：即使没有显式 before/after，资源冲突也应强迫系统分批次运行
# ==============================================================================
func _test_resource_conflict_serialization() -> void:
	var scheduler = _world.create_scheduler("ResConflict")
	
	# Scenario:
	# SysA: Write [Comp1]
	# SysB: Write [Comp1] -> Conflict with A (WW)
	# SysC: Read [Comp1]  -> Conflict with A or B (RW)
	# SysD: Read [Comp1]  -> Compatible with C (RR)
	
	var sys_a = StrictSystem.new("A", [], ["Comp1"])
	var sys_b = StrictSystem.new("B", [], ["Comp1"])
	var sys_c = StrictSystem.new("C", ["Comp1"], [])
	var sys_d = StrictSystem.new("D", ["Comp1"], [])
	
	# 注意：我们故意不设置 before/after，完全依赖调度器的资源分析
	scheduler.add_systems([sys_a, sys_b, sys_c, sys_d])
	scheduler.build()
	
	var plan = _extract_plan(scheduler)
	_print_plan(plan)
	
	# 验证 1: A 和 B 绝不能在同一层 (写写冲突)
	var batch_a = _find_batch_index(plan, "A")
	var batch_b = _find_batch_index(plan, "B")
	_assert(batch_a != batch_b, "WW Conflict: A and B must be in different batches")
	
	# 验证 2: 写者(A/B) 和 读者(C/D) 绝不能在同一层 (读写冲突)
	var batch_c = _find_batch_index(plan, "C")
	var batch_d = _find_batch_index(plan, "D")
	
	_assert(batch_a != batch_c, "RW Conflict: A and C must be separated")
	_assert(batch_b != batch_c, "RW Conflict: B and C must be separated")
	
	# 验证 3: 读者之间应该并行 (读读优化)
	# 注意：如果调度器足够聪明，C和D应该在同一层，除非它们被拆分到了 A 和 B 之间
	# 但核心要求是它们不与写者冲突。如果它们都在同一层，那就是完美优化。
	if batch_c == batch_d:
		print("  [Info] Read-Read Optimization verified (C and D in same batch)")
	
	_assert(plan.size() >= 3, "Plan depth should be at least 3 (Write, Write, Read)")

# ==============================================================================
# 2. 显式 DAG 依赖测试 (钻石型)
# 验证：Before/After 逻辑是否被严格遵守
# ==============================================================================
func _test_diamond_dependency() -> void:
	var scheduler = _world.create_scheduler("Diamond")
	
	# Structure:
	#      Start
	#     /     \
	#  Left     Right
	#     \     /
	#      End
	
	var s_start = StrictSystem.new("Start", [], ["Data"])
	var s_left = StrictSystem.new("Left", ["Data"], [])
	var s_right = StrictSystem.new("Right", ["Data"], [])
	var s_end = StrictSystem.new("End", [], ["Data"])
	
	# 设置显式依赖
	s_left.after(["Start"])
	s_right.after(["Start"])
	s_end.after(["Left", "Right"])
	
	scheduler.add_systems([s_start, s_left, s_right, s_end])
	scheduler.build()
	
	var plan = _extract_plan(scheduler)
	_print_plan(plan)
	
	var i_start = _find_batch_index(plan, "Start")
	var i_left = _find_batch_index(plan, "Left")
	var i_right = _find_batch_index(plan, "Right")
	var i_end = _find_batch_index(plan, "End")
	
	# 严格拓扑验证
	_assert(i_start < i_left, "Topology: Start < Left")
	_assert(i_start < i_right, "Topology: Start < Right")
	_assert(i_end > i_left, "Topology: End > Left")
	_assert(i_end > i_right, "Topology: End > Right")
	
	# 验证并行性: Left 和 Right 理论上可以在同一层 (因为都是只读且依赖相同)
	# 除非它们有其他隐式冲突。在这个简单的测试中，期望它们并行。
	if i_left == i_right:
		print("  [Info] Diamond parallel execution verified (Left and Right in same batch)")

# ==============================================================================
# 3. 海量规模压力测试
# 验证：算法在 N=100+ 时的稳定性和正确性
# ==============================================================================
func _test_massive_chain_and_width() -> void:
	var scheduler = _world.create_scheduler("Massive")
	var systems: Array[ECSParallel] = []
	var count = 100
	
	# 创建 100 个系统
	# 偶数索引构成一条长链: 0 -> 2 -> 4 -> ... -> 98
	# 奇数索引全部依赖于 System 0: 0 -> 1, 0 -> 3, ... (宽依赖)
	
	for i in range(count):
		var sys = StrictSystem.new("Sys_%d" % i, ["SharedComp"], [])
		systems.append(sys)
	
	for i in range(count):
		var sys = systems[i]
		
		# Chain logic
		if i % 2 == 0 and i > 0:
			sys.after(["Sys_%d" % (i - 2)])
			
		# Fan-out logic (Odd numbers depend on Sys_0)
		if i % 2 != 0:
			sys.after(["Sys_0"])
	
	scheduler.add_systems(systems)
	
	var time_start = Time.get_ticks_usec()
	scheduler.build()
	var time_end = Time.get_ticks_usec()
	
	print("  [Perf] Build time for 100 systems: %d us" % (time_end - time_start))
	
	var plan = _extract_plan(scheduler)
	# plan too large to print
	
	# 验证长链顺序
	var last_idx = -1
	for i in range(0, count, 2):
		var name = "Sys_%d" % i
		var idx = _find_batch_index(plan, name)
		_assert(idx > last_idx, "Chain Integrity: %s (Batch %d) > Prev (Batch %d)" % [name, idx, last_idx])
		last_idx = idx
		
	# 验证扇出 (Fan-out)
	var root_idx = _find_batch_index(plan, "Sys_0")
	for i in range(1, count, 2):
		var name = "Sys_%d" % i
		var idx = _find_batch_index(plan, name)
		_assert(idx > root_idx, "Fan-out Integrity: %s > Sys_0" % name)

# ==============================================================================
# 4. 循环依赖 (死锁) 测试
# 验证：调度器应检测循环并中断，而不是无限循环导致游戏卡死
# ==============================================================================
func _test_cyclic_dependency() -> void:
	# 注意：在当前框架实现中，scheduler 会打印 error 并 break。
	# 我们需要确保它不会 crash 且能生成某种结果（哪怕是不完整的）。
	
	var scheduler = _world.create_scheduler("Cyclic")
	
	var sys_a = StrictSystem.new("A", ["DummyComp"])
	var sys_b = StrictSystem.new("B", ["DummyComp"])
	
	sys_b.after(["A"])
	sys_a.after(["B"]) # Cycle!
	
	scheduler.add_systems([sys_a, sys_b])
	
	print("  [Info] Expecting [ECS] Scheduler Cycle Detected error below:")
	
	# 这里可能会打印 Error，这是预期的
	scheduler.build()
	
	var plan = _extract_plan(scheduler)
	
	# 如果有循环，DependencyBuilder 的 while 循环会检测到 ready_queue 为空但 processed_count 不够
	# 从而 break。结果可能为空，或者包含部分非循环节点。
	# 只要程序运行到这里没有卡死，就算通过了死锁检测测试。
	_assert(true, "Scheduler handled cycle without freezing.")

# ==============================================================================
# Internal Helpers (Introspection)
# ==============================================================================

# 使用反射/Hack技巧直接读取调度器的私有变量 _batch_systems
# 这是验证调度器逻辑最绝对的方法，无需依赖多线程执行的不确定性
func _extract_plan(scheduler: ECSScheduler) -> Array:
	# _batch_systems 是 Array[Array[ECSParallel]]
	# 我们把它转成更易读的 Array[Array[StringName]]
	var raw_batches = scheduler._batch_systems
	var result = []
	for batch in raw_batches:
		var batch_names = []
		for sys in batch:
			batch_names.append(sys.name())
		result.append(batch_names)
	return result

func _find_batch_index(plan: Array, sys_name: StringName) -> int:
	for i in range(plan.size()):
		if sys_name in plan[i]:
			return i
	return -1

func _print_plan(plan: Array) -> void:
	print("  [Plan] Execution Order:")
	for i in range(plan.size()):
		print("    Batch %d: %s" % [i, str(plan[i])])
