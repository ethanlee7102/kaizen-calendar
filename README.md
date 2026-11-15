# 66 Days

A native macOS sticky note on your desktop for building small daily habits: a month calendar, "never miss twice" streaks, and a 66-day journey per habit.

## Requirements

- macOS 26, Xcode 26

## Project layout

| Path | What's there |
|---|---|
| `App/` | The macOS app target (app life cycle, menus, wiring) |
| `Packages/Core` | The habit rules as pure Swift (no UI, no database) |
| `Packages/Persistence` | SQLiteData storage, migrations and queries |
| `Packages/UI` | Shared SwiftUI components, color tokens and bundled fonts |
| `Packages/AppShell` | macOS only: the desktop sticky-note window, its saved positions, day-change monitoring, open at login |
| `AppUITests/` | XCUITest tests of the window behavior (they take over the mouse and keyboard while running) |
| `Config/` | Entitlements (the app is sandboxed) |
| `scripts/` | Maintenance scripts (font subsetting) |

## Build and test

```sh
# App build + every package's tests + UI tests (what CI runs). The UI tests take over the
# mouse and keyboard for a few minutes and hide other apps meanwhile (if a run is aborted,
# use Show All in any app menu); add -skip-testing:AppUITests to leave them out.
xcodebuild test -project 66Days.xcodeproj -scheme "66 Days" -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData -skipMacroValidation

# One package, faster
swift test --package-path Packages/Core
```

Opening the project in Xcode the first time asks you to trust SQLiteData's macros ("Trust & Enable").

## Fonts

Shippori Mincho, Zen Kaku Gothic New and Klee One (SIL OFL 1.1), subset to Latin by `scripts/subset-fonts.sh`. Licenses are next to the font files in `Packages/UI/Sources/UI/Resources/Fonts`.
