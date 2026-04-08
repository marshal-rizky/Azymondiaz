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
