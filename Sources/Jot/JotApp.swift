import SwiftUI

@main
struct JotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Jot", systemImage: "note.text") {
            Button(L("menu.new")) { delegate.model.newNote() }
            Divider()
            Button(L("menu.quit")) { NSApplication.shared.terminate(nil) }
        }
    }
}
