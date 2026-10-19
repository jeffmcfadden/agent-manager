import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAIL: \(message)") }
    print("PASS: \(message)")
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("tmux-backend-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let executable = temporary.appendingPathComponent("tmux 'fixture")
let configuration = temporary.appendingPathComponent("config 'test.conf")
let output = temporary.appendingPathComponent("output")
let status = temporary.appendingPathComponent("status")
let record = temporary.appendingPathComponent("record.json")
try "".write(to: configuration, atomically: true, encoding: .utf8)
// A real subprocess exercises argument boundaries, errors, and shell attachment
// quoting without requiring permission to create a Unix socket in this sandbox.
let fixture = """
#!/usr/bin/ruby
require 'json'
root = File.dirname(__FILE__)
File.write(File.join(root, 'record.json'), JSON.generate({args: ARGV, tmux: ENV['TMUX'], tmpdir: ENV['TMUX_TMPDIR']}))
print File.read(File.join(root, 'output'))
exit File.read(File.join(root, 'status')).to_i
"""
try fixture.write(to: executable, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
func respond(_ text: String, code: Int = 0) throws {
    try text.write(to: output, atomically: true, encoding: .utf8)
    try "\(code)".write(to: status, atomically: true, encoding: .utf8)
}
func arguments() throws -> [String] {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as! [String: Any]
    return json["args"] as! [String]
}
let backend = try TmuxBackend(executable: executable, socketName: "isolated-test", configuration: configuration)
try respond("$12\tMy agent 'one'\tWorking ✓\t/a path/with spaces\t2\t1700000000\n$15\tother\t\t/tmp\t0\t1700000001\n")
let sessions = try backend.list()
check(sessions.count == 2 && sessions[0].id == "$12", "parse stable IDs and multiple sessions")
check(sessions[0].name == "My agent 'one'" && sessions[0].title == "Working ✓", "preserve names and Unicode titles")
check(sessions[1].title.isEmpty && sessions[0].attachedClients == 2, "empty titles and attachment counts")
let listArgs = try arguments()
check(Array(listArgs.prefix(4)) == ["-L", "isolated-test", "-f", configuration.path], "isolate socket and config")
check(listArgs[4] == "list-sessions", "discover sessions with tmux")
try respond("error connecting to /tmp/test (No such file or directory)\n", code: 1)
check(try backend.list().isEmpty, "missing server is an empty session list")
try respond("error connecting to /tmp/test (Operation not permitted)\n", code: 1)
do { _ = try backend.list(); fatalError("permission error was swallowed") }
catch { check(error.localizedDescription.contains("Operation not permitted"), "surface connection errors") }
try respond("$16\tnew\t\t/tmp\t0\t1700000001\n")
let created = try backend.create()
check(created.id == "$16", "create returns tmux's ID")
let createArgs = try arguments()
check(createArgs.contains("-d") && createArgs.contains("-P"), "create detached session and request metadata")
try respond("")
try backend.rename(id: "$16", name: "  My Agent 'one' ✓  ")
check(Array(try arguments().suffix(4)) == ["rename-session", "-t", "$16", "My Agent 'one' ✓"], "rename preserves ID and passes a trimmed Unicode name as one argument")
let beforeInvalidRename = try Data(contentsOf: record)
for invalid in ["   ", "bad:name", "bad.name", "bad\nname"] {
    do { try backend.rename(id: "$16", name: invalid); fatalError("invalid name accepted") }
    catch { check(try Data(contentsOf: record) == beforeInvalidRename, "invalid name rejected before invoking tmux") }
}
try respond("duplicate session: My Agent\n", code: 1)
do { try backend.rename(id: "$16", name: "My Agent"); fatalError("rename failure swallowed") }
catch { check(error.localizedDescription.contains("duplicate session"), "rename reports tmux errors") }
try respond("")
try backend.end(id: "$16")
check(Array(try arguments().suffix(3)) == ["kill-session", "-t", "$16"], "end targets only the selected session")
// Reproduce Ghostty 1.2.3's macOS shell wrapper, including its exec prefix.
// Dollar IDs and apostrophes must remain literal arguments.
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = ["--noprofile", "--norc", "-c", "exec -l " + backend.attachmentCommand(id: "$16")]
try process.run(); process.waitUntilExit()
check(process.terminationStatus == 0, "attachment executes through Ghostty's macOS wrapper")
check(Array(try arguments().suffix(3)) == ["attach-session", "-t", "$16"], "attachment quotes IDs and executable/config paths")
let json = try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as! [String: Any]
check(json["tmux"] is NSNull && json["tmpdir"] as? String == ProcessInfo.processInfo.environment["TMUX_TMPDIR"], "attachment clears nested tmux environment")
do { _ = try TmuxBackend.parse("garbage\n"); fatalError("invalid data accepted") }
catch { print("PASS: reject malformed session data") }
print("PASS: tmux backend command tests")

let personalBackend = try TmuxBackend(executable: executable)
try respond("")
_ = try personalBackend.list()
check(try arguments() == ["list-sessions", "-F", listArgs.last!],
      "default backend uses the default server and personal config")
check(!personalBackend.attachmentCommand(id: "$16").contains("'-f'"),
      "default attachment uses personal tmux configuration")
try respond("")
try backend.reloadPersonalConfiguration()
let reloadArgs = try arguments()
check(reloadArgs.suffix(2) == ["source-file", configuration.path],
      "config reload sources user settings without overriding server options")

check(!personalBackend.attachmentCommand(id: "$16").contains("'-L'"), "default attachment uses the default server")
