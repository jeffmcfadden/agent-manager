import Foundation

// Exercise the installed tmux format engine, rather than fixture output.
// This unique server never reads or changes the app's real sessions.
struct TestFailure: Error { let message: String }
func runLiveTest() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let backend = try TmuxBackend(socketName: "agent-manager-live-test-\(UUID().uuidString)",
                                  configuration: root.appendingPathComponent("Resources/tmux.conf"))
    defer { _ = try? backend.run(["kill-server"]) }
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
        print("PASS: \(message)")
    }
    try check(try backend.list().isEmpty, "isolated server starts empty")
    let session = try backend.create()
    try check(session.name.hasPrefix("session-"), "creation query returns a nonempty session name")
    let name = "Renamed Agent 'one' ✓"
    try backend.rename(id: session.id, name: name)
    let renamed = try backend.list().first { $0.id == session.id }
    try check(renamed?.name == name, "real tmux listing preserves the renamed session name")
    try check(renamed?.createdAt == session.createdAt, "renaming preserves session identity")
    let title = "Agent title ✓"
    let result = try backend.run(["select-pane", "-t", session.id, "-T", title])
    try check(result.status == 0, "set terminal title")
    let titled = try backend.list().first { $0.id == session.id }
    try check(titled?.title == title, "tmux format preserves the terminal title")
    try check(titled?.directory == NSHomeDirectory(), "tmux format preserves working directory")
    try backend.end(id: session.id)
    try check(try backend.list().isEmpty, "explicit end removes test session")
    print("PASS: live tmux rename/list round trip")

}
do { try runLiveTest() } catch {
    fputs("Live tmux test failed: \(error)\n", stderr)
    exit(1)
}
