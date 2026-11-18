import Foundation
import Testing
@testable import JotCore

/// The side list next to the editor: the row the user stands on is the note that is shown.
@MainActor @Suite struct NoteBrowserTests {
    let temp = TempDirectory()
    let debouncer = ManualDebouncer()
    let store: NoteStore
    let editor: Editor
    let history: HistoryModel
    let browser: NoteBrowser
    let anna = makeNote("Ring Anna om offerten", at: 30)
    let brew = makeNote("brew services restart", at: 20)
    let idea = makeNote("Idé: fästa anteckningar", at: 10)

    init() throws {
        store = NoteStore(files: NoteFiles(directory: temp.notes))
        store.load()
        for note in [anna, brew, idea] { try store.save(note) }
        editor = Editor(store: store, debouncer: debouncer, now: { date(1_000) })
        history = HistoryModel(store: store, locale: Locale(identifier: "en_GB"))
        browser = NoteBrowser(store: store, editor: editor, history: history)
        browser.openSession()
    }

    @Test func aSessionStartsWithANewEmptyNoteOutsideTheList() {
        #expect(editor.text.isEmpty)
        #expect(editor.savedNote == nil)
        #expect(!browser.isBrowsing)
        #expect(!browser.isContinuing)
        #expect(browser.highlightedID == nil)
    }

    @Test func searchThenDownShowsTheNewestNote() {
        #expect(browser.enterSearch())
        #expect(browser.isBrowsing)
        #expect(editor.text.isEmpty)

        browser.move(by: 1)

        #expect(editor.text == anna.text)
        #expect(editor.noteID == anna.id)
        #expect(history.focus == .list)
        #expect(browser.isContinuing)
        #expect(browser.highlightedID == anna.id)
    }

    @Test func movingThroughTheListShowsEachNote() {
        browser.enterSearch()
        browser.move(by: 1)
        browser.move(by: 1)
        #expect(editor.text == brew.text)
        browser.move(by: 1)
        #expect(editor.text == idea.text)
        browser.move(by: -1)
        #expect(editor.text == brew.text)
    }

    @Test func browsingChangesNoNote() {
        let before = store.notes
        browser.enterSearch()
        for _ in 0..<4 { browser.move(by: 1) }
        for _ in 0..<4 { browser.move(by: -1) }
        browser.cancel()

        #expect(store.notes == before)
        #expect(temp.fileNames().count == 3)
    }

    @Test func typingAQueryDoesNotChangeTheEditor() {
        browser.enterSearch()
        history.query = "restart"

        #expect(editor.text.isEmpty)
        #expect(browser.highlightedID == brew.id)
    }

    @Test func commitFromTheSearchFieldOpensTheFirstMatch() {
        browser.enterSearch()
        history.query = "restart"

        browser.commit()

        #expect(editor.text == brew.text)
        #expect(!browser.isBrowsing)
        #expect(browser.isContinuing)
        #expect(browser.highlightedID == brew.id)
    }

    @Test func commitFromTheListKeepsTheShownNote() {
        browser.enterSearch()
        browser.move(by: 1)
        browser.move(by: 1)

        browser.commit()

        #expect(editor.noteID == brew.id)
        #expect(!browser.isBrowsing)
    }

    @Test func commitWithNoMatchesKeepsTheEditor() {
        editor.text = "my draft"
        browser.enterSearch()
        history.query = "zzz"

        browser.commit()

        #expect(editor.text == "my draft")
        #expect(!browser.isBrowsing)
    }

    @Test func cancelReturnsToANewEmptyNote() {
        browser.enterSearch()
        browser.move(by: 1)
        browser.move(by: 1)

        browser.cancel()

        #expect(editor.text.isEmpty)
        #expect(editor.savedNote == nil)
        #expect(!browser.isBrowsing)
        #expect(!browser.isContinuing)
        #expect(store.notes.count == 3)
    }

    @Test func theDraftIsSavedBeforeBrowsingAndCancelReturnsToIt() throws {
        editor.text = "half a thought"
        let draftID = editor.noteID

        browser.enterSearch()
        #expect(store.note(id: draftID)?.text == "half a thought")
        browser.move(by: 1)
        browser.move(by: 1)
        #expect(editor.noteID != draftID)

        browser.cancel()

        #expect(editor.noteID == draftID)
        #expect(editor.text == "half a thought")
        #expect(!browser.isContinuing)
        #expect(store.notes.count == 4)
    }

    @Test func cancelReturnsToTheEarlierNoteTheUserWasIn() {
        browser.open(idea)
        browser.enterSearch()
        browser.move(by: 1)
        #expect(editor.noteID == anna.id)

        browser.cancel()

        #expect(editor.noteID == idea.id)
        #expect(browser.isContinuing)
    }

    @Test func cancelFromTheSearchFieldChangesNothing() {
        editor.text = "still writing"
        let id = editor.noteID
        browser.enterSearch()
        history.query = "anna"

        browser.cancel()

        #expect(editor.noteID == id)
        #expect(editor.text == "still writing")
    }

    @Test func cancelAfterTheOriginWasDeletedGivesANewNote() throws {
        editor.text = "about to go"
        let draftID = editor.noteID
        browser.enterSearch()
        browser.move(by: 1)
        #expect(editor.noteID == draftID)
        try browser.deleteSelected()

        browser.cancel()

        #expect(editor.text.isEmpty)
        #expect(editor.savedNote == nil)
        #expect(store.note(id: draftID) == nil)
    }

    @Test func stayKeepsWhatIsShownWithoutOpeningAnything() {
        browser.enterSearch()

        browser.stay()

        #expect(editor.text.isEmpty)
        #expect(editor.savedNote == nil)
        #expect(!browser.isBrowsing)
    }

    @Test func clickingARowOpensItAndLeavesTheList() {
        browser.enterSearch()

        browser.open(idea)

        #expect(editor.noteID == idea.id)
        #expect(!browser.isBrowsing)
        #expect(browser.isContinuing)
        #expect(browser.highlightedID == idea.id)
    }

    @Test func deleteInTheListShowsTheNoteThatTakesItsPlace() throws {
        browser.enterSearch()
        browser.move(by: 1)

        try browser.deleteSelected()

        #expect(store.notes.map(\.id) == [brew.id, idea.id])
        #expect(editor.noteID == brew.id)
        #expect(editor.text == brew.text)
    }

    @Test func undoBringsTheNoteBackAndShowsIt() throws {
        browser.enterSearch()
        browser.move(by: 1)
        try browser.deleteSelected()

        try browser.undoDelete()

        #expect(store.notes.map(\.id) == [anna.id, brew.id, idea.id])
        #expect(editor.noteID == anna.id)
        #expect(store.note(id: anna.id) == anna)
    }

    @Test func deletingTheLastNoteLeavesAnEmptyEditor() throws {
        browser.enterSearch()
        history.query = "restart"
        browser.move(by: 1)

        try browser.deleteSelected()

        #expect(editor.text.isEmpty)
        #expect(editor.savedNote == nil)
        #expect(!browser.isContinuing)
    }

    @Test func deletingARowWithTheMouseForgetsItInTheEditor() throws {
        browser.open(brew)

        try browser.delete(brew)

        #expect(store.note(id: brew.id) == nil)
        #expect(editor.text.isEmpty)
        #expect(!browser.isBrowsing)
        #expect(history.canUndoDelete)
    }

    @Test func deletingAnotherRowWithTheMouseLeavesTheEditorAlone() throws {
        editor.text = "writing"
        let id = editor.noteID

        try browser.delete(brew)

        #expect(editor.noteID == id)
        #expect(editor.text == "writing")
        #expect(store.note(id: brew.id) == nil)
    }

    @Test func enteringTheListIsRefusedWhileTheNoteCannotBeSaved() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.notes.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.notes.path) }
        editor.text = "only copy"

        #expect(!browser.enterSearch())
        #expect(!browser.isBrowsing)
        #expect(editor.text == "only copy")
    }

    @Test func startNewLeavesTheList() {
        browser.enterSearch()
        browser.move(by: 1)

        browser.startNew()

        #expect(editor.text.isEmpty)
        #expect(!browser.isBrowsing)
        #expect(!browser.isContinuing)
    }

    @Test func aNewSessionClearsTheSearchAndPicksUpOutsideChanges() throws {
        browser.enterSearch()
        history.query = "anna"
        browser.move(by: 1)
        try NoteFiles(directory: temp.notes).write(makeNote("added in Finder", at: 500))

        browser.closeSession()
        browser.openSession()

        #expect(history.query.isEmpty)
        #expect(editor.text.isEmpty)
        #expect(!browser.isBrowsing)
        #expect(store.notes.first?.text == "added in Finder")
    }

    @Test func closingTheSessionGivesUpDeletedNotes() throws {
        browser.enterSearch()
        browser.move(by: 1)
        try browser.deleteSelected()

        browser.closeSession()

        #expect(!history.canUndoDelete)
    }

    @Test func theNoteBeingWrittenIsHighlightedOnceItIsSaved() {
        editor.text = "new one"
        #expect(browser.highlightedID == nil)
        editor.flush()
        #expect(browser.highlightedID == editor.noteID)
    }
}
