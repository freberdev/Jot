import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Notes often hold commands and code. Keep "--" and straight quotes exactly as typed.
        // Set as app preferences, because the user's system-wide setting outranks registered defaults.
        UserDefaults.standard.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")

        model.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveNow()
    }

    @objc private func willSleep(_ notification: Notification) {
        model.saveNow()
    }
}
