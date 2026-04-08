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

## Manual smoke test

With a real `config.yaml`:

```
RUN_LIVE_TESTS=1 pytest tests/test_live.py -v -s
```

Put a sample handwritten math image at `tests/fixtures/math_sample.png` to exercise the vision path.
