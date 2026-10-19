import AppKit

/// Shares the catalog across windows and permits one local view per session.
final class WindowCoordinator {
    let store: SessionStore
    private let runtime: GhosttyRuntime
    private let stateStore: WorkspaceStateStore
    private(set) var windows: [WorkspaceWindowController] = []
    private var saving: DispatchWorkItem?
    private var shuttingDown = false
    var active: WorkspaceWindowController? { windows.first { $0.window === NSApp.keyWindow } }

    init(store: SessionStore, runtime: GhosttyRuntime, stateStore: WorkspaceStateStore = WorkspaceStateStore()) {
        self.store = store
        self.runtime = runtime
        self.stateStore = stateStore
        store.onChange = { [weak self] in self?.catalogChanged() }
    }
    func start() {
        let states = stateStore.load()
        if states.isEmpty { _ = newWindow() }
        else { states.forEach { _ = newWindow(state: $0) } }
        store.start()
    }
    @discardableResult
    func newWindow(state: WorkspaceState? = nil) -> WorkspaceWindowController {
        let controller = WorkspaceWindowController(store: store, state: state)
        if state == nil, let previous = windows.last?.window {
            controller.window?.cascadeTopLeft(from: NSPoint(x: previous.frame.minX + 24, y: previous.frame.maxY - 24))
        }
        controller.onNewSession = { [weak self, weak controller] in self?.create(in: controller) }
        controller.onStateChange = { [weak self] in self?.scheduleSave() }
        controller.onDisconnect = { [weak self] in self?.store.refresh(); self?.reloadWindows() }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.windows.removeAll { $0 === controller }
            self.reloadWindows()
            self.scheduleSave()
        }
        controller.sidebar.onSelect = { [weak self, weak controller] session, focus in
            guard let controller else { return }
            self?.select(session, in: controller, focus: focus)
        }
        controller.sidebar.onOpenInNewWindow = { [weak self] in self?.openInNewWindow($0) }
        controller.sidebar.onRename = { [weak self, weak controller] session in self?.rename(session, in: controller) }
        controller.sidebar.onEnd = { [weak self, weak controller] session in self?.end(session, in: controller) }
        controller.sidebar.onDetach = { [weak self] session in
            self?.windows.first(where: { $0.session === session })?.detach()
            self?.store.refresh()
            self?.reloadWindows()
        }
        controller.sidebar.location = { [weak self, weak controller] session in
            if controller?.session === session { return "Open here" }
            if self?.windows.contains(where: { $0.session === session }) == true { return "Open in another window" }
            return session.info.attachedClients > 0 ? "Attached elsewhere" : "Detached"
        }
        windows.append(controller)
        controller.present()
        reloadWindows()
        scheduleSave()
        return controller
    }
    func create(in requested: WorkspaceWindowController? = nil) {
        let target = requested ?? active ?? windows.last ?? newWindow()
        store.create { [weak self, weak target] session in
            guard let self else { return }
            let target = target.flatMap { candidate in self.windows.contains { $0 === candidate } ? candidate : nil } ?? self.newWindow()
            self.select(session, in: target)
        }
    }
    func select(_ session: TerminalSession, in target: WorkspaceWindowController, focus: Bool = true) {
        guard store.sessions.contains(where: { $0 === session }) else { return }
        if let existing = windows.first(where: { $0.session === session }) {
            existing.present()
            if focus { existing.focusTerminal() }
            target.reload() // Undo a sidebar highlight if we focused another window.
            return
        }
        let terminal = TerminalView(runtime: runtime, command: store.attachmentCommand(for: session))
        target.display(session, terminal: terminal, focus: focus)
        reloadWindows()
        scheduleSave()
    }
    func openInNewWindow(_ session: TerminalSession) {
        // This explicit action moves the local view rather than creating a
        // second client that would compete for the session's terminal size.
        windows.first(where: { $0.session === session })?.detach()
        select(session, in: newWindow())
    }
    func present() {
        (active ?? windows.last ?? newWindow()).present()
        store.refresh()
    }
    func detachActive() { active?.detach(); store.refresh(); reloadWindows() }
    func renameActive() { if let active, let session = active.session { rename(session, in: active) } }
    func endActive() { if let active, let session = active.session { end(session, in: active) } }

    private func rename(_ session: TerminalSession, in controller: WorkspaceWindowController?) {
        let alert = NSAlert()
        alert.messageText = "Rename Session"
        alert.informativeText = "This name appears in the sidebar and terminal window."
        let field = NSTextField(string: session.name)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        func show() {
            if let window = controller?.window {
                alert.beginSheetModal(for: window) { [weak self] response in
                    guard response == .alertFirstButtonReturn else { return }
                    alert.window.makeFirstResponder(nil) // Commit the text field's current editor.
                    do { self?.store.rename(session, to: try TmuxBackend.validatedName(field.stringValue)) }
                    catch { alert.informativeText = error.localizedDescription; show() }
                }
            } else if alert.runModal() == .alertFirstButtonReturn {
                alert.window.makeFirstResponder(nil)
                do { store.rename(session, to: try TmuxBackend.validatedName(field.stringValue)) }
                catch { alert.informativeText = error.localizedDescription; show() }
            }
        }
        show()
    }
    private func end(_ session: TerminalSession, in controller: WorkspaceWindowController?) {
        let alert = NSAlert()
        alert.messageText = "End \(session.name)?"
        alert.informativeText = "This ends the session and its running processes, including remote attachments."
        alert.addButton(withTitle: "End Session")
        alert.addButton(withTitle: "Cancel")
        if let window = controller?.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.store.end(session) }
            }
        } else if alert.runModal() == .alertFirstButtonReturn { store.end(session) }
    }

    private func catalogChanged() {
        for controller in windows {
            if let session = controller.session, !store.sessions.contains(where: { $0 === session }) { controller.detach() }
        }
        if store.hasLoaded {
            for controller in windows {
                if let reference = controller.pendingRestoration {
                    controller.pendingRestoration = nil
                    if let session = store.sessions.first(where: { reference.matches($0) }), !windows.contains(where: { $0.session === session }) {
                        select(session, in: controller, focus: false)
                    }
                }
            }
        }
        reloadWindows()
        scheduleSave()
    }
    private func reloadWindows() { windows.forEach { $0.reload() } }
    private func scheduleSave() {
        guard !shuttingDown else { return }
        saving?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saving = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func saveNow() {
        // Restoring in this order brings the previously active window forward.
        let front = active
        let ordered = windows.filter { $0 !== front } + (front.map { [$0] } ?? [])
        stateStore.save(ordered.map(\.state))
    }
    func shutdown() {
        shuttingDown = true
        saving?.cancel()
        saveNow() // Save selections before detaching the local views.
        for controller in windows {
            controller.onClose = nil
            controller.onStateChange = nil
            controller.onDisconnect = nil
            controller.detach(notify: false)
            controller.close()
        }
        windows.removeAll()
        store.onChange = nil
        store.shutdown()
    }
}
