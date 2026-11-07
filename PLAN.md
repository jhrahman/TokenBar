# TokenBar — Plan (simple version)

A tiny macOS menu bar app that shows your **Claude** and **Codex** usage (session % + weekly %, and when they reset).

**Rules to keep it simple:** one small Swift app, no dependencies, no database, no notifications, no charts, no auto-updater. If a feature isn't listed below, it's not in v1.

---

## What it does

1. Menu bar icon (two usage bars). Click it → small popover with two rows:
   - **Claude:** 5h % · weekly % · reset info (format below)
   - **Codex:** 5h % · weekly % · reset info (format below)

   **Reset text format**
   - **5h window** → relative countdown:
     - 1 hour or more: `5h · 42% · resetting in 1.3h` (one decimal)
     - under 1 hour: `5h · 42% · resetting in 30 min`
     - under 1 minute: `resetting in <1 min`
   - **Weekly window** → exact date and time, 12-hour clock:
     - `Weekly · 18% · resetting Mon, 26 Nov, 10 PM`
     - Show minutes only when non-zero, e.g. `10:30 PM`.
   - **Time zone:** always the Mac's current time zone, never UTC. Use `TimeZone.current`, so it follows you if you travel.
   - **Implementation (≈10 lines):** weekly uses a `DateFormatter` with `dateFormat = "EEE, d MMM, h a"` (switch to `"EEE, d MMM, h:mm a"` when minutes ≠ 0) and `locale = en_US_POSIX` so it stays 12-hour even if the Mac is set to 24-hour. 5h uses `resetsAt.timeIntervalSinceNow`.
   - The 5h countdown refreshes every minute while the popover is open, even between data fetches (it's computed from the stored reset time, no network needed).
   - If the reset time is missing or already passed: show `reset time unavailable` / `resetting now` and trigger a refresh.
   **On/Off toggle (in the popover itself):** a switch at the top of the popover, so one click on the menu bar icon, then one click on the switch, enables or disables TokenBar. No need to open Settings.
   - **Off (paused):** no polling, no network requests, no credential reads (so no Keychain prompts either). The popover shows only the toggle, "TokenBar is off", plus Settings and Quit. The menu bar icon switches to a dimmed, empty-bars version (same template image at lower opacity, no percentages).
   - **On:** refreshes immediately, then resumes the normal timer.
   - The state is saved in `UserDefaults` (`isEnabled`) and survives restarts and login. Default is On.
   - Stored data is cleared when turned off, so stale numbers are never shown after turning it back on.
   - Keyboard: ⌘E toggles while the popover is open. Optional: right-click the menu bar icon for a small menu with `Turn Off / Turn On`, `Settings…`, `Quit`.
   - Implementation: a `@AppStorage("isEnabled")` bool; the timer in `Usage.swift` starts and stops on change (about 10 lines).
2. **Settings** (dark ash glass window) with only:
   - Launch at login (on/off)
   - **Monitor Claude** (on/off) and **Monitor Codex** (on/off). Any combination works: both, only one, or neither.
     - **Dynamic:** changes apply instantly, no restart and no "Apply" button.
     - **Popover:** shows only the enabled providers' rows. If only one is on, only that row appears (and the popover gets shorter). Turning one back on adds its row and fetches right away.
     - **Menu bar icon:** adapts to what's on: both on → two bars; Claude only → one ember bar; Codex only → one mint bar. Same dynamic redraw.
     - **Disabled provider:** no polling, no network requests, no credential/Keychain reads for it, and its cached numbers are cleared.
     - **Neither on:** behaves like the master switch is off (dimmed icon, "Nothing to monitor, turn on Claude or Codex in Settings").
     - **Master switch vs. per-provider:** the popover On/Off switch pauses everything but keeps these choices; turning it back on restores exactly the same set.
     - **Provider setup:** each provider's Source picker and Connect button stay visible in Settings but grayed out while that provider is disabled.
     - **First run:** a provider is auto-enabled only if its local app/login is detected; otherwise both start on and show "Not logged in" so the user can connect.
     - Stored as `UserDefaults` keys `monitorClaude` / `monitorCodex`.
   - For each provider: **Source** = *Local app* or *Browser sign-in*, plus a Connect / Sign out button
   - Refresh interval (1 / 5 / 15 min)
3. Runs on Apple Silicon and Intel (universal binary), macOS 13+.

---

## Tech (minimal)

- **Swift + SwiftUI**, `MenuBarExtra` for the popover. No Dock icon (`LSUIElement`).
- **Swift Package Manager**, not Xcode project files. Easy to edit and build from VS Code + Claude Code:
  - Build universal: `swift build -c release --arch arm64 --arch x86_64`
  - A ~20-line `build.sh` wraps the binary into `TokenBar.app` (adds `Info.plist` + icon).
  - Check: `lipo -archs` should show `x86_64 arm64`.
- **Launch at login:** `SMAppService.mainApp.register()` / `.unregister()` — one toggle.
- **Settings glass look:** `NSVisualEffectView` (dark) + ash tint `#1C1D21` at ~60%, 1px white 10% border, 18px corners. If Reduce Transparency is on, use solid ash.
- **Storage:** preferences in `UserDefaults`; tokens only in Keychain.
- Polling on a timer (default 5 min) plus a refresh when the popover opens. Target: ~0% idle CPU, <30 MB RAM.

### Code layout (7 small files)

```
Package.swift
Sources/TokenBar/
  TokenBarApp.swift     # menu bar item + popover
  SettingsView.swift    # glass settings window
  Usage.swift           # UsageSnapshot model + store + timer
  OAuth.swift           # PKCE browser sign-in + token refresh (both providers)
  ClaudeSource.swift    # fetch Claude usage (local app / browser)
  CodexSource.swift     # fetch Codex usage (local app / browser)
  Keychain.swift        # tiny read/write helper
build.sh
```

---

## The two connection options (kept, but simple)

**Local app (default if detected, no browser step):** read the login the official tool already saved.
- Claude: Claude Code's login in the macOS Keychain.
- Codex: `~/.codex/auth.json` (fallback: the rate-limit info Codex writes into `~/.codex/sessions/`).
- Then ask the provider's usage endpoint for the numbers.
- Never refresh or modify those tokens (could log you out of the official app). If expired, show "Open Claude/Codex once".

**Browser sign-in (for users without the Claude/Codex app installed):** TokenBar does its own OAuth login with PKCE, no CLI needed.
- Click Connect → default browser opens the provider's sign-in page → TokenBar catches the redirect on a temporary `127.0.0.1` port (small `NWListener`, closed right after) → exchanges the code for tokens.
- Tokens are stored in TokenBar's own Keychain item (`TokenBar-claude`, `TokenBar-codex`).
- Because these tokens belong to TokenBar (not the official app), TokenBar **may refresh them** itself when they expire. Sign out deletes them.
- Source picker: *Local app* (read-only, never refreshed) or *Browser sign-in* (own tokens, refreshed). Default is Local app if detected, otherwise Browser sign-in.
- **Status: ON HOLD.** Browser sign-in needs an OAuth client ID registered for TokenBar. The only public ones belong to the official Claude Code / Codex CLIs, and reusing them means impersonating another vendor's app (ToS risk, can be blocked). We do **not** do that. It ships only once a legitimate route exists: our own registered client from Anthropic/OpenAI, or a provider-sanctioned usage API. Until then v1 = Local app source only, and Settings shows Browser sign-in as "Coming soon".

⚠️ The usage endpoints and file locations are **unofficial and may change**. Step 1 below confirms them on your Mac before building any UI.

---

## Icon & logo

- **Menu bar:** two stacked pill bars, monochrome template image (`menubar-icon.svg`). The icon is drawn in code from the enabled providers, so it shows two bars, or one when only Claude or only Codex is on. When TokenBar is turned off, the icon shows at ~40% opacity with empty tracks so you can tell at a glance.
- **App logo:** the same two bars (ember + mint) on a dark ash glass tile (`logo.svg`).

---

## Build steps (4)

1. **Spike (½ day):** a command-line script that prints real Claude + Codex usage from your Mac. Confirms endpoints and JSON shape (including the exact reset timestamp fields for 5h and weekly). Save sample responses as test fixtures. Add a tiny unit test for which providers are polled given the on/off combinations. Add a tiny unit test for the reset-text formatting (e.g. 78 min → `1.3h`, 30 min → `30 min`, weekly → `Mon, 26 Nov, 10 PM`).
2. **Menu bar + popover (½–1 day):** icon, popover with two rows, live data, simple error text ("Not logged in", "Open Claude once", "Offline").
3. **Settings (1 day):** glass window, launch at login, source picker, refresh interval.
4. **Package (½ day):** `build.sh` → universal `.app`, icon, zip. Test on Apple Silicon and Intel (or Rosetta). Notarization only if you want to share it publicly.

Total: about 3 days.

---

## First prompt for Claude Code

> Read `PLAN.md`. Do **step 1 only**: write a small Swift command-line tool (Swift Package) that finds my local Claude Code and Codex logins, calls their usage endpoints, and prints session % and weekly % with reset times for each. Don't build any UI yet. Save sample JSON responses to `Tests/fixtures/`. Tell me what you found about the endpoints before continuing.
