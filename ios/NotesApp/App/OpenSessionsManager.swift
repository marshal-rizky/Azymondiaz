import Foundation
import Observation

struct NotebookSession: Identifiable {
    let id: UUID
    let notebook: Notebook
    var activePageIndex: Int
}

@Observable
final class OpenSessionsManager {
    private(set) var sessions: [NotebookSession] = []
    var activeSessionID: UUID?

    /// Opens a notebook as a new tab (no-op if already open). Returns the session.
    @discardableResult
    func open(_ notebook: Notebook) -> NotebookSession {
        if let existing = session(for: notebook) {
            activeSessionID = existing.id
            return existing
        }
        let s = NotebookSession(id: UUID(), notebook: notebook, activePageIndex: 0)
        sessions.append(s)
        activeSessionID = s.id
        return s
    }

    /// Closes a tab. Switches focus to the previous tab if the closed one was active.
    func close(sessionID: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions.remove(at: idx)
        if activeSessionID == sessionID {
            activeSessionID = sessions.isEmpty ? nil : sessions[max(0, idx - 1)].id
        }
    }

    /// Returns the session for a notebook if it is already open.
    func session(for notebook: Notebook) -> NotebookSession? {
        sessions.first { $0.notebook.id == notebook.id }
    }

    /// Returns a session by its ID.
    func session(id: UUID) -> NotebookSession? {
        sessions.first { $0.id == id }
    }

    /// Updates the active page index for a session (called by NotebookViewModel on page change).
    func updateActivePageIndex(_ index: Int, sessionID: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[i].activePageIndex = index
    }
}
