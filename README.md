# 66 Days

A native macOS sticky note on your desktop for building small daily habits: a month calendar, "never miss twice" streaks, and a 66-day journey per habit.

## Requirements

- macOS 26, Xcode 26

## Project layout

| Path | What's there |
|---|---|
| `App/` | The macOS app target (windows, app lifecycle) |
| `Packages/Core` | The habit rules as pure Swift (no UI, no database) |
| `Packages/Persistence` | SQLiteData storage, migrations and queries |
| `Packages/UI` | Shared SwiftUI components, color tokens and bundled fonts |
| `Config/` | Entitlements (the app is sandboxed) |
| `scripts/` | Maintenance scripts (font subsetting) |

## Build and test

```sh
# App build + every package's tests (what CI runs)
xcodebuild test -project 66Days.xcodeproj -scheme "66 Days" -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData -skipMacroValidation

# One package, faster
swift test --package-path Packages/Core
```

Opening the project in Xcode the first time asks you to trust SQLiteData's macros ("Trust & Enable").

## Fonts

Shippori Mincho, Zen Kaku Gothic New and Klee One (SIL OFL 1.1), subset to Latin by `scripts/subset-fonts.sh`. Licenses are next to the font files in `Packages/UI/Sources/UI/Resources/Fonts`.
