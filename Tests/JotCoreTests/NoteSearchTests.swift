import Foundation
import Testing
@testable import JotCore

@Suite struct NoteSearchTests {
    let english = Locale(identifier: "en_GB")
    let notes = [
        makeNote("Ring Anna om offerten", at: 30),
        makeNote("brew services restart postgresql", at: 20),
        makeNote("Café on Storgatan 12", at: 10),
        makeNote("Ring Anna", at: 0),
    ]

    func search(_ query: String) -> [String] {
        NoteSearch.filter(notes, query: query, locale: english).map(\.text)
    }

    @Test func emptyQueryReturnsAll() {
        #expect(search("").count == 4)
    }

    @Test func whitespaceOnlyQueryReturnsAll() {
        #expect(search("  \t ").count == 4)
    }

    @Test func matchesAnywhereInText() {
        #expect(search("postgres") == ["brew services restart postgresql"])
    }

    @Test func isCaseInsensitive() {
        #expect(search("STORGATAN") == ["Café on Storgatan 12"])
    }

    @Test func allWordsMustMatch() {
        #expect(search("anna offert") == ["Ring Anna om offerten"])
    }

    @Test func wordOrderDoesNotMatter() {
        #expect(search("offert anna") == ["Ring Anna om offerten"])
    }

    @Test func ignoresAccentsInEnglish() {
        #expect(search("cafe") == ["Café on Storgatan 12"])
    }

    @Test func keepsOrder() {
        #expect(search("ring") == ["Ring Anna om offerten", "Ring Anna"])
    }

    @Test func noMatchGivesEmptyResult() {
        #expect(search("zzz").isEmpty)
    }

    @Test func matchesAcrossLines() {
        let multiline = [makeNote("first line\nsecond line with needle")]
        #expect(NoteSearch.filter(multiline, query: "first needle", locale: english).count == 1)
    }
}
