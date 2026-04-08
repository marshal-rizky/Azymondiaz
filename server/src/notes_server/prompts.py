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
