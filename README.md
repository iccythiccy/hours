# Hours

A home-screen app for logging work hours and texting them to a client in one tap.

**Live app:** https://iccythiccy.github.io/hours/

The text it writes looks like this:

```
11/10 9am-6:15pm (12:10pm-12:47pm break) 8hrs 38min
18hrs 38min total for the week.
```

## Install (iPhone)

1. Open the link above in **Safari** (not Chrome).
2. Tap **Share → Add to Home Screen → Add**.
3. Open it from the icon, tap the gear, and enter the client's name and mobile number.

On Android: open in Chrome, then **⋮ → Add to Home screen**.

## Daily use

- **Start → Now** when you arrive (kept even if you close the app), **End → Now** when you leave.
- Or tap any time to set it on Apple's time wheel. Times are exact to the minute.
- **+ Add** an unpaid break (up to two). Break times appear in the text and are subtracted from the totals.
- **Text** opens Messages to your client with the hours typed in. You still tap Send — no iPhone app can send a text for you.
- Back in the app, answer **Did your text go out?** with **Sent** or **Not sent**. Only **Sent** counts. (iPhone never tells a web app whether a text was sent, so the app asks.)

## What it does for you

| Feature | Behavior |
|---|---|
| Weekly total | Adds up Mon–Sun and resets every Monday. |
| Missed days | Weekdays with nothing logged show orange "Not logged" until you log them or mark them as a day off. |
| Blocked until fixed | Text and Copy stay off while: the end time is still the app's guess (tap **Now** or set it), a break has placeholder times, a break falls outside work hours, breaks overlap, or start and end are the same. |
| One-tap confirm | An overnight shift or a day over 13 hours is allowed after **Yes, that's right**. |
| Sent tracking | ✓ = sent (confirmed). ● = changed since sent. **Mark as not sent** undoes a wrong confirmation. |
| Corrections | If you change a day you already sent, the next text adds a `Correction:` line. If you've already sent today, **Text fix** sends a correction with the updated week total. A day logged after a later day was sent goes out as a correction too. Corrections compare the actual hours, not the wording, so changing settings never triggers one. |
| Deleting a sent day | Kept as "Removed · not sent yet" until you send `Correction: 11/9 removed`, so your client is never left with hours that no longer exist. **Bring this day back** restores it. |
| Day off | Counts as 0 hours, clears the missed-day warning, and isn't texted. |
| Undo | Any change to a day you'd already logged (including delete and day off) shows **Undo** for 5 seconds. |
| Week arrows | ‹ › next to the week label move between weeks. |
| Copy week | Copies every day plus the total as one message (for invoices or check-ins). |
| Backup | Settings → **Copy backup** / **Restore**. |

## Where the data lives

Everything is stored **on the phone**, inside the home-screen app (browser localStorage). No server, no account, nothing sent anywhere except the texts you send yourself.

- Each person who installs it has their own separate data.
- Deleting the home-screen icon or clearing Safari website data can erase it. Use **Copy backup** before reinstalling.
- The text thread with your client is also a complete record of past hours.

## How updates work

- The app is `index.html` (screen) + `core.js` (all hours math, text wording, corrections, validation, backup — no screen code), plus `sw.js` (offline support), `manifest.webmanifest` and icons, served by GitHub Pages from `main`.
- Pushing to `main` updates the live app within about a minute. Phones pick up the change the next time the app opens with a signal (the service worker loads the network first).
- When releasing: bump `VERSION`/`UPDATED` in `index.html` (shown at the bottom of Settings), and bump the cache name in `sw.js`.
- Saved data is backward compatible: older entry formats (duration-only breaks, single `bStart`/`bEnd` breaks) still load, and older "texted" records (stored as text before Nov 11, 2026) are converted to data on first open.

## Tests

Run both before every push; don't push if either fails.

```
node --test tests/core.test.js      # 27 work-week scenarios against core.js (Node 18+)
python3 tests/ui_test.py            # taps through the real screen in headless Chrome (needs playwright)
```

Covered: exact format, breaks, overnight shifts, week boundaries, blockers and confirms, nothing counting as sent until confirmed, corrections before/after the day's text, late-added and skipped days, deleting sent and unsent days, day off, settings changes not causing false corrections, migration of older saves, backup round trip.
- Changing the icon: replace `icon-180/192/512.png` and bump the `?v=` on the icon links. iPhones only pick up a new icon when the app is removed and added to the home screen again.

## Decisions

- **A web app, not a native one (for now).** A native iPhone app would add a lock-screen widget, reminders, iCloud backup and Siri, but costs $99/yr (Apple Developer Program, which covers unlimited apps) plus build/signing upkeep. Revisit if lock-screen clock-in becomes worth it.
- **Apple's own time wheel**, not a custom one, because it's the only way to get real haptics in a web app.
- **Exact times**, no rounding. Whole hours always show minutes (`1hr 0min`, `9hrs 0min`); under an hour shows `45min`.
- **No backup reminders.** The text thread is the fallback record.
- **Daily reminder:** done with an iPhone Shortcuts automation (Time of Day → Show Notification), not built into the app.
