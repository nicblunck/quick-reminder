# Quick Reminders

A menu bar utility for capturing Apple Reminders from a keyboard shortcut, without
opening Reminders.app.

Press **⌥Space**, type `call dentist tomorrow 5pm !!`, press **⌘↩**. Done.

## Build and run

The Xcode project is generated from `project.yml`:

```bash
xcodegen generate && xcodebuild build -project QuickReminders.xcodeproj -scheme QuickReminders -destination 'platform=macOS'
```

Run the tests:

```bash
xcodebuild test -project QuickReminders.xcodeproj -scheme QuickReminders -destination 'platform=macOS'
```

## What it captures

| Field | Supported | How |
|---|---|---|
| Title | ✅ | typed |
| List | ✅ | dropdown in the header |
| Due date / time | ✅ | natural language, or the date pill |
| Priority | ✅ | `!` / `!!` / `!!!`, or ⌘1 / ⌘2 / ⌘3 |
| Notes | ✅ | its own field, always visible |
| **Tags** | ❌ | no EventKit API — see below |
| **Flag** | ❌ | no EventKit API — see below |
| **Image attachments** | ❌ | no EventKit API — see below |
| **List icon** | ⚠️ | EventKit gives a list's name and colour but not its icon, so the glyph is generic and only the colour is real |

### Why tags, flag and images are missing

`EKReminder` exposes only title, notes, URL, priority, calendar, start/due date and
alarms. Tags, the flag and attachments have **no public EventKit API** at all. They
are reachable only through the Shortcuts "Add New Reminder" action, or the private
`ReminderKit` framework.

`#hashtags` typed into the field are deliberately **left in the title as plain text**
rather than silently dropped. They are searchable, but they are not real Reminders tags.

To add these later, write a second conformance to the `ReminderWriter` protocol
(`Services/ReminderWriter.swift`) that routes a `ReminderDraft` through a
user-installed Shortcut. Nothing above that protocol needs to change.

## Menu bar item

- **Click** — open quick entry
- **Right-click** (or ⌃-click) — Settings… and Quit

## The bottom toolbar

- **Calendar** — one popover holding both the shortcuts (Today, Tomorrow, Next
  Week, Next Month) and a full month grid, plus Remove Date. The grid is custom:
  `NSDatePicker` stops growing at roughly font 18, so a calendar at this size
  cannot be had from the system control. Weekday order, weekday names and month
  names still come from `Calendar` and `FormatStyle`.
- **Clock** — a popover mirroring the date one: the three shortcuts, then every
  quarter hour in a scrollable list that opens at the current value, plus Remove
  Time. Once a time is set the clock gains
  **−** and **+** either side inside a pill: each press steps an hour, **⇧-click**
  steps 30 minutes. Times are rendered with the system's short time style, so they
  follow your locale and your 24-Hour Time setting.
- **!!!** — priority: click to cycle none → ! → !! → !!! → none.

The **pin** beside the close button keeps the panel open when you switch to another
app, for when you need to go and look something up mid-capture. Esc, the close
button, the hotkey and a successful save all still close it.

Date and time are separate chips. A time on its own implies today; removing the date
chip removes the time with it, because a time alone cannot be stored.

## Natural language

Parsed against the moment you type, and always shown as a chip before saving so a
misparse is visible rather than silent. Dismissing a date chip puts the words back
into the title.

- **Days** — `today`, `tonight`, `tomorrow` / `tmrw`, `eod`, `next week`, `next month`
- **Weekdays** — `friday` (the coming one; today if today is Friday), `next friday` (a week later)
- **Offsets** — `in 30 minutes`, `in 2 hours`, `in 3 days`, `in 2 weeks`
- **Times** — `5pm`, `5:30pm`, `17:30`, `at 5` (picks the reading still ahead of now), `noon`, `midnight`
- **Absolute** — `August 20`, `12/3` (via `NSDataDetector`)
- **Priority** — `!` low, `!!` medium, `!!!` high

A day with no time is saved at the default time set in Settings (9:00 by default).

## Keyboard

| Key | Action |
|---|---|
| ⌥Space | Open / close the panel (rebindable in Settings) |
| ⌘↩ | Add reminder (Settings can make plain ↩ do it too; ⇧↩ then makes a new line) |
| Esc | Dismiss, discarding the draft |
| ⌘1 / ⌘2 / ⌘3 | High / medium / low priority |

## URL scheme

For Raycast, Alfred, Shortcuts or scripts:

```
quickreminders://new?text=call+dentist+tomorrow+5pm   # opens the panel, pre-filled
quickreminders://add?text=call+dentist+tomorrow+5pm   # saves immediately, no UI
```

A failed silent add falls back to opening the panel with the text intact, so nothing
typed is ever lost.

## Installing locally

Day to day, build and install straight into `/Applications`:

```bash
Scripts/install.sh
```

Run it again to update — it quits the running copy, replaces the bundle, and
leaves nothing behind. It signs with Developer ID but does not notarize, which
is fine for an app built on the machine that runs it: Gatekeeper only
quarantines things that arrive from elsewhere.

The stable signature is the real reason to install rather than run from
DerivedData. TCC keys the Reminders permission to an app's code signature, so an
ad-hoc build is a brand new app every time and has to be re-authorised on every
rebuild; a Developer ID signed build is granted once.

**Only ever run one copy.** Two bundles with the same identifier — say an
installed one and a DerivedData one — both put an item in the menu bar and both
register the global hotkey, and which one answers is arbitrary. `install.sh`
deletes its own build output for that reason. Launch by path
(`open /Applications/QuickReminders.app`), not by bundle id, since
LaunchServices resolves an id to whichever copy it happens to prefer.

## Releasing an update

Auto-updates use [Sparkle](https://sparkle-project.org). The app checks
`appcast.xml` in this repo; builds are attached to GitHub Releases.

**Not yet live.** No release has been published, so `appcast.xml` does not exist
and "Check for Updates…" will report an error. Until then, update with
`Scripts/install.sh` above.

```bash
Scripts/release.sh 1.1
```

That builds Release, signs with Developer ID, notarizes, staples, and rewrites
`appcast.xml`. It deliberately stops before publishing — it prints the two
commands to create the GitHub Release and push the appcast, so nothing goes out
by accident. **Create the release before pushing `appcast.xml`**, or Sparkle
will advertise a download that 404s.

One-time setup, which you must do yourself because it stores a password:

```bash
xcrun notarytool store-credentials "QuickReminders"
```

Passing no arguments makes notarytool prompt for the Apple ID, team ID and
app-specific password, with the password hidden. The `--password` flag works too
but writes the secret into shell history. The team is `U4K77TMBRU`, and the
password is an app-specific one generated at account.apple.com — not the Apple
ID password itself.

Note the Developer ID certificate belongs to team `U4K77TMBRU` (TIMO BLUNCK), so
notarization has to be submitted by an Apple ID that belongs to that team.

The Sparkle EdDSA signing key already lives in the login keychain. **Back it
up.** Losing it means existing installs will reject every future update, since
they verify against the public key baked into the app they are already running,
and the only fix is for each user to reinstall by hand.

Signing matters more than usual here: Sparkle installs an update by replacing
the app bundle, so an ad-hoc signed build would trip Gatekeeper and would also
lose its Reminders permission on every update, TCC treating each build as a new
app.

## Checking the UI without a window

`SnapshotTool` renders views to PNGs entirely offscreen. It sets the activation
policy to `.prohibited`, so nothing ever appears over what you are doing:

```bash
xcodebuild build -project QuickReminders.xcodeproj -scheme SnapshotTool -destination 'platform=macOS' -derivedDataPath build
./build/Build/Products/Debug/SnapshotTool   # writes to /tmp/qr-snapshots
```

It uses `NSHostingView` rather than SwiftUI's `ImageRenderer`, because AppKit-backed
controls like `Menu` only draw their real chrome in a live view tree — which is
exactly what you need to see when debugging a control's appearance.

## Notes on the build

**The app is deliberately not sandboxed.** With App Sandbox enabled and an ad-hoc
signature, `requestFullAccessToReminders()` fails with `NSMachErrorDomain 4099` — the
XPC connection to the Reminders daemon is refused and the permission prompt never
appears. Turning the sandbox off resolves it. Sandboxing would only be needed for Mac
App Store distribution, which would also require the Shortcuts path for tags anyway.

**The permission prompt reappears after a rebuild.** An ad-hoc signature changes on
every build, so TCC treats each build as a new app. Install a stable copy into
`/Applications` and grant it once; it will persist until you rebuild over it.

**The window is Liquid Glass, so the deployment target is macOS 26.** The
`glassEffect` API does not exist before Tahoe.

**The panel's entrance animates position only, never opacity.** Every frame of a
window `alphaValue` change makes the Liquid Glass material re-sample its backdrop,
which reads as flicker. Travel and easing carry the motion instead. For the same
reason there is no scale: AppKit cannot scale a window, and scaling in SwiftUI
needs a transparent margin around the card — which exposes the window's own frame
as an outline and leaves the shadow's alpha mask ambiguous.

**The panel dismisses on app deactivation, not on losing key focus.** Menus,
popovers (the graphical date picker) and notification banners all steal key status
without deactivating the app; tearing the panel down for any of those would discard
whatever had been typed.

**Reminders that are due actually fire.** A `dueDateComponents` value alone never
notifies — `RemindersService` also attaches an `EKAlarm` at the due date.
