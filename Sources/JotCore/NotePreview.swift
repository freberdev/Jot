/// A one-line summary of a note, used in the history list instead of a title.
public enum NotePreview {
    /// The first line that has any text in it, with surrounding whitespace removed and
    /// runs of whitespace collapsed, shortened to `limit` characters.
    public static func line(for text: String, limit: Int = 120) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        let words = firstLine.split(whereSeparator: \.isWhitespace)
        let line = words.joined(separator: " ")
        guard line.count > limit else { return line }
        return line.prefix(max(limit - 1, 0)) + "…"
    }
}
