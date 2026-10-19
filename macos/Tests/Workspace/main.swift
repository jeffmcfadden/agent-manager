import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAIL: \(message)") }
    print("PASS: \(message)")
}
func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    check(condition(), "asynchronous catalog operation completes")
}
func info(_ id: String, _ name: String, created: Int64 = 100) -> TmuxSessionInfo {
    TmuxSessionInfo(id: id, name: name, title: "Title", directory: "/tmp", attachedClients: 0, createdAt: created)
}
final class FakeBackend: SessionBackend {
    private let lock = NSLock()
    private var storage = [info("$0", "One")]
    private(set) var kills = 0
    private(set) var creates = 0
    private var nextCreated: TmuxSessionInfo?
    func replace(_ records: [TmuxSessionInfo]) { lock.lock(); defer { lock.unlock() }; storage = records }
    func createNext(_ record: TmuxSessionInfo) { lock.lock(); defer { lock.unlock() }; nextCreated = record }
    func list() throws -> [TmuxSessionInfo] { lock.lock(); defer { lock.unlock() }; return storage }
    func create() throws -> TmuxSessionInfo {
        lock.lock(); defer { lock.unlock() }
        creates += 1
        let record = nextCreated ?? info("$\(creates)", "New \(creates)")
        nextCreated = nil
        storage.removeAll { $0.id == record.id }
        storage.append(record)
        return record
    }
    func rename(id: String, name: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage = storage.map { $0.id == id ? info(id, name, created: $0.createdAt) : $0 }
    }
    func end(id: String) throws { lock.lock(); defer { lock.unlock() }; kills += 1; storage.removeAll { $0.id == id } }
    func attachmentCommand(id: String) -> String { "attach \(id)" }
}
let backend = FakeBackend()
let store = SessionStore(backend: backend)
store.start()
wait { store.hasLoaded }
check(backend.creates == 0 && store.sessions.count == 1, "launch discovers sessions without creating or attaching")
let original = store.sessions[0]
let reference = SessionReference(original.info)
store.rename(original, to: "Renamed remotely")
wait { store.sessions.first?.name == "Renamed remotely" }
check(store.sessions[0] === original && reference.matches(original), "renaming preserves session identity and restoration reference")
var created: TerminalSession?
store.create { created = $0 }
wait { created != nil }
check(created?.id == "$1" && store.sessions.count == 2, "creation returns record to requesting window")
backend.replace([info("$0", "New server", created: 200)])
store.refresh()
wait { store.sessions.count == 1 && store.sessions[0].info.createdAt == 200 }
check(store.sessions[0] !== original && !reference.matches(store.sessions[0]), "reused tmux ID cannot restore an unrelated session")
backend.createNext(info("$0", "Created after restart", created: 300))
var replacement: TerminalSession?
store.create { replacement = $0 }
wait { replacement != nil }
check(store.sessions.count == 1 && store.sessions[0].info.createdAt == 300,
      "creation after server restart replaces a recycled ID without duplicate records")
store.shutdown()
check(backend.kills == 0, "catalog shutdown never kills tmux sessions")
let restarted = SessionStore(backend: backend)
restarted.start()
wait { restarted.hasLoaded }
check(restarted.sessions[0].name == "Created after restart", "fresh catalog discovers surviving backend state")
restarted.end(restarted.sessions[0])
wait { restarted.sessions.isEmpty }
check(backend.kills == 1, "explicit end is the only termination path")
restarted.shutdown()

final class MemoryPreferences: WorkspacePreferences {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value as? Data }
}
let preferences = MemoryPreferences()
let stateStore = WorkspaceStateStore(defaults: preferences)
let states = [WorkspaceState(frame: "{{100, 200}, {1180, 740}}", sidebarWidth: 245,
                             sidebarCollapsed: false, session: reference),
              WorkspaceState(frame: "{{500, 100}, {900, 650}}", sidebarWidth: 300,
                             sidebarCollapsed: true, session: nil)]
stateStore.save(states)
let restored = WorkspaceStateStore(defaults: preferences).load()
check(restored.count == 2 && restored[0].session == reference && restored[1].session == nil,
      "multiple windows restore independent selections and empty views")
check(restored[0].frame == states[0].frame && restored[1].sidebarWidth == 300 && restored[1].sidebarCollapsed,
      "window frames and sidebar preferences survive serialization")
preferences.values["workspaceWindows.v1"] = Data("broken".utf8)
check(stateStore.load().isEmpty, "corrupt restoration data falls back to a fresh window")
print("PASS: workspace catalog and restoration tests")
