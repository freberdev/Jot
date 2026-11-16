import Foundation
import Testing
@testable import JotCore

/// Jot keeps every note in memory and searches by scanning. These tests hold that design
/// to account at sizes well beyond everyday use.
@MainActor @Suite(.serialized) struct ScaleTests {
    let temp = TempDirectory()
    var files: NoteFiles { NoteFiles(directory: temp.notes) }

    func elapsed(_ work: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        return try clock.measure(work)
    }

    @Test func tenThousandNotesLoadAndSearchQuickly() throws {
        let words = ["offert", "möte", "brew", "postgres", "idé", "portkod", "ring", "följ upp"]
        for index in 0..<10_000 {
            let text = "\(words[index % words.count]) nummer \(index)\nandra raden med lite mer text att söka i"
            try files.write(makeNote(text, at: TimeInterval(index)))
        }
        let store = NoteStore(files: files)

        let loading = elapsed { store.load() }
        #expect(store.notes.count == 10_000)
        #expect(loading < .seconds(2), "loading took \(loading)")

        var hits = 0
        let searching = elapsed {
            hits = NoteSearch.filter(store.notes, query: "portkod 9", locale: Locale(identifier: "sv_SE")).count
        }
        #expect(hits > 0)
        #expect(searching < .milliseconds(50), "searching took \(searching)")
    }

    @Test func aMegabyteNoteSavesQuickly() throws {
        let store = NoteStore(files: files)
        let note = makeNote(String(repeating: "En rad text i en mycket lång anteckning.\n", count: 26_000))
        #expect(note.text.utf8.count > 1_000_000)

        let saving = try elapsed { try store.save(note) }

        #expect(saving < .milliseconds(100), "saving took \(saving)")
        #expect(files.loadAll().first?.text.count == note.text.count)
    }
}
