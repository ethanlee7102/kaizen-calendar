# Desktop window prototype (throwaway)

Checks whether a desktop-level "sticky note" window can behave the way 66 Days needs. This is not production code.

## Run

```sh
./make-app.sh
```

- A note appears on the desktop, and **66** appears in the menu bar.
- The menu bar menu switches the window level and collection behavior live.
- Every event is logged to `~/Library/Logs/66DaysPrototype.log`; the expanded note also shows the log.
- Before each test, use **Add Test Marker…** so the log says what was being tested.

## Outcome (2026-11-09)

The real app will use **one-desktop mode**: Spaces = none, Mission Control = stationary, flag = ignoresCycle, level = desktop icons + 1.
- **Why:** `canJoinAllSpaces` makes the note blink in after swiping back from a full-screen app. Desktop-level windows are never placed on full-screen Spaces.
- **Ruled out:** the follow-you trick, Auto desktop detection, private CGS APIs and wallpaper level (can't be clicked).
- **Expanded mode:** normal level, `[.managed, .fullScreenNone]`, auto-collapses when the active Space changes.

## Default config (the starting guess)

- Level: desktop icons + 1
- Spaces: canJoinAllSpaces
- Mission Control: stationary
- Flags: ignoresCycle

## Test checklist

| # | Test | Want |
|---|---|---|
| 1 | Drag the note around | Moves freely |
| 2 | Click a checkbox while another app is focused | Toggles, without stealing focus or needing a second click |
| 3 | Open app windows over it | The note stays behind them |
| 4 | Click the wallpaper (Settings → Desktop & Dock → "Click wallpaper to reveal desktop" = Always) | The note stays put and visible |
| 5 | Show Desktop (F11 / trackpad spread) | The note stays visible |
| 6 | Switch desktops (Ctrl+←/→) | Same spot on every desktop |
| 7 | Mission Control | Not shown as a window to arrange |
| 8 | Stage Manager on | Stays on the desktop; not a thumbnail on the side |
| 9 | Full-screen app | The note isn't drawn over it |
| 10 | Expand / Collapse | Expands in front and focused; collapses back to its saved spot at desktop level |
| 11 | Drag to the external monitor, then quit and relaunch | Comes back on the external monitor |
| 12 | Unplug the external monitor | Moves to the laptop screen, same corner, fully visible |
| 13 | Replug the monitor | Returns to its spot on the external monitor |
| 14 | Change resolution / display arrangement | Keeps its corner, never off-screen |
| 15 | Reboot / log out and back in | (Launch at login comes later; just check the saved position) |

If a row fails, try other levels and behaviors from the menu and note which combination works.
