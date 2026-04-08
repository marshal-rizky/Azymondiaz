from pathlib import Path
from notes_server.sync_store import SyncStore
from notes_server.models import NotebookSnapshot, PageSnapshot

def make_notebook(id="nb1", page_count=2, t=1000.0):
    return NotebookSnapshot(
        id=id, title="Physics", cover_color="#ff0000", updated_at=t,
        pages=[
            PageSnapshot(
                id=f"p{i}", notebook_id=id, index=i,
                template="line", drawing_blob_base64="AAAA",
                thumbnail_blob_base64=None, updated_at=t,
            )
            for i in range(page_count)
        ],
    )

def test_push_writes_notebook_and_pages(tmp_path: Path):
    store = SyncStore(tmp_path / "notes.sqlite")
    written = store.push([make_notebook()])
    assert written == 2

def test_pull_returns_written_notebooks(tmp_path: Path):
    store = SyncStore(tmp_path / "notes.sqlite")
    store.push([make_notebook()])
    result = store.pull()
    assert len(result) == 1
    assert result[0].id == "nb1"
    assert len(result[0].pages) == 2

def test_push_upserts_on_second_call(tmp_path: Path):
    store = SyncStore(tmp_path / "notes.sqlite")
    store.push([make_notebook(page_count=2, t=1000)])
    store.push([make_notebook(page_count=3, t=2000)])
    result = store.pull()
    assert len(result) == 1
    assert len(result[0].pages) == 3
    assert result[0].updated_at == 2000

def test_pull_by_notebook_id(tmp_path: Path):
    store = SyncStore(tmp_path / "notes.sqlite")
    store.push([make_notebook("a"), make_notebook("b")])
    result = store.pull(notebook_id="b")
    assert len(result) == 1
    assert result[0].id == "b"
