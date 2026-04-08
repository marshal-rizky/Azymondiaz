from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient
from notes_server.server import create_app
from notes_server.groq_client import GroqResult
from tests.test_server_health import make_test_config

def test_transform_cleanup(tmp_path):
    app = create_app(make_test_config(tmp_path))
    with patch("notes_server.server.GroqClient") as MockClient:
        instance = MagicMock()
        instance.vision.return_value = GroqResult(
            text="clean text", tokens=15, model="llama-3.2-90b-vision-preview",
        )
        MockClient.return_value = instance
        client = TestClient(app)
        r = client.post("/ai/transform", json={
            "action": "cleanup",
            "image_base64": "AAAA",
        })
    assert r.status_code == 200
    body = r.json()
    assert body["result_type"] == "text"
    assert body["text"] == "clean text"
    assert body["model_used"] == "llama-3.2-90b-vision-preview"

def test_transform_list_returns_markdown(tmp_path):
    app = create_app(make_test_config(tmp_path))
    with patch("notes_server.server.GroqClient") as MockClient:
        instance = MagicMock()
        instance.vision.return_value = GroqResult(
            text="- item one\n- item two", tokens=10, model="llama-3.2-90b-vision-preview",
        )
        MockClient.return_value = instance
        client = TestClient(app)
        r = client.post("/ai/transform", json={
            "action": "list",
            "image_base64": "AAAA",
        })
    body = r.json()
    assert body["result_type"] == "markdown"
    assert "item one" in body["markdown"]
