# Agent Manager

Experiments in managing agent sessions with native apps.

Clone with `git clone https://github.com/jeffmcfadden/agent-manager.git`.

The existing Swift/AppKit Mac app, Xcode project, tests, and dependency tooling
live in [`macos/`](macos/README.md). This leaves the project root available for
a future iOS companion and any shared components.

## Mac app

Open [`macos/AgentManager.xcodeproj`](macos/AgentManager.xcodeproj) in Xcode and
run the **AgentManager** scheme on **My Mac**.

For dependency setup and command-line builds, work from the Mac directory:

```sh
cd macos
mise trust
mise install
brew install tmux
xcodebuild -downloadComponent MetalToolchain
mise exec -- bin/setup-ghostty
bin/build
```

See the [Mac README](macos/README.md) for prerequisites, session behavior,
architecture, and testing instructions.

## License

Copyright © 2026 Jeff McFadden. Original Agent Manager code and artwork are
licensed under [WTFPL version 2](LICENSE). Contributions to original project
files are provided under the same license.

Third-party components retain their own licenses. See
[third-party notices](THIRD_PARTY_NOTICES.md) for attribution, bundled license
texts, source availability, and redistribution instructions. These notices
are included in the app under **Agent Manager → Licenses…**.
