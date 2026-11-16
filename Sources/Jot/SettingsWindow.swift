import AppKit
import SwiftUI

/// The settings window. Jot has no Dock icon, so the window is created and brought forward by hand;
/// SwiftUI's own Settings scene tends to open behind other apps in that situation.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeContent: () -> AnyView

    init(content: @escaping () -> some View) {
        makeContent = { AnyView(content()) }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
            window.title = L("settings.title")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Jot is not the active app when this is called from the capture panel or the menu bar.
        // The cooperative `activate()` is ignored in that situation and leaves the window
        // inactive behind the current app, so the older, insistent call is used.
        (NSApp as InsistentActivation).activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Reaches `activate(ignoringOtherApps:)` without a deprecation warning at the call site.
@MainActor
private protocol InsistentActivation {
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: InsistentActivation {}
