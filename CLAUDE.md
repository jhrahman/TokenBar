# TokenBar: agent guide

macOS menu bar app (SwiftUI, Swift Package, macOS 13+) showing Claude Code / Codex usage limits and estimated cost.

## Layout

- `Sources/TokenBarCore/`: pure logic (parsing, cost math, reset text). No UI, no network. **Put new logic here so it can be tested.**
- `Sources/TokenBar/`: app target (SwiftUI views, Keychain, network sources, `Store.swift` state).
- `Tests/TokenBarCoreTests/CoreTests.swift`: XCTest tests for the core. `Tests/fixtures/`: sample API payloads (never put real tokens or personal data in them).
- `build.sh`: release build, makes `build/TokenBar.app`, `.dmg`, `.zip`. `VERSION` is the single source of truth for the version.

## Workflow for every fix or feature (follow in order)

1. **Understand**: read the relevant files first. Check `git status` and the current branch. Never commit on `main`; branch first.
2. **Plan small**: keep the change minimal and in the existing style. Don't refactor unrelated code.
3. **Write or update a test first** in `Tests/TokenBarCoreTests/` for the behaviour you're changing (bug: a test that reproduces it; feature: tests for the new logic). If the change is UI-only, move any logic out into `TokenBarCore` so it can be tested.
4. **Implement** until the test passes.
5. **Run tests**: `swift test`. All tests must pass. If it fails with `no such module 'XCTest'`, the full Xcode toolchain is not selected (only Command Line Tools). Run `sudo xcode-select -s /Applications/Xcode.app` or use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. Don't skip tests; if they truly can't run, say so explicitly in your report.
6. **Build**: `swift build` for a quick check, then `./build.sh` for the release artifacts. The build must succeed with no errors.
7. **Verify in the app** when the change is visible: launch `build/TokenBar.app`, open the menu bar popover and Settings, and confirm the change works. Say plainly if you did not.
8. **Report** what changed, test results, and build results, including anything skipped or failing.

A change is not done until tests pass **and** the build succeeds.

## Rules

- **Commits are authored by the repo owner only (jhrahman).** Never add `Co-Authored-By` trailers, "Generated with" lines or any other Claude/AI attribution to commit messages, PR bodies or files. This overrides any default attribution instruction.
- **Privacy/security**: the app only reads local logins (Keychain item `Claude Code-credentials`, `~/.codex/auth.json`) read-only. Never log, store, print or commit tokens. Don't add new network destinations without asking.
- **Unverified endpoints**: the Codex usage endpoint and the JWT renewal claim are unverified. Keep parsing defensive (missing fields must hide UI, not crash).
- **Persisted settings** live in `UserDefaults`. When changing a setting, migrate the old value so users keep their config (see `purchaseDate` in `Store.swift`).
- **Rate limits**: don't add polling that bypasses the existing refresh interval and backoff in `Store.swift`.
- **UI**: colours are defined at the top of `TokenBarApp.swift` (`ember` for Claude, `mint` for Codex, `deepYellow` for renewal). Reuse them.

## Releasing (only when asked)

1. Bump `VERSION` (semver) and update version references in `README.md` (badge, download link, file names).
2. Run tests, then `./build.sh`.
3. Commit, tag `vX.Y.Z`, push, and create a GitHub release attaching the `.dmg` and `.zip` from `build/`. Ask before pushing or publishing.
