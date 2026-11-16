import Foundation
@testable import JotCore

/// A temporary directory that is removed when the value is deallocated.
final class TempDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jot-tests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        // Restore permissions first so a directory made read-only by a test can be removed.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    var notes: URL { url.appendingPathComponent("Notes", isDirectory: true) }

    func fileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: notes.path)) ?? []).sorted()
    }
}

func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_800_000_000 + seconds)
}

func makeNote(_ text: String, at seconds: TimeInterval = 0, id: UUID = UUID()) -> Note {
    Note(id: id, text: text, created: date(seconds), modified: date(seconds))
}
