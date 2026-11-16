import JotCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginItemFailed = false
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                LabeledContent(L("settings.shortcut.label")) {
                    ShortcutRecorder(model: model)
                }
                Text(model.shortcutMessage ?? L("settings.shortcut.hint"))
                    .font(.callout)
                    .foregroundStyle(model.shortcutMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle(L("settings.login.label"), isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        guard enabled != LoginItem.isEnabled else { return }
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginItemFailed = false
                        } catch {
                            loginItemFailed = true
                            opensAtLogin = LoginItem.isEnabled
                        }
                    }
                if loginItemFailed {
                    Text(L("settings.login.failed"))
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section(L("settings.storage.title")) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.notesFolderDisplay)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .accessibilityLabel(L("settings.storage.folder"))
                        .accessibilityValue(model.notesFolderDisplay)
                    Spacer()
                    Button(L("settings.storage.reveal")) { model.revealNotesFolder() }
                }
                Text(L("settings.storage.privacy"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(L("settings.clear.button"), role: .destructive) {
                    isConfirmingClear = true
                }
                .disabled(model.store.notes.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            L("settings.clear.title"), isPresented: $isConfirmingClear
        ) {
            Button(L("settings.clear.confirm"), role: .destructive) { model.clearHistory() }
            Button(L("settings.clear.cancel"), role: .cancel) {}
        } message: {
            Text(L("settings.clear.message", model.store.notes.count))
        }
    }
}
