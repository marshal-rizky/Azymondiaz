"""
Live smoke tests — hit real Groq. Enable with:
    RUN_LIVE_TESTS=1 pytest tests/test_live.py -v -s

Requires a real config.yaml at server/config.yaml with working keys.
"""
import os
import base64
import pytest
from pathlib import Path
from fastapi.testclient import TestClient
from notes_server.server import create_app
from notes_server.config import load_config

pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_LIVE_TESTS") != "1",
    reason="Live tests disabled. Set RUN_LIVE_TESTS=1 to enable.",
)

@pytest.fixture
def live_client():
    cfg = load_config(Path("config.yaml"))
    app = create_app(cfg)
    return TestClient(app)

def test_live_health(live_client):
    r = live_client.get("/health")
    assert r.status_code == 200
    print("Key pool:", r.json()["key_pool"])

def test_live_chat_returns_reply(live_client):
    r = live_client.post("/ai/chat", json={
        "page_id": "test", "message": "Say 'pong' and nothing else.",
        "history": [], "scope": "page",
    })
    assert r.status_code == 200
    print("Reply:", r.json()["reply"])
    assert len(r.json()["reply"]) > 0

def test_live_transform_cleanup_with_fixture(live_client):
    fixture = Path("tests/fixtures/math_sample.png")
    if not fixture.exists():
        pytest.skip("No math_sample.png fixture")
    b64 = base64.b64encode(fixture.read_bytes()).decode()
    r = live_client.post("/ai/transform", json={
        "action": "cleanup",
        "image_base64": b64,
    })
    assert r.status_code == 200
    print("Result:", r.json())
