import Foundation

struct SessionReference: Codable, Equatable {
    let id: String
    let createdAt: Int64
    init(_ info: TmuxSessionInfo) { id = info.id; createdAt = info.createdAt }
    func matches(_ session: TerminalSession) -> Bool { id == session.id && createdAt == session.info.createdAt }
}

struct WorkspaceState: Codable {
    var frame: String
    var sidebarWidth: Double
    var sidebarCollapsed: Bool
    var session: SessionReference?
}

protocol WorkspacePreferences {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}
extension UserDefaults: WorkspacePreferences {}

final class WorkspaceStateStore {
    private let defaults: WorkspacePreferences
    private let key = "workspaceWindows.v1"
    init(defaults: WorkspacePreferences = UserDefaults.standard) { self.defaults = defaults }
    func load() -> [WorkspaceState] {
        guard let data = defaults.data(forKey: key), let states = try? JSONDecoder().decode([WorkspaceState].self, from: data) else { return [] }
        return Array(states.prefix(20))
    }
    func save(_ states: [WorkspaceState]) {
        if let data = try? JSONEncoder().encode(states) { defaults.set(data, forKey: key) }
    }
}
