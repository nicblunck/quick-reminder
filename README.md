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

## Widgets and filters

Quick Reminders also *reads*. **Settings ▸ Filters** builds named, coloured queries
over the Reminders database, and each one can be dropped on the desktop or in
Notification Center as a Small, Medium or Large widget.

A filter is a tree of conditions rather than a fixed set of toggles, so `all`,
`any` and `none` groups nest freely:

| Filter | Conditions | Matches |
| --- | --- | --- |
| Work Today | `all`: due on or before **0** days, list is any of *Work* | today plus anything overdue |
| Work This Week | `all`: due on or after **1**, due on or before **7**, list is any of *Work* | the coming week, today excluded |
| Later | `any`: due on or after **8**, due date is not set | everything further out, plus undated |

That third one is why the tree exists — "beyond the week **or** with no deadline at
all" has no expression as a flat list of ANDed rules.

Conditions read due date, start date, list, priority, title, notes, completion and
repeat. Dates are relative (`0` = today, `1` = tomorrow, `-1` = yesterday), so the
filters keep meaning the same thing tomorrow. Two deliberate defaults:

* An **empty list selection constrains nothing**. The seeded filters ship that way
  until you pick your work lists, so a fresh install shows everything rather than
  nothing.
* **Completed reminders are hidden** unless a rule mentions completion explicitly.

Each filter carries a name, an SF Symbol and a tint, and the editor previews live
counts against your real reminders as you type.

On the widget itself, tapping a circle completes the reminder in place, and the **+**
in the corner opens the quick entry panel. The add button can be turned off per
filter, or per widget in the widget's own configuration.

### How the two processes share

The app is not sandboxed; a widget extension always is. Everything they share
travels through the App Group
`U4K77TMBRU.group.com.nicolasblunck.QuickReminders` — the team prefix is
required, and an unprefixed `group.` name silently yields a nil container.

**The widget never touches EventKit.** It cannot: a sandboxed extension holds no
Reminders grant of its own, and a widget has no way to show a TCC prompt, so its
XPC connection to the Reminders daemon is refused outright:

```
[com.apple.eventkit:EventKit] Error loading access: Error Domain=NSMachErrorDomain Code=4099
[com.apple.reminderkit:xpc] XPC connection was invalidated
```

That is the same Mach 4099 the ad-hoc signing note in `project.yml` describes,
reached by a different route — here the signature is fine and the grant is what
is missing. It is not fixable from inside the extension.

So the app does the work. `WidgetSnapshotPublisher` fetches once, evaluates every
filter against that one fetch, and writes the results to `snapshot.json` in the
group container; the widget's timeline provider only reads that file. The app
republishes on launch, whenever a filter changes, and on `EKEventStoreChanged`,
each debounced. A widget shows "Waiting for Quick Reminders" if the app has never
published, and notes the age of its rows once a snapshot goes stale.

Completing a reminder from a widget goes the same way round. The extension cannot
write to EventKit either, so `CompleteTaskIntent` appends to
`inbox/pending-completions.json` and the app — watching that directory with a
`DispatchSource` — applies it and republishes. The round trip is invisible in
practice, and nothing steals focus.

Two traps worth keeping in mind, both of which cost real time here:

* **Watch the inbox, not the container.** The publisher's own `snapshot.json`
  write lands in the container root. Watching the root means the app republishes
  in response to its own output — a loop that ran at ~860 reloads and ~1700
  EventKit fetches per two minutes before it was caught.
* **Storage is plain files, not `UserDefaults(suiteName:)`.** A shared suite is
  the obvious choice and it does not work: cfprefsd refuses the group domain with
  *"Using kCFPreferencesAnyUser with a container is only allowed for System
  Containers"* and detaches, making reads unreliable in the extension.

`ReminderQuery`'s read path is `nonisolated` throughout. EventKit calls a fetch's
completion on its own queue, and inside a `@MainActor` type that closure inherits
main-actor isolation — which trips libdispatch's queue assertion and kills the
process with *"Block was expected to execute on queue [com.apple.main-thread]"*.

Signing matters more than usual here. Both `Scripts/install.sh` and
`Scripts/release.sh` re-sign after building, and a re-sign without
`--entitlements` silently strips the sandbox and App Group from the widget —
which, from the desktop, looks exactly like a widget that never loads.

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

It also renders the widgets, at all three macOS widget sizes, and the filter
editor. Two caveats specific to those: `widgetFamily` is read-only in the
environment, so `FilterWidgetView` takes a `familyOverride` the tool sets instead;
and `containerBackground(for: .widget)` is inert outside a real widget host, so the
tool paints the card's fill and corner radius itself. What the tool cannot tell you
is whether the extension can reach EventKit at runtime — that only shows up once a
widget is actually on the desktop.

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
