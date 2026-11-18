import Foundation
import Testing
@testable import JotCore

@MainActor @Suite struct HistoryModelTests {
    let temp = TempDirectory()
    let store: NoteStore
    let anna = makeNote("Ring Anna om offerten", at: 30)
    let brew = makeNote("brew services restart", at: 20)
    let idea = makeNote("Idé: fästa anteckningar", at: 10)

    init() throws {
        store = NoteStore(files: NoteFiles(directory: temp.notes))
        store.load()
        for note in [anna, brew, idea] { try store.save(note) }
    }

    func makeHistory() -> HistoryModel {
        let history = HistoryModel(store: store, locale: Locale(identifier: "en_GB"))
        history.reset()
        return history
    }

    @Test func resetSelectsFirstRowAndFocusesSearch() {
        let history = makeHistory()
        #expect(history.results.map(\.id) == [anna.id, brew.id, idea.id])
        #expect(history.selectedID == anna.id)
        #expect(history.focus == .search)
        #expect(history.query.isEmpty)
    }

    @Test func queryChangeSelectsFirstMatch() {
        let history = makeHistory()
        history.moveSelection(by: 1)
        history.moveSelection(by: 1)

        history.query = "restart"

        #expect(history.results.map(\.id) == [brew.id])
        #expect(history.selectedID == brew.id)
        #expect(history.focus == .search)
    }

    @Test func queryWithoutMatchesClearsSelection() {
        let history = makeHistory()
        history.query = "zzz"
        #expect(history.results.isEmpty)
        #expect(history.selected == nil)
    }

    @Test func downFromSearchEntersListOnTheSameRow() {
        let history = makeHistory()
        history.moveSelection(by: 1)
        #expect(history.focus == .list)
        #expect(history.selectedID == anna.id)
    }

    @Test func downInListMovesToNextRow() {
        let history = makeHistory()
        history.moveSelection(by: 1)
        history.moveSelection(by: 1)
        #expect(history.selectedID == brew.id)
    }

    @Test func upFromFirstRowReturnsToSearch() {
        let history = makeHistory()
        history.moveSelection(by: 1)
        history.moveSelection(by: -1)
        #expect(history.focus == .search)
        #expect(history.selectedID == anna.id)
    }

    @Test func selectionStopsAtLastRow() {
        let history = makeHistory()
        for _ in 0..<10 { history.moveSelection(by: 1) }
        #expect(history.selectedID == idea.id)
        #expect(history.focus == .list)
    }

    @Test func selectChoosesARowAndFocusesTheList() {
        let history = makeHistory()
        history.select(idea.id)
        #expect(history.selected == idea)
        #expect(history.focus == .list)
    }

    @Test func deleteSelectsTheRowThatTookItsPlace() throws {
        let history = makeHistory()
        history.select(brew.id)

        try history.deleteSelected()

        #expect(store.notes.map(\.id) == [anna.id, idea.id])
        #expect(history.selectedID == idea.id)
        #expect(temp.fileNames().count == 2)
    }

    @Test func deleteLastRowSelectsPrevious() throws {
        let history = makeHistory()
        history.select(idea.id)
        try history.deleteSelected()
        #expect(history.selectedID == brew.id)
    }

    @Test func deleteOnlyRowClearsSelection() throws {
        let history = makeHistory()
        history.query = "restart"
        history.moveSelection(by: 1)

        try history.deleteSelected()

        #expect(history.results.isEmpty)
        #expect(history.selectedID == nil)
    }

    @Test func deleteWithNothingSelectedDoesNothing() throws {
        let history = makeHistory()
        history.query = "zzz"
        try history.deleteSelected()
        #expect(store.notes.count == 3)
        #expect(!history.canUndoDelete)
    }

    @Test func undoRestoresNoteFileAndSelection() throws {
        let history = makeHistory()
        history.select(brew.id)
        try history.deleteSelected()
        #expect(history.canUndoDelete)

        try history.undoDelete()

        #expect(store.notes.map(\.id) == [anna.id, brew.id, idea.id])
        #expect(store.note(id: brew.id) == brew)
        #expect(history.selectedID == brew.id)
        #expect(temp.fileNames().count == 3)
        #expect(!history.canUndoDelete)
    }

    @Test func undoIsLastInFirstOut() throws {
        let history = makeHistory()
        history.select(anna.id)
        try history.deleteSelected()
        try history.deleteSelected()
        #expect(store.notes.map(\.id) == [idea.id])

        try history.undoDelete()
        #expect(store.notes.map(\.id) == [brew.id, idea.id])
        try history.undoDelete()
        #expect(store.notes.map(\.id) == [anna.id, brew.id, idea.id])
    }

    @Test func undoWithNothingDeletedDoesNothing() throws {
        let history = makeHistory()
        try history.undoDelete()
        #expect(store.notes.count == 3)
    }

    @Test func resetKeepsDeletedNotesRestorable() throws {
        let history = makeHistory()
        history.moveSelection(by: 1)
        try history.deleteSelected()

        history.reset()

        #expect(history.canUndoDelete)
        try history.undoDelete()
        #expect(store.notes.count == 3)
    }

    @Test func forgetDeletedDropsUndo() throws {
        let history = makeHistory()
        history.moveSelection(by: 1)
        try history.deleteSelected()

        history.forgetDeleted()

        #expect(!history.canUndoDelete)
        try history.undoDelete()
        #expect(store.notes.count == 2)
    }

    @Test func focusSearchSelectsTheFirstMatchAndKeepsTheQuery() {
        let history = makeHistory()
        history.query = "a"
        history.moveSelection(by: 1)
        history.moveSelection(by: 1)
        #expect(history.focus == .list)

        history.focusSearch()

        #expect(history.focus == .search)
        #expect(history.query == "a")
        #expect(history.selectedID == history.results.first?.id)
    }

    @Test func emptyHistoryHasNoSelection() throws {
        try store.deleteAll()
        let history = makeHistory()
        history.moveSelection(by: 1)
        #expect(history.selected == nil)
        #expect(history.results.isEmpty)
    }

    @Test func selectionFollowsANoteThatDisappearsElsewhere() throws {
        let history = makeHistory()
        history.select(brew.id)

        try store.delete(id: brew.id)

        #expect(history.selected == nil)
        history.moveSelection(by: 1)
        #expect(history.selected != nil)
    }
}
