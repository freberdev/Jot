import JotCore
import SwiftUI

/// History mode: a search field and the notes, most recently changed first.
///
/// The search field keeps the keyboard the whole time. Whether keys act on the query or on
/// the selected note is decided by `history.focus`, which the panel consults for every key.
struct HistoryView: View {
    let model: AppModel
    @Bindable var history: HistoryModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(L("history.search.placeholder"), text: $history.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .accessibilityLabel(L("history.search.label"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 11)

            Divider()

            let results = history.results
            if results.isEmpty {
                Text(history.query.isEmpty ? L("history.empty") : L("history.noMatches"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(results) { note in
                                HistoryRow(
                                    note: note,
                                    isSelected: note.id == history.selectedID,
                                    listHasFocus: history.focus == .list,
                                    didCopy: note.id == model.copiedNoteID,
                                    model: model)
                                    .id(note.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: history.selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .onAppear { searchFocused = true }
    }
}

private struct HistoryRow: View {
    let note: Note
    let isSelected: Bool
    let listHasFocus: Bool
    let didCopy: Bool
    let model: AppModel
    @State private var isHovered = false

    private var isEmphasized: Bool { isSelected && listHasFocus }

    var body: some View {
        HStack(spacing: 10) {
            Text(NotePreview.line(for: note.text))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected || isHovered {
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

            Text(TimeLabel.string(for: note.modified, now: Date()))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(isEmphasized ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isEmphasized ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.open(note) })
        .simultaneousGesture(TapGesture().onEnded { model.history.select(note.id) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NotePreview.line(for: note.text)), \(TimeLabel.string(for: note.modified, now: Date()))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.open(note) }
        .accessibilityAction(named: L("history.row.copy")) { model.copy(note) }
        .accessibilityAction(named: L("history.row.delete")) { model.delete(note) }
    }

    private var background: AnyShapeStyle {
        if isEmphasized { return AnyShapeStyle(Color.accentColor) }
        if isSelected { return AnyShapeStyle(.primary.opacity(0.1)) }
        if isHovered { return AnyShapeStyle(.primary.opacity(0.05)) }
        return AnyShapeStyle(.clear)
    }
}
