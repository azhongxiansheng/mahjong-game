extends RefCounted


func should_save_current_frame(phase: String) -> bool:
	return phase == "after"
