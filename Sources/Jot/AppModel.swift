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

    /// The id of the note whose copy was just confirmed in the history list.
    private(set) var copiedNoteID: UUID?
    /// True while an earlier note is being continued, false for a note started in this session.
    private(set) var isContinuing = false

    /// The global shortcut that opens Jot.
    private(set) var shortcut: Shortcut
    /// Something the user should know about the shortcut they just chose, or nil.
    var shortcutMessage: String?
    /// True until the capture window has been closed for the first time after the first launch.
    private(set) var showsWelcome = false

    let store: NoteStore
    let editor: Editor
    let history: HistoryModel

    @ObservationIgnored private let preferences = Preferences()
    @ObservationIgnored private var settingsWindow: SettingsWindowController?

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
        history = HistoryModel(store: store)
        shortcut = preferences.shortcut
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
        resumeHotKey()

        settingsWindow = SettingsWindowController { [unowned self] in SettingsView(model: self) }

        enableLoginItemOnce()
        if !preferences.hasShownWelcome {
            preferences.hasShownWelcome = true
            showsWelcome = true
            newNote()
        }
    }

    /// Jot is of little use if the shortcut stops working after a restart, so "open at login"
    /// is turned on the first time Jot runs from the Applications folder. Only ever once:
    /// after that the choice belongs to the user.
    private func enableLoginItemOnce() {
        guard LoginItem.isInstalled, !preferences.didAutoEnableLoginItem else { return }
        preferences.didAutoEnableLoginItem = true
        try? LoginItem.setEnabled(true)
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
        isContinuing = editor.savedNote != nil
        mode = .write
        panel?.show(focusing: .editor)
    }

    // MARK: History

    func showHistory() {
        editor.flush()
        history.reset()
        mode = .history
        panel?.show(focusing: .search)
    }

    func backToWriting() {
        mode = .write
        panel?.focus(.editor)
    }

    func open(_ note: Note) {
        editor.open(note)
        // A note that could not be saved stays in the editor; then there is nothing to switch to.
        if editor.noteID == note.id { isContinuing = true }
        backToWriting()
    }

    func delete(_ note: Note) {
        history.select(note.id)
        deleteSelected()
    }

    private func deleteSelected() {
        guard let id = history.selected?.id else { return }
        do {
            try history.deleteSelected()
            editor.forget(id: id)
            if editor.savedNote == nil { isContinuing = false }
        } catch {
            NSSound.beep()
        }
    }

    private func undoDelete() {
        do { try history.undoDelete() } catch { NSSound.beep() }
    }

    func closePanel() {
        editor.leave()
        panel?.hide()
        showsWelcome = false
    }

    // MARK: Settings

    func openSettings() {
        closePanel()
        settingsWindow?.show()
    }

    /// The shortcut as the user sees it, for example "⇧⌘J".
    var shortcutDisplay: String {
        shortcut.modifierSymbols + KeyNames.name(for: shortcut.keyCode)
    }

    func suspendHotKey() {
        hotKey.unregister()
    }

    func resumeHotKey() {
        hotKey.register(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers)
    }

    /// Switches to a new shortcut. If the system refuses it, the previous one stays.
    func setShortcut(_ new: Shortcut) {
        if hotKey.register(keyCode: new.keyCode, carbonModifiers: new.carbonModifiers) {
            shortcut = new
            preferences.shortcut = new
            shortcutMessage = nil
        } else {
            resumeHotKey()
            shortcutMessage = L("settings.shortcut.refused")
        }
    }

    var notesFolderDisplay: String {
        (store.directory.path as NSString).abbreviatingWithTildeInPath
    }

    func revealNotesFolder() {
        try? FileManager.default.createDirectory(
            at: store.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(store.directory)
    }

    func clearHistory() {
        do {
            try store.deleteAll()
            editor.forget(id: editor.noteID)
            isContinuing = false
            history.reset()
        } catch {
            NSSound.beep()
        }
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

    private var keyContext: KeyContext {
        switch (mode, history.focus) {
        case (.write, _): .writing
        case (.history, .search): .historySearch
        case (.history, .list): .historyList
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // Let an input method finish composing before any key is taken away from it.
        if let textView = panel?.panel.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }
        let press = KeyPress(keyCode: event.keyCode, modifiers: KeyModifiers(event.modifierFlags))
        guard let command = KeyRouter.command(for: press, in: keyContext) else {
            // Typing while the list has focus continues the search.
            if KeyRouter.returnsFocusToSearch(press, in: keyContext) { history.focus = .search }
            return false
        }
        perform(command)
        return true
    }

    func perform(_ command: KeyCommand) {
        switch command {
        case .close: closePanel()
        case .newNote: newNote()
        case .copyAll: copyAll()
        case .showHistory: showHistory()
        case .backToWriting: backToWriting()
        case .focusSearch: history.focus = .search
        case .moveUp: history.moveSelection(by: -1)
        case .moveDown: history.moveSelection(by: 1)
        case .openSelected: if let note = history.selected { open(note) }
        case .copySelected: if let note = history.selected { copy(note) }
        case .deleteSelected: deleteSelected()
        case .undoDelete: undoDelete()
        case .settings: openSettings()
        }
    }

    // MARK: Copying

    func copyAll() {
        guard !editor.text.isEmpty else { return }
        putOnPasteboard(editor.text)
        didCopy = true
        scheduleCopyReset()
    }

    func copy(_ note: Note) {
        putOnPasteboard(note.text)
        copiedNoteID = note.id
        scheduleCopyReset()
    }

    private func putOnPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func scheduleCopyReset() {
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.didCopy = false
            self?.copiedNoteID = nil
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
