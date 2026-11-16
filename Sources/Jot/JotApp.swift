import SwiftUI

@main
struct JotApp: App {
    var body: some Scene {
        MenuBarExtra("Jot", systemImage: "note.text") {
            Button("Quit Jot") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
