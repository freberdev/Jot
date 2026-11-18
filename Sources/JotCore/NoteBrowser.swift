import Foundation
import Observation

/// The list of notes beside the editor, and how the two follow each other.
///
/// The row the user stands on is the note that is shown: moving through the list with the
/// arrow keys opens each note in the editor. Typing a search does not change the editor;
/// only moving into the list, or choosing a match, does.
@MainActor @Observable
public final class NoteBrowser {
    /// True while the keyboard is in the list, in the search field or on the rows.
    public private(set) var isBrowsing = false
    /// True while the editor holds an earlier note, false for a note started in this session.
    public private(set) var isContinuing = false

    private let store: NoteStore
    private let editor: Editor
    private let history: HistoryModel
    /// Where the user was when they went into the list, to return to on cancel.
    private var origin: (noteID: UUID?, wasContinuing: Bool)?

    public init(store: NoteStore, editor: Editor, history: HistoryModel) {
        self.store = store
        self.editor = editor
        self.history = history
    }

    /// The row to mark in the list: the one the keyboard is on while browsing,
    /// otherwise the note in the editor, if it has been saved.
    public var highlightedID: UUID? {
        if isBrowsing { return history.selectedID }
        return editor.savedNote == nil ? nil : editor.noteID
    }

    // MARK: Sessions

    /// The window opens: a fresh list, read again if the folder changed, and a new empty note.
    public func openSession() {
        store.reloadIfChanged()
        history.reset()
        startNew()
    }

    /// The window closes: deleted notes can no longer be restored.
    public func closeSession() {
        history.forgetDeleted()
        end()
    }

    /// Finishes the current note and starts an empty one, outside the list.
    public func startNew() {
        editor.startNew()
        isContinuing = editor.savedNote != nil
        end()
    }

    // MARK: Into and out of the list

    /// Moves the keyboard to the search field. Returns false, and does nothing, if the note
    /// in the editor cannot be saved: it has to stay until it is safe.
    @discardableResult
    public func enterSearch() -> Bool {
        if !isBrowsing {
            editor.flush()
            guard !editor.saveFailed else { return false }
            origin = (editor.savedNote?.id, isContinuing)
            isBrowsing = true
        }
        history.focusSearch()
        return true
    }

    /// Moves through the list. On the rows, the note the user lands on is shown at once.
    public func move(by delta: Int) {
        guard isBrowsing else { return }
        history.moveSelection(by: delta)
        if history.focus == .list { showSelected() }
    }

    /// Return or Tab: the selected note becomes the one being edited.
    public func commit() {
        guard isBrowsing else { return }
        showSelected()
        end()
    }

    /// The text got the keyboard some other way, such as a click: keep what is shown.
    public func stay() {
        end()
    }

    /// Escape: back to the note the user was in before going into the list.
    public func cancel() {
        guard isBrowsing, let origin else {
            end()
            return
        }
        end()
        if let id = origin.noteID, let note = store.note(id: id) {
            if editor.noteID != id { editor.open(note) }
            if editor.noteID == id { isContinuing = origin.wasContinuing }
        } else if editor.savedNote != nil {
            // They came from a note that was never saved, or that is gone: a new empty one.
            startNew()
        }
    }

    /// A click on a row: open it and put the keyboard in the text.
    public func open(_ note: Note) {
        show(note)
        end()
    }

    // MARK: Deleting

    public func deleteSelected() throws {
        guard let note = history.selected else { return }
        try delete(note)
    }

    /// Deletes a note. If it was the one in the editor, the editor lets go of it; while on
    /// the rows, the note that takes its place is shown.
    public func delete(_ note: Note) throws {
        history.select(note.id)
        try history.deleteSelected()
        editor.forget(id: note.id)
        if editor.savedNote == nil { isContinuing = false }
        if isBrowsing {
            showSelected()
        } else {
            history.focusSearch()
        }
    }

    /// Brings back the most recently deleted note and shows it.
    public func undoDelete() throws {
        try history.undoDelete()
        if isBrowsing { showSelected() }
    }

    // MARK: Private

    private func showSelected() {
        guard let note = history.selected else { return }
        show(note)
    }

    private func show(_ note: Note) {
        guard note.id != editor.noteID else { return }
        editor.open(note)
        // A note that could not be saved stays in the editor; then nothing was opened.
        if editor.noteID == note.id { isContinuing = true }
    }

    private func end() {
        isBrowsing = false
        origin = nil
    }
}
