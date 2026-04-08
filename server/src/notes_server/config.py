from dataclasses import dataclass
from pathlib import Path
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
    raw = yaml.safe_load(path.read_text())
    g = raw["groq"]
    return Config(
        groq=GroqConfig(
            keys=g["keys"],
            cooldown_seconds=g["cooldown_seconds"],
            models=g["models"],
        ),
        mathpix=MathpixConfig(**raw["mathpix"]),
        sync=SyncConfig(**raw["sync"]),
        voice=VoiceConfig(**raw["voice"]),
        ai=AIConfig(**raw["ai"]),
        logging=LoggingConfig(**raw["logging"]),
    )
