import Foundation
import Observation

/// The note being written, and the rules for when it reaches the disk.
///
/// - A change is saved once typing has paused, and at once on `flush()`.
/// - A note that is empty, or only whitespace, is never created.
/// - A saved note that has been emptied stays on disk until `leave()`, so an
///   accidental "select all, delete" can still be undone.
@MainActor @Observable
public final class Editor {
    public var text: String = "" {
        didSet {
            guard !isReplacingText, text != oldValue else { return }
            debouncer.schedule { [weak self] in self?.save() }
        }
    }

    public private(set) var noteID = UUID()
    /// The note as it was last written, or `nil` if nothing has been saved yet.
    public private(set) var savedNote: Note?
    /// True after a save that did not reach the disk. The text is kept and the next save retries.
    public private(set) var saveFailed = false

    private let store: NoteStore
    private let debouncer: Debouncing
    private let now: () -> Date
    private var isReplacingText = false

    public init(store: NoteStore, debouncer: Debouncing, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.debouncer = debouncer
        self.now = now
    }

    /// Finishes the current note and starts an empty one.
    /// If the current note could not be saved it stays, since this is the only copy of its text.
    public func startNew() {
        leave()
        guard !saveFailed else { return }
        replace(id: UUID(), savedNote: nil, text: "")
    }

    /// Finishes the current note and continues an existing one.
    /// If the current note could not be saved it stays, since this is the only copy of its text.
    public func open(_ note: Note) {
        if note.id == noteID {
            // Already the current note. If its text has been wiped, this is how the user gets it
            // back, so the saved text is restored instead of the note being removed as emptied.
            if isBlank {
                debouncer.cancel()
                replace(id: note.id, savedNote: savedNote ?? note, text: note.text)
            } else {
                flush()
            }
            return
        }
        leave()
        guard !saveFailed else { return }
        replace(id: note.id, savedNote: note, text: note.text)
    }

    /// Drops the current note without saving, if it is the one with this id.
    /// Used when the note has been deleted elsewhere, so that typing cannot bring it back.
    public func forget(id: UUID) {
        guard id == noteID else { return }
        debouncer.cancel()
        saveFailed = false
        replace(id: UUID(), savedNote: nil, text: "")
    }

    /// Saves now instead of waiting for typing to pause.
    public func flush() {
        debouncer.cancel()
        save()
    }

    /// Saves, and removes the note if all of its text has been deleted.
    public func leave() {
        flush()
        guard isBlank, savedNote != nil else { return }
        do {
            try store.delete(id: noteID)
            savedNote = nil
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    private var isBlank: Bool {
        text.allSatisfy(\.isWhitespace)
    }

    private func save() {
        guard !isBlank, text != savedNote?.text else {
            // Nothing that is not already on disk.
            saveFailed = false
            return
        }
        let moment = now()
        let note = Note(id: noteID, text: text, created: savedNote?.created ?? moment, modified: moment)
        do {
            try store.save(note)
            savedNote = note
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    private func replace(id: UUID, savedNote: Note?, text: String) {
        isReplacingText = true
        defer { isReplacingText = false }
        noteID = id
        self.savedNote = savedNote
        self.text = text
    }
}
