import Foundation
import Testing
@testable import JotCore

/// A debouncer the test fires by hand.
@MainActor final class ManualDebouncer: Debouncing {
    private var pending: (@MainActor () -> Void)?
    private(set) var scheduleCount = 0

    func schedule(_ action: @escaping @MainActor () -> Void) {
        scheduleCount += 1
        pending = action
    }

    func cancel() { pending = nil }

    var hasPending: Bool { pending != nil }

    func fire() {
        let action = pending
        pending = nil
        action?()
    }
}

@MainActor @Suite struct EditorTests {
    let temp = TempDirectory()
    let debouncer = ManualDebouncer()
    let store: NoteStore
    var clock = Clock()

    final class Clock { var now = date(0) }

    init() {
        store = NoteStore(files: NoteFiles(directory: temp.notes))
        store.load()
    }

    func makeEditor() -> Editor {
        let clock = clock
        return Editor(store: store, debouncer: debouncer, now: { clock.now })
    }

    @Test func typingSchedulesOneSave() {
        let editor = makeEditor()
        editor.text = "C"
        editor.text = "Ca"
        editor.text = "Call"

        debouncer.fire()

        #expect(store.notes.map(\.text) == ["Call"])
        #expect(temp.fileNames().count == 1)
    }

    @Test func nothingIsWrittenBeforeTheDelay() {
        let editor = makeEditor()
        editor.text = "not yet"

        #expect(debouncer.hasPending)
        #expect(store.notes.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func flushSavesImmediately() {
        let editor = makeEditor()
        editor.text = "right now"

        editor.flush()

        #expect(store.notes.map(\.text) == ["right now"])
        #expect(!debouncer.hasPending)
        #expect(editor.savedNote?.text == "right now")
    }

    @Test(arguments: ["", "   \n", "\t\n \n"])
    func emptyNoteIsNeverSaved(text: String) {
        let editor = makeEditor()
        editor.text = text

        editor.flush()
        editor.leave()

        #expect(store.notes.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func savedNoteCarriesTheClock() {
        let editor = makeEditor()
        clock.now = date(30)
        editor.text = "timed"
        editor.flush()

        #expect(editor.savedNote?.created == date(30))
        #expect(editor.savedNote?.modified == date(30))
    }

    @Test func unchangedOpenedNoteKeepsItsTimestamp() throws {
        let note = makeNote("read only", at: 10)
        try store.save(note)
        let editor = makeEditor()
        clock.now = date(500)

        editor.open(note)
        editor.flush()
        editor.leave()

        #expect(store.notes == [note])
    }

    @Test func editingOpenedNoteUpdatesModifiedOnly() throws {
        let note = makeNote("draft", at: 10)
        try store.save(note)
        let editor = makeEditor()
        editor.open(note)
        clock.now = date(500)

        editor.text = "draft, improved"
        editor.flush()

        let saved = try #require(store.note(id: note.id))
        #expect(saved.text == "draft, improved")
        #expect(saved.created == date(10))
        #expect(saved.modified == date(500))
        #expect(store.notes.count == 1)
    }

    @Test func emptiedNoteStaysUntilLeave() {
        let editor = makeEditor()
        editor.text = "about to be cleared"
        editor.flush()

        editor.text = ""
        debouncer.fire()
        #expect(store.notes.map(\.text) == ["about to be cleared"])

        editor.leave()
        #expect(store.notes.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func startNewLeavesCurrentFirst() {
        let editor = makeEditor()
        editor.text = "first thought"
        let firstID = editor.noteID

        editor.startNew()

        #expect(store.notes.map(\.text) == ["first thought"])
        #expect(editor.text.isEmpty)
        #expect(editor.noteID != firstID)
        #expect(editor.savedNote == nil)
        #expect(!debouncer.hasPending)
    }

    @Test func openLeavesCurrentFirst() throws {
        let existing = makeNote("existing", at: 5)
        try store.save(existing)
        let editor = makeEditor()
        clock.now = date(50)
        editor.text = "half a thought"

        editor.open(existing)

        #expect(store.notes.map(\.text) == ["half a thought", "existing"])
        #expect(editor.text == "existing")
        #expect(editor.noteID == existing.id)
    }

    @Test func openingDoesNotScheduleASave() throws {
        let existing = makeNote("existing", at: 5)
        try store.save(existing)
        let editor = makeEditor()

        editor.open(existing)

        #expect(!debouncer.hasPending)
    }

    @Test func failedSaveKeepsTextAndRetries() throws {
        let editor = makeEditor()
        editor.text = "seed"
        editor.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.notes.path)

        editor.text = "must not be lost"
        editor.flush()

        #expect(editor.saveFailed)
        #expect(editor.text == "must not be lost")
        #expect(store.notes.map(\.text) == ["seed"])

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.notes.path)
        editor.flush()

        #expect(!editor.saveFailed)
        #expect(store.notes.map(\.text) == ["must not be lost"])
    }

    @Test func unsavedTextIsNotReplacedByANewNote() throws {
        let existing = makeNote("existing", at: 5)
        try store.save(existing)
        let editor = makeEditor()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.notes.path)
        editor.text = "only copy"
        let id = editor.noteID

        editor.startNew()
        editor.open(existing)

        #expect(editor.text == "only copy")
        #expect(editor.noteID == id)
        #expect(editor.saveFailed)
    }

    @Test func forgettingTheOpenNoteStartsAnEmptyOneWithoutSaving() throws {
        let note = makeNote("deleted from history", at: 5)
        try store.save(note)
        let editor = makeEditor()
        editor.open(note)
        editor.text = "deleted from history, with an edit"
        try store.delete(id: note.id)

        editor.forget(id: note.id)

        #expect(editor.text.isEmpty)
        #expect(editor.noteID != note.id)
        #expect(editor.savedNote == nil)
        #expect(!debouncer.hasPending)
        editor.leave()
        #expect(store.notes.isEmpty)
    }

    @Test func forgettingAnotherNoteChangesNothing() {
        let editor = makeEditor()
        editor.text = "still here"
        let id = editor.noteID

        editor.forget(id: UUID())

        #expect(editor.text == "still here")
        #expect(editor.noteID == id)
    }

    @Test func reopeningTheEmptiedNoteRestoresIt() throws {
        let editor = makeEditor()
        editor.text = "wiped by accident"
        editor.flush()
        let note = try #require(store.notes.first)
        editor.text = ""
        editor.flush()

        editor.open(note)

        #expect(editor.text == "wiped by accident")
        #expect(temp.fileNames().count == 1)
        editor.leave()
        #expect(store.notes.map(\.text) == ["wiped by accident"])
        #expect(temp.fileNames().count == 1)
    }

    @Test func reopeningTheCurrentNoteKeepsWhatIsInTheEditor() throws {
        let editor = makeEditor()
        editor.text = "first version"
        editor.flush()
        let stale = try #require(store.notes.first)
        editor.text = "second version"

        editor.open(stale)

        #expect(editor.text == "second version")
        #expect(store.notes.map(\.text) == ["second version"])
    }

    @Test func saveFailedClearsWhenThereIsNothingLeftToSave() throws {
        let editor = makeEditor()
        editor.text = "seed"
        editor.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.notes.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.notes.path) }
        editor.text = "seed, changed"
        editor.flush()
        #expect(editor.saveFailed)

        editor.text = "seed"
        editor.flush()

        #expect(!editor.saveFailed)
    }

    @Test func onlyReplacingTheTextFromOutsideBumpsTheRevision() throws {
        let existing = makeNote("existing", at: 5)
        try store.save(existing)
        let editor = makeEditor()
        let start = editor.contentRevision

        editor.text = "typed"
        editor.text = "typed more"
        editor.flush()
        #expect(editor.contentRevision == start)

        editor.open(existing)
        #expect(editor.contentRevision == start + 1)
        editor.startNew()
        #expect(editor.contentRevision == start + 2)
    }

    @Test func timerDebouncerFiresOnceAfterDelay() async throws {
        let debouncer = TimerDebouncer(delay: .milliseconds(50))
        var fired: [String] = []

        debouncer.schedule { fired.append("first") }
        debouncer.schedule { fired.append("second") }
        #expect(fired.isEmpty)

        // Other suites may keep the main actor busy, so wait for the action rather than for a fixed time.
        let deadline = ContinuousClock.now + .seconds(10)
        while fired.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(fired == ["second"])
    }

    @Test func timerDebouncerCancelPreventsFiring() async throws {
        let debouncer = TimerDebouncer(delay: .milliseconds(50))
        var fired = false

        debouncer.schedule { fired = true }
        debouncer.cancel()

        try await Task.sleep(for: .milliseconds(300))
        #expect(!fired)
    }
}
