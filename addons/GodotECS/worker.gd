extends RefCounted
class_name ECSWorker

class Job extends RefCounted:
	func execute() -> void:
		pass

var _mutex := Mutex.new()
var _jobs: Array[Job]
var _thread: Thread
var _waiter: Semaphore
var _exit_thread: bool
var _last_worker: ECSWorker
var _rng := RandomNumberGenerator.new()

# take job by self
func pop() -> Job:
	_mutex.lock()
	var result := _jobs.pop_back()
	_mutex.unlock()
	return result
	
# add job
func push(job: Job) -> void:
	_mutex.lock()
	_jobs.push_back(job)
	_mutex.unlock()
	_waiter.post()
	
# add jobs
func push_jobs(jobs: Array[Job]) -> void:
	_mutex.lock()
	_jobs.append_array(jobs)
	_mutex.unlock()
	_waiter.post()
	
# work stealing by other thread
func steal() -> Job:
	_mutex.lock()
	var result: Job
	if not _jobs.is_empty():
		result = _jobs.front()
		_jobs = _jobs.slice(1)
	_mutex.unlock()
	return result
	
func steal_and_execute() -> bool:
	var job := steal()
	if job:
		job.execute()
	return job != null
	
func thread_function() -> void:
	while not _exit_thread:
		var job := pop()
		if job == null:
			_on_work_stealing()
			continue
		job.execute()
	
func start() -> void:
	if _thread:
		return
	_exit_thread = false
	_thread = Thread.new()
	_waiter = Semaphore.new()
	assert(_thread)
	_thread.start(thread_function)
	
func stop() -> void:
	if not _thread:
		return
	_exit_thread = true
	_waiter.post()
	_thread.wait_to_finish()
	_thread = null
	_waiter = null
	_last_worker = null
	
func _draw_worker() -> ECSWorker:
	return _queue[_rng.randi_range(0, _queue.size()-1)]
	
func _on_work_stealing() -> void:
	# steal job from last worker
	if _last_worker and _last_worker.steal_and_execute():
		return
		
	# random steal job
	for _i in range(0, _queue.size()):
		var worker: ECSWorker = _draw_worker()
		if worker == self:
			continue
		if worker.steal_and_execute():
			_last_worker = worker
			return
		
	# set last worker null
	_last_worker = null
		
	# waiting
	_waiter.wait()
	
# external thread queue
var _queue: Array[ECSWorker]
	
func _init(queue: Array[ECSWorker]) -> void:
	_queue = queue
	
