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
