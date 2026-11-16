import AppKit
import JotCore
import SwiftUI

/// Shows the current shortcut. Click it, then press the new combination.
struct ShortcutRecorder: View {
    let model: AppModel
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? L("settings.shortcut.recording") : model.shortcutDisplay)
                .frame(minWidth: 130)
        }
        .accessibilityLabel(L("settings.shortcut.change"))
        .accessibilityValue(model.shortcutDisplay)
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        model.shortcutMessage = nil
        // The current shortcut must not fire while the user is choosing a new one.
        model.suspendHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        model.resumeHotKey()
    }

    private func handle(_ event: NSEvent) {
        let modifiers = KeyModifiers(event.modifierFlags)
        if event.keyCode == 53, modifiers.isEmpty {
            stop()
            return
        }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard shortcut.isValid else {
            model.shortcutMessage = L("settings.shortcut.needsModifier")
            return
        }
        stop()
        model.setShortcut(shortcut)
    }
}
