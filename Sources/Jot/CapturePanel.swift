import AppKit
import SwiftUI

/// The floating capture window. It takes keyboard input without making Jot the active app,
/// so the app the user came from stays in front and gets focus back when the panel closes.
final class CapturePanel: NSPanel {
    /// Sees every key press first. Returns true when the key has been dealt with.
    var keyHandler: (@MainActor (NSEvent) -> Bool)?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: CapturePanelController.defaultSize),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Command shortcuts arrive here before they reach the menu bar…
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    // …and every other key arrives here before it reaches the text field.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Creates the panel once and shows, hides, places and focuses it.
@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    enum FocusTarget { case editor, search }

    static let defaultSize = NSSize(width: 480, height: 300)
    /// The width of the list of notes.
    static let listWidth: CGFloat = 220
    /// The list together with the line that separates it from the text.
    private static let sidebarExtent: CGFloat = listWidth + 1
    private static let minimumSize = NSSize(width: 360, height: 200)
    /// The stored frame is that of the window without the list, so that showing or hiding
    /// the list never changes the size of the writing area.
    private static let frameKey = "capturePanelFrame"

    let panel = CapturePanel()
    var onResignKey: (() -> Void)?

    private let defaults: UserDefaults
    private var isPlacing = false
    private var sidebarVisible = false
    private var focusRequest = 0

    init(rootView: some View, defaults: UserDefaults = .standard, keyHandler: @escaping @MainActor (NSEvent) -> Bool) {
        self.defaults = defaults
        super.init()

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)

        panel.contentView = background
        panel.keyHandler = keyHandler
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }
    var hasFocus: Bool { panel.isVisible && panel.isKeyWindow }

    func show(focusing target: FocusTarget, sidebarVisible: Bool) {
        if !panel.isVisible {
            self.sidebarVisible = sidebarVisible
            place()
        }
        panel.makeKeyAndOrderFront(nil)
        focus(target)
    }

    /// Makes room for the list to the right of the text, or takes that room away again.
    func setSidebarVisible(_ visible: Bool) {
        guard visible != sidebarVisible else { return }
        sidebarVisible = visible
        guard panel.isVisible else { return }
        isPlacing = true
        defer { isPlacing = false }
        var frame = panel.frame
        frame.size.width += visible ? Self.sidebarExtent : -Self.sidebarExtent
        apply(frame)
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Puts the insertion point in the text field. SwiftUI's own focus handling is not
    /// dependable the first time a view appears in a panel, so this goes straight to AppKit:
    /// now, and again once SwiftUI has had a chance to build a view that was just added.
    func focus(_ target: FocusTarget) {
        focusRequest += 1
        let request = focusRequest
        applyFocus(target)
        for delay in [0, 0.05, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.focusRequest == request else { return }
                self.applyFocus(target)
            }
        }
    }

    private func applyFocus(_ target: FocusTarget) {
        guard panel.isVisible, let root = panel.contentView else { return }
        let responder: NSView? = switch target {
        case .editor: root.firstDescendant { ($0 as? NSTextView).map { $0.isEditable && !$0.isFieldEditor } ?? false }
        case .search: root.firstDescendant { ($0 as? NSTextField)?.isEditable ?? false }
        }
        guard let responder else { return }
        if panel.firstResponder !== responder, !isEditing(responder) {
            panel.makeFirstResponder(responder)
        }
    }

    /// A text field is being edited when its field editor is first responder.
    private func isEditing(_ view: NSView) -> Bool {
        guard let field = view as? NSTextField else { return false }
        return field.currentEditor() != nil
    }

    // MARK: Placement

    /// Where the user last left the panel, or the upper middle of the screen with the pointer.
    private func place() {
        isPlacing = true
        defer { isPlacing = false }
        var frame = savedFrame() ?? defaultFrame()
        if sidebarVisible { frame.size.width += Self.sidebarExtent }
        apply(frame)
    }

    private func savedFrame() -> NSRect? {
        guard let saved = defaults.string(forKey: Self.frameKey) else { return nil }
        let frame = NSRectFromString(saved)
        guard frame.width >= Self.minimumSize.width, frame.height >= Self.minimumSize.height,
              NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) })
        else { return nil }
        return frame
    }

    private func defaultFrame() -> NSRect {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.defaultSize
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - visible.height * 0.18,
            width: size.width, height: size.height)
    }

    /// Sets the frame, moved left if needed so the right edge stays on its screen.
    private func apply(_ proposed: NSRect) {
        var frame = proposed
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        if let visible = screen?.visibleFrame, frame.maxX > visible.maxX {
            frame.origin.x = max(visible.minX, visible.maxX - frame.width)
        }
        panel.minSize = NSSize(
            width: Self.minimumSize.width + (sidebarVisible ? Self.sidebarExtent : 0),
            height: Self.minimumSize.height)
        panel.setFrame(frame, display: panel.isVisible)
    }

    private func rememberFrame() {
        guard !isPlacing, panel.isVisible else { return }
        var frame = panel.frame
        if sidebarVisible { frame.size.width -= Self.sidebarExtent }
        defaults.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    func windowDidMove(_ notification: Notification) { rememberFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { rememberFrame() }
    func windowDidResignKey(_ notification: Notification) { onResignKey?() }
}

private extension NSView {
    func firstDescendant(where matches: (NSView) -> Bool) -> NSView? {
        for subview in subviews {
            if matches(subview) { return subview }
            if let found = subview.firstDescendant(where: matches) { return found }
        }
        return nil
    }
}
