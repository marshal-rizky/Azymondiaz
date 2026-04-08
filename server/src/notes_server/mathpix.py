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
