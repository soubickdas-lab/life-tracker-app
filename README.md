# 📱 Life Tracker — Mac & iPhone app

A native SwiftUI front end for the Life Tracker Google Sheet. One codebase, two platforms.
The sheet stays the brain: Calendar sync, WhatsApp updates, the Telegram bot and Siri all keep working exactly as they do now.

## How it talks to the sheet

The Apps Script web app gained a small JSON API (`?key=…&api=…`). Every call answers with the
**whole fresh state**, so the app never drifts out of step:

| api | does |
|---|---|
| `state` | yesterday / today / tomorrow with their tasks, the habits with streaks, last weight, last 10 notes |
| `add` | one line of plain language — the same parser Siri and Telegram use (`gym at 7 pm`, `remove gym`, `kitna baaki`) |
| `toggle` | tick / untick a task by id |
| `delete` | remove a task (a 🔁 copy stays gone for that day) |
| `rename` | rename a task |
| `move` | `move` a task to a new time or day |
| `habit` | tick / untick today's habit |
| `weight` | log today's weight |
| `note` | add to the 🗒️ Notes tab |

## The app — the sheet, screen for screen

Every tab is drawn the way the sheet draws it: a coloured banner, the same column headers, striped rows,
and empty rows at the bottom you can type straight into. Typing a name in an empty row adds that task;
clearing a name deletes it; typing in TIME SLOT moves it; the ✓ and 🔁 boxes behave like the sheet's.
⌘1…⌘7 switch tabs, ⌘R refreshes.


Every tab of the sheet has a screen here — the sheet never needs to be opened.


- **Day screen** — progress ring, Yesterday / Today / Tomorrow switch, tasks with their time,
  `🔁 daily` and `carried over` chips, tick to complete, double-click to rename, right-click (or swipe on iPhone) for delete / move.
- **Compose bar** — type the way you text the bot; the reply comes back as a toast.
- **Habits** — tappable chips with the streak on each.
- **Notes screen** — weight box and the notes list.
- **Plan** — 🗓️ Scheduled (book anything for a future date with an optional time) and 🎯 Long Term (status, % done, target date).
- **Body** — weight, waist, chest, arm, body fat and a note per day, with the history underneath; tap a row to edit that day.
- **Setup** — every ⚙️ Setup switch and value (mail hours, reminder lead, WhatsApp, Telegram, hourly list…), the habit list (add / rename target / turn off / delete), the categories, and the 🧾 Log.
- **Settings** — the web app link and key, kept in this device's UserDefaults and sent only to your own web app.

## Reminders

Every time the sheet answers, the app re-plans local notifications for today's timed, unfinished tasks —
one alert **N minutes before** each, where N is the sheet's own "Remind me N min before a task" setting.
Permission is asked once on first launch. This is on top of the WhatsApp reminders, and works with the app closed.

## Building

```bash
# once per Xcode install, needs your password
sudo xcodebuild -license accept

# Mac
xcodebuild -project LifeTracker.xcodeproj -scheme LifeTracker -destination 'platform=macOS' build

# iPhone simulator
xcodebuild -project LifeTracker.xcodeproj -scheme LifeTracker -destination 'platform=iOS Simulator,name=iPhone 17' build
```

For a real iPhone: open the project in Xcode, pick your device, set a team under Signing, then
re-sign through SideStore the way the other sideloaded apps are handled (free accounts expire after 7 days).

## Putting it on the iPhone

The repo carries a ready, unsigned build — SideStore signs it on the phone.

**Once:** SideStore ▸ Sources ▸ **+** ▸ paste

```
https://raw.githubusercontent.com/soubickdas-lab/life-tracker-app/main/dist/source.json
```

Life Tracker then shows up under that source; tap Install. Every later version arrives
in the same place — no cable, no re-export.

Or skip the source entirely and hand SideStore the file:
[dist/LifeTracker.ipa](dist/LifeTracker.ipa).

**Shipping an update** — one command, from anywhere:

```bash
./scripts/ship.sh 1.1
```

It writes the new number into `VERSION` (both builds read that one file), rebuilds the IPA,
refreshes `dist/`, commits and pushes. Leave the number off to re-ship the current version;
it will warn you, because SideStore only offers an update when the number changes.

The script exports `DEVELOPER_DIR` itself — without that, plain `git` goes through Xcode
and stops to ask for a licence that has never been accepted on this Mac.

## Building without Xcode's licence

`sudo xcodebuild -license accept` has never been run on this Mac, so `xcrun`, `xcodebuild`
and the simulator tooling all refuse. Both build scripts sidestep that by calling the
toolchain directly: `swiftc` from `XcodeDefault.xctoolchain` with an explicit `-sdk`, and
`Contents/Developer/usr/bin/simctl` for the simulator. Nothing else is needed.
