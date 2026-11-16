import Foundation
import Testing
@testable import JotCore

@Suite struct NoteTests {
    @Test func newNotesGetDistinctIDs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let a = Note(text: "a", created: now, modified: now)
        let b = Note(text: "a", created: now, modified: now)
        #expect(a.id != b.id)
        #expect(a != b)
    }
}
