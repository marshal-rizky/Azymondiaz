import json
import time
from pathlib import Path
from typing import Any


class RequestLogger:
    def __init__(self, log_dir: Path):
        self._dir = Path(log_dir)
        self._dir.mkdir(parents=True, exist_ok=True)
        self._path = self._dir / "requests.jsonl"

    def log(self, entry: dict[str, Any]) -> None:
        record = {"timestamp": time.time(), **entry}
        with self._path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")
