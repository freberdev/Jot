/// The modifier keys that take part in shortcuts.
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// A key pressed together with modifiers. `keyCode` is the hardware key, independent of layout.
public struct KeyPress: Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// What the capture window does in response to a key.
public enum KeyCommand: Equatable, Sendable {
    case close
    case showHistory
    case backToWriting
    case focusSearch
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
        static let z: UInt16 = 6
        static let c: UInt16 = 8
        static let f: UInt16 = 3
        static let q: UInt16 = 12
        static let w: UInt16 = 13
        static let returnKey: UInt16 = 36
        static let comma: UInt16 = 43
        static let n: UInt16 = 45
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let enter: UInt16 = 76
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    public static func command(for press: KeyPress, in context: KeyContext) -> KeyCommand? {
        let inHistory = context != .writing
        let inList = context == .historyList

        switch (press.keyCode, press.modifiers) {
        case (Key.escape, []):
            return inHistory ? .backToWriting : .close
        case (Key.w, .command), (Key.q, .command):
            return .close
        case (Key.f, .command):
            return inHistory ? .focusSearch : .showHistory
        case (Key.n, .command):
            return .newNote
        case (Key.comma, .command):
            return .settings
        case (Key.c, [.command, .shift]):
            return inHistory ? .copySelected : .copyAll
        case (Key.c, .command):
            return inList ? .copySelected : nil
        case (Key.down, []):
            return inHistory ? .moveDown : nil
        case (Key.up, []):
            return inList ? .moveUp : nil
        case (Key.returnKey, []), (Key.enter, []):
            return inHistory ? .openSelected : nil
        case (Key.delete, .command):
            return inList ? .deleteSelected : nil
        case (Key.z, .command):
            return inList ? .undoDelete : nil
        default:
            return nil
        }
    }

    /// True for a key that is meant for the search field although the list has focus:
    /// anything typed without Command or Control that is not part of the key table.
    public static func returnsFocusToSearch(_ press: KeyPress, in context: KeyContext) -> Bool {
        guard context == .historyList, command(for: press, in: context) == nil else { return false }
        return press.modifiers.isDisjoint(with: [.command, .control])
    }
}
