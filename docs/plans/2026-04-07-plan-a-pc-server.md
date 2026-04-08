# Plan A — PC Companion Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Python/FastAPI server on the user's PC that proxies AI requests to Groq, manages a pool of API keys with rotation, hosts notebook sync storage, and serves as the prompt-iteration sandbox for the iPad app.

**Architecture:** Single-file FastAPI app (`server.py`) wiring together small, focused modules: `Config` (YAML loader), `KeyPool` (Groq key rotation with cooldown/failure tracking), `PromptLoader` (hot-reloaded `.txt` files from disk), `GroqClient` (thin wrapper over the `groq` SDK), `SyncStore` (SQLite-backed notebook mirror), and `RequestLogger` (JSON Lines audit log). All inference is cloud-only (Groq). All state is local.

**Tech Stack:**
- Python 3.11+
- FastAPI + Uvicorn
- `groq` Python SDK
- `pydantic` for request/response models
- `pyyaml` for config
- `pytest` + `pytest-asyncio` for tests
- Built-in `sqlite3` (no ORM needed for a single-user mirror)

---

## Scope

**In scope for Plan A:**
- All endpoints the iPad will call: `/ai/transform`, `/ai/chat`, `/ai/transcribe`, `/sync/push`, `/sync/pull`, `/health`
- Key pool rotation + cooldown logic
- Prompt loading and hot reload
- Request logging
- SQLite-backed sync mirror
- Optional Mathpix integration for Math mode
- End-to-end integration smoke test (manual, gated by env var)

**Out of scope (deferred):**
- iPad app (Plans B and C)
- Web dashboard over the logs (nice-to-have, not needed for MVP)
- Any actual PC-running Ollama work (rejected in spec)
- Authentication (single user on LAN; not needed)

---

## File Structure

```
server/
├── pyproject.toml
├── README.md
├── .gitignore
├── config.yaml.example
├── config.yaml           # gitignored, user creates from example
├── prompts/
│   ├── transform_cleanup.txt
│   ├── transform_typed_text.txt
│   ├── transform_math.txt
│   ├── transform_physics.txt
│   ├── transform_chemistry.txt
│   ├── transform_explain.txt
│   ├── transform_list.txt
│   └── chat_system.txt
├── src/
│   └── notes_server/
│       ├── __init__.py
│       ├── config.py         # Config dataclass + loader
│       ├── key_pool.py       # KeyState, KeyPool
│       ├── prompts.py        # PromptLoader with mtime-based hot reload
│       ├── groq_client.py    # GroqClient wrapper
│       ├── logger.py         # RequestLogger (JSONL)
│       ├── sync_store.py     # SyncStore (SQLite)
│       ├── mathpix.py        # Optional MathpixClient
│       ├── models.py         # Pydantic request/response models
│       └── server.py         # FastAPI app, endpoints
├── tests/
│   ├── __init__.py
│   ├── conftest.py
│   ├── test_config.py
│   ├── test_key_pool.py
│   ├── test_prompts.py
│   ├── test_logger.py
│   ├── test_sync_store.py
│   ├── test_server_health.py
│   ├── test_server_chat.py
│   ├── test_server_transform.py
│   ├── test_server_transcribe.py
│   ├── test_server_sync.py
│   └── fixtures/
│       └── math_sample.png
└── logs/                  # gitignored
```

Each module has one responsibility, single-file, small enough to hold in context. Tests mirror the `src/` layout.

---

## Task 1: Project scaffolding

**Files:**
- Create: `server/pyproject.toml`
- Create: `server/.gitignore`
- Create: `server/README.md`
- Create: `server/config.yaml.example`
- Create: `server/src/notes_server/__init__.py` (empty)
- Create: `server/tests/__init__.py` (empty)
- Create: `server/tests/conftest.py`

- [ ] **Step 1: Create `server/pyproject.toml`**

```toml
[project]
name = "notes-server"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
  "fastapi>=0.110",
  "uvicorn[standard]>=0.29",
  "groq>=0.11",
  "pydantic>=2.6",
  "pyyaml>=6.0",
  "httpx>=0.27",
]

[project.optional-dependencies]
dev = [
  "pytest>=8.0",
  "pytest-asyncio>=0.23",
  "pytest-mock>=3.12",
]

[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
pythonpath = ["src"]
```

- [ ] **Step 2: Create `server/.gitignore`**

```
__pycache__/
*.pyc
.venv/
venv/
logs/
config.yaml
*.sqlite
.pytest_cache/
```

- [ ] **Step 3: Create `server/README.md`**

```markdown
# Notes Server

PC companion for the iPad AI Notes app. Proxies AI requests to Groq, manages key rotation, hosts notebook sync.

## Setup

1. `python -m venv .venv && source .venv/bin/activate` (Windows: `.venv\Scripts\activate`)
2. `pip install -e ".[dev]"`
3. `cp config.yaml.example config.yaml` and fill in your Groq keys
4. `uvicorn notes_server.server:app --reload --host 0.0.0.0 --port 8000`

## Test

```
pytest              # unit tests
RUN_LIVE_TESTS=1 pytest tests/test_live.py   # real Groq calls (manual)
```
```

- [ ] **Step 4: Create `server/config.yaml.example`**

```yaml
groq:
  keys:
    - sk-REPLACE-ME-1
    - sk-REPLACE-ME-2
    - sk-REPLACE-ME-3
    - sk-REPLACE-ME-4
    - sk-REPLACE-ME-5
  cooldown_seconds: 60
  models:
    chat: "llama-3.3-70b-versatile"
    vision: "llama-3.2-90b-vision-preview"
    whisper: "whisper-large-v3-turbo"

mathpix:
  enabled: false
  app_id: ""
  app_key: ""

sync:
  db_path: "./notes_mirror.sqlite"

voice:
  default_language: "auto"

ai:
  response_language: "match_input"

logging:
  dir: "./logs"
```

- [ ] **Step 5: Create empty `__init__.py` files and `conftest.py`**

`server/src/notes_server/__init__.py`: empty file.
`server/tests/__init__.py`: empty file.
`server/tests/conftest.py`:

```python
import sys
from pathlib import Path

# Ensure src/ is on the path for tests
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))
```

- [ ] **Step 6: Install and verify*

Run: `cd server && python -m venv .venv && .venv\Scripts\activate && pip install -e ".[dev]"`
Expected: installs without errors.
Run: `pytest`
Expected: "no tests ran" (0 tests collected is fine at this point).

- [ ] **Step 7: Commit**

```bash
git init
git add server/
git commit -m "feat(server): scaffold notes-server project"
```

---

## Task 2: Config loader

**Files:**
- Create: `server/src/notes_server/config.py`
- Create: `server/tests/test_config.py`

- [ ] **Step 1: Write the failing test**

`server/tests/test_config.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_config.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'notes_server.config'`.

- [ ] **Step 3: Write minimal implementation**

`server/src/notes_server/config.py`:

```python
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
import yaml

@dataclass
class GroqConfig:
    keys: list[str]
    cooldown_seconds: int
    models: dict[str, str]

@dataclass
class MathpixConfig:
    enabled: bool
    app_id: str
    app_key: str

@dataclass
class SyncConfig:
    db_path: str

@dataclass
class VoiceConfig:
    default_language: str

@dataclass
class AIConfig:
    response_language: str

@dataclass
class LoggingConfig:
    dir: str

@dataclass
class Config:
    groq: GroqConfig
    mathpix: MathpixConfig
    sync: SyncConfig
    voice: VoiceConfig
    ai: AIConfig
    logging: LoggingConfig

def load_config(path: Path) -> Config:
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {path}")
    raw: dict[str, Any] = yaml.safe_load(path.read_text())
    return Config(
        groq=GroqConfig(**raw["groq"]),
        mathpix=MathpixConfig(**raw["mathpix"]),
        sync=SyncConfig(**raw["sync"]),
        voice=VoiceConfig(**raw["voice"]),
        ai=AIConfig(**raw["ai"]),
        logging=LoggingConfig(**raw["logging"]),
    )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_config.py -v`
Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/config.py server/tests/test_config.py
git commit -m "feat(server): config loader"
```

---

## Task 3: KeyPool with rotation and cooldown

**Files:**
- Create: `server/src/notes_server/key_pool.py`
- Create: `server/tests/test_key_pool.py`

- [ ] **Step 1: Write the failing tests**

`server/tests/test_key_pool.py`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/test_key_pool.py -v`
Expected: all fail with import error.

- [ ] **Step 3: Write minimal implementation**

`server/src/notes_server/key_pool.py`:

```python
import time
from dataclasses import dataclass, field
from typing import Literal

Status = Literal["ok", "cooling_down", "dead"]

@dataclass
class KeyState:
    key: str
    status: Status = "ok"
    cooldown_until: float = 0.0
    consecutive_errors: int = 0

class KeyPool:
    def __init__(self, keys: list[str], cooldown_seconds: int = 60):
        self._states: list[KeyState] = [KeyState(key=k) for k in keys]
        self._cooldown = cooldown_seconds
        self._cursor = 0

    def _is_available(self, s: KeyState) -> bool:
        if s.status == "dead":
            return False
        if s.status == "cooling_down" and time.time() < s.cooldown_until:
            return False
        if s.status == "cooling_down" and time.time() >= s.cooldown_until:
            s.status = "ok"
        return True

    def pick(self) -> str | None:
        n = len(self._states)
        for _ in range(n):
            s = self._states[self._cursor % n]
            self._cursor += 1
            if self._is_available(s):
                return s.key
        return None

    def _find(self, key: str) -> KeyState | None:
        return next((s for s in self._states if s.key == key), None)

    def mark_rate_limited(self, key: str, retry_after: float | None = None):
        s = self._find(key)
        if not s:
            return
        s.status = "cooling_down"
        s.cooldown_until = time.time() + (retry_after or self._cooldown)

    def mark_error(self, key: str):
        s = self._find(key)
        if not s:
            return
        s.consecutive_errors += 1
        if s.consecutive_errors >= 3:
            s.status = "dead"

    def mark_success(self, key: str):
        s = self._find(key)
        if not s:
            return
        s.consecutive_errors = 0
        if s.status != "dead":
            s.status = "ok"

    def summary(self) -> dict[str, dict]:
        return {
            s.key: {
                "status": s.status,
                "cooldown_until": s.cooldown_until,
                "consecutive_errors": s.consecutive_errors,
            }
            for s in self._states
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/test_key_pool.py -v`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/key_pool.py server/tests/test_key_pool.py
git commit -m "feat(server): KeyPool with rotation, cooldown, and error tracking"
```

---

## Task 4: PromptLoader with hot reload

**Files:**
- Create: `server/src/notes_server/prompts.py`
- Create: `server/tests/test_prompts.py`

- [ ] **Step 1: Write the failing tests**

`server/tests/test_prompts.py`:

```python
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
    # bump mtime explicitly in case FS granularity is coarse
    import os
    os.utime(f, None)
    assert loader.get("greet") == "v2"
```

- [ ] **Step 2: Run to verify failure**

Run: `pytest tests/test_prompts.py -v`
Expected: import error.

- [ ] **Step 3: Implement**

`server/src/notes_server/prompts.py`:

```python
from pathlib import Path

class PromptLoader:
    def __init__(self, base_dir: Path):
        self._base = Path(base_dir)
        self._cache: dict[str, tuple[float, str]] = {}  # name -> (mtime, text)

    def get(self, name: str) -> str:
        path = self._base / f"{name}.txt"
        if not path.exists():
            raise KeyError(f"Prompt not found: {name}")
        mtime = path.stat().st_mtime
        cached = self._cache.get(name)
        if cached and cached[0] == mtime:
            return cached[1]
        text = path.read_text(encoding="utf-8")
        self._cache[name] = (mtime, text)
        return text
```

- [ ] **Step 4: Run to verify pass**

Run: `pytest tests/test_prompts.py -v`
Expected: 3 PASS.

- [ ] **Step 5: Create the actual prompt files**

Create these in `server/prompts/`:

`transform_cleanup.txt`:
```
You are cleaning up a scribbled handwritten image. The user drew this with an Apple Pencil. Return a clean, typed version of exactly what was written. Preserve math, bullet points, and structure. Do not add commentary. Respond in the same language the user wrote in.
```

`transform_typed_text.txt`:
```
Transcribe the handwritten content in the image to plain typed text. Preserve line breaks and structure. Do not interpret or expand. Return only the transcription.
```

`transform_math.txt`:
```
The image contains handwritten math. Transcribe the expression or problem to clean LaTeX, then solve or simplify it step by step. Explain each step briefly in the language the user wrote in. If there is a question mark or equals sign with blank, provide the answer.
```

`transform_physics.txt`:
```
The image contains handwritten physics work (equations, diagrams, or both). Identify what is being asked, list relevant formulas, show the solution step by step. For diagrams, describe what you see and state any assumptions. Respond in the language the user wrote in.
```

`transform_chemistry.txt`:
```
The image contains handwritten chemistry (equations, structures, or reactions). Interpret carefully. For structural formulas, note that vision models are unreliable and flag any uncertainty. Explain step by step in the language the user wrote in.
```

`transform_explain.txt`:
```
Explain the handwritten content in the image clearly and concisely. Match the depth of explanation to what was written. Respond in the language the user wrote in.
```

`transform_list.txt`:
```
Convert the handwritten content in the image to a clean markdown bulleted or numbered list. Preserve the structure and language. Return only the list.
```

`chat_system.txt`:
```
You are a helpful note-taking assistant. The user is a student taking handwritten notes on an iPad. They will ask questions about the content of their notes. Be concise. Match the language the user writes in. If relevant notes are attached as images, refer to them directly.
```

- [ ] **Step 6: Commit**

```bash
git add server/src/notes_server/prompts.py server/tests/test_prompts.py server/prompts/
git commit -m "feat(server): PromptLoader with hot reload + initial prompts"
```

---

## Task 5: RequestLogger (JSONL)

**Files:**
- Create: `server/src/notes_server/logger.py`
- Create: `server/tests/test_logger.py`

- [ ] **Step 1: Write the failing test**

`server/tests/test_logger.py`:

```python
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
```

- [ ] **Step 2: Run to verify failure**

Run: `pytest tests/test_logger.py -v`
Expected: import error.

- [ ] **Step 3: Implement**

`server/src/notes_server/logger.py`:

```python
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
```

- [ ] **Step 4: Run to verify pass**

Run: `pytest tests/test_logger.py -v`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/logger.py server/tests/test_logger.py
git commit -m "feat(server): JSONL request logger"
```

---

## Task 6: GroqClient wrapper

**Files:**
- Create: `server/src/notes_server/groq_client.py`
- Create: `server/tests/test_groq_client.py`

- [ ] **Step 1: Write the failing test (mocked Groq SDK)**

`server/tests/test_groq_client.py`:

```python
from unittest.mock import MagicMock
from notes_server.groq_client import GroqClient

def test_chat_calls_groq_sdk(mocker):
    fake_sdk = MagicMock()
    fake_sdk.chat.completions.create.return_value = MagicMock(
        choices=[MagicMock(message=MagicMock(content="hello"))],
        usage=MagicMock(total_tokens=12),
    )
    client = GroqClient(api_key="k1", sdk=fake_sdk)
    result = client.chat(
        model="llama-3.3-70b-versatile",
        system="sys",
        messages=[{"role": "user", "content": "hi"}],
    )
    assert result.text == "hello"
    assert result.tokens == 12
    fake_sdk.chat.completions.create.assert_called_once()
    args = fake_sdk.chat.completions.create.call_args.kwargs
    assert args["model"] == "llama-3.3-70b-versatile"
    assert args["messages"][0]["content"] == "sys"
    assert args["messages"][1]["content"] == "hi"

def test_vision_sends_image_as_base64(mocker):
    fake_sdk = MagicMock()
    fake_sdk.chat.completions.create.return_value = MagicMock(
        choices=[MagicMock(message=MagicMock(content="I see a cat"))],
        usage=MagicMock(total_tokens=42),
    )
    client = GroqClient(api_key="k1", sdk=fake_sdk)
    result = client.vision(
        model="llama-3.2-90b-vision-preview",
        prompt="describe",
        image_base64="AAAA",
    )
    assert result.text == "I see a cat"
    msg = fake_sdk.chat.completions.create.call_args.kwargs["messages"][-1]
    assert msg["role"] == "user"
    content = msg["content"]
    assert any(c["type"] == "text" for c in content)
    assert any(c["type"] == "image_url" for c in content)

def test_transcribe_calls_audio_api():
    fake_sdk = MagicMock()
    fake_sdk.audio.transcriptions.create.return_value = MagicMock(text="hello world")
    client = GroqClient(api_key="k1", sdk=fake_sdk)
    result = client.transcribe(
        model="whisper-large-v3-turbo",
        audio_bytes=b"fake-wav",
        language="id",
    )
    assert result.text == "hello world"
    call = fake_sdk.audio.transcriptions.create.call_args.kwargs
    assert call["model"] == "whisper-large-v3-turbo"
    assert call["language"] == "id"
```

- [ ] **Step 2: Run to verify failure**

Run: `pytest tests/test_groq_client.py -v`
Expected: import error.

- [ ] **Step 3: Implement**

`server/src/notes_server/groq_client.py`:

```python
from dataclasses import dataclass
from typing import Any, Optional

@dataclass
class GroqResult:
    text: str
    tokens: int = 0
    model: str = ""

class GroqClient:
    def __init__(self, api_key: str, sdk: Any | None = None):
        if sdk is None:
            from groq import Groq
            sdk = Groq(api_key=api_key)
        self._sdk = sdk

    def chat(self, model: str, system: str, messages: list[dict]) -> GroqResult:
        full_messages = [{"role": "system", "content": system}, *messages]
        resp = self._sdk.chat.completions.create(model=model, messages=full_messages)
        choice = resp.choices[0]
        return GroqResult(
            text=choice.message.content,
            tokens=getattr(resp.usage, "total_tokens", 0),
            model=model,
        )

    def vision(self, model: str, prompt: str, image_base64: str) -> GroqResult:
        content = [
            {"type": "text", "text": prompt},
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{image_base64}"},
            },
        ]
        resp = self._sdk.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": content}],
        )
        choice = resp.choices[0]
        return GroqResult(
            text=choice.message.content,
            tokens=getattr(resp.usage, "total_tokens", 0),
            model=model,
        )

    def transcribe(self, model: str, audio_bytes: bytes, language: Optional[str] = None) -> GroqResult:
        kwargs: dict[str, Any] = {"model": model, "file": ("audio.wav", audio_bytes)}
        if language and language != "auto":
            kwargs["language"] = language
        resp = self._sdk.audio.transcriptions.create(**kwargs)
        return GroqResult(text=resp.text, model=model)
```

- [ ] **Step 4: Run to verify pass**

Run: `pytest tests/test_groq_client.py -v`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/groq_client.py server/tests/test_groq_client.py
git commit -m "feat(server): GroqClient wrapper for chat/vision/transcribe"
```

---

## Task 7: Pydantic models for requests/responses

**Files:**
- Create: `server/src/notes_server/models.py`

- [ ] **Step 1: Implement models directly (no tests needed — these are just dataclasses)**

`server/src/notes_server/models.py`:

```python
from pydantic import BaseModel, Field
from typing import Literal, Optional

# --- Transform ---

TransformAction = Literal[
    "cleanup",
    "typed_text",
    "math",
    "physics",
    "chemistry",
    "explain",
    "list",
]

class TransformRequest(BaseModel):
    action: TransformAction
    image_base64: str
    context: Optional[str] = None

class TransformResponse(BaseModel):
    result_type: Literal["text", "markdown", "svg"]
    text: Optional[str] = None
    markdown: Optional[str] = None
    svg: Optional[str] = None
    model_used: str

# --- Chat ---

ChatRole = Literal["user", "assistant"]

class ChatMessage(BaseModel):
    role: ChatRole
    content: str

class ChatRequest(BaseModel):
    page_id: str
    message: str
    history: list[ChatMessage] = Field(default_factory=list)
    scope: Literal["page", "notebook"] = "page"
    context_image_base64: Optional[str] = None

class ChatResponse(BaseModel):
    reply: str
    tokens_used: int
    model_used: str

# --- Transcribe ---

class TranscribeRequest(BaseModel):
    audio_base64: str
    language: Optional[str] = None

class TranscribeResponse(BaseModel):
    text: str
    language_detected: Optional[str] = None

# --- Sync ---

class PageSnapshot(BaseModel):
    id: str
    notebook_id: str
    index: int
    template: str
    drawing_blob_base64: str
    thumbnail_blob_base64: Optional[str] = None
    updated_at: float

class NotebookSnapshot(BaseModel):
    id: str
    title: str
    cover_color: str
    updated_at: float
    pages: list[PageSnapshot]

class SyncPushRequest(BaseModel):
    notebooks: list[NotebookSnapshot]
    since_timestamp: float = 0.0

class SyncPushResponse(BaseModel):
    accepted_at: float
    pages_written: int

class SyncPullRequest(BaseModel):
    notebook_id: Optional[str] = None

class SyncPullResponse(BaseModel):
    notebooks: list[NotebookSnapshot]

# --- Health ---

class HealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    key_pool: dict
```

- [ ] **Step 2: Commit**

```bash
git add server/src/notes_server/models.py
git commit -m "feat(server): pydantic request/response models"
```

---

## Task 8: SyncStore (SQLite)

**Files:**
- Create: `server/src/notes_server/sync_store.py`
- Create: `server/tests/test_sync_store.py`

- [ ] **Step 1: Write failing tests**

`server/tests/test_sync_store.py`:

```python
from pathlib import Path
from notes_server.sync_store import SyncStore
from notes_server.models import NotebookSnapshot, PageSnapshot

def make_notebook(id="nb1", page_count=2, t=1000.0):
    return NotebookSnapshot(
        id=id, title="Physics", cover_color="#ff0000", updated_at=t,
        pages=[
            PageSnapshot(
                id=f"p{i}", notebook_id=id, index=i,
                template="line", drawing_blob_base64="AAAA",
                thumbnail_blob_base64=None, updated_at=t,
            )
            for i in range(page_count)
        ],
    )

def test_push_writes_notebook_and_pages(tmp_path: Path):
    store = SyncStore(tmp_path / "notes.sqlite")
    written = store.push([make_notebook()])
    assert written == 2

def test_pull_returns_written_notebooks(tmp_path: Path):
    store = SyncStore(tmp_path / "notes.sqlite")
    store.push([make_notebook()])
    result = store.pull()
    assert len(result) == 1
    assert result[0].id == "nb1"
    assert len(result[0].pages) == 2

def test_push_upserts_on_second_call(tmp_path: Path):
    store = SyncStore(tmp_path / "notes.sqlite")
    store.push([make_notebook(page_count=2, t=1000)])
    store.push([make_notebook(page_count=3, t=2000)])
    result = store.pull()
    assert len(result) == 1
    assert len(result[0].pages) == 3
    assert result[0].updated_at == 2000

def test_pull_by_notebook_id(tmp_path: Path):
    store = SyncStore(tmp_path / "notes.sqlite")
    store.push([make_notebook("a"), make_notebook("b")])
    result = store.pull(notebook_id="b")
    assert len(result) == 1
    assert result[0].id == "b"
```

- [ ] **Step 2: Run to verify failure**

Run: `pytest tests/test_sync_store.py -v`
Expected: import error.

- [ ] **Step 3: Implement**

`server/src/notes_server/sync_store.py`:

```python
import sqlite3
from pathlib import Path
from notes_server.models import NotebookSnapshot, PageSnapshot

SCHEMA = """
CREATE TABLE IF NOT EXISTS notebooks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    cover_color TEXT NOT NULL,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS pages (
    id TEXT PRIMARY KEY,
    notebook_id TEXT NOT NULL,
    idx INTEGER NOT NULL,
    template TEXT NOT NULL,
    drawing_b64 TEXT NOT NULL,
    thumbnail_b64 TEXT,
    updated_at REAL NOT NULL,
    FOREIGN KEY(notebook_id) REFERENCES notebooks(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_pages_notebook ON pages(notebook_id);
"""

class SyncStore:
    def __init__(self, db_path: Path):
        self._path = Path(db_path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with self._conn() as c:
            c.executescript(SCHEMA)

    def _conn(self):
        conn = sqlite3.connect(self._path)
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

    def push(self, notebooks: list[NotebookSnapshot]) -> int:
        pages_written = 0
        with self._conn() as c:
            for nb in notebooks:
                c.execute(
                    """INSERT INTO notebooks(id,title,cover_color,updated_at)
                       VALUES(?,?,?,?)
                       ON CONFLICT(id) DO UPDATE SET
                         title=excluded.title,
                         cover_color=excluded.cover_color,
                         updated_at=excluded.updated_at""",
                    (nb.id, nb.title, nb.cover_color, nb.updated_at),
                )
                # replace pages for this notebook
                c.execute("DELETE FROM pages WHERE notebook_id = ?", (nb.id,))
                for p in nb.pages:
                    c.execute(
                        """INSERT INTO pages(id,notebook_id,idx,template,drawing_b64,thumbnail_b64,updated_at)
                           VALUES(?,?,?,?,?,?,?)""",
                        (p.id, p.notebook_id, p.index, p.template,
                         p.drawing_blob_base64, p.thumbnail_blob_base64, p.updated_at),
                    )
                    pages_written += 1
            c.commit()
        return pages_written

    def pull(self, notebook_id: str | None = None) -> list[NotebookSnapshot]:
        with self._conn() as c:
            if notebook_id:
                rows = c.execute(
                    "SELECT id,title,cover_color,updated_at FROM notebooks WHERE id = ?",
                    (notebook_id,),
                ).fetchall()
            else:
                rows = c.execute(
                    "SELECT id,title,cover_color,updated_at FROM notebooks"
                ).fetchall()
            result: list[NotebookSnapshot] = []
            for nb_id, title, color, updated in rows:
                page_rows = c.execute(
                    """SELECT id,notebook_id,idx,template,drawing_b64,thumbnail_b64,updated_at
                       FROM pages WHERE notebook_id = ? ORDER BY idx""",
                    (nb_id,),
                ).fetchall()
                pages = [
                    PageSnapshot(
                        id=r[0], notebook_id=r[1], index=r[2], template=r[3],
                        drawing_blob_base64=r[4], thumbnail_blob_base64=r[5],
                        updated_at=r[6],
                    )
                    for r in page_rows
                ]
                result.append(NotebookSnapshot(
                    id=nb_id, title=title, cover_color=color,
                    updated_at=updated, pages=pages,
                ))
            return result
```

- [ ] **Step 4: Run to verify pass**

Run: `pytest tests/test_sync_store.py -v`
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/sync_store.py server/tests/test_sync_store.py
git commit -m "feat(server): SQLite-backed sync store"
```

---

## Task 9: FastAPI app skeleton + /health

**Files:**
- Create: `server/src/notes_server/server.py`
- Create: `server/tests/test_server_health.py`

- [ ] **Step 1: Write the failing test**

`server/tests/test_server_health.py`:

```python
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
```

- [ ] **Step 2: Run to verify failure**

Run: `pytest tests/test_server_health.py -v`
Expected: import error.

- [ ] **Step 3: Implement**

`server/src/notes_server/server.py`:

```python
from pathlib import Path
from fastapi import FastAPI
from notes_server.config import Config, load_config
from notes_server.key_pool import KeyPool
from notes_server.prompts import PromptLoader
from notes_server.logger import RequestLogger
from notes_server.sync_store import SyncStore
from notes_server.models import HealthResponse

class AppState:
    def __init__(self, config: Config):
        self.config = config
        self.key_pool = KeyPool(
            keys=config.groq.keys,
            cooldown_seconds=config.groq.cooldown_seconds,
        )
        prompt_dir = Path(__file__).parent.parent.parent / "prompts"
        self.prompts = PromptLoader(prompt_dir)
        self.logger = RequestLogger(Path(config.logging.dir))
        self.sync_store = SyncStore(Path(config.sync.db_path))

def create_app(config: Config | None = None) -> FastAPI:
    if config is None:
        config = load_config(Path("config.yaml"))
    state = AppState(config)
    app = FastAPI(title="Notes Server")
    app.state.ctx = state

    @app.get("/health", response_model=HealthResponse)
    def health():
        return HealthResponse(status="ok", key_pool=state.key_pool.summary())

    return app

app = create_app() if Path("config.yaml").exists() else None
```

- [ ] **Step 4: Run to verify pass**

Run: `pytest tests/test_server_health.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/server.py server/tests/test_server_health.py
git commit -m "feat(server): FastAPI app skeleton with /health"
```

---

## Task 10: /ai/chat endpoint

**Files:**
- Modify: `server/src/notes_server/server.py`
- Create: `server/tests/test_server_chat.py`

- [ ] **Step 1: Write failing test**

`server/tests/test_server_chat.py`:

```python
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
```

- [ ] **Step 2: Run to verify failure**

Run: `pytest tests/test_server_chat.py -v`
Expected: 404 (endpoint not defined).

- [ ] **Step 3: Implement**

Add these imports to the top of `server/src/notes_server/server.py`:

```python
import time
from fastapi import HTTPException
from notes_server.groq_client import GroqClient
from notes_server.models import (
    HealthResponse,
    ChatRequest, ChatResponse,
)
```

Add this endpoint function inside `create_app` after the `/health` endpoint:

```python
    @app.post("/ai/chat", response_model=ChatResponse)
    def chat(req: ChatRequest):
        key = state.key_pool.pick()
        if key is None:
            raise HTTPException(status_code=503, detail="All keys exhausted")
        start = time.time()
        try:
            client = GroqClient(api_key=key)
            system_prompt = state.prompts.get("chat_system")
            messages = [m.model_dump() for m in req.history]
            messages.append({"role": "user", "content": req.message})
            result = client.chat(
                model=config.groq.models["chat"],
                system=system_prompt,
                messages=messages,
            )
            state.key_pool.mark_success(key)
            latency = int((time.time() - start) * 1000)
            state.logger.log({
                "action": "chat",
                "model": result.model,
                "latency_ms": latency,
                "tokens": result.tokens,
                "page_id": req.page_id,
            })
            return ChatResponse(
                reply=result.text,
                tokens_used=result.tokens,
                model_used=result.model,
            )
        except Exception as e:
            state.key_pool.mark_error(key)
            raise HTTPException(status_code=502, detail=f"Upstream error: {e}")
```

- [ ] **Step 4: Run to verify pass**

Run: `pytest tests/test_server_chat.py -v`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/server.py server/tests/test_server_chat.py
git commit -m "feat(server): /ai/chat endpoint"
```

---

## Task 11: /ai/transform endpoint

**Files:**
- Modify: `server/src/notes_server/server.py`
- Create: `server/tests/test_server_transform.py`

- [ ] **Step 1: Write failing test**

`server/tests/test_server_transform.py`:

```python
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
```

- [ ] **Step 2: Run to verify failure**

Run: `pytest tests/test_server_transform.py -v`
Expected: 404.

- [ ] **Step 3: Implement**

Add import to `server.py`:

```python
from notes_server.models import TransformRequest, TransformResponse, TransformAction
```

Add this helper before `create_app`:

```python
ACTION_TO_PROMPT: dict[str, str] = {
    "cleanup": "transform_cleanup",
    "typed_text": "transform_typed_text",
    "math": "transform_math",
    "physics": "transform_physics",
    "chemistry": "transform_chemistry",
    "explain": "transform_explain",
    "list": "transform_list",
}

ACTION_RESULT_TYPE: dict[str, str] = {
    "cleanup": "text",
    "typed_text": "text",
    "math": "markdown",
    "physics": "markdown",
    "chemistry": "markdown",
    "explain": "markdown",
    "list": "markdown",
}
```

Add endpoint inside `create_app`:

```python
    @app.post("/ai/transform", response_model=TransformResponse)
    def transform(req: TransformRequest):
        key = state.key_pool.pick()
        if key is None:
            raise HTTPException(status_code=503, detail="All keys exhausted")
        start = time.time()
        try:
            prompt_name = ACTION_TO_PROMPT[req.action]
            prompt = state.prompts.get(prompt_name)
            client = GroqClient(api_key=key)
            result = client.vision(
                model=config.groq.models["vision"],
                prompt=prompt,
                image_base64=req.image_base64,
            )
            state.key_pool.mark_success(key)
            latency = int((time.time() - start) * 1000)
            state.logger.log({
                "action": f"transform.{req.action}",
                "model": result.model,
                "latency_ms": latency,
                "tokens": result.tokens,
            })
            result_type = ACTION_RESULT_TYPE[req.action]
            resp_kwargs: dict = {"result_type": result_type, "model_used": result.model}
            if result_type == "text":
                resp_kwargs["text"] = result.text
            elif result_type == "markdown":
                resp_kwargs["markdown"] = result.text
            return TransformResponse(**resp_kwargs)
        except Exception as e:
            state.key_pool.mark_error(key)
            raise HTTPException(status_code=502, detail=f"Upstream error: {e}")
```

- [ ] **Step 4: Run to verify pass**

Run: `pytest tests/test_server_transform.py -v`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/server.py server/tests/test_server_transform.py
git commit -m "feat(server): /ai/transform endpoint with action routing"
```

---

## Task 12: /ai/transcribe endpoint

**Files:**
- Modify: `server/src/notes_server/server.py`
- Create: `server/tests/test_server_transcribe.py`

- [ ] **Step 1: Write failing test**

`server/tests/test_server_transcribe.py`:

```python
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
```

- [ ] **Step 2: Run to verify failure**

Expected: 404.

- [ ] **Step 3: Implement**

Add import:

```python
import base64
from notes_server.models import TranscribeRequest, TranscribeResponse
```

Add endpoint:

```python
    @app.post("/ai/transcribe", response_model=TranscribeResponse)
    def transcribe(req: TranscribeRequest):
        key = state.key_pool.pick()
        if key is None:
            raise HTTPException(status_code=503, detail="All keys exhausted")
        start = time.time()
        try:
            audio_bytes = base64.b64decode(req.audio_base64)
            client = GroqClient(api_key=key)
            lang = req.language or config.voice.default_language
            result = client.transcribe(
                model=config.groq.models["whisper"],
                audio_bytes=audio_bytes,
                language=lang,
            )
            state.key_pool.mark_success(key)
            latency = int((time.time() - start) * 1000)
            state.logger.log({
                "action": "transcribe",
                "model": result.model,
                "latency_ms": latency,
                "language": lang,
            })
            return TranscribeResponse(text=result.text, language_detected=lang)
        except Exception as e:
            state.key_pool.mark_error(key)
            raise HTTPException(status_code=502, detail=f"Upstream error: {e}")
```

- [ ] **Step 4: Run to verify pass**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/server.py server/tests/test_server_transcribe.py
git commit -m "feat(server): /ai/transcribe endpoint"
```

---

## Task 13: /sync/push and /sync/pull endpoints

**Files:**
- Modify: `server/src/notes_server/server.py`
- Create: `server/tests/test_server_sync.py`

- [ ] **Step 1: Write failing test**

`server/tests/test_server_sync.py`:

```python
from fastapi.testclient import TestClient
from notes_server.server import create_app
from tests.test_server_health import make_test_config

def make_nb_payload(id="nb1", pages=2):
    return {
        "id": id,
        "title": "Physics",
        "cover_color": "#ff0000",
        "updated_at": 1000.0,
        "pages": [
            {
                "id": f"p{i}", "notebook_id": id, "index": i,
                "template": "line", "drawing_blob_base64": "AAAA",
                "thumbnail_blob_base64": None, "updated_at": 1000.0,
            }
            for i in range(pages)
        ],
    }

def test_push_then_pull_roundtrip(tmp_path):
    app = create_app(make_test_config(tmp_path))
    client = TestClient(app)
    r = client.post("/sync/push", json={
        "notebooks": [make_nb_payload()],
        "since_timestamp": 0.0,
    })
    assert r.status_code == 200
    assert r.json()["pages_written"] == 2

    r2 = client.post("/sync/pull", json={})
    assert r2.status_code == 200
    body = r2.json()
    assert len(body["notebooks"]) == 1
    assert body["notebooks"][0]["id"] == "nb1"
    assert len(body["notebooks"][0]["pages"]) == 2

def test_pull_by_notebook_id(tmp_path):
    app = create_app(make_test_config(tmp_path))
    client = TestClient(app)
    client.post("/sync/push", json={
        "notebooks": [make_nb_payload("a"), make_nb_payload("b")],
        "since_timestamp": 0.0,
    })
    r = client.post("/sync/pull", json={"notebook_id": "b"})
    body = r.json()
    assert len(body["notebooks"]) == 1
    assert body["notebooks"][0]["id"] == "b"
```

- [ ] **Step 2: Run to verify failure**

Expected: 404.

- [ ] **Step 3: Implement**

Add imports:

```python
from notes_server.models import (
    SyncPushRequest, SyncPushResponse,
    SyncPullRequest, SyncPullResponse,
)
```

Add endpoints:

```python
    @app.post("/sync/push", response_model=SyncPushResponse)
    def sync_push(req: SyncPushRequest):
        written = state.sync_store.push(req.notebooks)
        return SyncPushResponse(accepted_at=time.time(), pages_written=written)

    @app.post("/sync/pull", response_model=SyncPullResponse)
    def sync_pull(req: SyncPullRequest):
        notebooks = state.sync_store.pull(notebook_id=req.notebook_id)
        return SyncPullResponse(notebooks=notebooks)
```

- [ ] **Step 4: Run to verify pass**

Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/server.py server/tests/test_server_sync.py
git commit -m "feat(server): /sync/push and /sync/pull endpoints"
```

---

## Task 14: Mathpix integration (optional, Math mode)

**Files:**
- Create: `server/src/notes_server/mathpix.py`
- Create: `server/tests/test_mathpix.py`
- Modify: `server/src/notes_server/server.py` (math action routing)

- [ ] **Step 1: Write failing test**

`server/tests/test_mathpix.py`:

```python
from unittest.mock import MagicMock
from notes_server.mathpix import MathpixClient

def test_mathpix_ocr_returns_latex():
    fake_http = MagicMock()
    fake_http.post.return_value.json.return_value = {
        "text": "\\int_0^1 x^2 dx",
        "confidence": 0.98,
    }
    fake_http.post.return_value.status_code = 200
    client = MathpixClient(app_id="a", app_key="b", http=fake_http)
    result = client.ocr(image_base64="AAAA")
    assert "int" in result.latex
    assert result.confidence > 0.9
```

- [ ] **Step 2: Implement**

`server/src/notes_server/mathpix.py`:

```python
from dataclasses import dataclass
from typing import Any

@dataclass
class MathpixResult:
    latex: str
    confidence: float

class MathpixClient:
    def __init__(self, app_id: str, app_key: str, http: Any | None = None):
        self._app_id = app_id
        self._app_key = app_key
        if http is None:
            import httpx
            http = httpx.Client()
        self._http = http

    def ocr(self, image_base64: str) -> MathpixResult:
        resp = self._http.post(
            "https://api.mathpix.com/v3/text",
            headers={
                "app_id": self._app_id,
                "app_key": self._app_key,
                "Content-Type": "application/json",
            },
            json={
                "src": f"data:image/png;base64,{image_base64}",
                "formats": ["text"],
            },
        )
        if resp.status_code != 200:
            raise RuntimeError(f"Mathpix error: {resp.status_code}")
        data = resp.json()
        return MathpixResult(
            latex=data.get("text", ""),
            confidence=data.get("confidence", 0.0),
        )
```

- [ ] **Step 3: Wire into `/ai/transform` math action**

In `server.py`, modify the `transform` endpoint to check for math mode and use Mathpix when enabled:

Replace the existing math handling in the `transform` function with this branch at the top:

```python
        if req.action == "math" and config.mathpix.enabled:
            try:
                from notes_server.mathpix import MathpixClient
                mpx = MathpixClient(
                    app_id=config.mathpix.app_id,
                    app_key=config.mathpix.app_key,
                )
                ocr = mpx.ocr(image_base64=req.image_base64)
                # then ask the chat model to solve/explain the LaTeX
                chat_key = state.key_pool.pick()
                if chat_key is None:
                    raise HTTPException(status_code=503, detail="All keys exhausted")
                client = GroqClient(api_key=chat_key)
                prompt = state.prompts.get("transform_math")
                result = client.chat(
                    model=config.groq.models["chat"],
                    system=prompt,
                    messages=[{"role": "user", "content": f"LaTeX:\n{ocr.latex}\n\nSolve step by step."}],
                )
                state.key_pool.mark_success(chat_key)
                state.logger.log({
                    "action": "transform.math.mathpix",
                    "model": result.model,
                    "latex": ocr.latex,
                    "confidence": ocr.confidence,
                })
                return TransformResponse(
                    result_type="markdown",
                    markdown=f"**LaTeX:** `{ocr.latex}`\n\n{result.text}",
                    model_used=f"mathpix + {result.model}",
                )
            except Exception as e:
                state.logger.log({"action": "transform.math.mathpix.error", "error": str(e)})
                # fall through to vision path
```

- [ ] **Step 4: Run all server tests**

Run: `pytest tests/test_mathpix.py tests/test_server_transform.py -v`
Expected: all PASS (existing transform test still works since Mathpix is disabled in test config).

- [ ] **Step 5: Commit**

```bash
git add server/src/notes_server/mathpix.py server/tests/test_mathpix.py server/src/notes_server/server.py
git commit -m "feat(server): optional Mathpix integration for Math mode"
```

---

## Task 15: End-to-end live smoke test (manual, opt-in)

**Files:**
- Create: `server/tests/test_live.py`

- [ ] **Step 1: Write an opt-in integration test**

`server/tests/test_live.py`:

```python
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
```

- [ ] **Step 2: Add instructions to README**

Append to `server/README.md`:

```markdown

## Manual smoke test

With a real `config.yaml`:

```
RUN_LIVE_TESTS=1 pytest tests/test_live.py -v -s
```

Put a sample handwritten math image at `tests/fixtures/math_sample.png` to exercise the vision path.
```

- [ ] **Step 3: Run all tests (mocked path)**

Run: `pytest`
Expected: all tests PASS, live tests SKIPPED.

- [ ] **Step 4: Run server manually**

```
cp config.yaml.example config.yaml  # fill in real keys
uvicorn notes_server.server:app --reload --host 0.0.0.0 --port 8000
```

Verify in another terminal:

```
curl http://localhost:8000/health
```

Expected: JSON with `status: ok` and the 5 keys listed.

- [ ] **Step 5: Commit**

```bash
git add server/tests/test_live.py server/README.md
git commit -m "test(server): live smoke test harness"
```

---

## Plan A — Done Criteria

Plan A is complete when:

1. `pytest` runs green with all unit tests.
2. `uvicorn notes_server.server:app` starts without errors.
3. `curl http://localhost:8000/health` returns valid JSON with the key pool summary.
4. Live smoke test (`RUN_LIVE_TESTS=1 pytest tests/test_live.py`) passes a basic chat request against real Groq.
5. All prompts are readable and the hot-reload round-trip works (edit a `.txt` file, replay a request, see new behavior).

At this point the server is ready to serve the iPad app. Plans B and C can now assume all these endpoints exist and behave as specified here.
