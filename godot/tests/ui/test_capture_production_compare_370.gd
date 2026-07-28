extends GutTest

const POLICY_PATH := "res://tools/capture_phase_policy_370.gd"


func test_before_uses_copied_baseline_and_only_after_saves_current_frame() -> void:
	assert_true(ResourceLoader.exists(POLICY_PATH),
		"capture 必须抽出可测相位策略阻止 before 落入当前帧 save_png")
	if not ResourceLoader.exists(POLICY_PATH):
		return
	var policy: Object = (load(POLICY_PATH) as Script).new()
	assert_true(policy.has_method("should_save_current_frame"))
	if not policy.has_method("should_save_current_frame"):
		return
	assert_false(policy.call("should_save_current_frame", "before"))
	assert_true(policy.call("should_save_current_frame", "after"))
