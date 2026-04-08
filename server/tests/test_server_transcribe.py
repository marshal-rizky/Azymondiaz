import base64
from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient
from notes_server.server import create_app
from notes_server.groq_client import GroqResult
from tests.test_server_health import make_test_config

def test_transcribe_returns_text(tmp_path):
    app = create_app(make_test_config(tmp_path))
    with patch("notes_server.server.GroqClient") as MockClient:
        instance = MagicMock()
        instance.transcribe.return_value = GroqResult(
            text="halo dunia", tokens=0, model="whisper-large-v3-turbo",
        )
        MockClient.return_value = instance
        client = TestClient(app)
        audio_b64 = base64.b64encode(b"fake-wav").decode()
        r = client.post("/ai/transcribe", json={
            "audio_base64": audio_b64,
            "language": "id",
        })
    assert r.status_code == 200
    assert r.json()["text"] == "halo dunia"
    instance.transcribe.assert_called_once()
    call = instance.transcribe.call_args.kwargs
    assert call["language"] == "id"
