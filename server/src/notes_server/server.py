import base64
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
    TransformRequest, TransformResponse,
    TranscribeRequest, TranscribeResponse,
)


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

    @app.post("/ai/transform", response_model=TransformResponse)
    def transform(req: TransformRequest):
        key = state.key_pool.pick()
        if key is None:
            raise HTTPException(status_code=503, detail="All keys exhausted")
        start = time.time()
        try:
            prompt_name = ACTION_TO_PROMPT[req.action]
            prompt = state.prompts.get(prompt_name)
            groq = GroqClient(api_key=key)
            result = groq.vision(
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

    @app.post("/ai/transcribe", response_model=TranscribeResponse)
    def transcribe(req: TranscribeRequest):
        key = state.key_pool.pick()
        if key is None:
            raise HTTPException(status_code=503, detail="All keys exhausted")
        start = time.time()
        try:
            audio_bytes = base64.b64decode(req.audio_base64)
            groq = GroqClient(api_key=key)
            lang = req.language or config.voice.default_language
            result = groq.transcribe(
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

    return app


app = create_app() if Path("config.yaml").exists() else None
