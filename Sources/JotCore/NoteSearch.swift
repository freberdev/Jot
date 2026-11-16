import Foundation

/// Text search over notes.
public enum NoteSearch {
    /// The notes that contain every word of `query`, in their original order.
    /// Case and accents are ignored the way `locale` expects. An empty query matches everything.
    public static func filter(_ notes: [Note], query: String, locale: Locale = .current) -> [Note] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return notes }
        return notes.filter { note in
            words.allSatisfy { word in
                note.text.range(
                    of: word, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
            }
        }
    }
}
