# Agent Manager

Experiments in managing agent sessions with native apps.

Clone with `git clone https://github.com/jeffmcfadden/agent-manager.git`.

## Download

Download the Apple Silicon app from [GitHub Releases](https://github.com/jeffmcfadden/agent-manager/releases).
Requires macOS 13 or newer and tmux (`brew install tmux`). Unzip the download
and move AgentManager.app to Applications. Releases are currently ad hoc signed,
not Developer ID signed or notarized, so macOS may require explicit approval
before opening a downloaded build.

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

## Build a release

Run `ruby bin/release` on Apple Silicon to create the optimized Release app,
ZIP, checksums, and release notes under `macos/build/release`. Commit the
release source changes, then run `ruby bin/release --upload-only` to push the
commit and publish version 1.0.0 as tag `v1.0.0`. This requires an authenticated
GitHub CLI. `ruby bin/release --publish` builds and publishes in one invocation
when the working tree is already clean. The script never force-pushes or
overwrites an existing release.
