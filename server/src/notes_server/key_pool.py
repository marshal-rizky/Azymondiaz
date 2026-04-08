import time
from dataclasses import dataclass
from typing import Literal

Status = Literal["ok", "cooling_down", "dead"]


@dataclass
class KeyState:
    key: str
    status: Status = "ok"
    cooldown_until: float = 0.0
    consecutive_errors: int = 0


class KeyPool:
    def __init__(self, keys: list[str], cooldown_seconds: int = 60):
        self._states: list[KeyState] = [KeyState(key=k) for k in keys]
        self._cooldown = cooldown_seconds
        self._cursor = 0

    def _is_available(self, s: KeyState) -> bool:
        if s.status == "dead":
            return False
        if s.status == "cooling_down" and time.time() < s.cooldown_until:
            return False
        if s.status == "cooling_down" and time.time() >= s.cooldown_until:
            s.status = "ok"
        return True

    def pick(self) -> str | None:
        n = len(self._states)
        for _ in range(n):
            s = self._states[self._cursor % n]
            self._cursor += 1
            if self._is_available(s):
                return s.key
        return None

    def _find(self, key: str) -> KeyState | None:
        return next((s for s in self._states if s.key == key), None)

    def mark_rate_limited(self, key: str, retry_after: float | None = None):
        s = self._find(key)
        if not s:
            return
        s.status = "cooling_down"
        s.cooldown_until = time.time() + (retry_after or self._cooldown)

    def mark_error(self, key: str):
        s = self._find(key)
        if not s:
            return
        s.consecutive_errors += 1
        if s.consecutive_errors >= 3:
            s.status = "dead"

    def mark_success(self, key: str):
        s = self._find(key)
        if not s:
            return
        s.consecutive_errors = 0
        if s.status != "dead":
            s.status = "ok"

    def summary(self) -> dict[str, dict]:
        return {
            s.key: {
                "status": s.status,
                "cooldown_until": s.cooldown_until,
                "consecutive_errors": s.consecutive_errors,
            }
            for s in self._states
        }
