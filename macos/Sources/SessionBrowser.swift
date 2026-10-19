import AppKit

/// Shared tmux catalog, presented as a native sidebar in every workspace window.
final class SessionBrowser: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    private let store: SessionStore
    private let table = NSTableView()
    private let search = NSSearchField()
    private let status = NSTextField(wrappingLabelWithString: "Loading sessions…")
    private var rows: [TerminalSession] = []
    private var selectedID: String?
    private var updating = false
    var onSelect: ((TerminalSession, Bool) -> Void)?
    var onOpenInNewWindow: ((TerminalSession) -> Void)?
    var onRename: ((TerminalSession) -> Void)?
    var onEnd: ((TerminalSession) -> Void)?
    var onDetach: ((TerminalSession) -> Void)?
    var location: ((TerminalSession) -> String)?

    init(store: SessionStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        view = background
        search.placeholderString = "Search Sessions"
        search.delegate = self
        let heading = NSTextField(labelWithString: "Sessions")
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        table.addTableColumn(NSTableColumn(identifier: .init("session")))
        table.headerView = nil
        table.rowHeight = 52
        table.style = .sourceList
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked(_:))
        table.allowsEmptySelection = true
        table.setAccessibilityLabel("Sessions")
        let context = NSMenu()
        context.delegate = self
        table.menu = context
        scroll.documentView = table
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        for item in [search, heading, scroll, status] {
            item.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(item)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: background.safeAreaLayoutGuide.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            heading.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 16),
            heading.leadingAnchor.constraint(equalTo: search.leadingAnchor, constant: 4),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12)
        ])
    }

    func reload(selectedID: String?) {
        _ = view // Load the view on macOS 13 as well as newer releases.
        self.selectedID = selectedID
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rows = store.sessions.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        updating = true
        table.reloadData()
        if let row = rows.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        updating = false
        status.stringValue = query.isEmpty ? store.status : "\(rows.count) matching sessions"
    }
    func focusSearch() { view.window?.makeFirstResponder(search) }
    func controlTextDidChange(_ obj: Notification) { reload(selectedID: selectedID) }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let session = rows[row]
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString: session.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let state = location?(session) ?? (session.info.attachedClients > 0 ? "Attached elsewhere" : "Detached")
        let detail = session.title.isEmpty ? session.info.directory : session.title
        let subtitle = NSTextField(labelWithString: detail)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
let symbol: String
switch state {
case "Open here": symbol = "terminal.fill"
case "Open in another window": symbol = "macwindow.on.rectangle"
case "Attached elsewhere": symbol = "display"
default: symbol = "circle.dashed"
}
let stateIcon = NSImageView()
stateIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: state)
stateIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
stateIcon.contentTintColor = .secondaryLabelColor
stateIcon.toolTip = state
stateIcon.setAccessibilityLabel(state)
stateIcon.translatesAutoresizingMaskIntoConstraints = false
cell.addSubview(stateIcon)
cell.toolTip = "\(session.name)\n\(state)\n\(detail)"
        for label in [title, subtitle] { label.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(label) }
        NSLayoutConstraint.activate([
stateIcon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
stateIcon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
stateIcon.widthAnchor.constraint(equalToConstant: 16),
stateIcon.heightAnchor.constraint(equalToConstant: 16),
title.leadingAnchor.constraint(equalTo: stateIcon.trailingAnchor, constant: 8),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor)
        ])
        cell.textField = title
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updating, rows.indices.contains(table.selectedRow) else { return }
        // Keyboard navigation previews the terminal while retaining sidebar focus.
        onSelect?(rows[table.selectedRow], false)
    }
    @objc private func clicked(_ sender: Any?) {
        guard rows.indices.contains(table.clickedRow) else { return }
        onSelect?(rows[table.clickedRow], true)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard rows.indices.contains(row) else { return }
        let session = rows[row]
        for (title, action) in [("Open in New Window", #selector(openNew(_:))), ("Rename Session…", #selector(rename(_:))),
                                ("Detach Session", #selector(detach(_:))), ("End Session…", #selector(end(_:)))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = session
        }
    }
    @objc private func openNew(_ sender: NSMenuItem) { if let session = sender.representedObject as? TerminalSession { onOpenInNewWindow?(session) } }
    @objc private func rename(_ sender: NSMenuItem) { if let session = sender.representedObject as? TerminalSession { onRename?(session) } }
    @objc private func detach(_ sender: NSMenuItem) { if let session = sender.representedObject as? TerminalSession { onDetach?(session) } }
    @objc private func end(_ sender: NSMenuItem) { if let session = sender.representedObject as? TerminalSession { onEnd?(session) } }
}
