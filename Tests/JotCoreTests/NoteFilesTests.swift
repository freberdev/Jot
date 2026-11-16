import Foundation
import Testing
@testable import JotCore

@Suite struct NoteFilesTests {
    let temp = TempDirectory()
    var files: NoteFiles { NoteFiles(directory: temp.notes) }

    @Test func writeThenLoadRoundTrips() throws {
        let note = Note(text: "Call Anna", created: date(0.123), modified: date(60.456))
        try files.write(note)

        let loaded = files.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == note.id)
        #expect(loaded[0].text == "Call Anna")
        #expect(abs(loaded[0].created.timeIntervalSince(note.created)) < 0.001)
        #expect(abs(loaded[0].modified.timeIntervalSince(note.modified)) < 0.001)
    }

    @Test func loadOfMissingDirectoryIsEmpty() {
        #expect(files.loadAll().isEmpty)
    }

    @Test func writeCreatesMissingDirectory() throws {
        try files.write(makeNote("first"))
        try FileManager.default.removeItem(at: temp.notes)

        try files.write(makeNote("second"))

        #expect(files.loadAll().map(\.text) == ["second"])
    }

    @Test func writeLeavesOnlyTheNoteFile() throws {
        let note = makeNote("text")
        try files.write(note)
        try files.write(note)

        #expect(temp.fileNames() == ["\(note.id.uuidString).json"])
    }

    @Test func permissionsAreOwnerOnly() throws {
        let note = makeNote("private")
        try files.write(note)

        let directory = try FileManager.default.attributesOfItem(atPath: temp.notes.path)
        let file = try FileManager.default.attributesOfItem(
            atPath: temp.notes.appendingPathComponent("\(note.id.uuidString).json").path)
        #expect(directory[.posixPermissions] as? Int == 0o700)
        #expect(file[.posixPermissions] as? Int == 0o600)
    }

    @Test func loadSkipsForeignAndBrokenFiles() throws {
        let good = makeNote("good")
        try files.write(good)
        let future = UUID()
        let strays: [String: String] = [
            ".DS_Store": "binary junk",
            "half.json": "{\"id\":",
            "\(future.uuidString).json":
                "{\"version\":99,\"id\":\"\(future.uuidString)\",\"body\":\"from the future\"}",
        ]
        for (name, content) in strays {
            try Data(content.utf8).write(to: temp.notes.appendingPathComponent(name))
        }

        #expect(files.loadAll().map(\.id) == [good.id])
        for (name, content) in strays {
            let data = try Data(contentsOf: temp.notes.appendingPathComponent(name))
            #expect(String(decoding: data, as: UTF8.self) == content)
        }
    }

    @Test(arguments: [
        String(repeating: "0123456789abcdef", count: 65_536),
        "Tänk på 🎉 och 👨‍👩‍👧 — “citat”",
        "one\r\ntwo\r\n",
        "\n\n\n",
        "tab\there\u{0000}null",
    ])
    func oddTextRoundTrips(text: String) throws {
        let note = makeNote(text)
        try files.write(note)

        let loaded = try #require(files.loadAll().first)
        #expect(Array(loaded.text.unicodeScalars) == Array(text.unicodeScalars))
    }

    @Test func deleteIsIdempotent() throws {
        let note = makeNote("gone")
        try files.write(note)

        try files.delete(id: note.id)
        try files.delete(id: note.id)

        #expect(files.loadAll().isEmpty)
    }

    @Test func deleteAllLeavesForeignFiles() throws {
        try files.write(makeNote("a"))
        try files.write(makeNote("b"))
        try Data("mine".utf8).write(to: temp.notes.appendingPathComponent("readme.txt"))

        try files.deleteAll()

        #expect(temp.fileNames() == ["readme.txt"])
    }

    @Test func deleteAllLeavesNoteFilesItCannotRead() throws {
        try files.write(makeNote("readable"))
        let future = UUID(), broken = UUID()
        try Data("{\"version\":99,\"id\":\"\(future.uuidString)\",\"body\":\"newer\"}".utf8)
            .write(to: temp.notes.appendingPathComponent("\(future.uuidString).json"))
        try Data("{\"id\":".utf8).write(to: temp.notes.appendingPathComponent("\(broken.uuidString).json"))

        try files.deleteAll()

        #expect(temp.fileNames() == ["\(broken.uuidString).json", "\(future.uuidString).json"].sorted())
    }

    @Test func defaultDirectoryIsInApplicationSupport() {
        #expect(NoteFiles.defaultDirectory.path.hasSuffix("/Library/Application Support/Jot/Notes"))
    }
}
