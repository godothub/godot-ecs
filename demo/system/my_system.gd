extends ECSSystem

func _on_update(delta: float) -> void:
	for c: MyComponent in view("my_component"):
		c.value1 += 1
		c.value2 += delta
	
