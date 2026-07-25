"""Backup new-api circuit breaker with injectable monotonic clock.

Only real backup HTTP attempts count as failures. Fast-fails while OPEN do not.
HALF_OPEN allows a single concurrent probe.

Each successful try_acquire returns a CircuitPermit (generation + probe flag).
record_success/record_failure consume that permit exactly once; repeat or
cross-result settlement returns False and does not change state. Stale permits
from an older generation never change state.
"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Callable


class CircuitState(str, Enum):
    CLOSED = "CLOSED"
    OPEN = "OPEN"
    HALF_OPEN = "HALF_OPEN"


@dataclass(frozen=True)
class CircuitPermit:
    """Lease for one real backup HTTP attempt."""

    generation: int
    is_probe: bool
    token: int


class CircuitBreaker:
    def __init__(
        self,
        *,
        failure_threshold: int = 3,
        cooldown_ms: int = 30_000,
        clock_ms: Callable[[], float] | None = None,
    ) -> None:
        self.failure_threshold = max(1, int(failure_threshold))
        self.cooldown_ms = max(1, int(cooldown_ms))
        self._clock_ms = clock_ms or (lambda: time.monotonic() * 1000.0)
        self._lock = threading.RLock()
        self._state = CircuitState.CLOSED
        self._failures = 0
        self._opened_at_ms = 0.0
        self._generation = 0
        self._next_token = 1
        self._half_open_probe_token: int | None = None
        # Current-generation unsettled permits only (bounded by in-flight backups).
        self._active_tokens: set[int] = set()

    def state(self) -> str:
        with self._lock:
            self._maybe_half_open()
            return self._state.value

    def failure_count(self) -> int:
        with self._lock:
            return self._failures

    def try_acquire(self) -> CircuitPermit | None:
        """Return a permit if a real backup HTTP call may proceed; else None."""
        with self._lock:
            self._maybe_half_open()
            if self._state is CircuitState.OPEN:
                return None
            if self._state is CircuitState.HALF_OPEN:
                if self._half_open_probe_token is not None:
                    return None
                token = self._alloc_token()
                self._half_open_probe_token = token
                return CircuitPermit(
                    generation=self._generation,
                    is_probe=True,
                    token=token,
                )
            token = self._alloc_token()
            return CircuitPermit(
                generation=self._generation,
                is_probe=False,
                token=token,
            )

    def record_success(self, permit: CircuitPermit) -> bool:
        """Consume permit once and apply success, or no-op if already settled/stale."""
        with self._lock:
            if not self._take_permit_for_settlement(permit):
                return False
            if permit.is_probe:
                # Valid HALF_OPEN probe: recover.
                self._state = CircuitState.CLOSED
                self._failures = 0
                self._bump_generation()
                return True
            # CLOSED success: clear failure streak.
            self._failures = 0
            return True

    def record_failure(self, permit: CircuitPermit) -> bool:
        """Consume permit once and apply failure, or no-op if already settled/stale."""
        with self._lock:
            if not self._take_permit_for_settlement(permit):
                return False
            if permit.is_probe:
                self._state = CircuitState.OPEN
                self._opened_at_ms = float(self._clock_ms())
                self._bump_generation()
                return True
            self._failures += 1
            if self._failures >= self.failure_threshold:
                self._state = CircuitState.OPEN
                self._opened_at_ms = float(self._clock_ms())
                self._bump_generation()
            return True

    def snapshot(self) -> dict[str, str | int | bool]:
        """Health summary — never includes secrets or endpoints."""
        with self._lock:
            self._maybe_half_open()
            return {
                "circuit": self._state.value,
                "failures": self._failures,
            }

    def _alloc_token(self) -> int:
        token = self._next_token
        self._next_token += 1
        self._active_tokens.add(token)
        return token

    def _take_permit_for_settlement(self, permit: CircuitPermit) -> bool:
        """Validate generation/state/token, then remove from active (one-shot)."""
        if not isinstance(permit, CircuitPermit):
            return False
        if permit.generation != self._generation:
            return False
        if permit.token not in self._active_tokens:
            return False
        if permit.is_probe:
            if self._state is not CircuitState.HALF_OPEN:
                return False
            if self._half_open_probe_token != permit.token:
                return False
        else:
            if self._state is not CircuitState.CLOSED:
                return False
        self._active_tokens.discard(permit.token)
        if permit.is_probe:
            self._half_open_probe_token = None
        return True

    def _bump_generation(self) -> None:
        self._generation += 1
        self._active_tokens.clear()
        self._half_open_probe_token = None

    def _maybe_half_open(self) -> None:
        if self._state is CircuitState.OPEN:
            now = float(self._clock_ms())
            if now - self._opened_at_ms >= self.cooldown_ms:
                self._state = CircuitState.HALF_OPEN
                self._half_open_probe_token = None
                # Generation kept; active set already cleared at OPEN.
