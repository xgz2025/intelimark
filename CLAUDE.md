# Nextmark

Apple-native "save with purpose" app for iPhone, iPad and Mac. Product and design
decisions live in `Docs/` — read `Docs/architecture.md` before structural changes.

## Layout
- `project.yml` — XcodeGen spec (8 targets: app, Share, Safari and Widgets extensions, × iOS/macOS). The `.xcodeproj` is generated and git-ignored; never hand-edit one.
- `App/Shared`, `App/iOS`, `App/macOS` — app targets (composition root is `AppModel`).
- `Extensions/` — Share, Safari Web Extension, Widgets.
- `Packages/NextmarkKit` — all shared code and tests (Swift Testing).

## Rules
- Extensions link only `Model`, `Capture`, `CaptureUI`, `DesignSystem`. They never open the database or run AI; they write capture envelopes (`EnvelopeStore`) and exit.
- AI writes only the derived layer of an item; user fields (`userTitle`, `note`, `intent`, …) are never overwritten.
- Swift 6 language mode, strict concurrency. Prefer value types and actors; callbacks from Apple APIs that arrive off the main thread go through `@Sendable` completions.
- Tests must not touch `AppGroup` locations; inject temporary directories.
- Keep the build warning-free: CI fails on any compiler warning in our code (`scripts/check-warnings.sh`; third-party packages are ignored).
- Never put model identifiers in commits, code or docs.
- Every source file (`.swift`, `.js`, `.sh`, `.py`) starts with the proprietary copyright header used across the repo (Copyright © 2026 Gaoliang Luo. All rights reserved.); copy it from any existing file. `Package.swift` keeps `// swift-tools-version` and scripts keep `#!` as their first line.

## Commands (macOS with Xcode 26)
- `make test` — package tests
- `make open` — generate and open the Xcode project
- `make build-ios` / `make build-macos` — unsigned builds as CI runs them

Linux cloud sessions have no Swift toolchain: rely on the GitHub Actions `CI` workflow (macOS 26 runner) to compile and test.
