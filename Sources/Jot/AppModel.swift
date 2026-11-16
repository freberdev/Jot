import AppKit
import JotCore
import Observation
import SwiftUI

/// Ties the notes, the editor, the capture panel and the global shortcut together.
@MainActor @Observable
final class AppModel {
    enum Mode { case write, history }

    private(set) var mode: Mode = .write
    /// True for a moment after the note has been copied, so the button can confirm it.
    private(set) var didCopy = false

    let store: NoteStore
    let editor: Editor

    @ObservationIgnored private var panel: CapturePanelController?
    @ObservationIgnored private let hotKey = HotKey()
    @ObservationIgnored private var copyResetTask: Task<Void, Never>?

    init() {
        // "-notesDirectory <path>" on the command line points Jot at another folder, for development.
        let directory = UserDefaults.standard.string(forKey: "notesDirectory")
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? NoteFiles.defaultDirectory
        store = NoteStore(files: NoteFiles(directory: directory))
        editor = Editor(store: store, debouncer: TimerDebouncer())
    }

    /// Called once the app has launched: builds the panel and claims the shortcut.
    func start() {
        store.load()

        let controller = CapturePanelController(rootView: CaptureRootView(model: self)) { [weak self] event in
            self?.handleKey(event) ?? false
        }
        controller.onResignKey = { [weak self] in self?.editor.flush() }
        panel = controller

        hotKey.onPressed = { [weak self] in self?.hotKeyPressed() }
        hotKey.register(keyCode: 38 /* J */, carbonModifiers: 0x0100 | 0x0200 /* ⌘⇧ */)
    }

    // MARK: Opening and closing

    /// Closed: open with a new note. Open with focus: close. Open without focus: take focus back.
    func hotKeyPressed() {
        guard let panel else { return }
        if !panel.isVisible {
            newNote()
        } else if panel.hasFocus {
            closePanel()
        } else {
            panel.show(focusing: mode == .write ? .editor : .search)
        }
    }

    func newNote() {
        editor.startNew()
        mode = .write
        panel?.show(focusing: .editor)
    }

    func closePanel() {
        editor.leave()
        panel?.hide()
    }

    /// Saves whatever is being written. Called when the app quits or the Mac goes to sleep.
    func saveNow() {
        if panel?.isVisible == true {
            editor.flush()
        } else {
            editor.leave()
        }
    }

    // MARK: Keys

    private var keyContext: KeyContext { .writing }

    private func handleKey(_ event: NSEvent) -> Bool {
        // Let an input method finish composing before any key is taken away from it.
        if let textView = panel?.panel.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }
        let press = KeyPress(keyCode: event.keyCode, modifiers: KeyModifiers(event.modifierFlags))
        guard let command = KeyRouter.command(for: press, in: keyContext) else { return false }
        perform(command)
        return true
    }

    func perform(_ command: KeyCommand) {
        switch command {
        case .close: closePanel()
        case .newNote: newNote()
        case .copyAll: copyAll()
        default: break
        }
    }

    // MARK: Copying

    func copyAll() {
        guard !editor.text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editor.text, forType: .string)
        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}
