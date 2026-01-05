extends ECSSystem

# override
func _on_enter(w: ECSWorld) -> void:
	# init
	_init_entity()
	
	# add system
	w.add_system("my_system", preload("my_system.gd").new(self))
	w.add_system("save_system", preload("save_system.gd").new(self))
	
	# debug print on
	w.debug_print = true
	w.debug_entity = true
	
# override
func _on_exit(w: ECSWorld) -> void:
	# remove system
	w.remove_system("my_system")
	w.remove_system("save_system")
	
	# free
	_free_entity()
	
func _init_entity():
	# create entity
	var e = world().create_entity()
	# add component
	e.add_component("player_unit")
	e.add_component("my_component", MyComponent.new())
	
func _free_entity():
	world().remove_all_entities()
	
