import Foundation

/// A single note. Notes have no title; the first line of the text serves as the preview.
public struct Note: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public let created: Date
    public var modified: Date

    public init(id: UUID = UUID(), text: String, created: Date, modified: Date) {
        self.id = id
        self.text = text
        self.created = created
        self.modified = modified
    }
}
