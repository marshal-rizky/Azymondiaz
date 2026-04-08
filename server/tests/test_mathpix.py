from unittest.mock import MagicMock
from notes_server.mathpix import MathpixClient

def test_mathpix_ocr_returns_latex():
    fake_http = MagicMock()
    fake_http.post.return_value.json.return_value = {
        "text": "\\int_0^1 x^2 dx",
        "confidence": 0.98,
    }
    fake_http.post.return_value.status_code = 200
    client = MathpixClient(app_id="a", app_key="b", http=fake_http)
    result = client.ocr(image_base64="AAAA")
    assert "int" in result.latex
    assert result.confidence > 0.9
