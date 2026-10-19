# Project conventions

- All application UI must use AppKit. Never use SwiftUI.
- Use Swift for application code; Ruby for build tooling where practical.
- Use libghostty for terminal rendering and local attachment PTYs; tmux owns persistent shell sessions and history.
- Prefer small objects with clear ownership and responsibilities.
