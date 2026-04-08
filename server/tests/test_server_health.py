from fastapi.testclient import TestClient
from notes_server.server import create_app
from notes_server.config import Config, GroqConfig, MathpixConfig, SyncConfig, VoiceConfig, AIConfig, LoggingConfig

def make_test_config(tmp_path):
    return Config(
        groq=GroqConfig(
            keys=["k1","k2"], cooldown_seconds=60,
            models={"chat":"llama-3.3-70b-versatile",
                    "vision":"llama-3.2-90b-vision-preview",
                    "whisper":"whisper-large-v3-turbo"},
        ),
        mathpix=MathpixConfig(enabled=False, app_id="", app_key=""),
        sync=SyncConfig(db_path=str(tmp_path / "notes.sqlite")),
        voice=VoiceConfig(default_language="auto"),
        ai=AIConfig(response_language="match_input"),
        logging=LoggingConfig(dir=str(tmp_path / "logs")),
    )

def test_health_returns_ok(tmp_path):
    app = create_app(make_test_config(tmp_path))
    client = TestClient(app)
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert "key_pool" in body
    assert set(body["key_pool"].keys()) == {"k1", "k2"}
