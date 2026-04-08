import time
from pathlib import Path
from notes_server.prompts import PromptLoader

def test_loads_prompt_from_file(tmp_path: Path):
    (tmp_path / "hello.txt").write_text("say hello")
    loader = PromptLoader(tmp_path)
    assert loader.get("hello") == "say hello"

def test_missing_prompt_raises(tmp_path: Path):
    import pytest
    loader = PromptLoader(tmp_path)
    with pytest.raises(KeyError):
        loader.get("nope")

def test_hot_reload_picks_up_changes(tmp_path: Path):
    f = tmp_path / "greet.txt"
    f.write_text("v1")
    loader = PromptLoader(tmp_path)
    assert loader.get("greet") == "v1"
    time.sleep(0.05)
    f.write_text("v2")
    import os
    os.utime(f, None)
    assert loader.get("greet") == "v2"
