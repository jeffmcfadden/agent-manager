import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var backend: TmuxBackend!
    private var runtime: GhosttyRuntime!
    private var coordinator: WindowCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            backend = try TmuxBackend()
            runtime = try GhosttyRuntime()
            let store = SessionStore(backend: backend)
            coordinator = WindowCoordinator(store: store, runtime: runtime)
            store.onError = { error in
                let alert = NSAlert()
                alert.messageText = "tmux operation failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Unable to start Agent Manager"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        NSWindow.allowsAutomaticWindowTabbing = false
        buildMenu()
        coordinator.start()
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func reloadTmuxConfiguration(_ sender: Any?) {
        let backend = self.backend!
        DispatchQueue.global(qos: .userInitiated).async {
            do { try backend.reloadPersonalConfiguration() }
            catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Couldn’t reload tmux configuration"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
    @objc func newWindow(_ sender: Any?) { coordinator.newWindow() }
    @objc func showLicenses(_ sender: Any?) {
        guard let resources = Bundle.main.resourceURL else { return }
        NSWorkspace.shared.open(resources.appendingPathComponent("Licenses", isDirectory: true))
    }
    @objc func newSession(_ sender: Any?) { coordinator.create() }
    @objc func showSessions(_ sender: Any?) { coordinator.present(); coordinator.active?.showSidebar() }
    @objc func toggleSidebar(_ sender: Any?) { coordinator.active?.toggleSidebar(sender) }
    @objc func renameSession(_ sender: Any?) { coordinator.renameActive() }
    @objc func detachSession(_ sender: Any?) { coordinator.detachActive() }
    @objc func endSession(_ sender: Any?) { coordinator.endActive() }
    @objc func openInNewWindow(_ sender: Any?) {
        if let session = coordinator.active?.session { coordinator.openInNewWindow(session) }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if [#selector(renameSession(_:)), #selector(detachSession(_:)), #selector(endSession(_:)), #selector(openInNewWindow(_:))].contains(item.action) {
            return coordinator?.active?.session != nil
        }
        if item.action == #selector(toggleSidebar(_:)) { return coordinator?.active != nil }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateNow }
    func applicationWillTerminate(_ notification: Notification) { coordinator?.shutdown(); coordinator = nil; runtime = nil }
    func applicationDidBecomeActive(_ notification: Notification) { if let app = runtime?.app { ghostty_app_set_focus(app, true) } }
    func applicationDidResignActive(_ notification: Notification) { if let app = runtime?.app { ghostty_app_set_focus(app, false) } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.present()
        return true
    }

    private func buildMenu() {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            let result = NSMenu(title: title)
            item.submenu = result
            return result
        }
        func action(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command]) {
            let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
        }
        let app = submenu("Agent Manager")
        app.addItem(withTitle: "About Agent Manager", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        action(app, "Licenses…", #selector(showLicenses(_:)))
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Agent Manager", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Agent Manager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("File")
        action(file, "New Window", #selector(newWindow(_:)), "n", [.command, .shift])
        action(file, "New Session", #selector(newSession(_:)), "n")
        action(file, "Open Session in New Window", #selector(openInNewWindow(_:)))
        file.addItem(.separator())
        action(file, "Rename Session…", #selector(renameSession(_:)), "r", [.command, .shift])
        action(file, "Detach Session", #selector(detachSession(_:)), "d", [.command, .shift])
        action(file, "End Session…", #selector(endSession(_:)))
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        action(file, "Reload tmux Configuration", #selector(reloadTmuxConfiguration(_:)))
        let edit = submenu("Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        let view = submenu("View")
        action(view, "Toggle Sidebar", #selector(toggleSidebar(_:)), "s", [.command, .control])
        action(view, "Show Sessions", #selector(showSessions(_:)), "1")
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.command, .control]
        let windows = submenu("Window")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windows.addItem(.separator())
        windows.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windows
        NSApp.mainMenu = menu
    }
}
