import AppKit

/// Owns a window's selection and one disposable tmux attachment.
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation {
    let sidebar: SessionBrowser
    let split = NSSplitViewController()
    private let content = NSViewController()
    private let sidebarItem: NSSplitViewItem
    private let placeholder = NSStackView()
    private let store: SessionStore
    private(set) var session: TerminalSession?
    private(set) var terminal: TerminalView?
    private var savedSidebarWidth: CGFloat = 250
    var pendingRestoration: SessionReference?
    var onClose: (() -> Void)?
    var onStateChange: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onNewSession: (() -> Void)?

    init(store: SessionStore, state: WorkspaceState? = nil) {
        self.store = store
        sidebar = SessionBrowser(store: store)
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Agent Manager"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 400)
        window.tabbingMode = .disallowed // Sidebar first; native window tabs are deferred.
        window.delegate = self
        content.view = NSView()
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 360
        sidebarItem.canCollapse = true
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: content))
        window.contentViewController = split
        configurePlaceholder()
        let toolbar = NSToolbar(identifier: "WorkspaceToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.center()
        if let state {
            pendingRestoration = state.session
            var frame = NSRectFromString(state.frame)
            if frame.width.isFinite && frame.height.isFinite && frame.width >= 680 && frame.height >= 400 &&
                NSScreen.screens.contains(where: { $0.visibleFrame.intersection(frame).width >= 100 && $0.visibleFrame.intersection(frame).height >= 100 }) {
                if let screen = NSScreen.screens.max(by: {
                    let a = $0.visibleFrame.intersection(frame), b = $1.visibleFrame.intersection(frame)
                    return a.width * a.height < b.width * b.height
                }) {
                    let available = screen.visibleFrame
                    frame.size.width = min(frame.width, available.width)
                    frame.size.height = min(frame.height, available.height)
                    frame.origin.x = max(available.minX, min(frame.minX, available.maxX - frame.width))
                    frame.origin.y = max(available.minY, min(frame.minY, available.maxY - frame.height))
                }
                window.setFrame(frame, display: false)
            }
            savedSidebarWidth = CGFloat(state.sidebarWidth.isFinite ? min(360, max(200, state.sidebarWidth)) : 250)
        }
        split.view.layoutSubtreeIfNeeded()
        split.splitView.setPosition(savedSidebarWidth, ofDividerAt: 0)
        sidebarItem.isCollapsed = state?.sidebarCollapsed ?? false
        NotificationCenter.default.addObserver(self, selector: #selector(dividerChanged(_:)), name: NSSplitView.didResizeSubviewsNotification, object: split.splitView)
        reload()
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:state:)") }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func configurePlaceholder() {
        let icon = NSImageView(image: NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        let heading = NSTextField(labelWithString: "Choose a Session")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString: "Select a session in the sidebar, or create a new one.\nYour sessions keep running when you close this window.")
        hint.alignment = .center
        hint.textColor = .secondaryLabelColor
        let button = NSButton(title: "New Session", target: self, action: #selector(newSession(_:)))
        button.bezelStyle = .rounded
        placeholder.orientation = .vertical
        placeholder.spacing = 12
        [icon, heading, hint, button].forEach(placeholder.addArrangedSubview)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 44), icon.heightAnchor.constraint(equalToConstant: 44),
            placeholder.centerXAnchor.constraint(equalTo: content.view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: content.view.centerYAnchor),
            placeholder.widthAnchor.constraint(lessThanOrEqualTo: content.view.widthAnchor, constant: -48)
        ])
    }

    func present() {
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func display(_ session: TerminalSession, terminal: TerminalView, focus: Bool) {
        detach(notify: false)
        self.session = session
        self.terminal = terminal
        pendingRestoration = nil
        terminal.onCloseRequested = { [weak self, weak terminal] _ in
            guard let self, let terminal, self.terminal === terminal else { return }
            self.detach()
            self.onDisconnect?()
        }
        placeholder.isHidden = true
        terminal.frame = content.view.bounds
        terminal.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(terminal)
        let area = content.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: area.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: area.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: area.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: area.bottomAnchor)
        ])
        if focus { focusTerminal() } else { terminal.setFocused(false) }
        reload()
        onStateChange?()
    }
    func focusTerminal() { if let terminal { window?.makeFirstResponder(terminal); terminal.setFocused(window?.isKeyWindow ?? false) } }
    func detach(notify: Bool = true) {
        let old = terminal
        terminal = nil
        session = nil
        old?.onCloseRequested = nil
        old?.onTitleChange = nil
        old?.close()
        old?.removeFromSuperview()
        placeholder.isHidden = false
        if notify { pendingRestoration = nil; reload(); onStateChange?() }
    }
    func reload() {
        if let session {
            window?.title = session.name
            window?.subtitle = session.title == session.name ? "" : session.title
        } else { window?.title = "Agent Manager"; window?.subtitle = "" }
        sidebar.reload(selectedID: session?.id)
        window?.toolbar?.validateVisibleItems()
    }
    var state: WorkspaceState {
        WorkspaceState(frame: NSStringFromRect(window?.frame ?? .zero), sidebarWidth: Double(savedSidebarWidth),
                       sidebarCollapsed: sidebarItem.isCollapsed, session: session.map { SessionReference($0.info) } ?? pendingRestoration)
    }
    @objc func toggleSidebar(_ sender: Any?) { split.toggleSidebar(sender); onStateChange?() }
    func showSidebar() { sidebarItem.isCollapsed = false; sidebar.focusSearch(); onStateChange?() }
    @objc private func newSession(_ sender: Any?) { onNewSession?() }
    @objc private func detachSession(_ sender: Any?) { detach(); onDisconnect?() }
    @objc private func dividerChanged(_ notification: Notification) {
        if !sidebarItem.isCollapsed, sidebar.view.frame.width >= 200 { savedSidebarWidth = sidebar.view.frame.width }
        onStateChange?()
    }
    func windowWillClose(_ notification: Notification) { detach(notify: false); onClose?() }
    func windowDidMove(_ notification: Notification) { onStateChange?() }
    func windowDidResize(_ notification: Notification) { onStateChange?() }
    func windowDidBecomeKey(_ notification: Notification) { terminal?.setFocused(window?.firstResponder === terminal) }
    func windowDidResignKey(_ notification: Notification) { terminal?.setFocused(false) }
    func windowDidChangeOcclusionState(_ notification: Notification) {
        if let surface = terminal?.surface { ghostty_surface_set_occlusion(surface, window?.occlusionState.contains(.visible) ?? false) }
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.toggleSidebar, .sidebarTrackingSeparator, .init("NewSession"), .init("DetachSession"), .flexibleSpace] }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { item.itemIdentifier != .init("DetachSession") || session != nil }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.toggleSidebar, .sidebarTrackingSeparator, .init("NewSession"), .flexibleSpace, .init("DetachSession")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == .sidebarTrackingSeparator { return NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: split.splitView, dividerIndex: 0) }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        switch identifier {
        case .toggleSidebar:
            item.label = "Toggle Sidebar"; item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: item.label); item.action = #selector(toggleSidebar(_:))
        case .init("NewSession"):
            item.label = "New Session"; item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: item.label); item.action = #selector(newSession(_:))
        case .init("DetachSession"):
            item.label = "Detach Session"; item.image = NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: item.label); item.action = #selector(detachSession(_:))
        default: return nil
        }
        item.toolTip = item.label
        return item
    }
}
