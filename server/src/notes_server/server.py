import time
from pathlib import Path
from fastapi import FastAPI, HTTPException
from notes_server.config import Config, load_config
from notes_server.key_pool import KeyPool
from notes_server.prompts import PromptLoader
from notes_server.logger import RequestLogger
from notes_server.sync_store import SyncStore
from notes_server.groq_client import GroqClient
from notes_server.models import (
    HealthResponse,
    ChatRequest, ChatResponse,
)


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

    @app.post("/ai/chat", response_model=ChatResponse)
    def chat(req: ChatRequest):
        key = state.key_pool.pick()
        if key is None:
            raise HTTPException(status_code=503, detail="All keys exhausted")
        start = time.time()
        try:
            groq = GroqClient(api_key=key)
            system_prompt = state.prompts.get("chat_system")
            messages = [m.model_dump() for m in req.history]
            messages.append({"role": "user", "content": req.message})
            result = groq.chat(
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

    return app


app = create_app() if Path("config.yaml").exists() else None
