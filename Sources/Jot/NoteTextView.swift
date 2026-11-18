import AppKit
import JotCore
import SwiftUI

/// The writing surface: a plain-text `NSTextView`.
///
/// SwiftUI's `TextEditor` hands the whole text back and forth on every key press, which makes
/// typing lag once a note grows large. Here the text view owns the text while the user types,
/// and is only reloaded when the editor replaces the text from outside.
struct NoteTextView: NSViewRepresentable {
    let editor: Editor
    /// Called when the text view takes the keyboard.
    let onFocus: () -> Void

    static let font = NSFont.systemFont(ofSize: 15)

    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // The panel's title bar is hidden; do not leave room for it above the text.
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = FocusReportingTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.onFocus = onFocus
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        // Notes often hold commands and code. Keep "--" and straight quotes exactly as typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: Self.font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        textView.setAccessibilityLabel(L("capture.editor.label"))

        context.coordinator.load(into: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              context.coordinator.loadedRevision != editor.contentRevision
        else { return }
        context.coordinator.load(into: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let editor: Editor
        private(set) var loadedRevision = -1

        init(editor: Editor) {
            self.editor = editor
        }

        /// Shows the editor's text, with the insertion point at the end and a clean undo history,
        /// so that undo can never bring back the text of another note.
        func load(into textView: NSTextView) {
            loadedRevision = editor.contentRevision
            textView.string = editor.text
            textView.undoManager?.removeAllActions()
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        }

        /// The editor may have switched to another note since the view was last loaded, with
        /// SwiftUI's update still to come. Typing must never put one note's text into another,
        /// so in that case the view is brought up to date first and the key press is dropped.
        func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?
        ) -> Bool {
            guard loadedRevision != editor.contentRevision else { return true }
            load(into: textView)
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  loadedRevision == editor.contentRevision
            else { return }
            editor.text = textView.string
        }
    }
}

/// A text view that says when it becomes the place the keyboard goes.
private final class FocusReportingTextView: NSTextView {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?() }
        return became
    }
}
