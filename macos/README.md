# Agent Manager

Native macOS terminal experiment using **Swift + AppKit** and Ghostty's full
terminal embedding API, with **tmux as the persistent session backend**. No
SwiftUI. Ghostty renders an attached tmux client; the separate tmux server owns
the real shells and their terminal history.

## Run in Xcode

Run the commands below from the `macos/` directory (`cd macos` from the repository
root). The Xcode project, source files, tests, tools, and local dependencies all
live in this directory.

Install **tmux** (`brew install tmux`) before running the app. The app looks in
`/opt/homebrew/bin`, `/usr/local/bin`, and `/usr/bin`; set `AGENT_MANAGER_TMUX` to an
absolute executable path in the Xcode scheme for another location. tmux 3.5a is
installed on the development Mac. tmux is currently an external prerequisite,
not bundled into the app.

1. Trust the relocated configuration with `mise trust`, then install the project
   toolchain with `mise install`. The project's `mise.toml`
   pins **Zig 0.14.1** for Ghostty **v1.2.3**.
2. Install Xcode's **Metal Toolchain**, required to compile Ghostty's renderer
   (once per Xcode installation):

   ```sh
   xcodebuild -downloadComponent MetalToolchain
   ```

3. From this project folder, prepare the dependency once:

   ```sh
   mise exec -- bin/setup-ghostty
   ```

4. Open **AgentManager.xcodeproj** in Xcode.
5. Select the **AgentManager** scheme and **My Mac**, then press **⌘R**.

Xcode compiles the Swift app, links libghostty, bundles its runtime resources,
and signs the app locally. No Apple developer team is needed. Debug and Release
builds target the current Mac's architecture, matching the dependency setup.
Use Xcode's normal breakpoints and debugger for the Swift host.

Dependency setup requires full Xcode, Ruby, and internet access. It downloads the
pinned Ghostty source into `vendor/ghostty`, builds the library, and stages its
header, static library, and resources in `vendor/libghostty`. Run setup again if
you remove `vendor/` or move the project to a Mac with a different architecture.
Xcode builds do not download or rebuild Ghostty. A build phase reports a clear
error if setup has not been completed.

Setup applies a small, repeatable build patch that excludes GNU libintl when
translations are disabled. Run setup again after updating from an older checkout;
the build checks for the new library marker. Application builds bundle the
repository's LICENSE, THIRD_PARTY_NOTICES.md, and ThirdParty directory. These
are available through **Agent Manager → Licenses…**. Original application code
uses WTFPL v2; dependencies retain their respective licenses.

On macOS SDK 26 and newer, setup selects an installed macOS 14 or 15 SDK from
Command Line Tools for Zig's build. Zig 0.14.1 fails to link its build runner
against the newer SDK. This workaround applies only to dependency setup;
Xcode still uses its selected SDK for the Swift app. Override the dependency
SDK with `GHOSTTY_MACOS_SDK=/path/to/MacOSX15.5.sdk` if necessary.

If Xcode's Metal shim cannot discover an installed Metal toolchain, set
`GHOSTTY_METAL_TOOLCHAIN=/path/to/Metal.xctoolchain` during dependency setup.
This uses the installed compiler directly without changing Xcode settings.

Command-line builds use the same Xcode project:

```sh
bin/build
bin/run
```

These place the app in `build/Build/Products/Debug/AgentManager.app`. Xcode's UI
uses its configured Derived Data location instead.

## Terminal behavior

Each window contains a native, resizable sidebar and its selected terminal.
Click a session to display it in that window. Switching sessions disconnects the
previous local client while its tmux shell continues running. Search filters
session names and terminal titles; arrow keys navigate the sidebar, and clicking
a row puts keyboard focus in the terminal.

- **⌘⇧N / File → New Window** opens another workspace window.
- **⌘N / New Session** creates a tmux shell in your home directory and selects it
  in the active window. The toolbar's **+** does the same thing.
- **⌘⌃S / View → Toggle Sidebar** collapses or reveals the sidebar.
- **⌘1 / Show Sessions** reveals the sidebar and focuses its search field.
- **⌘⇧R / Rename Session…** changes the current session's persistent tmux name.
- **⌘⇧D / Detach Session** disconnects the terminal and leaves the window open.
- **⌘W / End Session…** ends the visible tmux session after confirmation, keeping
  the window open. It is disabled when no session is visible.
- **Close Window** closes a window, disconnecting its local client without ending
  the shell.
- **⌘Q** disconnects local clients and quits; tmux keeps the shells alive.

Right-click a sidebar row to rename, detach, end, or open it in another window.
Normal selection of a session already open elsewhere brings that window forward.
The explicit **Open in New Window** action moves its local view to a new window;
it does not create duplicate local clients competing for terminal size. SSH
clients may still attach independently. The Window menu provides normal macOS
window navigation, minimize, and zoom. Window tabs are deferred for this milestone.

Window positions, sizes, sidebar widths/collapse state, and selected sessions
are saved in app preferences. Reopening restores those windows and attaches to
surviving sessions, without creating new shells. Closed windows stay closed.
A missing session restores as an empty window with a New Session action. Saved
references include tmux's session ID and creation time to avoid reconnecting to
an unrelated session if the server restarts and IDs are reused. Frames are kept
on available displays when the monitor arrangement changes.

Rows show tmux session names, active pane titles, and attachment location.
Remote renames and session creation/deletion are reconciled every two seconds;
management commands run off the main thread. A local client exiting clears its
window's terminal; only tmux determines whether the underlying session ended.
Names can include spaces and Unicode; tmux rejects empty names, periods, colons,
and duplicate names. You can also detach using **Ctrl-B**, then **D**.

The app shares tmux’s default server with ordinary `tmux` commands. Existing
default-server sessions appear in the sidebar. Sessions on the former
`agent-manager` server remain available with `tmux -L agent-manager attach`.
The app lets tmux load your normal personal configuration, including status bar,
key bindings, and history settings. Configuration is loaded when the server starts, so an
already-running server needs its config reloaded (for example,
`tmux source-file ~/.tmux.conf` inside an attached session). The server
starts when the first session is created and exits when the last session ends.
Sessions survive the UI quitting or crashing, but not the tmux server dying,
logout, or reboot. Sleep pauses execution.

After SSHing to this Mac as the same user, list or attach to these sessions:

```sh
tmux list-sessions
tmux attach-session -t session-1234abcd
```

Use the actual name from the list. To rename a session externally:

```sh
tmux rename-session -t session-1234abcd "My Agent"
```

The app identifies sessions by tmux's `$<number>` IDs within the server lifetime,
so renaming a session does not break its window. Multiple clients may attach;
attaching from the app does not forcibly disconnect an SSH client.

Ghostty's local scrollback is recreated on attachment. tmux retains its own
history and redraws the current screen; use tmux copy mode (**Ctrl-B [**, then
**q** to leave) for history from before attachment. Copy/paste/select all remain
in the app's Edit menu. Ghostty uses built-in defaults independent of your
installed Ghostty application's config.

## Structure

The CRT/robot app icon is configured in Xcode's `Resources/Assets.xcassets`, with
`AppIcon` selected as the target's app icon for both Debug and Release. Xcode's
asset compiler generates the bundled ICNS and icon metadata, including the
standard 1024×1024 representation. The original 1254×1254 transparent PNG and
generation prompt are in `Resources/Artwork/`. Run `bin/build-icon` to regenerate
the app icon asset catalog's PNG sizes from that master, then build in Xcode.

- `AgentManager.xcodeproj`: native app target and shared build/run scheme.
- `Sources/AppDelegate.swift`: AppKit lifecycle and standard app/File/Edit/View/Window menus.
- `Sources/TerminalSession.swift`: window-independent tmux records and asynchronous catalog reconciliation.
- `Sources/SessionBrowser.swift`: searchable source-list sidebar and contextual actions.
- `Sources/WorkspaceWindowController.swift`: split-view window and disposable Ghostty attachment.
- `Sources/WindowCoordinator.swift`: window ownership, session selection, and duplicate-view policy.
- `Sources/WorkspaceState.swift`: saved geometry and session references.
- `Sources/TmuxBackend.swift`: tmux discovery, creation, termination, and attachment commands.
- `Resources/tmux.conf`: isolated live-test configuration.
- `Sources/GhosttyRuntime.swift`: library initialization and host callbacks.
- `Sources/TerminalView.swift`: NSView surface, resizing, keyboard/IME and mouse input.
- `Sources/main.swift`: AppKit entry point.
- `bin/setup-ghostty`: Ruby dependency setup.
- `bin/ghostty_archive.rb`: stages a complete static archive from Zig's object files.
- `bin/check-ghostty`, `bin/copy-ghostty-resources`: Xcode build phases.
- `bin/build`, `bin/run`: command-line Xcode build and launch wrappers.

## Validation status

Dependency setup and the Debug Xcode command-line build now succeed, including
linking and local signing. Setup uses mise's Zig 0.14.1 and the installed macOS
15.5 SDK. Bundled themes are disabled because the pinned upstream theme archive
returns HTTP 404; Ghostty's default terminal colors remain available.

On this toolchain, upstream's combined `libghostty-fat.a` omitted object files
that were present in the original Zig archives, causing undefined symbols at
the Xcode link step. Setup now extracts the exact input archives recorded in
Zig's cache manifest, makes their objects readable, gives them distinct names,
and combines those object files directly. It verifies the staged library exports
`ghostty_init` before continuing. This workaround depends on the pinned release's
cache manifest format.

The tmux change passes the Debug Xcode build and headless backend command tests:

```sh
bin/test-tmux
bin/test-workspace
```

These tests exercise real subprocess argument passing, socket/config isolation,
metadata parsing, missing-server vs connection-error handling, detached creation,
explicit termination, and attachment shell quoting (including apostrophes and
literal `$` session IDs). Workspace tests cover asynchronous discovery, renaming
without losing identity, explicit termination, safe shutdown, server ID reuse,
and multi-window state serialization including sidebar preferences.

Full integration could not run in the agent session: creating tmux's Unix socket
is denied, and graphical application registration is restricted. From a normal
Terminal in a logged-in graphical session, run:

```sh
bin/test-sessions
```

This uses an isolated test app and uniquely named tmux server. It checks session switching within one window, independent window selections,
existing-window focus, close/detach behavior, restoration after UI shutdown,
unchanged shell PID/environment, remote rename reconciliation, and termination. Its
cleanup kills only the uniquely named test server, never your app's server.
The integration test compiles but remains unverified at runtime here.

For a manual check, create two sessions and switch between them in the sidebar.
Run `sleep 10; echo still-running` in one, switch away, then return after ten
seconds. Open another window and select the other session. Resize both windows
and their sidebars, quit, and reopen: geometry and selected sessions should return.
Also check sidebar collapse/search, remote SSH attachment and rename, closing one
window without disturbing the other, and explicit End Session.

Upstream: https://github.com/ghostty-org/ghostty/tree/v1.2.3

To verify renaming against the installed tmux server implementation, run
`bin/test-tmux-live`. It creates and cleans up a separate temporary server,
checks that renamed sessions are returned with their new names and stable IDs,
and leaves application sessions untouched. This test requires permission to
create local Unix sockets; run it from Terminal if the agent sandbox blocks it.

Use **File → Reload tmux Configuration** to apply your personal config to the
running default server. Your personal config determines the tmux prefix;
for example, `set -g prefix C-s` means press Control-S, release it, then press
`%` for a left/right split or `"` for a top/bottom split.
