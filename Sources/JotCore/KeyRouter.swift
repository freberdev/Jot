/// The modifier keys that take part in shortcuts.
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// A key pressed together with modifiers.
///
/// `keyCode` is the hardware key, the same on every keyboard layout. `character` is what that
/// key types on the current layout, so that ⌘Z is the key marked Z whether the keyboard is
/// Swedish, French or German.
public struct KeyPress: Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers
    public var character: String?

    public init(keyCode: UInt16, modifiers: KeyModifiers, character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }
}

/// What the capture window does in response to a key.
public enum KeyCommand: Equatable, Sendable {
    case close
    /// Leave the list and return to the note the user came from.
    case backToWriting
    /// Go to the search field of the list, showing the list if it is hidden.
    case focusSearch
    /// Show or hide the list.
    case toggleSidebar
    case newNote
    case copyAll
    case settings
    case moveUp
    case moveDown
    case openSelected
    case copySelected
    case deleteSelected
    case undoDelete
}

/// Where the keyboard is when a key arrives.
public enum KeyContext: Sendable {
    case writing
    case historySearch
    case historyList
}

/// The capture window's key table. Keys that are not listed go to the text field as usual.
public enum KeyRouter {
    private enum Key {
        static let returnKey: UInt16 = 36
        static let tab: UInt16 = 48
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let enter: UInt16 = 76
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    /// The characters of the shortcut keys on a US keyboard, by key code. Used when the
    /// current layout gives no Latin character for a key.
    public static let usCharacters: [UInt16: String] = [
        1: "s", 3: "f", 6: "z", 8: "c", 12: "q", 13: "w", 43: ",", 45: "n",
    ]

    public static func command(for press: KeyPress, in context: KeyContext) -> KeyCommand? {
        let inHistory = context != .writing
        let inList = context == .historyList

        // Keys without a character are matched by position.
        switch (press.keyCode, press.modifiers) {
        case (Key.escape, []):
            return inHistory ? .backToWriting : .close
        case (Key.down, []):
            return inHistory ? .moveDown : nil
        case (Key.up, []):
            return inList ? .moveUp : nil
        case (Key.returnKey, []), (Key.enter, []):
            return inHistory ? .openSelected : nil
        case (Key.tab, []), (Key.tab, .shift):
            // In the text Tab types a tab. From the list it leads back to the text.
            return inHistory ? .openSelected : nil
        case (Key.delete, .command):
            return inList ? .deleteSelected : nil
        default:
            break
        }

        // Letters are matched by what the key types.
        switch (press.character?.lowercased(), press.modifiers) {
        case ("w", .command), ("q", .command):
            return .close
        case ("f", .command):
            return .focusSearch
        case ("s", [.command, .option]):
            return .toggleSidebar
        case ("n", .command):
            return .newNote
        case (",", .command):
            return .settings
        case ("c", [.command, .shift]):
            return inHistory ? .copySelected : .copyAll
        case ("c", .command):
            return inList ? .copySelected : nil
        case ("z", .command):
            return inList ? .undoDelete : nil
        default:
            return nil
        }
    }

    /// Holding a key down repeats it. Only moving through the list should repeat;
    /// a held ⌘⌫ must not delete one note after another.
    public static func repeatsWhenHeld(_ command: KeyCommand) -> Bool {
        command == .moveUp || command == .moveDown
    }

    /// True for a key that is meant for the search field although the list has focus:
    /// anything typed without Command or Control that is not part of the key table.
    public static func returnsFocusToSearch(_ press: KeyPress, in context: KeyContext) -> Bool {
        guard context == .historyList, command(for: press, in: context) == nil else { return false }
        return press.modifiers.isDisjoint(with: [.command, .control])
    }
}
