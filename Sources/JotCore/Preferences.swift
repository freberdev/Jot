import Foundation

/// The app's few stored settings.
public struct Preferences {
    private enum Key {
        static let shortcut = "shortcut"
        static let didAutoEnableLoginItem = "didAutoEnableLoginItem"
        static let hasShownWelcome = "hasShownWelcome"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The shortcut that opens Jot. Falls back to the default if nothing usable is stored.
    public var shortcut: Shortcut {
        get {
            guard let data = defaults.data(forKey: Key.shortcut),
                  let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
                  shortcut.isValid
            else { return .default }
            return shortcut
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.shortcut)
        }
    }

    /// Set once Jot has turned on "open at login" by itself, so it never does so a second time.
    public var didAutoEnableLoginItem: Bool {
        get { defaults.bool(forKey: Key.didAutoEnableLoginItem) }
        nonmutating set { defaults.set(newValue, forKey: Key.didAutoEnableLoginItem) }
    }

    /// Set once the capture window has introduced itself on first launch.
    public var hasShownWelcome: Bool {
        get { defaults.bool(forKey: Key.hasShownWelcome) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasShownWelcome) }
    }
}
