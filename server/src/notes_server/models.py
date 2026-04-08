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
