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

## What it does for you

| Feature | Behavior |
|---|---|
| Weekly total | Adds up Mon–Sun and resets every Monday. |
| Missed days | Weekdays with nothing logged show orange "Not logged" until you log them or mark them as a day off. |
| AM/PM check | Warns if a day crosses midnight or runs over 13 hours, or if a break falls outside work hours or two breaks overlap. |
| Texted tracking | ✓ = texted. ● = changed since texted. |
| Corrections | If you change a day you already texted, the next text adds a `Correction:` line. If you've already texted today, **Text fix** sends a correction with the updated week total. A day logged late is sent as a correction too. |
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

- The whole app is `index.html`, plus `sw.js` (offline support), `manifest.webmanifest` and icons, served by GitHub Pages from `main`.
- Pushing to `main` updates the live app within about a minute. Phones pick up the change the next time the app opens with a signal (the service worker loads the network first).
- When releasing: bump `VERSION`/`UPDATED` in `index.html` (shown at the bottom of Settings), and bump the cache name in `sw.js`.
- Saved data is backward compatible: older entry formats (duration-only breaks, single `bStart`/`bEnd` breaks) still load.
- Changing the icon: replace `icon-180/192/512.png` and bump the `?v=` on the icon links. iPhones only pick up a new icon when the app is removed and added to the home screen again.

## Decisions

- **A web app, not a native one (for now).** A native iPhone app would add a lock-screen widget, reminders, iCloud backup and Siri, but costs $99/yr (Apple Developer Program, which covers unlimited apps) plus build/signing upkeep. Revisit if lock-screen clock-in becomes worth it.
- **Apple's own time wheel**, not a custom one, because it's the only way to get real haptics in a web app.
- **Exact times**, no rounding.
- **No backup reminders.** The text thread is the fallback record.
- **Daily reminder:** done with an iPhone Shortcuts automation (Time of Day → Show Notification), not built into the app.
