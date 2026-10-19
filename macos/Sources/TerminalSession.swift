import Foundation

/// A tmux catalog record. Window controllers own disposable Ghostty attachments.
final class TerminalSession {
    private(set) var info: TmuxSessionInfo
    var id: String { info.id }
    var name: String { info.name }
    var title: String { info.title }
    init(info: TmuxSessionInfo) { self.info = info }
    func update(_ info: TmuxSessionInfo) { self.info = info }
}

/// UI state is reconciled with tmux, including sessions created or ended over SSH.
/// All public methods run on main; blocking tmux commands run on one worker queue.
final class SessionStore {
    private let backend: SessionBackend
    private let queue = DispatchQueue(label: "local.agent-manager.tmux", qos: .userInitiated)
    private var timer: Timer?
    private var refreshing = false
    private var stopped = false
    private(set) var sessions: [TerminalSession] = []
    private(set) var status = "Loading sessions…"
    var onChange: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(backend: SessionBackend) { self.backend = backend }
    private(set) var hasLoaded = false

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard !refreshing, !stopped else { return }
        refreshing = true
        let backend = self.backend
        queue.async { [weak self] in
            let result = Result { try backend.list() }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped else { return }
                self.refreshing = false
                switch result {
                case .success(let records): self.reconcile(records)
                case .failure(let error):
                    self.status = "Couldn’t refresh sessions: \(error.localizedDescription)"
                    self.onChange?()
                }
            }
        }
    }

    func create(completion: @escaping (TerminalSession) -> Void) {
        let backend = self.backend
        perform({ try backend.create() }) { [weak self] info in
            guard let self else { return }
            let session = self.sessions.first(where: { $0.id == info.id && $0.info.createdAt == info.createdAt }) ?? self.makeSession(info)
            self.sessions.removeAll { $0.id == info.id && $0 !== session }
            if !self.sessions.contains(where: { $0 === session }) { self.sessions.append(session) }
            self.onChange?()
            completion(session)
            self.refresh()
        }
    }

    func attachmentCommand(for session: TerminalSession) -> String {
        backend.attachmentCommand(id: session.id)
    }

    func end(_ session: TerminalSession) {
        let backend = self.backend
        let id = session.id
        perform({ try backend.end(id: id) }) { [weak self, weak session] _ in
            guard let self else { return }
            if let session {
                self.sessions.removeAll { $0 === session }
            }
            self.onChange?()
            self.refresh()
        }
    }

    func rename(_ session: TerminalSession, to name: String) {
        let backend = self.backend
        let id = session.id
        perform({ try backend.rename(id: id, name: name) }) { [weak self] _ in self?.refresh() }
    }

    /// Session lifetime belongs to tmux; shutdown only stops catalog polling.
    func shutdown() {
        stopped = true
        timer?.invalidate()
        timer = nil
        sessions.removeAll()
    }

    private func perform<Value>(_ work: @escaping () throws -> Value, completion: @escaping (Value) -> Void) {
        guard !stopped else { return }
        queue.async { [weak self] in
            let result = Result(catching: work)
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped else { return }
                switch result {
                case .success(let value): completion(value)
                case .failure(let error): self.onError?(error); self.refresh()
                }
            }
        }
    }

    private func makeSession(_ info: TmuxSessionInfo) -> TerminalSession { TerminalSession(info: info) }

    private func reconcile(_ records: [TmuxSessionInfo]) {
        let old = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        sessions = records.map { info in
            let session = old[info.id].flatMap { $0.info.createdAt == info.createdAt ? $0 : nil } ?? makeSession(info)
            session.update(info)
            return session
        }
        hasLoaded = true
        status = "\(sessions.count) \(sessions.count == 1 ? "session" : "sessions") · tmux backend"
        onChange?()
    }
}
