import sqlite3
from pathlib import Path
from notes_server.models import NotebookSnapshot, PageSnapshot

SCHEMA = """
CREATE TABLE IF NOT EXISTS notebooks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    cover_color TEXT NOT NULL,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS pages (
    id TEXT PRIMARY KEY,
    notebook_id TEXT NOT NULL,
    idx INTEGER NOT NULL,
    template TEXT NOT NULL,
    drawing_b64 TEXT NOT NULL,
    thumbnail_b64 TEXT,
    updated_at REAL NOT NULL,
    FOREIGN KEY(notebook_id) REFERENCES notebooks(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_pages_notebook ON pages(notebook_id);
"""

class SyncStore:
    def __init__(self, db_path: Path):
        self._path = Path(db_path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with self._conn() as c:
            c.executescript(SCHEMA)

    def _conn(self):
        conn = sqlite3.connect(self._path)
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

    def push(self, notebooks: list[NotebookSnapshot]) -> int:
        pages_written = 0
        with self._conn() as c:
            for nb in notebooks:
                c.execute(
                    """INSERT INTO notebooks(id,title,cover_color,updated_at)
                       VALUES(?,?,?,?)
                       ON CONFLICT(id) DO UPDATE SET
                         title=excluded.title,
                         cover_color=excluded.cover_color,
                         updated_at=excluded.updated_at""",
                    (nb.id, nb.title, nb.cover_color, nb.updated_at),
                )
                # replace pages for this notebook
                c.execute("DELETE FROM pages WHERE notebook_id = ?", (nb.id,))
                for p in nb.pages:
                    c.execute(
                        """INSERT OR REPLACE INTO pages(id,notebook_id,idx,template,drawing_b64,thumbnail_b64,updated_at)
                           VALUES(?,?,?,?,?,?,?)""",
                        (p.id, p.notebook_id, p.index, p.template,
                         p.drawing_blob_base64, p.thumbnail_blob_base64, p.updated_at),
                    )
                    pages_written += 1
            c.commit()
        return pages_written

    def pull(self, notebook_id: str | None = None) -> list[NotebookSnapshot]:
        with self._conn() as c:
            if notebook_id:
                rows = c.execute(
                    "SELECT id,title,cover_color,updated_at FROM notebooks WHERE id = ?",
                    (notebook_id,),
                ).fetchall()
            else:
                rows = c.execute(
                    "SELECT id,title,cover_color,updated_at FROM notebooks"
                ).fetchall()
            result: list[NotebookSnapshot] = []
            for nb_id, title, color, updated in rows:
                page_rows = c.execute(
                    """SELECT id,notebook_id,idx,template,drawing_b64,thumbnail_b64,updated_at
                       FROM pages WHERE notebook_id = ? ORDER BY idx""",
                    (nb_id,),
                ).fetchall()
                pages = [
                    PageSnapshot(
                        id=r[0], notebook_id=r[1], index=r[2], template=r[3],
                        drawing_blob_base64=r[4], thumbnail_blob_base64=r[5],
                        updated_at=r[6],
                    )
                    for r in page_rows
                ]
                result.append(NotebookSnapshot(
                    id=nb_id, title=title, cover_color=color,
                    updated_at=updated, pages=pages,
                ))
            return result
