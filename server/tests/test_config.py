import textwrap
from pathlib import Path
from notes_server.config import Config, load_config

def test_load_config_parses_groq_keys(tmp_path: Path):
    cfg = tmp_path / "config.yaml"
    cfg.write_text(textwrap.dedent("""
        groq:
          keys: [k1, k2, k3]
          cooldown_seconds: 30
          models:
            chat: llama-3.3-70b-versatile
            vision: llama-3.2-90b-vision-preview
            whisper: whisper-large-v3-turbo
        mathpix:
          enabled: false
          app_id: ""
          app_key: ""
        sync:
          db_path: ./test.sqlite
        voice:
          default_language: auto
        ai:
          response_language: match_input
        logging:
          dir: ./logs
    """))

    config = load_config(cfg)

    assert isinstance(config, Config)
    assert config.groq.keys == ["k1", "k2", "k3"]
    assert config.groq.cooldown_seconds == 30
    assert config.groq.models["chat"] == "llama-3.3-70b-versatile"
    assert config.mathpix.enabled is False
    assert config.sync.db_path == "./test.sqlite"

def test_load_config_missing_file_raises(tmp_path: Path):
    import pytest
    with pytest.raises(FileNotFoundError):
        load_config(tmp_path / "nope.yaml")
