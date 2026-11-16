import Testing
@testable import JotCore

@Suite struct NotePreviewTests {
    @Test func skipsLeadingBlankLines() {
        #expect(NotePreview.line(for: "\n\n  Hello  \nworld") == "Hello")
    }

    @Test func collapsesWhitespace() {
        #expect(NotePreview.line(for: "a \t  b") == "a b")
    }

    @Test func truncatesWithEllipsis() {
        let preview = NotePreview.line(for: String(repeating: "x", count: 200), limit: 10)
        #expect(preview == String(repeating: "x", count: 9) + "…")
    }

    @Test func textAtTheLimitIsNotTruncated() {
        #expect(NotePreview.line(for: "0123456789", limit: 10) == "0123456789")
    }

    @Test func emptyTextGivesEmptyString() {
        #expect(NotePreview.line(for: "") == "")
    }

    @Test func onlyNewlinesGivesEmptyString() {
        #expect(NotePreview.line(for: "\n\n \n") == "")
    }

    @Test func crlfIsOneLineBreak() {
        #expect(NotePreview.line(for: "one\r\ntwo") == "one")
    }

    @Test func emojiAreNotCutInHalf() {
        #expect(NotePreview.line(for: "👨‍👩‍👧👨‍👩‍👧👨‍👩‍👧", limit: 2) == "👨‍👩‍👧…")
    }
}
