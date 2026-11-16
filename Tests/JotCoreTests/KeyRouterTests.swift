import Testing
@testable import JotCore

@Suite struct KeyRouterTests {
    // Virtual key codes (ANSI layout positions).
    static let escape: UInt16 = 53, returnKey: UInt16 = 36, enter: UInt16 = 76
    static let up: UInt16 = 126, down: UInt16 = 125, delete: UInt16 = 51
    static let c: UInt16 = 8, f: UInt16 = 3, n: UInt16 = 45, q: UInt16 = 12
    static let w: UInt16 = 13, z: UInt16 = 6, comma: UInt16 = 43, a: UInt16 = 0

    func route(_ key: UInt16, _ modifiers: KeyModifiers = [], in context: KeyContext) -> KeyCommand? {
        KeyRouter.command(for: KeyPress(keyCode: key, modifiers: modifiers), in: context)
    }

    @Test func escapeClosesWhenWritingAndGoesBackFromHistory() {
        #expect(route(Self.escape, in: .writing) == .close)
        #expect(route(Self.escape, in: .historySearch) == .backToWriting)
        #expect(route(Self.escape, in: .historyList) == .backToWriting)
    }

    @Test(arguments: [KeyContext.writing, .historySearch, .historyList])
    func commandWAndQCloseEverywhere(context: KeyContext) {
        #expect(route(Self.w, .command, in: context) == .close)
        #expect(route(Self.q, .command, in: context) == .close)
    }

    @Test func commandFOpensHistoryThenFocusesSearch() {
        #expect(route(Self.f, .command, in: .writing) == .showHistory)
        #expect(route(Self.f, .command, in: .historySearch) == .focusSearch)
        #expect(route(Self.f, .command, in: .historyList) == .focusSearch)
    }

    @Test(arguments: [KeyContext.writing, .historySearch, .historyList])
    func commandNStartsANewNoteAndCommandCommaOpensSettings(context: KeyContext) {
        #expect(route(Self.n, .command, in: context) == .newNote)
        #expect(route(Self.comma, .command, in: context) == .settings)
    }

    @Test func commandShiftCCopiesTheWholeNote() {
        #expect(route(Self.c, [.command, .shift], in: .writing) == .copyAll)
        #expect(route(Self.c, [.command, .shift], in: .historySearch) == .copySelected)
        #expect(route(Self.c, [.command, .shift], in: .historyList) == .copySelected)
    }

    @Test func plainCommandCIsLeftToTheTextFieldExceptInTheList() {
        #expect(route(Self.c, .command, in: .writing) == nil)
        #expect(route(Self.c, .command, in: .historySearch) == nil)
        #expect(route(Self.c, .command, in: .historyList) == .copySelected)
    }

    @Test func arrowsMoveTheSelectionOnlyInHistory() {
        #expect(route(Self.down, in: .writing) == nil)
        #expect(route(Self.up, in: .writing) == nil)
        #expect(route(Self.down, in: .historySearch) == .moveDown)
        #expect(route(Self.up, in: .historySearch) == nil)
        #expect(route(Self.down, in: .historyList) == .moveDown)
        #expect(route(Self.up, in: .historyList) == .moveUp)
    }

    @Test func returnOpensTheSelectedNoteInHistory() {
        #expect(route(Self.returnKey, in: .writing) == nil)
        #expect(route(Self.returnKey, in: .historySearch) == .openSelected)
        #expect(route(Self.returnKey, in: .historyList) == .openSelected)
        #expect(route(Self.enter, in: .historyList) == .openSelected)
    }

    @Test func deleteAndUndoActOnNotesOnlyInTheList() {
        #expect(route(Self.delete, .command, in: .writing) == nil)
        #expect(route(Self.delete, .command, in: .historySearch) == nil)
        #expect(route(Self.delete, .command, in: .historyList) == .deleteSelected)
        #expect(route(Self.z, .command, in: .writing) == nil)
        #expect(route(Self.z, .command, in: .historySearch) == nil)
        #expect(route(Self.z, .command, in: .historyList) == .undoDelete)
    }

    @Test func extraModifiersDoNotMatch() {
        #expect(route(Self.escape, .shift, in: .writing) == nil)
        #expect(route(Self.w, [.command, .option], in: .writing) == nil)
        #expect(route(Self.delete, in: .historyList) == nil)
        #expect(route(Self.returnKey, .shift, in: .historyList) == nil)
    }

    @Test func ordinaryTypingIsNeverRouted() {
        for context in [KeyContext.writing, .historySearch, .historyList] {
            #expect(route(Self.a, in: context) == nil)
            #expect(route(Self.a, .shift, in: context) == nil)
        }
    }

    @Test func typingInTheListReturnsFocusToSearch() {
        #expect(KeyRouter.returnsFocusToSearch(KeyPress(keyCode: Self.a, modifiers: []), in: .historyList))
        #expect(KeyRouter.returnsFocusToSearch(KeyPress(keyCode: Self.delete, modifiers: []), in: .historyList))
        #expect(!KeyRouter.returnsFocusToSearch(KeyPress(keyCode: Self.a, modifiers: .command), in: .historyList))
        #expect(!KeyRouter.returnsFocusToSearch(KeyPress(keyCode: Self.down, modifiers: []), in: .historyList))
        #expect(!KeyRouter.returnsFocusToSearch(KeyPress(keyCode: Self.a, modifiers: []), in: .historySearch))
        #expect(!KeyRouter.returnsFocusToSearch(KeyPress(keyCode: Self.a, modifiers: []), in: .writing))
    }
}
