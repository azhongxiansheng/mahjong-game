class_name CharacterVoicePolicy extends RefCounted

const PRIORITY_NORMAL := 10
const PRIORITY_HIGH := 20

var _profile: CharacterPresentationProfile
var _character_ids: Array = []
var _entry_played := false
var _unique_leader_seat := -1
var _local_seat := 0


func _init(profile: CharacterPresentationProfile = null) -> void:
	_profile = profile


func bind_characters(character_ids: Array, local_seat: int = 0) -> void:
	_character_ids = character_ids.duplicate()
	_local_seat = local_seat
	_entry_played = false
	_unique_leader_seat = -1


func set_local_seat(local_seat: int) -> void:
	_local_seat = local_seat


func requests_for_event(event: BattleEvent) -> Array:
	if event == null or _profile == null or not _profile.is_valid():
		return []
	match event.type:
		&"GAME_BEGIN":
			if not _entry_played and _character_at(_local_seat) == _profile.character_id:
				_entry_played = true
				return [_request(&"entry", PRIORITY_NORMAL)]
		&"SKILL_TRIGGERED":
			if StringName(String(event.extra.get("skill_id", ""))) == _profile.ability_id \
					and _character_at(event.actor_seat) == _profile.character_id:
				return [_request(&"ability", PRIORITY_HIGH)]
		&"WIN_DECLARED":
			if _character_at(event.actor_seat) == _profile.character_id:
				return [_request(&"win", PRIORITY_HIGH)]
			if not bool(event.extra.get("is_tsumo", false)):
				var discarder := int(event.extra.get("discarder_seat", -1))
				if _character_at(discarder) == _profile.character_id:
					return [_request(&"hurt", PRIORITY_NORMAL)]
	return []


func requests_for_scores(scores: Array) -> Array:
	if _profile == null or not _profile.is_valid():
		return []
	var leader := _find_unique_leader(scores)
	var became_profile_leader := (
		leader != _unique_leader_seat
		and _character_at(leader) == _profile.character_id
	)
	_unique_leader_seat = leader
	if became_profile_leader:
		return [_request(&"advantage", PRIORITY_NORMAL)]
	return []


func requests_for_match_result(final_scores: Array) -> Array:
	if _profile == null or not _profile.is_valid() \
			or _character_at(_local_seat) != _profile.character_id \
			or final_scores.size() < 4:
		return []
	var top_score := int(final_scores[0])
	for score in final_scores:
		top_score = maxi(top_score, int(score))
	if int(final_scores[_local_seat]) < top_score:
		return [_request(&"result_lose", PRIORITY_HIGH)]
	return []


func _character_at(seat: int) -> StringName:
	if seat < 0 or seat >= _character_ids.size():
		return &""
	return StringName(String(_character_ids[seat]))


func _find_unique_leader(scores: Array) -> int:
	if scores.size() < 4:
		return -1
	var best := int(scores[0])
	var leader := 0
	var tied := false
	for seat in range(1, scores.size()):
		var score := int(scores[seat])
		if score > best:
			best = score
			leader = seat
			tied = false
		elif score == best:
			tied = true
	return -1 if tied else leader


func _request(event_kind: StringName, priority: int) -> Dictionary:
	return {
		"character_id": _profile.character_id,
		"event_kind": event_kind,
		"priority": priority,
	}
