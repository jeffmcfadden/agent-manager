import AppKit

final class TerminalView: NSView, NSTextInputClient {
    private let runtime: GhosttyRuntime
    private let command: String?
    private(set) var surface: ghostty_surface_t?
    var onTitleChange: ((String) -> Void)?
    var onCloseRequested: ((Bool) -> Void)?
    private var marked = NSAttributedString(string: "")
    private var pendingText: String?
    private var handlingKey = false

    init(runtime: GhosttyRuntime, command: String? = nil) {
        self.runtime = runtime
        self.command = command
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 640))
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError("Use init(runtime:)") }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { setFocused(window?.isKeyWindow ?? false) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { setFocused(false) }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, surface == nil else { return }
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = window.backingScaleFactor
        config.font_size = 14
        surface = NSHomeDirectory().withCString { directory in
            config.working_directory = directory
            if let command {
                return command.withCString { commandPointer in
                    config.command = commandPointer
                    return ghostty_surface_new(runtime.app, &config)
                }
            }
            return ghostty_surface_new(runtime.app, &config)
        }
        guard let surface else {
            let alert = NSAlert()
            alert.messageText = "Unable to create a terminal surface"
            alert.runModal()
            return
        }
        ghostty_surface_set_focus(surface, window.isKeyWindow)
        updateSize()
    }

    func close() {
        if let surface { ghostty_surface_free(surface) }
        surface = nil
    }
    func setFocused(_ focused: Bool) {
        if let surface { ghostty_surface_set_focus(surface, focused) }
    }
    func setVisible(_ visible: Bool) {
        guard let surface else { return }
        if !visible { setFocused(false) }
        ghostty_surface_set_occlusion(surface, visible)
        if visible { updateSize(); ghostty_surface_refresh(surface) }
    }
    deinit { close() }
    override func layout() { super.layout(); updateSize() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateSize() }
    private func updateSize() {
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? 1
        ghostty_surface_set_content_scale(surface, scale, scale)
        let pixels = convertToBacking(bounds)
        ghostty_surface_set_size(surface, UInt32(max(1, pixels.width)), UInt32(max(1, pixels.height)))
        if let id = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            ghostty_surface_set_display_id(surface, id.uint32Value)
        }
        ghostty_surface_refresh(surface)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self))
    }
    private func modifiers(_ event: NSEvent) -> ghostty_input_mods_e {
        var bits: UInt32 = 0
        if event.modifierFlags.contains(.shift) { bits |= GHOSTTY_MODS_SHIFT.rawValue }
        if event.modifierFlags.contains(.control) { bits |= GHOSTTY_MODS_CTRL.rawValue }
        if event.modifierFlags.contains(.option) { bits |= GHOSTTY_MODS_ALT.rawValue }
        if event.modifierFlags.contains(.command) { bits |= GHOSTTY_MODS_SUPER.rawValue }
        if event.modifierFlags.contains(.capsLock) { bits |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: bits)
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else { return }
        pendingText = nil
        handlingKey = true
        interpretKeyEvents([event])
        handlingKey = false
        var key = ghostty_input_key_s()
        key.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        key.keycode = UInt32(event.keyCode)
        key.mods = modifiers(event)
        key.consumed_mods = ghostty_input_mods_e(rawValue: key.mods.rawValue & ~(GHOSTTY_MODS_CTRL.rawValue | GHOSTTY_MODS_SUPER.rawValue))
        key.unshifted_codepoint = event.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 0
        key.composing = hasMarkedText()
        let fallback: String? = {
            guard let characters = event.characters else { return nil }
            if characters.count == 1, let scalar = characters.unicodeScalars.first {
                if scalar.value < 0x20 {
                    return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
                }
                if (0xF700...0xF8FF).contains(scalar.value) { return nil }
            }
            return characters
        }()
        let text = pendingText ?? fallback ?? ""
        // Control characters are encoded from physical keys and modifiers by Ghostty.
        if !text.isEmpty, text.unicodeScalars.first!.value >= 0x20, !hasMarkedText() {
            text.withCString { key.text = $0; _ = ghostty_surface_key(surface, key) }
        } else { _ = ghostty_surface_key(surface, key) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self,
              event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.command) else { return false }
        keyDown(with: event)
        return true
    }
    
    override func keyUp(with event: NSEvent) {
    
            guard let surface else { return }
            var key = ghostty_input_key_s()
            key.action = GHOSTTY_ACTION_RELEASE
            key.keycode = UInt32(event.keyCode)
            key.mods = modifiers(event)
            _ = ghostty_surface_key(surface, key)
        }
    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 56, 60: flag = .shift
        case 59, 62: flag = .control
        case 58, 61: flag = .option
        case 54, 55: flag = .command
        case 57: flag = .capsLock
        default: return
        }
        var key = ghostty_input_key_s()
        key.keycode = UInt32(event.keyCode)
        key.mods = modifiers(event)
        key.action = event.modifierFlags.contains(flag) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        _ = ghostty_surface_key(surface, key)
    }

    private func moveMouse(_ event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, point.y, modifiers(event))
    }
    private func mouse(_ event: NSEvent, _ state: ghostty_input_mouse_state_e, _ button: ghostty_input_mouse_button_e) {
        window?.makeFirstResponder(self)
        moveMouse(event)
        if let surface { _ = ghostty_surface_mouse_button(surface, state, button, modifiers(event)) }
    }
    override func mouseDown(with event: NSEvent) { mouse(event, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT) }
    override func mouseUp(with event: NSEvent) { mouse(event, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT) }
    override func rightMouseDown(with event: NSEvent) { mouse(event, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT) }
    override func rightMouseUp(with event: NSEvent) { mouse(event, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT) }
    override func otherMouseDown(with event: NSEvent) { mouse(event, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_MIDDLE) }
    override func otherMouseUp(with event: NSEvent) { mouse(event, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE) }
    override func mouseMoved(with event: NSEvent) { moveMouse(event) }
    override func mouseDragged(with event: NSEvent) { moveMouse(event) }
    override func rightMouseDragged(with event: NSEvent) { moveMouse(event) }
    override func otherMouseDragged(with event: NSEvent) { moveMouse(event) }
    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, event.hasPreciseScrollingDeltas ? 1 : 0)
    }

    private func binding(_ action: String) {
        guard let surface else { return }
        action.withCString { _ = ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count)) }
    }
    @objc func copy(_ sender: Any?) { binding("copy_to_clipboard") }
    @objc func paste(_ sender: Any?) { binding("paste_from_clipboard") }
    override func selectAll(_ sender: Any?) { binding("select_all") }

    // AppKit's text input system handles keyboard layouts, dead keys and IME composition.
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String ?? "")
        unmarkText()
        if handlingKey { pendingText = (pendingText ?? "") + text }
        else if let surface { text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) } }
    }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString) ?? NSAttributedString(string: string as? String ?? "")
        if let surface { marked.string.withCString { ghostty_surface_preedit(surface, $0, UInt(marked.string.utf8.count)) } }
    }
    func unmarkText() {
        marked = NSAttributedString(string: "")
        if let surface { ghostty_surface_preedit(surface, nil, 0) }
    }
    func hasMarkedText() -> Bool { marked.length > 0 }
    func markedRange() -> NSRange { hasMarkedText() ? NSRange(location: 0, length: marked.length) : NSRange(location: NSNotFound, length: 0) }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x = 0.0, y = 0.0, width = 0.0, height = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        return window.convertToScreen(convert(NSRect(x: x, y: y, width: width, height: height), to: nil))
    }
    override func doCommand(by selector: Selector) { /* Ghostty encodes special keys. */ }
}
