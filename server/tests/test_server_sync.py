from fastapi.testclient import TestClient
from notes_server.server import create_app
from tests.test_server_health import make_test_config

def make_nb_payload(id="nb1", pages=2):
    return {
        "id": id,
        "title": "Physics",
        "cover_color": "#ff0000",
        "updated_at": 1000.0,
        "pages": [
            {
                "id": f"p{i}", "notebook_id": id, "index": i,
                "template": "line", "drawing_blob_base64": "AAAA",
                "thumbnail_blob_base64": None, "updated_at": 1000.0,
            }
            for i in range(pages)
        ],
    }

def test_push_then_pull_roundtrip(tmp_path):
    app = create_app(make_test_config(tmp_path))
    client = TestClient(app)
    r = client.post("/sync/push", json={
        "notebooks": [make_nb_payload()],
        "since_timestamp": 0.0,
    })
    assert r.status_code == 200
    assert r.json()["pages_written"] == 2

    r2 = client.post("/sync/pull", json={})
    assert r2.status_code == 200
    body = r2.json()
    assert len(body["notebooks"]) == 1
    assert body["notebooks"][0]["id"] == "nb1"
    assert len(body["notebooks"][0]["pages"]) == 2

def test_pull_by_notebook_id(tmp_path):
    app = create_app(make_test_config(tmp_path))
    client = TestClient(app)
    client.post("/sync/push", json={
        "notebooks": [make_nb_payload("a"), make_nb_payload("b")],
        "since_timestamp": 0.0,
    })
    r = client.post("/sync/pull", json={"notebook_id": "b"})
    body = r.json()
    assert len(body["notebooks"]) == 1
    assert body["notebooks"][0]["id"] == "b"
