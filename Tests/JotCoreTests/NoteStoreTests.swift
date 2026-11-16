import Foundation
import Testing
@testable import JotCore

@MainActor @Suite struct NoteStoreTests {
    let temp = TempDirectory()
    var files: NoteFiles { NoteFiles(directory: temp.notes) }

    func loadedStore() -> NoteStore {
        let store = NoteStore(files: files)
        store.load()
        return store
    }

    @Test func loadSortsNewestFirst() throws {
        try files.write(makeNote("old", at: 0))
        try files.write(makeNote("new", at: 200))
        try files.write(makeNote("middle", at: 100))

        #expect(loadedStore().notes.map(\.text) == ["new", "middle", "old"])
    }

    @Test func saveInsertsAtTheTop() throws {
        let store = loadedStore()
        try store.save(makeNote("first", at: 0))
        try store.save(makeNote("second", at: 10))

        #expect(store.notes.map(\.text) == ["second", "first"])
        #expect(temp.fileNames().count == 2)
    }

    @Test func saveOfExistingReplacesItAndMovesItUp() throws {
        let store = loadedStore()
        var first = makeNote("first", at: 0)
        try store.save(first)
        try store.save(makeNote("second", at: 10))

        first.text = "first, edited"
        first.modified = date(20)
        try store.save(first)

        #expect(store.notes.map(\.text) == ["first, edited", "second"])
        #expect(store.note(id: first.id)?.text == "first, edited")
        #expect(temp.fileNames().count == 2)
    }

    @Test func deleteRemovesFileAndRow() throws {
        let store = loadedStore()
        let note = makeNote("gone")
        try store.save(note)

        let deleted = try store.delete(id: note.id)

        #expect(deleted == note)
        #expect(store.notes.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func deleteOfUnknownNoteReturnsNil() throws {
        #expect(try loadedStore().delete(id: UUID()) == nil)
    }

    @Test func deleteAllEmptiesBoth() throws {
        let store = loadedStore()
        try store.save(makeNote("a"))
        try store.save(makeNote("b", at: 1))

        try store.deleteAll()

        #expect(store.notes.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func survivesRestart() throws {
        let first = loadedStore()
        try first.save(makeNote("still here", at: 5))

        #expect(loadedStore().notes.map(\.text) == ["still here"])
    }

    @Test func equalTimestampsOrderStably() throws {
        let ids = (0..<5).map { _ in UUID() }
        for id in ids { try files.write(makeNote("same moment", at: 0, id: id)) }

        let first = loadedStore().notes.map(\.id)
        let second = loadedStore().notes.map(\.id)

        #expect(first == second)
        #expect(first == ids.sorted { $0.uuidString < $1.uuidString })
    }

    @Test func olderModifiedSortsLower() throws {
        let store = loadedStore()
        try store.save(makeNote("recent", at: 100))
        // The clock was set back: this save carries an older timestamp.
        try store.save(makeNote("written with an earlier clock", at: 50))

        #expect(store.notes.map(\.text) == ["recent", "written with an earlier clock"])
    }

    @Test func failedSaveLeavesTheListUntouched() throws {
        let store = loadedStore()
        try store.save(makeNote("kept"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.notes.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.notes.path) }

        #expect(throws: (any Error).self) { try store.save(makeNote("lost", at: 10)) }
        #expect(store.notes.map(\.text) == ["kept"])
    }
}
