import time
from notes_server.key_pool import KeyPool, KeyState

def make_pool(keys=None, cooldown=1):
    return KeyPool(keys=keys or ["k1", "k2", "k3"], cooldown_seconds=cooldown)

def test_pick_returns_keys_round_robin():
    pool = make_pool()
    picks = [pool.pick() for _ in range(6)]
    assert picks == ["k1", "k2", "k3", "k1", "k2", "k3"]

def test_mark_rate_limited_skips_key_until_cooldown_expires():
    pool = make_pool(cooldown=1)
    pool.mark_rate_limited("k1")
    assert pool.pick() == "k2"
    assert pool.pick() == "k3"
    assert pool.pick() == "k2"   # k1 still cooling
    time.sleep(1.1)
    # k1 should be back in rotation
    assert "k1" in [pool.pick() for _ in range(3)]

def test_three_consecutive_errors_mark_key_dead():
    pool = make_pool()
    for _ in range(3):
        pool.mark_error("k1")
    picks = [pool.pick() for _ in range(10)]
    assert "k1" not in picks

def test_all_keys_exhausted_returns_none():
    pool = make_pool(keys=["only"], cooldown=999)
    pool.mark_rate_limited("only")
    assert pool.pick() is None

def test_successful_call_resets_error_count():
    pool = make_pool()
    pool.mark_error("k1")
    pool.mark_error("k1")
    pool.mark_success("k1")
    pool.mark_error("k1")
    pool.mark_error("k1")
    # still alive (4 errors but reset in middle, so 2 consecutive)
    picks = [pool.pick() for _ in range(9)]
    assert "k1" in picks

def test_summary_returns_status_per_key():
    pool = make_pool()
    pool.mark_rate_limited("k2")
    summary = pool.summary()
    assert summary["k1"]["status"] == "ok"
    assert summary["k2"]["status"] == "cooling_down"
    assert summary["k3"]["status"] == "ok"
