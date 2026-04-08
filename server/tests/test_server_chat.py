from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient
from notes_server.server import create_app
from notes_server.groq_client import GroqResult
from tests.test_server_health import make_test_config

def test_chat_endpoint_returns_reply(tmp_path):
    app = create_app(make_test_config(tmp_path))
    with patch("notes_server.server.GroqClient") as MockClient:
        instance = MagicMock()
        instance.chat.return_value = GroqResult(
            text="hello back", tokens=20, model="llama-3.3-70b-versatile",
        )
        MockClient.return_value = instance
        client = TestClient(app)
        r = client.post("/ai/chat", json={
            "page_id": "p1",
            "message": "hi",
            "history": [],
            "scope": "page",
        })
    assert r.status_code == 200
    body = r.json()
    assert body["reply"] == "hello back"
    assert body["tokens_used"] == 20
    assert body["model_used"] == "llama-3.3-70b-versatile"

def test_chat_returns_503_when_pool_exhausted(tmp_path):
    app = create_app(make_test_config(tmp_path))
    state = app.state.ctx
    for k in list(state.key_pool._states):
        state.key_pool.mark_rate_limited(k.key, retry_after=9999)
    client = TestClient(app)
    r = client.post("/ai/chat", json={
        "page_id": "p1", "message": "hi", "history": [], "scope": "page",
    })
    assert r.status_code == 503
    assert "all keys exhausted" in r.json()["detail"].lower()
