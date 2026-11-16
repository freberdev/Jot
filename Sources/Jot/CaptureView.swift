import JotCore
import SwiftUI

/// The content of the capture panel.
struct CaptureRootView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            // The editor stays alive behind the history, so the insertion point and scroll
            // position are where they were when the user comes back.
            CaptureView(model: model, editor: model.editor)
                .opacity(model.mode == .write ? 1 : 0)
                .allowsHitTesting(model.mode == .write)
                .accessibilityHidden(model.mode != .write)

            if model.mode == .history {
                HistoryView(model: model, history: model.history)
            }
        }
        .ignoresSafeArea()
    }
}

/// Writing mode: all text, and one quiet line of status and controls underneath.
struct CaptureView: View {
    let model: AppModel
    @Bindable var editor: Editor
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $editor.text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .accessibilityLabel(L("capture.editor.label"))
                    // A fresh text view per note, so undo can never bring back another note's text.
                    .id(editor.noteID)

                if editor.text.isEmpty {
                    Text(model.showsWelcome
                        ? L("capture.placeholder.welcome", model.shortcutDisplay)
                        : L("capture.placeholder"))
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 16)

            footer
        }
        .onAppear { editorFocused = true }
        .onChange(of: editor.noteID) { editorFocused = true }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(status)
                .font(.caption)
                .foregroundStyle(editor.saveFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))

            Spacer()

            Button {
                model.showHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help(L("capture.history.help"))
            .accessibilityLabel(L("capture.history.label"))

            Button {
                model.copyAll()
            } label: {
                Image(systemName: model.didCopy ? "checkmark" : "doc.on.doc")
                    .frame(width: 16)
            }
            .help(L("capture.copy.help"))
            .accessibilityLabel(L("capture.copy.label"))
            .disabled(editor.text.isEmpty)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var status: String {
        if editor.saveFailed { return L("capture.status.saveFailed") }
        if model.isContinuing, let note = editor.savedNote {
            return TimeLabel.string(for: note.modified, now: Date())
        }
        return L("capture.status.new")
    }
}
