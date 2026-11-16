import Foundation
import Observation

/// All notes, held in memory and kept in step with the files on disk.
///
/// The list only changes after the corresponding file operation has succeeded,
/// so what is shown is always what is stored.
@MainActor @Observable
public final class NoteStore {
    /// Most recently modified first.
    public private(set) var notes: [Note] = []

    private let files: NoteFiles

    public init(files: NoteFiles) {
        self.files = files
    }

    public var directory: URL { files.directory }

    /// Replaces the list with what is on disk.
    public func load() {
        notes = files.loadAll().sorted(by: Self.isOrderedBefore)
    }

    public func note(id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    /// Writes the note and inserts it, or replaces the note with the same id.
    public func save(_ note: Note) throws {
        try files.write(note)
        notes.removeAll { $0.id == note.id }
        let index = notes.firstIndex { Self.isOrderedBefore(note, $0) } ?? notes.endIndex
        notes.insert(note, at: index)
    }

    /// Removes the note and returns it, or returns `nil` if there is no such note.
    @discardableResult
    public func delete(id: UUID) throws -> Note? {
        guard let note = note(id: id) else { return nil }
        try files.delete(id: id)
        notes.removeAll { $0.id == id }
        return note
    }

    public func deleteAll() throws {
        try files.deleteAll()
        notes = []
    }

    /// Newest change first. Ties are broken by creation time and then by id,
    /// so the order never differs between two loads of the same files.
    static func isOrderedBefore(_ a: Note, _ b: Note) -> Bool {
        if a.modified != b.modified { return a.modified > b.modified }
        if a.created != b.created { return a.created > b.created }
        return a.id.uuidString < b.id.uuidString
    }
}
