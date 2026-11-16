import Foundation

/// Reads and writes notes as one JSON file each, named `<id>.json`, in a single directory.
///
/// Anything else in the directory is ignored and never touched.
public struct NoteFiles: Sendable {
    public static let formatVersion = 1

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Jot/Notes`
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jot", isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
    }

    /// Every readable note in the directory, in no particular order.
    /// Files that are not notes, are damaged, or come from a newer version are skipped.
    public func loadAll() -> [Note] {
        noteFileURLs().compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let stored = try? Self.decoder.decode(StoredNote.self, from: data),
                  stored.version <= Self.formatVersion
            else { return nil }
            return Note(id: stored.id, text: stored.text, created: stored.created, modified: stored.modified)
        }
    }

    /// Writes the note so that a crash can never leave a half-written file behind:
    /// the data goes to a temporary file that then replaces the old one in a single step.
    public func write(_ note: Note) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }

        let stored = StoredNote(
            version: Self.formatVersion, id: note.id, text: note.text,
            created: note.created, modified: note.modified)
        let data = try Self.encoder.encode(stored)

        let destination = url(for: note.id)
        let temporary = directory.appendingPathComponent(".\(note.id.uuidString).json.tmp")
        try? fileManager.removeItem(at: temporary)
        guard fileManager.createFile(
            atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        guard rename(temporary.path, destination.path) == 0 else {
            let code = errno
            try? fileManager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// Removes the note's file. Deleting a note that is already gone is not an error.
    public func delete(id: UUID) throws {
        do {
            try FileManager.default.removeItem(at: url(for: id))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already gone.
        }
    }

    /// Removes every note file and nothing else.
    public func deleteAll() throws {
        for url in noteFileURLs() {
            try FileManager.default.removeItem(at: url)
        }
    }

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func noteFileURLs() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { url in
            url.pathExtension == "json" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
        }
    }

    private struct StoredNote: Codable {
        var version: Int
        var id: UUID
        var text: String
        var created: Date
        var modified: Date
    }

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = try? dateStyle.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Not an ISO 8601 date: \(string)")
            }
            return date
        }
        return decoder
    }()
}
