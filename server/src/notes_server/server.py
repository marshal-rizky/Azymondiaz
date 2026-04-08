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
