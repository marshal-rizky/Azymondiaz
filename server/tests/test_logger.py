import json
from pathlib import Path
from notes_server.logger import RequestLogger

def test_logs_request_to_jsonl(tmp_path: Path):
    logger = RequestLogger(tmp_path)
    logger.log({
        "action": "chat",
        "model": "llama-3.3-70b-versatile",
        "latency_ms": 842,
        "tokens": 310,
    })
    logfile = tmp_path / "requests.jsonl"
    assert logfile.exists()
    line = logfile.read_text().strip()
    parsed = json.loads(line)
    assert parsed["action"] == "chat"
    assert "timestamp" in parsed

def test_multiple_entries_append(tmp_path: Path):
    logger = RequestLogger(tmp_path)
    logger.log({"action": "a"})
    logger.log({"action": "b"})
    lines = (tmp_path / "requests.jsonl").read_text().strip().splitlines()
    assert len(lines) == 2
    assert json.loads(lines[0])["action"] == "a"
    assert json.loads(lines[1])["action"] == "b"
