import AppKit
import JotCore
import Observation
import SwiftUI

/// Ties the notes, the editor, the capture panel and the global shortcut together.
@MainActor @Observable
final class AppModel {
    /// Whether the list of notes is showing beside the text.
    private(set) var isSidebarVisible = true
    /// True for a moment after the note has been copied, so the button can confirm it.
    private(set) var didCopy = false
    /// The id of the note whose copy was just confirmed in the list.
    private(set) var copiedNoteID: UUID?
    /// Whether the list is shown each time the window opens.
    var showsListOnOpen: Bool {
        didSet { preferences.showsListOnOpen = showsListOnOpen }
    }

    /// The global shortcut that opens Jot.
    private(set) var shortcut: Shortcut
    /// Something the user should know about the shortcut they just chose, or nil.
    var shortcutMessage: String?
    /// True until the capture window has been closed for the first time after the first launch.
    private(set) var showsWelcome = false
    /// True while the settings window is waiting for the user to press a new shortcut.
    private(set) var isRecordingShortcut = false

    let store: NoteStore
    let editor: Editor
    let history: HistoryModel
    let browser: NoteBrowser

    @ObservationIgnored private let preferences = Preferences()
    @ObservationIgnored private var settingsWindow: SettingsWindowController?
    @ObservationIgnored private var shortcutMonitor: Any?

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
        browser = NoteBrowser(store: store, editor: editor, history: history)
        shortcut = preferences.shortcut
        showsListOnOpen = preferences.showsListOnOpen
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

        let settings = SettingsWindowController { [unowned self] in SettingsView(model: self) }
        settings.onInactive = { [weak self] in self?.stopRecordingShortcut() }
        settingsWindow = settings

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
            openPanel()
        } else if panel.hasFocus {
            closePanel()
        } else {
            panel.show(focusing: browser.isBrowsing ? .search : .editor, sidebarVisible: isSidebarVisible)
        }
    }

    /// Shows the window with a new empty note and the list as the user prefers it.
    private func openPanel() {
        isSidebarVisible = showsListOnOpen
        browser.openSession()
        panel?.show(focusing: .editor, sidebarVisible: isSidebarVisible)
    }

    func newNote() {
        guard let panel, panel.isVisible else {
            openPanel()
            return
        }
        browser.startNew()
        panel.show(focusing: .editor, sidebarVisible: isSidebarVisible)
    }

    func closePanel() {
        editor.leave()
        if editor.saveFailed {
            // The window holds the only copy of the text. Keep it, and its warning, on screen.
            NSSound.beep()
            return
        }
        panel?.hide()
        browser.closeSession()
        showsWelcome = false
    }

    // MARK: The list

    /// Shows the window if needed and puts the keyboard in the list's search field.
    func searchNotes() {
        if panel?.isVisible != true { openPanel() }
        focusSearch()
    }

    private func focusSearch() {
        guard browser.enterSearch() else {
            NSSound.beep()
            return
        }
        setSidebar(visible: true)
        panel?.focus(.search)
    }

    func toggleSidebar() {
        if isSidebarVisible, browser.isBrowsing {
            browser.stay()
            panel?.focus(.editor)
        }
        setSidebar(visible: !isSidebarVisible)
    }

    private func setSidebar(visible: Bool) {
        guard visible != isSidebarVisible else { return }
        isSidebarVisible = visible
        panel?.setSidebarVisible(visible)
    }

    /// A click on a row.
    func open(_ note: Note) {
        browser.open(note)
        panel?.focus(.editor)
    }

    func delete(_ note: Note) {
        do { try browser.delete(note) } catch { NSSound.beep() }
    }

    /// The text view took the keyboard, for example through a click.
    func editorDidGetFocus() {
        if browser.isBrowsing { browser.stay() }
    }

    /// The search field took the keyboard, for example through a click.
    func searchDidGetFocus() {
        guard !browser.isBrowsing else { return }
        if !browser.enterSearch() {
            NSSound.beep()
            panel?.focus(.editor)
        }
    }

    // MARK: Settings

    func openSettings() {
        closePanel()
        guard !editor.saveFailed else { return }
        settingsWindow?.show()
    }

    /// The shortcut as the user sees it, for example "⇧⌘J".
    var shortcutDisplay: String {
        shortcut.modifierSymbols + KeyNames.name(for: shortcut.keyCode)
    }

    private func resumeHotKey() {
        hotKey.register(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers)
    }

    /// Waits for the next key combination and makes it the shortcut. Escape cancels.
    func startRecordingShortcut() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutMessage = nil
        // The current shortcut must not fire while the user is choosing a new one.
        hotKey.unregister()
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.recordShortcut(from: event)
            return nil
        }
    }

    /// Ends recording and puts the shortcut back in force. Also called when the settings
    /// window closes or loses focus, so the shortcut can never be left switched off.
    func stopRecordingShortcut() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        resumeHotKey()
    }

    private func recordShortcut(from event: NSEvent) {
        let modifiers = KeyModifiers(event.modifierFlags)
        if event.keyCode == 53, modifiers.isEmpty {
            stopRecordingShortcut()
            return
        }
        let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard candidate.isValid else {
            shortcutMessage = L("settings.shortcut.needsModifier")
            return
        }
        stopRecordingShortcut()
        setShortcut(candidate)
    }

    /// Switches to a new shortcut. If the system refuses it, the previous one stays.
    private func setShortcut(_ new: Shortcut) {
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
            history.reset()
            browser.startNew()
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
        guard browser.isBrowsing else { return .writing }
        return history.focus == .search ? .historySearch : .historyList
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // Let an input method finish composing before any key is taken away from it.
        if let textView = panel?.panel.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }
        let press = JotCore.KeyPress(event)
        guard let command = KeyRouter.command(for: press, in: keyContext) else {
            // Typing while the list has focus continues the search.
            if KeyRouter.returnsFocusToSearch(press, in: keyContext) { history.focus = .search }
            return false
        }
        // A held key is swallowed rather than repeated, except for moving through the list.
        if !event.isARepeat || KeyRouter.repeatsWhenHeld(command) {
            perform(command)
        }
        return true
    }

    func perform(_ command: KeyCommand) {
        switch command {
        case .close: closePanel()
        case .newNote: newNote()
        case .copyAll: copyAll()
        case .settings: openSettings()
        case .focusSearch: focusSearch()
        case .toggleSidebar: toggleSidebar()
        case .moveUp: browser.move(by: -1)
        case .moveDown: browser.move(by: 1)
        case .copySelected: if let note = history.selected { copy(note) }
        case .backToWriting:
            browser.cancel()
            panel?.focus(.editor)
        case .openSelected:
            browser.commit()
            panel?.focus(.editor)
        case .deleteSelected:
            do { try browser.deleteSelected() } catch { NSSound.beep() }
        case .undoDelete:
            do { try browser.undoDelete() } catch { NSSound.beep() }
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

extension JotCore.KeyPress {
    /// The key and modifiers of an event, with the character the key types on the current layout.
    init(_ event: NSEvent) {
        // With Command held, most non-Latin layouts report a Latin character in `characters`.
        // Control and Option change `characters` to something else, so the unmodified one is tried too.
        let candidates = [event.characters, event.charactersIgnoringModifiers]
        let character = candidates.compactMap { $0 }.first { text in
            text.unicodeScalars.count == 1 && text.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
        }
        self.init(
            keyCode: event.keyCode,
            modifiers: KeyModifiers(event.modifierFlags),
            character: character ?? KeyRouter.usCharacters[event.keyCode])
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
