import Foundation
import Observation

/// The history list: what is shown, which row is selected, and deleting with undo.
@MainActor @Observable
public final class HistoryModel {
    /// Where keys go. The search field edits the query; the list acts on the selected note.
    public enum Focus: Sendable { case search, list }

    /// Changing the query selects the first match and returns focus to the search field.
    public var query: String = "" {
        didSet {
            selectedID = results.first?.id
            focus = .search
        }
    }

    public var focus: Focus = .search
    public private(set) var selectedID: UUID?

    private let store: NoteStore
    private let locale: Locale
    /// Notes deleted since the history was opened, most recent last.
    private var deleted: [Note] = []

    public init(store: NoteStore, locale: Locale = .current) {
        self.store = store
        self.locale = locale
    }

    public var results: [Note] {
        NoteSearch.filter(store.notes, query: query, locale: locale)
    }

    public var selected: Note? {
        guard let selectedID else { return nil }
        return results.first { $0.id == selectedID }
    }

    public var canUndoDelete: Bool { !deleted.isEmpty }

    /// Back to the state the history opens in. Deleted notes can no longer be restored.
    public func reset() {
        deleted = []
        query = ""
    }

    public func select(_ id: UUID) {
        selectedID = id
        focus = .list
    }

    /// Moves the selection down (positive) or up (negative).
    /// Down from the search field enters the list on the selected row; up from the first row leaves it.
    public func moveSelection(by delta: Int) {
        let results = results
        guard !results.isEmpty, delta != 0 else { return }
        guard let index = results.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = results[0].id
            if delta > 0 { focus = .list }
            return
        }
        switch focus {
        case .search:
            if delta > 0 { focus = .list }
        case .list:
            if index == 0, delta < 0 {
                focus = .search
            } else {
                selectedID = results[min(max(index + delta, 0), results.count - 1)].id
            }
        }
    }

    /// Deletes the selected note and selects the row that takes its place.
    public func deleteSelected() throws {
        guard let note = selected, let index = results.firstIndex(of: note) else { return }
        try store.delete(id: note.id)
        deleted.append(note)
        let remaining = results
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    /// Brings back the most recently deleted note, exactly as it was.
    public func undoDelete() throws {
        guard let note = deleted.last else { return }
        try store.save(note)
        deleted.removeLast()
        selectedID = note.id
        focus = .list
    }
}
