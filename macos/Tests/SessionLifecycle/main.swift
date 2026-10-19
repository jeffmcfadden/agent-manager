import AppKit

// Real tmux + Ghostty integration, isolated from the app's server/preferences.
final class LifecycleTest: NSObject, NSApplicationDelegate {
    var runtime: GhosttyRuntime!
    var backend: TmuxBackend!
    var store: SessionStore!
    var coordinator: WindowCoordinator!
    var first: TerminalSession!
    var second: TerminalSession!
    var firstWindow: WorkspaceWindowController!
    var secondWindow: WorkspaceWindowController!
    var pid = ""
    let socket = "agent-manager-test-\(UUID().uuidString)"
    let preferences = TestPreferences()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("agent-manager-test-\(UUID().uuidString)")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            backend = try TmuxBackend(socketName: socket, configuration: Bundle.main.url(forResource: "tmux", withExtension: "conf"))
            runtime = try GhosttyRuntime()
            configure()
            waitFor("empty server discovered", { self.store.hasLoaded }) {
                self.firstWindow = self.coordinator.windows[0]
                self.coordinator.create(in: self.firstWindow)
                self.waitFor("new session attached in workspace", { self.firstWindow.terminal?.surface != nil }) {
                    self.first = self.firstWindow.session
                    self.after(1) { self.startShell() }
                }
            }
        } catch { fail("Initialization: \(error)") }
    }
    func configure() {
        store = SessionStore(backend: backend)
        store.onError = { [weak self] in self?.fail($0.localizedDescription) }
        coordinator = WindowCoordinator(store: store, runtime: runtime,
                                        stateStore: WorkspaceStateStore(defaults: preferences))
        coordinator.start()
    }
    func startShell() {
        send(firstWindow, "export SESSION_TEST_VALUE=preserved; echo $$ > '\(directory.path)/pid'; sleep 4; echo done > '\(directory.path)/done'\n")
        waitFor("shell accepted input", { !self.read("pid").isEmpty }) {
            self.pid = self.read("pid").trimmingCharacters(in: .whitespacesAndNewlines)
            self.coordinator.create(in: self.firstWindow)
            self.waitFor("sidebar selection switches to a second session", { self.firstWindow.session?.id != self.first.id }) {
                self.second = self.firstWindow.session
                self.check(self.coordinator.windows.count == 1 && self.store.sessions.count == 2,
                           "switching sessions reuses window and preserves both shells")
                self.waitFor("background shell continues while another session is selected", { self.read("done").contains("done") }) {
                    self.coordinator.select(self.first, in: self.firstWindow)
                    self.after(1) {
                        self.send(self.firstWindow, "printf '%s:%s' \"$SESSION_TEST_VALUE\" \"$$\" > '\(self.directory.path)/state'\n")
                        self.waitFor("original shell PID and environment survive switching", { self.read("state") == "preserved:\(self.pid)" }) {
                            self.testWindows()
                        }
                    }
                }
            }
        }
    }
    func testWindows() {
        secondWindow = coordinator.newWindow()
        coordinator.select(first, in: secondWindow)
        check(secondWindow.session == nil && firstWindow.session === first,
              "selecting a session open elsewhere focuses existing view")
        coordinator.select(second, in: secondWindow)
        check(firstWindow.session === first && secondWindow.session === second,
              "windows maintain independent selections")
        coordinator.saveNow()
        coordinator.shutdown()
        configure()
        waitFor("window selections restored from saved state", {
            self.coordinator.windows.count == 2 && self.coordinator.windows.allSatisfy { $0.terminal?.surface != nil }
        }) {
            self.check(self.store.sessions.count == 2, "restoration attaches without creating sessions")
            self.first = self.store.sessions.first { $0.id == self.first.id }
            self.second = self.store.sessions.first { $0.id != self.first.id }
            self.firstWindow = self.coordinator.windows.first { $0.session === self.first }
            self.secondWindow = self.coordinator.windows.first { $0.session === self.second }
            self.testCloseAndRename()
        }
    }
    func testCloseAndRename() {
        secondWindow.window?.performClose(nil)
        check(coordinator.windows.count == 1 && secondWindow.terminal == nil,
              "closing window frees attachment and preserves other window")
        check(store.sessions.count == 2, "closing window does not end tmux session")
        do {
            try backend.rename(id: first.id, name: "Remote rename")
            store.refresh()
            waitFor("window follows backend rename", { self.firstWindow.window?.title == "Remote rename" }) {
                self.send(self.firstWindow, "exit\n")
                self.waitFor("shell exit removes session and shows empty content", { self.firstWindow.session == nil }) {
                    self.check(self.coordinator.windows.count == 1, "shell exit keeps workspace open")
                    self.store.end(self.second)
                    self.waitFor("explicit end removes remaining session", { self.store.sessions.isEmpty }) {
                        self.cleanup()
                        print("PASS: sidebar/window tmux lifecycle integration")
                        exit(0)
                    }
                }
            }
        } catch { fail(error.localizedDescription) }
    }
    func send(_ window: WorkspaceWindowController, _ text: String) {
        guard let surface = window.terminal?.surface else { fail("No attached surface") }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
    }
    func read(_ name: String) -> String { (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    func after(_ seconds: Double, _ body: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body) }
    func waitFor(_ label: String, _ condition: @escaping () -> Bool, deadline: Date = Date().addingTimeInterval(12), then: @escaping () -> Void) {
        if condition() { print("PASS: \(label)"); then(); return }
        if Date() > deadline { fail("Timed out: \(label)") }
        after(0.2) { self.waitFor(label, condition, deadline: deadline, then: then) }
    }
    func check(_ condition: Bool, _ message: String) { if !condition { fail(message) }; print("PASS: \(message)") }
    func fail(_ message: String) -> Never { print("FAIL: \(message)"); cleanup(); exit(1) }
    func cleanup() {
        coordinator?.shutdown()
        if let backend { _ = try? backend.run(["kill-server"]) }
        try? FileManager.default.removeItem(at: directory)
    }
}
final class TestPreferences: WorkspacePreferences {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value as? Data }
}
let application = NSApplication.shared
let test = LifecycleTest()
application.setActivationPolicy(.regular)
application.delegate = test
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { test.fail("test timed out") }
application.run()
