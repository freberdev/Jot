import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Notes often hold commands and code. Keep "--" and straight quotes exactly as typed.
        // Set as app preferences, because the user's system-wide setting outranks registered defaults.
        UserDefaults.standard.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")

        // "-appearance dark" or "-appearance light" on the command line overrides the system, for development.
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }

        model.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
    }

    /// Opening Jot again while it is running, from Spotlight or Finder, shows the capture window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        model.newNote()
        return false
    }

    /// Quitting must never silently throw away text. If the note cannot be written to disk,
    /// the user decides whether to quit anyway.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.saveNow()
        guard model.editor.saveFailed else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("quit.unsaved.title")
        alert.informativeText = L("quit.unsaved.message")
        alert.addButton(withTitle: L("quit.unsaved.stay"))
        alert.addButton(withTitle: L("quit.unsaved.quit"))
        NSApp.activateInsistently()
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }

    @objc private func willSleep(_ notification: Notification) {
        model.saveNow()
    }
}
