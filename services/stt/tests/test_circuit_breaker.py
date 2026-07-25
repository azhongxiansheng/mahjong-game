"""Deterministic circuit breaker tests with injectable clock + generation permits."""

from __future__ import annotations

from stt_service.circuit_breaker import CircuitBreaker, CircuitState


class FakeClock:
    def __init__(self, start: float = 0.0) -> None:
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, ms: float) -> None:
        self.now += ms


def test_closed_to_open_then_fast_fail():
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=3, cooldown_ms=1000, clock_ms=clock)
    assert cb.state() == CircuitState.CLOSED.value
    p1 = cb.try_acquire()
    assert p1 is not None
    assert cb.record_failure(p1) is True
    p2 = cb.try_acquire()
    assert p2 is not None
    assert cb.record_failure(p2) is True
    assert cb.state() == CircuitState.CLOSED.value
    p3 = cb.try_acquire()
    assert p3 is not None
    assert cb.record_failure(p3) is True
    assert cb.state() == CircuitState.OPEN.value
    assert cb.try_acquire() is None  # fast fail, no HTTP
    assert cb.failure_count() == 3


def test_stale_closed_success_does_not_close_open():
    """Codex P2-1 repro: concurrent CLOSED acquires; first fails OPEN; second success must not CLOSED."""
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=1, cooldown_ms=10_000, clock_ms=clock)
    old_a = cb.try_acquire()
    old_b = cb.try_acquire()
    assert old_a is not None and old_b is not None
    assert cb.record_failure(old_a) is True
    assert cb.state() == CircuitState.OPEN.value
    assert cb.record_success(old_b) is False  # stale generation
    assert cb.state() == CircuitState.OPEN.value
    assert cb.try_acquire() is None


def test_stale_success_does_not_close_half_open_or_steal_probe():
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=1, cooldown_ms=500, clock_ms=clock)
    stale = cb.try_acquire()
    assert stale is not None
    assert cb.record_failure(stale) is True
    assert cb.state() == CircuitState.OPEN.value
    clock.advance(500)
    assert cb.state() == CircuitState.HALF_OPEN.value
    # Stale CLOSED success must not recover before/during real probe.
    assert cb.record_success(stale) is False
    assert cb.state() == CircuitState.HALF_OPEN.value
    probe = cb.try_acquire()
    assert probe is not None and probe.is_probe is True
    assert cb.try_acquire() is None  # only one probe
    assert cb.record_success(stale) is False  # still cannot steal
    assert cb.state() == CircuitState.HALF_OPEN.value
    assert cb.record_success(probe) is True
    assert cb.state() == CircuitState.CLOSED.value
    assert cb.failure_count() == 0


def test_half_open_probe_failure_reopens():
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=2, cooldown_ms=100, clock_ms=clock)
    p1 = cb.try_acquire()
    assert p1 is not None
    cb.record_failure(p1)
    p2 = cb.try_acquire()
    assert p2 is not None
    cb.record_failure(p2)
    assert cb.state() == CircuitState.OPEN.value
    clock.advance(100)
    probe = cb.try_acquire()
    assert probe is not None and probe.is_probe is True
    assert cb.record_failure(probe) is True
    assert cb.state() == CircuitState.OPEN.value
    assert cb.try_acquire() is None


def test_half_open_single_probe_and_recover():
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=2, cooldown_ms=500, clock_ms=clock)
    for _ in range(2):
        p = cb.try_acquire()
        assert p is not None
        cb.record_failure(p)
    assert cb.state() == CircuitState.OPEN.value
    clock.advance(500)
    assert cb.state() == CircuitState.HALF_OPEN.value
    probe = cb.try_acquire()
    assert probe is not None
    assert cb.try_acquire() is None  # concurrent half-open blocked
    assert cb.record_success(probe) is True
    assert cb.state() == CircuitState.CLOSED.value
    assert cb.failure_count() == 0
    assert cb.try_acquire() is not None


def test_concurrent_closed_failures_reach_threshold():
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=2, cooldown_ms=1000, clock_ms=clock)
    a = cb.try_acquire()
    b = cb.try_acquire()
    assert a is not None and b is not None
    assert cb.record_failure(a) is True
    assert cb.state() == CircuitState.CLOSED.value
    assert cb.record_failure(b) is True
    assert cb.state() == CircuitState.OPEN.value
    assert cb.try_acquire() is None
    # Further stale failure also ignored
    assert cb.record_failure(a) is False
    assert cb.state() == CircuitState.OPEN.value


def test_same_permit_double_failure_does_not_open():
    """P2 r3：同一 CLOSED permit 只能结算一次；重复 failure 不得把一次 HTTP 计两次。"""
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=2, cooldown_ms=1000, clock_ms=clock)
    p = cb.try_acquire()
    assert p is not None
    assert cb.record_failure(p) is True
    assert cb.state() == CircuitState.CLOSED.value
    assert cb.failure_count() == 1
    # 同 permit 再次 failure：无效
    assert cb.record_failure(p) is False
    assert cb.state() == CircuitState.CLOSED.value
    assert cb.failure_count() == 1
    # 另一真实请求才能把计数推到阈值
    p2 = cb.try_acquire()
    assert p2 is not None
    assert cb.record_failure(p2) is True
    assert cb.state() == CircuitState.OPEN.value
    assert cb.failure_count() == 2


def test_permit_success_then_failure_noop():
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=2, cooldown_ms=1000, clock_ms=clock)
    p = cb.try_acquire()
    assert p is not None
    assert cb.record_success(p) is True
    assert cb.failure_count() == 0
    assert cb.record_failure(p) is False
    assert cb.state() == CircuitState.CLOSED.value
    assert cb.failure_count() == 0


def test_permit_failure_then_success_noop():
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=3, cooldown_ms=1000, clock_ms=clock)
    p = cb.try_acquire()
    assert p is not None
    assert cb.record_failure(p) is True
    assert cb.failure_count() == 1
    assert cb.record_success(p) is False
    assert cb.state() == CircuitState.CLOSED.value
    assert cb.failure_count() == 1  # 不得被已消费 permit 清零


def test_half_open_probe_settled_only_once():
    clock = FakeClock()
    cb = CircuitBreaker(failure_threshold=1, cooldown_ms=100, clock_ms=clock)
    p0 = cb.try_acquire()
    assert p0 is not None
    assert cb.record_failure(p0) is True
    clock.advance(100)
    probe = cb.try_acquire()
    assert probe is not None and probe.is_probe is True
    assert cb.record_success(probe) is True
    assert cb.state() == CircuitState.CLOSED.value
    # probe 已消费：重复 success/failure 均无效
    assert cb.record_success(probe) is False
    assert cb.record_failure(probe) is False
    assert cb.state() == CircuitState.CLOSED.value


def test_snapshot_has_no_secrets_shape():
    cb = CircuitBreaker(failure_threshold=1, cooldown_ms=10, clock_ms=FakeClock())
    snap = cb.snapshot()
    assert set(snap.keys()) <= {"circuit", "failures"}
    blob = str(snap)
    assert "token" not in blob.lower()
    assert "Bearer" not in blob
