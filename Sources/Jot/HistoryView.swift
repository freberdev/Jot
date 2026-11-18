import JotCore
import SwiftUI

/// The list beside the text: a search field and the notes, most recently changed first.
///
/// While the keyboard is in the list the search field holds it the whole time. Whether keys
/// act on the query or on the selected note is decided by `history.focus`, which the panel
/// consults for every key.
struct HistoryView: View {
    let model: AppModel
    @Bindable var history: HistoryModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(L("history.search.placeholder"), text: $history.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .accessibilityLabel(L("history.search.label"))
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            let results = history.results
            if results.isEmpty {
                Text(history.query.isEmpty ? L("history.empty") : L("history.noMatches"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let highlighted = model.browser.highlightedID
                let rowsHaveKeyboard = model.browser.isBrowsing && history.focus == .list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(results) { note in
                                HistoryRow(
                                    note: note,
                                    isHighlighted: note.id == highlighted,
                                    hasKeyboard: rowsHaveKeyboard,
                                    didCopy: note.id == model.copiedNoteID,
                                    model: model)
                                    .id(note.id)
                            }
                        }
                        .padding(5)
                    }
                    .onChange(of: highlighted) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                    .onChange(of: history.query) {
                        // When the search is cleared the list is whole again; keep the current note in view.
                        guard let highlighted else { return }
                        DispatchQueue.main.async { proxy.scrollTo(highlighted) }
                    }
                }
            }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { model.searchDidGetFocus() }
        }
    }
}

private struct HistoryRow: View {
    let note: Note
    let isHighlighted: Bool
    let hasKeyboard: Bool
    let didCopy: Bool
    let model: AppModel
    @State private var isHovered = false

    /// Strong highlight: the keyboard acts on this row. Faint highlight: this is the note in the editor.
    private var isEmphasized: Bool { isHighlighted && hasKeyboard }

    var body: some View {
        let preview = NotePreview.line(for: note.text)
        let time = TimeLabel.string(for: note.modified, now: Date())

        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preview)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(time)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isEmphasized ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered || isEmphasized {
                Button {
                    model.copy(note)
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc").frame(width: 14)
                }
                .help(L("history.row.copy"))
                .accessibilityLabel(L("history.row.copy"))

                Button {
                    model.delete(note)
                } label: {
                    Image(systemName: "trash").frame(width: 14)
                }
                .help(L("history.row.delete"))
                .accessibilityLabel(L("history.row.delete"))
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isEmphasized ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(background, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { model.open(note) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(preview), \(time)")
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.open(note) }
        .accessibilityAction(named: L("history.row.copy")) { model.copy(note) }
        .accessibilityAction(named: L("history.row.delete")) { model.delete(note) }
    }

    private var background: AnyShapeStyle {
        if isEmphasized { return AnyShapeStyle(Color.accentColor) }
        if isHighlighted { return AnyShapeStyle(.primary.opacity(0.1)) }
        if isHovered { return AnyShapeStyle(.primary.opacity(0.05)) }
        return AnyShapeStyle(.clear)
    }
}
