import JotCore
import SwiftUI

@main
struct JotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Jot", systemImage: "note.text") {
            MenuContent(model: delegate.model)
        }
    }
}

private struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Button(L("menu.new", model.shortcutDisplay)) { model.newNote() }
        Button(L("menu.search")) { model.searchNotes() }
        Divider()
        Button(L("menu.settings")) { model.openSettings() }
        Divider()
        Button(L("menu.quit")) { NSApplication.shared.terminate(nil) }
    }
}
