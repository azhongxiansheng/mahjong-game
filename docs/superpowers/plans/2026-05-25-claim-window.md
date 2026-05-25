# 鸣牌窗口完善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable chi/pon/kan claiming for both players and AI, with correct priority resolution, chankan, and kuikae restriction — making the CLAIM phase fully functional.

**Architecture:** The TurnEngine and ClaimValidator already implement all apply/check methods. This plan wires them into BattleController's main loop and adds AI claiming decisions to HeuristicAi. The approach: (1) add self-kan detection in the draw phase, (2) build a unified claim resolution function in BattleController that handles priority, (3) add AI claim decision methods to HeuristicAi, (4) wire chankan into the added_kan path, (5) add kuikae validation to ClaimValidator.

**Tech Stack:** GDScript (Godot 4.5), GUT 9.x test framework

**Key files overview:**

| File | Role | Action |
|------|------|--------|
| `godot/core/turn_engine/claim_validator.gd` | Pure-function claim legality | Modify: add `kuikae_restricted_ids()` |
| `godot/ai/heuristic_ai.gd` | AI decision-making | Modify: add `decide_claim()`, `decide_self_kan()` |
| `godot/battle/battle_controller.gd` | Main battle orchestrator | Modify: replace CLAIM skip with `_resolve_claims()`, add self-kan in draw, add chankan |
| `godot/battle/playable_battle_controller.gd` | Player input subclass | Modify: add self-kan UI, chi companion selection |
| `godot/ui/four_player_table/player_action_panel.gd` | Player action buttons | Modify: add ankan/added_kan buttons + state |
| `godot/tests/core/test_claim_validator.gd` | ClaimValidator tests | Modify: add kuikae tests |
| `godot/tests/battle/test_claim_resolution.gd` | New: claim priority tests | Create |
| `godot/tests/battle/test_self_kan.gd` | New: self-kan tests | Create |
| `godot/tests/ai/test_ai_claiming.gd` | New: AI claim decision tests | Create |
| `godot/tests/battle/test_chankan.gd` | New: chankan tests | Create |

---

### Task 1: Kuikae Restriction in ClaimValidator

Add a pure function to compute which tile IDs are forbidden to discard after a chi/pon claim (喰い替え禁止).

**Rule:** After chi, you cannot discard the tile you just claimed NOR any tile that would complete the same sequence from a different position. After pon, you cannot discard the 4th copy of the same tile. This is the standard Japanese mahjong kuikae rule.

**Files:**
- Modify: `godot/core/turn_engine/claim_validator.gd`
- Modify: `godot/tests/core/test_claim_validator.gd`

- [ ] **Step 1: Write failing tests for kuikae**

Add to `godot/tests/core/test_claim_validator.gd`:

```gdscript
# ---- kuikae_restricted_ids ----

func test_kuikae_chi_restricts_claimed_and_suji():
	# Chi 2-3-[4]: claimed W4 with companions W2,W3
	# Restricted: W4 (claimed tile) + W1 (would form 1-2-3 replacing 4 at low end)
	# Actually for standard kuikae: after chi [2,3,4], cannot discard 1 or 4
	# W4 = the claimed tile itself; W1 = suji partner
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W4, [TileId.W2, TileId.W3], true)
	assert_true(TileId.W4 in restricted, "cannot discard claimed tile")
	assert_true(TileId.W1 in restricted, "suji restriction: W1")

func test_kuikae_chi_middle_wait_restricts_only_claimed():
	# Chi [3,_,5] with claimed W4 (kanchan position)
	# Only W4 restricted (no suji partner for middle wait)
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W4, [TileId.W3, TileId.W5], true)
	assert_true(TileId.W4 in restricted)
	assert_eq(restricted.size(), 1, "middle: only claimed tile restricted")

func test_kuikae_chi_high_end():
	# Chi [4,5,6] with claimed W4 (low end)
	# Restricted: W4 + W7 (suji high end)
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W4, [TileId.W5, TileId.W6], true)
	assert_true(TileId.W4 in restricted)
	assert_true(TileId.W7 in restricted, "suji restriction: W7")

func test_kuikae_chi_edge_w7_w8_w9():
	# Chi [7,8,9] with claimed W7
	# Restricted: W7 only (no W10 exists)
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W7, [TileId.W8, TileId.W9], true)
	assert_true(TileId.W7 in restricted)
	assert_eq(restricted.size(), 1)

func test_kuikae_pon_restricts_4th_copy():
	# Pon: restricted = [claimed_tile_id] (the 4th copy if in hand)
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W5, [], false)
	assert_eq(restricted, [TileId.W5])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/core -gselect=test_claim_validator -gexit`
Expected: FAIL — `kuikae_restricted_ids` not defined.

- [ ] **Step 3: Implement kuikae_restricted_ids**

Add to `godot/core/turn_engine/claim_validator.gd`:

```gdscript
# 喰い替え: after chi/pon, which tile IDs are forbidden to discard immediately.
# is_chi=true: claimed_id + suji partner (the tile at the "other end" of the sequence).
# is_chi=false (pon): just claimed_id (cannot discard 4th copy).
# companion_ids: the two tiles from hand used in chi (sorted ascending); empty for pon.
static func kuikae_restricted_ids(claimed_id: int, companion_ids: Array, is_chi: bool) -> Array:
	var restricted: Array = [claimed_id]
	if not is_chi:
		return restricted
	if companion_ids.size() != 2:
		return restricted
	var lo: int = min(companion_ids[0], companion_ids[1])
	var hi: int = max(companion_ids[0], companion_ids[1])
	# Determine claimed tile position in the meld
	if claimed_id < lo:
		# Claimed is lowest: meld is [claimed, lo, hi] → suji = hi + 1
		var suji: int = hi + 1
		if _in_same_suit(claimed_id, suji):
			restricted.append(suji)
	elif claimed_id > hi:
		# Claimed is highest: meld is [lo, hi, claimed] → suji = lo - 1
		var suji: int = lo - 1
		if _in_same_suit(claimed_id, suji):
			restricted.append(suji)
	# else: claimed is middle (kanchan) → no suji partner
	return restricted

static func _in_same_suit(a: int, b: int) -> bool:
	if is_honor(a) or is_honor(b):
		return false
	for rng in [[TileId.W1, TileId.W9], [TileId.T1, TileId.T9], [TileId.S1, TileId.S9]]:
		if a >= rng[0] and a <= rng[1] and b >= rng[0] and b <= rng[1]:
			return true
	return false
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/core -gselect=test_claim_validator -gexit`
Expected: All PASS including new kuikae tests.

- [ ] **Step 5: Commit**

```bash
git add godot/core/turn_engine/claim_validator.gd godot/tests/core/test_claim_validator.gd
git commit -m "feat(claim): add kuikae_restricted_ids to ClaimValidator

Computes forbidden discard tile IDs after chi/pon per standard
Japanese mahjong kuikae rule. Pure function, no state mutation.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 2: AI Claim Decision Methods

Add `decide_claim()` and `decide_self_kan()` to HeuristicAi. The AI should pon when it has a pair matching the discarded tile and its shanten would improve. Chi is skipped for v1 AI (too complex for heuristic; AI chi often hurts hand shape). Ankan/added_kan when available (free value).

**Files:**
- Modify: `godot/ai/heuristic_ai.gd`
- Create: `godot/tests/ai/test_ai_claiming.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/ai/test_ai_claiming.gd`:

```gdscript
extends GutTest

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func _seat_with_hand(ids: Array, seat_id: int = 1) -> Seat:
	var s := Seat.new(seat_id)
	s.hand = _hand(ids)
	return s

# ---- decide_claim ----

func test_ai_pons_when_has_pair():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5,  # pair of W5
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	var result: Dictionary = ai.decide_claim(seat, TileId.W5, 0)
	assert_eq(result.get("action", ""), "pon", "should pon with pair")

func test_ai_skips_when_no_pair():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5,  # only 1 copy
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E, TileId.S5,
	])
	var result: Dictionary = ai.decide_claim(seat, TileId.W5, 0)
	assert_eq(result.get("action", ""), "skip")

func test_ai_skips_chi_v1():
	# AI never chi in v1 (even if valid)
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W4, TileId.W6,  # could chi W5
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	seat.seat_id = 1
	var result: Dictionary = ai.decide_claim(seat, TileId.W5, 0)
	assert_eq(result.get("action", ""), "skip", "AI skips chi in v1")

func test_ai_minkan_when_has_triplet():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	var result: Dictionary = ai.decide_claim(seat, TileId.W5, 0)
	assert_eq(result.get("action", ""), "minkan", "should minkan with triplet")

# ---- decide_self_kan ----

func test_ai_ankan_when_has_four():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5, TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	var result: Dictionary = ai.decide_self_kan(seat)
	assert_eq(result.get("action", ""), "ankan")
	assert_eq(result.get("tile_id", -1), TileId.W5)

func test_ai_added_kan_when_has_pon_plus_4th():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5,  # 4th copy
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E, TileId.E,
	])
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 0)
	seat.melds = [pon]
	var result: Dictionary = ai.decide_self_kan(seat)
	assert_eq(result.get("action", ""), "added_kan")
	assert_eq(result.get("tile_id", -1), TileId.W5)

func test_ai_no_self_kan_when_nothing():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	var result: Dictionary = ai.decide_self_kan(seat)
	assert_eq(result.get("action", ""), "skip")

func test_ai_skips_ankan_when_riichi():
	# Riichi AI cannot ankan (would change wait pattern) — v1 simplification
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5, TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	seat.riichi = RiichiState.new()
	seat.riichi.declared = true
	var result: Dictionary = ai.decide_self_kan(seat)
	assert_eq(result.get("action", ""), "skip", "riichi blocks ankan for AI")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path godot --import && godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/ai -gselect=test_ai_claiming -gexit`
Expected: FAIL — `decide_claim` and `decide_self_kan` not defined.

- [ ] **Step 3: Implement AI claim decisions**

Add to `godot/ai/heuristic_ai.gd`:

```gdscript
# AI claiming decision: given a discarded tile, decide whether to pon/minkan/skip.
# v1: AI never chi (chi often hurts hand shape for heuristic AI).
# Returns: {"action": "pon"|"minkan"|"skip"}
func decide_claim(seat: Seat, discarded_id: int, discarder_seat: int) -> Dictionary:
	if seat.seat_id == discarder_seat:
		return {"action": "skip"}
	if seat.riichi.declared:
		return {"action": "skip"}
	var count: int = seat.hand.count_of(discarded_id)
	if count >= 3:
		return {"action": "minkan"}
	if count >= 2:
		return {"action": "pon"}
	return {"action": "skip"}

# Self-kan decision: after drawing, check if AI should declare ankan or added_kan.
# v1: always kan when possible (free value), except during riichi.
# Returns: {"action": "ankan"|"added_kan"|"skip", "tile_id": int}
func decide_self_kan(seat: Seat) -> Dictionary:
	if seat.riichi.declared:
		return {"action": "skip"}
	var ankan_ids: Array = ClaimValidator.ankan_candidates(seat.hand)
	if not ankan_ids.is_empty():
		return {"action": "ankan", "tile_id": ankan_ids[0]}
	for m in seat.melds:
		if m.kind == Meld.Kind.PON:
			var tid: int = m.tiles[0].id
			if ClaimValidator.can_added_kan(seat.melds, seat.hand, tid):
				return {"action": "added_kan", "tile_id": tid}
	return {"action": "skip"}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/ai -gselect=test_ai_claiming -gexit`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add godot/ai/heuristic_ai.gd godot/tests/ai/test_ai_claiming.gd godot/tests/ai/test_ai_claiming.gd.uid
git commit -m "feat(ai): add decide_claim and decide_self_kan to HeuristicAi

AI will pon/minkan when holding pair/triplet of discarded tile.
AI declares ankan/added_kan when possible (except during riichi).
v1 simplification: AI never chi.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 3: Self-Kan in BattleController Draw Phase

After drawing, check if the current seat can declare ankan or added_kan. For AI: auto-decide via `ai.decide_self_kan()`. For player: handled in Task 6 (UI). This task wires the AI path only.

**Files:**
- Modify: `godot/battle/battle_controller.gd`
- Create: `godot/tests/battle/test_self_kan.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/battle/test_self_kan.gd`:

```gdscript
extends GutTest

# Test that AI declares ankan when holding 4 copies after draw.
# Uses BattleController with a rigged hand.

func test_ai_ankan_after_draw():
	var bc := BattleController.new(100, 0, true)  # heuristic AI
	# Rig seat 1's hand: give them 3 copies of E, wall top = E
	var seat1: Seat = bc.state.seats[1]
	seat1.hand = Hand.new()
	for tid in [TileId.E, TileId.E, TileId.E,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3, TileId.S5]:
		seat1.hand.add(Tile.new(tid))
	# Put E on top of wall
	bc.state.wall._live_wall.insert(0, Tile.new(TileId.E))
	# Advance to seat 1 draw
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DRAW
	# Run one draw step
	bc._step_draw()
	# After draw: seat 1 should have drawn E (now 4 copies) and decided ankan
	# Check: seat 1 has an ANKAN meld
	var has_ankan := false
	for m in seat1.melds:
		if m.kind == Meld.Kind.ANKAN and m.tiles[0].id == TileId.E:
			has_ankan = true
	assert_true(has_ankan, "AI should declare ankan with 4 copies of E")

func test_ai_added_kan_after_draw():
	var bc := BattleController.new(100, 0, true)
	var seat1: Seat = bc.state.seats[1]
	# Give seat 1 a PON of W5 and 1 W5 in hand
	seat1.hand = Hand.new()
	for tid in [TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.S5, TileId.S5, TileId.E, TileId.E]:
		seat1.hand.add(Tile.new(tid))
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 0)
	seat1.melds = [pon]
	# Put W5 on top of wall so seat 1 draws it
	bc.state.wall._live_wall.insert(0, Tile.new(TileId.W5))
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DRAW
	bc._step_draw()
	# Check: PON should be upgraded to ADDED_KAN
	var has_added_kan := false
	for m in seat1.melds:
		if m.kind == Meld.Kind.ADDED_KAN and m.tiles[0].id == TileId.W5:
			has_added_kan = true
	assert_true(has_added_kan, "AI should declare added_kan")

func test_no_self_kan_during_riichi():
	var bc := BattleController.new(100, 0, true)
	var seat1: Seat = bc.state.seats[1]
	seat1.hand = Hand.new()
	for tid in [TileId.E, TileId.E, TileId.E,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3, TileId.S5]:
		seat1.hand.add(Tile.new(tid))
	seat1.riichi.declare(0, false)
	bc.state.wall._live_wall.insert(0, Tile.new(TileId.E))
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DRAW
	bc._step_draw()
	var has_ankan := false
	for m in seat1.melds:
		if m.kind == Meld.Kind.ANKAN:
			has_ankan = true
	assert_false(has_ankan, "riichi blocks ankan")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path godot --import && godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle -gselect=test_self_kan -gexit`
Expected: FAIL — self-kan not triggered in `_step_draw`.

- [ ] **Step 3: Add self-kan logic to BattleController._step_draw**

In `godot/battle/battle_controller.gd`, after the tsumo check in `_step_draw()`, add self-kan check. The key insertion point is after tsumo detection but before returning (when tsumo is not accepted or not winning):

Add a new method and call it from `_step_draw`:

```gdscript
# After tsumo check in _step_draw, try self-kan (ankan/added_kan) for AI seats.
# Player self-kan is handled by PlayableBattleController override.
func _try_ai_self_kan() -> void:
	var actor: int = state.current_seat
	if not ai.has_method("decide_self_kan"):
		return
	var seat: Seat = state.seats[actor]
	var decision: Dictionary = ai.decide_self_kan(seat)
	var action: String = String(decision.get("action", "skip"))
	if action == "ankan":
		var tid: int = int(decision.get("tile_id", -1))
		if engine.apply_ankan(actor, tid):
			_emit(&"PLAYER_ACTION", actor, null, {"kind": "ankan", "tile_id": tid})
	elif action == "added_kan":
		var tid: int = int(decision.get("tile_id", -1))
		if engine.apply_added_kan(actor, tid):
			_emit(&"PLAYER_ACTION", actor, null, {"kind": "added_kan", "tile_id": tid})
```

In `_step_draw()`, after the tsumo check block (`if win.is_winning and _should_accept_tsumo...`), add:

```gdscript
	# Self-kan check (AI only; player path in PlayableBattleController)
	if not _settled:
		_try_ai_self_kan()
```

Similarly in `_step_draw_async()`, add the same call after the tsumo check.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path godot --import && godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle -gselect=test_self_kan -gexit`
Expected: All PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add godot/battle/battle_controller.gd godot/tests/battle/test_self_kan.gd godot/tests/battle/test_self_kan.gd.uid
git commit -m "feat(battle): AI self-kan (ankan/added_kan) after draw

After drawing, HeuristicAi checks for ankan (4 copies) or added_kan
(4th copy + existing PON). Emits PLAYER_ACTION event for replay.
Blocked during riichi per standard rules.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 4: Unified Claim Resolution in BattleController

Replace the CLAIM phase skip with a proper `_resolve_claims()` that:
1. Collects all AI claim intentions (pon/minkan from HeuristicAi)
2. Applies priority: existing ron (already handled in `_try_auto_ron`) > pon/minkan > chi
3. Executes the winning claim via TurnEngine
4. Emits TILE_CLAIMED + MELD_FORMED events
5. If no claims, advances to next seat

**Files:**
- Modify: `godot/battle/battle_controller.gd`
- Create: `godot/tests/battle/test_claim_resolution.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/battle/test_claim_resolution.gd`:

```gdscript
extends GutTest

func test_ai_pon_fires_during_claim_phase():
	# Rig: seat 0 discards W5, seat 2 has pair of W5 → should pon
	var bc := BattleController.new(100, 0, true)
	var seat2: Seat = bc.state.seats[2]
	seat2.hand = Hand.new()
	for tid in [TileId.W5, TileId.W5,  # pair to pon
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E]:
		seat2.hand.add(Tile.new(tid))
	# Force seat 0 to discard W5
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DRAW
	var drawn := bc.engine.draw_for_current()
	# Add W5 to seat 0 hand if not already there, then force discard it
	if bc.state.seats[0].hand.count_of(TileId.W5) == 0:
		bc.state.seats[0].hand.add(Tile.new(TileId.W5))
	bc.engine.discard(TileId.W5)
	# Now phase = CLAIM; call _resolve_claims
	var discarded := Tile.new(TileId.W5)
	bc._resolve_claims(discarded, 0)
	# seat 2 should have PON meld and be current_seat
	var has_pon := false
	for m in seat2.melds:
		if m.kind == Meld.Kind.PON and m.tiles[0].id == TileId.W5:
			has_pon = true
	assert_true(has_pon, "seat 2 should pon W5")
	assert_eq(bc.state.current_seat, 2, "current_seat should be claimant")
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD, "phase should be DISCARD after pon")

func test_no_claims_advances_to_next_seat():
	var bc := BattleController.new(100, 0, true)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded := Tile.new(TileId.HAKU)
	# No AI has pair of HAKU (random seed, unlikely all have 2+)
	# Clear all AI hands of HAKU to guarantee
	for i in range(1, 4):
		while bc.state.seats[i].hand.count_of(TileId.HAKU) > 0:
			bc.state.seats[i].hand.remove_by_id(TileId.HAKU)
	bc._resolve_claims(discarded, 0)
	assert_eq(bc.state.current_seat, 1, "should advance to next seat")
	assert_eq(bc.state.phase, BattlePhase.Kind.DRAW)

func test_pon_priority_over_chi():
	# Seat 0 discards W5; seat 1 (next) could chi, seat 3 could pon
	# Pon wins over chi
	var bc := BattleController.new(100, 0, true)
	# seat 1: can chi W5 (has W4, W6)
	bc.state.seats[1].hand = Hand.new()
	for tid in [TileId.W4, TileId.W6,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.E, TileId.E, TileId.S5, TileId.S5, TileId.S5]:
		bc.state.seats[1].hand.add(Tile.new(tid))
	# seat 3: can pon W5 (has pair)
	bc.state.seats[3].hand = Hand.new()
	for tid in [TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E]:
		bc.state.seats[3].hand.add(Tile.new(tid))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc._resolve_claims(Tile.new(TileId.W5), 0)
	# seat 3 should have ponned (priority over seat 1 chi)
	var seat3_has_pon := false
	for m in bc.state.seats[3].melds:
		if m.kind == Meld.Kind.PON:
			seat3_has_pon = true
	assert_true(seat3_has_pon, "pon has priority over chi")

func test_tile_claimed_event_emitted():
	var bc := BattleController.new(100, 0, true)
	var seat2: Seat = bc.state.seats[2]
	seat2.hand = Hand.new()
	for tid in [TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E]:
		seat2.hand.add(Tile.new(tid))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc._resolve_claims(Tile.new(TileId.W5), 0)
	var found_claim_event := false
	for ev in bc.events:
		if ev.type == &"TILE_CLAIMED":
			found_claim_event = true
	assert_true(found_claim_event, "TILE_CLAIMED event should be emitted")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path godot --import && godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle -gselect=test_claim_resolution -gexit`
Expected: FAIL — `_resolve_claims` not defined.

- [ ] **Step 3: Implement _resolve_claims in BattleController**

Add to `godot/battle/battle_controller.gd`:

```gdscript
# Unified claim resolution: after a discard, check all non-discarder seats for
# pon/minkan claims (chi deferred to v2 for AI). Priority: pon/minkan > chi.
# Ron is handled separately in _try_auto_ron (already runs before CLAIM phase).
# Player claims are handled by PlayableBattleController override of this method.
func _resolve_claims(discarded: Tile, discarder: int) -> void:
	if not ai.has_method("decide_claim"):
		engine.advance_to_next_seat()
		return
	# Collect AI claim intentions (skip player seat 0 — handled by subclass)
	var best_claim: Dictionary = {}
	var best_seat: int = -1
	var best_priority: int = 0  # 2=pon/minkan, 1=chi
	for offset in range(1, 4):
		var candidate: int = (discarder + offset) % 4
		if candidate == 0:
			continue  # player seat handled by PlayableBattleController
		var seat: Seat = state.seats[candidate]
		var decision: Dictionary = ai.decide_claim(seat, discarded.id, discarder)
		var action: String = String(decision.get("action", "skip"))
		var priority: int = 0
		if action == "pon" or action == "minkan":
			priority = 2
		elif action == "chi":
			priority = 1
		if priority > best_priority:
			best_priority = priority
			best_seat = candidate
			best_claim = decision
	if best_seat < 0:
		engine.advance_to_next_seat()
		return
	var action: String = String(best_claim.get("action", ""))
	var claimed_ti := TileInstance.make(discarded, discarder, null)
	if action == "pon":
		if engine.apply_pon(best_seat, discarded):
			_emit(&"PLAYER_ACTION", best_seat, null, {"kind": "pon", "tile_id": discarded.id})
			_emit(&"TILE_CLAIMED", best_seat, claimed_ti, {"discarder_seat": discarder, "claim_type": "pon"})
		else:
			engine.advance_to_next_seat()
	elif action == "minkan":
		if engine.apply_minkan(best_seat, discarded):
			_emit(&"PLAYER_ACTION", best_seat, null, {"kind": "minkan", "tile_id": discarded.id})
			_emit(&"TILE_CLAIMED", best_seat, claimed_ti, {"discarder_seat": discarder, "claim_type": "minkan"})
		else:
			engine.advance_to_next_seat()
	else:
		engine.advance_to_next_seat()
```

Then update `run_to_end()` and `run_to_end_async()` to replace the CLAIM skip. In `run_to_end()`:

```gdscript
		elif state.phase == BattlePhase.Kind.CLAIM:
			# Resolve AI claims (player claims in PlayableBattleController)
			var last_discard: Tile = _get_last_discarded()
			var last_discarder: int = _get_last_discarder()
			_resolve_claims(last_discard, last_discarder)
```

Add helpers:

```gdscript
func _get_last_discarded() -> Tile:
	for i in range(events.size() - 1, -1, -1):
		if events[i].type == &"TILE_DISCARDED" and events[i].tile_instance != null:
			return Tile.new(events[i].tile_instance.tile_id, events[i].tile_instance.is_red_dora)
	return null

func _get_last_discarder() -> int:
	for i in range(events.size() - 1, -1, -1):
		if events[i].type == &"TILE_DISCARDED":
			return events[i].actor_seat
	return -1
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path godot --import && godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle -gselect=test_claim_resolution -gexit`
Expected: All PASS.

- [ ] **Step 5: Run full test suite**

Run: `godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: 0 failures. Existing tests used `run_to_end()` sync path which previously skipped CLAIM. Now AI will pon/kan, which may change game outcomes in seed-dependent tests. If any tests break due to different game flow: update seed or accept new behavior (the old behavior was wrong — AI should claim).

- [ ] **Step 6: Commit**

```bash
git add godot/battle/battle_controller.gd godot/tests/battle/test_claim_resolution.gd godot/tests/battle/test_claim_resolution.gd.uid
git commit -m "feat(battle): unified claim resolution replacing CLAIM skip

_resolve_claims collects AI pon/minkan intentions, applies priority
(pon/minkan > chi), executes via TurnEngine, emits TILE_CLAIMED event.
Both sync and async paths now run claim resolution instead of
auto-advancing.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 5: Chankan (Robbing a Kan)

When any seat declares added_kan, other seats can ron the tile being added (chankan / 抢杠). This is a standard Japanese mahjong rule. The yaku evaluator already has `Chankan` (YakuId.CHANKAN) and `GameContext.is_chankan` — they just need to be wired in.

**Files:**
- Modify: `godot/battle/battle_controller.gd`
- Create: `godot/tests/battle/test_chankan.gd`

- [ ] **Step 1: Write failing tests**

Create `godot/tests/battle/test_chankan.gd`:

```gdscript
extends GutTest

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func test_chankan_ron_on_added_kan():
	# Seat 1 declares added_kan on W5.
	# Seat 2 is tenpai waiting for W5 → should ron (chankan).
	var bc := BattleController.new(100, 0, true)
	# Seat 2: tenpai waiting W5 (kanchan W4-W6)
	bc.state.seats[2].hand = _hand([
		TileId.W4, TileId.W6,  # waiting W5
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	bc.state.seats[2].furiten = FuritenState.new()
	# Seat 1 setup: has W5 in hand + PON of W5
	bc.state.seats[1].hand = _hand([
		TileId.W5,  # 4th copy for added_kan
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.S5, TileId.S5, TileId.S5,
	])
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 0)
	bc.state.seats[1].melds = [pon]
	# Try chankan
	var ronned: bool = bc._try_chankan_ron(TileId.W5, 1)
	assert_true(ronned, "seat 2 should ron via chankan")

func test_chankan_no_ron_when_furiten():
	var bc := BattleController.new(100, 0, true)
	bc.state.seats[2].hand = _hand([
		TileId.W4, TileId.W6,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	bc.state.seats[2].furiten = FuritenState.new()
	bc.state.seats[2].furiten.permanent = true  # furiten blocks ron
	bc.state.seats[1].hand = _hand([TileId.W5])
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 0)
	bc.state.seats[1].melds = [pon]
	var ronned: bool = bc._try_chankan_ron(TileId.W5, 1)
	assert_false(ronned, "furiten blocks chankan ron")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path godot --import && godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle -gselect=test_chankan -gexit`
Expected: FAIL — `_try_chankan_ron` not defined.

- [ ] **Step 3: Implement chankan in BattleController**

Add to `godot/battle/battle_controller.gd`:

```gdscript
# Chankan: when a seat declares added_kan, other seats can ron the tile.
# Returns true if someone ronned (game settles).
func _try_chankan_ron(kan_tile_id: int, kan_declarer: int) -> bool:
	var kan_tile := Tile.new(kan_tile_id)
	for offset in range(1, 4):
		var candidate: int = (kan_declarer + offset) % 4
		var seat: Seat = state.seats[candidate]
		if not ClaimValidator.can_ron(seat.hand, seat.melds, kan_tile, seat.furiten):
			continue
		var ron_check: Dictionary = _check_ron_chankan(kan_tile, candidate)
		if not ron_check.is_winning:
			continue
		if apply_ron(candidate, kan_tile, kan_declarer, false):
			return true
	return false

# Like _check_ron but with is_chankan=true in GameContext.
func _check_ron_chankan(ron_tile: Tile, winner_seat: int) -> Dictionary:
	var winner: Seat = state.seats[winner_seat]
	var typed_melds: Array[Meld] = []
	for m in winner.melds:
		typed_melds.append(m)
	var wp: Dictionary = WinPattern.detect(winner.hand, typed_melds, ron_tile)
	if not wp.is_winning:
		return {"is_winning": false}
	var game_ctx := _build_game_ctx(winner, false)
	game_ctx.is_chankan = true
	var yaku_wc := WinContext.new(winner.hand, typed_melds, ron_tile, wp, game_ctx)
	var yaku_list = YakuEvaluator.evaluate(yaku_wc)
	var has_yaku: bool = yaku_list.is_yakuman() or yaku_list.size() > 0
	if not has_yaku:
		return {"is_winning": false}
	return {"is_winning": true, "wp": wp, "yaku_list": yaku_list, "melds": typed_melds}
```

Then wire chankan into `_try_ai_self_kan()` — before applying added_kan, check for chankan:

```gdscript
	elif action == "added_kan":
		var tid: int = int(decision.get("tile_id", -1))
		# Chankan check: before applying, let others ron
		if _try_chankan_ron(tid, actor):
			return  # someone ronned the kan tile
		if engine.apply_added_kan(actor, tid):
			_emit(&"PLAYER_ACTION", actor, null, {"kind": "added_kan", "tile_id": tid})
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path godot --import && godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle -gselect=test_chankan -gexit`
Expected: All PASS.

- [ ] **Step 5: Run full test suite**

Run: `godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add godot/battle/battle_controller.gd godot/tests/battle/test_chankan.gd godot/tests/battle/test_chankan.gd.uid
git commit -m "feat(battle): chankan (robbing a kan) implementation

When added_kan is declared, other seats can ron the kan tile.
Uses GameContext.is_chankan=true for yaku evaluation (gives +1 han
chankan yaku). Wired into both AI self-kan and future player kan paths.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 6: Player Self-Kan UI + Claim Resolution Override

Wire player self-kan (ankan/added_kan) into PlayableBattleController's draw phase, and ensure player claims integrate with AI claim resolution.

**Files:**
- Modify: `godot/battle/playable_battle_controller.gd`
- Modify: `godot/ui/four_player_table/player_action_panel.gd`

- [ ] **Step 1: Add ankan/added_kan buttons to PlayerActionPanel**

In `godot/ui/four_player_table/player_action_panel.gd`, add new button vars and a new state:

```gdscript
var _btn_ankan: Button = null
var _btn_added_kan: Button = null
```

In `_build_ui()`, add them after existing buttons (adjust PANEL_W to 660 to fit):

```gdscript
_btn_ankan = _make_btn("暗杠", 12 + 462, 32, Color(0.85, 0.50, 0.15))
_btn_added_kan = _make_btn("加杠", 12 + 528, 32, Color(0.85, 0.50, 0.15))
_btn_skip = _make_btn("跳过", 12 + 594, 32, Color(0.55, 0.55, 0.55))

_btn_ankan.pressed.connect(_on_btn_ankan)
_btn_added_kan.pressed.connect(_on_btn_added_kan)
```

Add button callbacks:

```gdscript
func _on_btn_ankan() -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		player_action_chosen.emit({"action": "ankan"})

func _on_btn_added_kan() -> void:
	if _state == State.WAITING_DISCARD:
		_click_sfx()
		player_action_chosen.emit({"action": "added_kan"})
```

Update `enter_waiting_discard` to accept kan availability:

```gdscript
func enter_waiting_discard(can_tsumo: bool, can_ankan: bool = false, can_added_kan: bool = false) -> void:
	_state = State.WAITING_DISCARD
	_label_status.text = "轮到你出牌（点手牌切）"
	_hide_btn(_btn_riichi)
	if can_tsumo:
		_show_btn(_btn_tsumo)
	else:
		_hide_btn(_btn_tsumo)
	_hide_btn(_btn_ron)
	_hide_btn(_btn_chi)
	_hide_btn(_btn_pon)
	_hide_btn(_btn_minkan)
	_hide_btn(_btn_skip)
	if can_ankan:
		_show_btn(_btn_ankan)
	else:
		_hide_btn(_btn_ankan)
	if can_added_kan:
		_show_btn(_btn_added_kan)
	else:
		_hide_btn(_btn_added_kan)
```

Update `_refresh_bg` to include new buttons, and `enter_idle` / other `enter_*` methods to hide them.

- [ ] **Step 2: Handle ankan/added_kan in PlayableBattleController**

In `godot/battle/playable_battle_controller.gd`, modify `_get_discard_decision` to detect kan availability and pass to UI, then handle the action:

In the player path of `_get_discard_decision`, before `_action_panel.enter_waiting_discard`:

```gdscript
	# Check if player can declare self-kan
	var can_ankan: bool = not ClaimValidator.ankan_candidates(seat.hand).is_empty()
	var can_added: bool = false
	for m in seat.melds:
		if m.kind == Meld.Kind.PON:
			if ClaimValidator.can_added_kan(seat.melds, seat.hand, m.tiles[0].id):
				can_added = true
				break
	_action_panel.enter_waiting_discard(false, can_ankan, can_added)
```

In the action loop, handle ankan/added_kan:

```gdscript
		if action == "ankan":
			var ankan_ids: Array = ClaimValidator.ankan_candidates(seat.hand)
			if not ankan_ids.is_empty():
				# Chankan not applicable to ankan (concealed)
				if engine.apply_ankan(actor, ankan_ids[0]):
					_emit(&"PLAYER_ACTION", actor, null, {"kind": "ankan", "tile_id": ankan_ids[0]})
					_seat_panel_player.set_hand_clickable(false)
					_action_panel.enter_idle("暗杠！")
					return null  # returning null signals BC to skip normal discard (phase is already DISCARD from rinshan)
			continue
		elif action == "added_kan":
			for m in seat.melds:
				if m.kind == Meld.Kind.PON:
					var tid: int = m.tiles[0].id
					if ClaimValidator.can_added_kan(seat.melds, seat.hand, tid):
						if _try_chankan_ron(tid, actor):
							_seat_panel_player.set_hand_clickable(false)
							_action_panel.enter_idle("抢杠！")
							return null
						if engine.apply_added_kan(actor, tid):
							_emit(&"PLAYER_ACTION", actor, null, {"kind": "added_kan", "tile_id": tid})
							_seat_panel_player.set_hand_clickable(false)
							_action_panel.enter_idle("加杠！")
							return null
						break
			continue
```

- [ ] **Step 3: Override _resolve_claims in PlayableBattleController**

Override `_resolve_claims` to integrate player claiming with AI claiming:

```gdscript
func _resolve_claims(discarded: Tile, discarder: int) -> void:
	if discarder == PLAYER_SEAT:
		# Player discarded — only AI can claim
		super(discarded, discarder)
		return
	# AI discarded — player already had claim window in _try_player_claim_async
	# If player claimed, phase is already DISCARD. If player skipped, check AI claims.
	if state.phase == BattlePhase.Kind.DISCARD:
		return  # player already claimed
	super(discarded, discarder)
```

- [ ] **Step 4: Run full test suite**

Run: `godot --headless --path godot --import && godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add godot/battle/playable_battle_controller.gd godot/ui/four_player_table/player_action_panel.gd
git commit -m "feat(ui): player self-kan buttons + claim resolution integration

Adds ankan/added_kan buttons to PlayerActionPanel. Player can declare
concealed quad or add to existing pon during their discard phase.
Chankan check runs before added_kan. Player claims integrate with
AI claim resolution priority.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 7: Wire Kuikae into Discard Validation + Integration Test

After a chi/pon claim, the claimant must not discard a kuikae-restricted tile. Add validation in BattleController and a full integration test running `run_to_end()`.

**Files:**
- Modify: `godot/battle/battle_controller.gd`
- Modify: `godot/battle/battle_state.gd`

- [ ] **Step 1: Add kuikae tracking to BattleState**

Add to `godot/battle/battle_state.gd`:

```gdscript
var kuikae_restricted: Array = [[], [], [], []]  # per-seat restricted tile IDs after claim
```

- [ ] **Step 2: Set kuikae after claims in BattleController**

In `_resolve_claims`, after successful pon/chi, record restrictions:

```gdscript
	if action == "pon":
		if engine.apply_pon(best_seat, discarded):
			state.kuikae_restricted[best_seat] = ClaimValidator.kuikae_restricted_ids(
				discarded.id, [], false)
			# ... emit events
```

Clear kuikae after discard in `_step_discard` / `_step_discard_async`:

```gdscript
	# Clear kuikae restriction after discard completes
	state.kuikae_restricted[actor] = []
```

- [ ] **Step 3: Enforce kuikae in AI discard**

In `_get_discard_decision`, filter out restricted tiles:

```gdscript
func _get_discard_decision(seat: Seat, actor: int) -> Tile:
	# ... existing riichi tsumogiri logic ...
	var pick: Tile = ai.decide_discard(seat)
	# Kuikae: if AI picks a restricted tile, find alternative
	if not state.kuikae_restricted[actor].is_empty():
		var restricted: Array = state.kuikae_restricted[actor]
		if pick != null and restricted.has(pick.id):
			for t in seat.hand._tiles:
				if not restricted.has(t.id):
					return t
	return pick
```

- [ ] **Step 4: Run full test suite**

Run: `godot --headless --path godot --import && godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add godot/battle/battle_controller.gd godot/battle/battle_state.gd
git commit -m "feat(battle): enforce kuikae restriction after chi/pon

After claiming, the claimant cannot discard the restricted tile IDs
(claimed tile + suji partner for chi). Restriction clears after
the claimant's discard completes.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 8: Full Integration Regression + Cleanup

Run the entire test suite, verify the game still plays end-to-end with claiming enabled, fix any regressions.

**Files:**
- All modified files from Tasks 1-7

- [ ] **Step 1: Rebuild class cache**

Run: `godot --headless --path godot --import`

- [ ] **Step 2: Run full test suite**

Run: `godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
Expected: 0 failures, 0 parse errors.

- [ ] **Step 3: Run a BattleController end-to-end smoke test**

Verify that `run_to_end()` with heuristic AI completes without error and produces claim events:

```bash
godot --headless --path godot -d -s addons/gut/gut_cmdln.gd -gdir=res://tests/battle -gselect=test_claim_resolution -gexit
```

- [ ] **Step 4: Fix any regressions**

If any existing tests break due to changed game outcomes (AI now claims), update the specific assertion or seed. Document why in the commit.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "test: integration regression fixes for claim window

Updated seed-dependent test assertions to account for AI claiming
behavior. All tests pass with claim resolution active.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```
