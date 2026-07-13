extends PlayerDecisionPort

signal choice_submitted(choice: Dictionary)

var requests: Array[Dictionary] = []
var presentations: Array[Dictionary] = []
var responder: Callable


func request(kind: StringName, context: Dictionary = {}) -> Dictionary:
	requests.append({"kind": kind, "context": context.duplicate(true)})
	if responder.is_valid():
		return responder.call(kind, context)
	return await choice_submitted


func present(state_name: StringName, context: Dictionary = {}) -> void:
	presentations.append({"state": state_name, "context": context.duplicate(true)})


func submit(choice: Dictionary) -> void:
	choice_submitted.emit(choice)
