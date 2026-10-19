import AppKit

/// Owns the library application. Surfaces must be destroyed before this object.
final class GhosttyRuntime {
    private(set) var app: ghostty_app_t!

    init() throws {
        if let resources = Bundle.main.resourceURL {
            setenv("GHOSTTY_RESOURCES_DIR", resources.appendingPathComponent("ghostty").path, 1)
            let terminfo = resources.appendingPathComponent("terminfo").path
            if FileManager.default.fileExists(atPath: terminfo) { setenv("TERMINFO", terminfo, 1) }
        }
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS,
              let config = ghostty_config_new() else { throw RuntimeError.initialization }
        defer { ghostty_config_free(config) }
        // Start with library defaults, independent of the installed Ghostty app's config.
        ghostty_config_finalize(config)
        var callbacks = ghostty_runtime_config_s()
        callbacks.userdata = Unmanaged.passUnretained(self).toOpaque()
        callbacks.wakeup_cb = { pointer in
            guard let pointer else { return }
            // The callback may run on an IO thread. AppKit and app_tick belong on main.
            let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { [weak runtime] in
                if let app = runtime?.app { ghostty_app_tick(app) }
            }
        }
        callbacks.action_cb = { _, target, action in
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let pointer = ghostty_surface_userdata(surface) else { return false }
            let view = Unmanaged<TerminalView>.fromOpaque(pointer).takeUnretainedValue()
            switch action.tag {
            case GHOSTTY_ACTION_RENDER:
                ghostty_surface_draw(surface)
                return true
            case GHOSTTY_ACTION_SET_TITLE:
                if let title = action.action.set_title.title { view.onTitleChange?(String(cString: title)) }
                return true
            default: return false
            }
        }
        callbacks.read_clipboard_cb = { pointer, _, state in
            guard let pointer else { return }
            let view = Unmanaged<TerminalView>.fromOpaque(pointer).takeUnretainedValue()
            guard let surface = view.surface else { return }
            (NSPasteboard.general.string(forType: .string) ?? "").withCString {
                ghostty_surface_complete_clipboard_request(surface, $0, state, false)
            }
        }
        callbacks.confirm_read_clipboard_cb = { pointer, text, state, _ in
            guard let pointer, let text else { return }
            let view = Unmanaged<TerminalView>.fromOpaque(pointer).takeUnretainedValue()
            guard let surface = view.surface else { return }
            let alert = NSAlert()
            alert.messageText = "Allow terminal clipboard access?"
            alert.informativeText = "The terminal requested clipboard access or a paste that needs confirmation."
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                ghostty_surface_complete_clipboard_request(surface, text, state, true)
            }
        }
        callbacks.write_clipboard_cb = { _, text, _, confirm in
            guard let text else { return }
            if confirm {
                let alert = NSAlert()
                alert.messageText = "Allow terminal to replace the clipboard?"
                alert.addButton(withTitle: "Allow")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(cString: text), forType: .string)
        }
        callbacks.close_surface_cb = { pointer, processAlive in
            guard let pointer else { return }
            let view = Unmanaged<TerminalView>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { [weak view] in view?.onCloseRequested?(processAlive) }
        }
        guard let app = ghostty_app_new(&callbacks, config) else { throw RuntimeError.initialization }
        self.app = app
    }

    deinit { if let app { ghostty_app_free(app) } }

    enum RuntimeError: Error { case initialization }
}
