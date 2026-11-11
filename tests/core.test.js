// Run: node --test tests/
const test = require("node:test");
const assert = require("node:assert/strict");
const H = require("../core.js");

const S = { showBrk: true };
const W = (start, end, breaks) => {
  const e = { start, end, brk: 0 };
  if (breaks) { e.breaks = breaks.map(([s, x]) => ({ s, e: x })); e.brk = e.breaks.reduce((t, b) => t + H.between(b.s, b.e), 0); }
  return e;
};
const clone = o => JSON.parse(JSON.stringify(o));
// Simulate: compose for `cur` with `form`, save the form, then confirm "Sent".
function send(entries, cur, form, settings = S, at = 1) {
  if (form) {
    const prev = entries[cur];
    entries[cur] = Object.assign(clone(form), prev && prev.sent ? { sent: prev.sent } : {});
  }
  const r = H.compose(entries, cur, form || entries[cur], settings);
  assert.ok(r, `expected something to send for ${cur}`);
  H.applySent(entries, r.records, at);
  return r;
}
const compose = (entries, cur, settings = S) => H.compose(entries, cur, entries[cur], settings);

// Mon 11/9 .. Sun 11/15, then Mon 11/16
const MON = "2026-11-09", TUE = "2026-11-10", WED = "2026-11-11", THU = "2026-11-12", SUN = "2026-11-15", NEXT_MON = "2026-11-16";

test("formatting: exact times, minutes always shown on whole hours", () => {
  assert.equal(H.fmtTime("09:00"), "9am");
  assert.equal(H.fmtTime("18:15"), "6:15pm");
  assert.equal(H.fmtTime("12:00"), "12pm");
  assert.equal(H.fmtTime("00:30"), "12:30am");
  assert.equal(H.fmtDur(60), "1hr 0min");
  assert.equal(H.fmtDur(540), "9hrs 0min");
  assert.equal(H.fmtDur(555), "9hrs 15min");
  assert.equal(H.fmtDur(45), "45min");
  assert.equal(H.fmtDur(0), "0min");
  assert.equal(H.parseDur("19hrs 15min total for the week."), 1155);
  assert.equal(H.parseDur("10hrs total for the week."), 600);
});

test("user's exact format", () => {
  const e = { [MON]: W("09:00", "19:00") };
  send(e, MON);
  const r = H.compose(e, TUE, W("09:00", "18:15"), S);
  assert.equal(r.text, "11/10 9am-6:15pm 9hrs 15min\n19hrs 15min total for the week.");
  assert.equal(r.kind, "daily");
});

test("breaks: subtracted, times in text, sorted, hidden by setting", () => {
  const d = W("09:00", "18:15", [["15:00", "15:15"], ["12:10", "12:47"]]);
  assert.equal(H.worked(d), 555 - 37 - 15);
  assert.equal(H.dayLine(TUE, d, S), "11/10 9am-6:15pm (12:10pm-12:47pm, 3pm-3:15pm breaks) 8hrs 23min");
  assert.equal(H.dayLine(TUE, d, { showBrk: false }), "11/10 9am-6:15pm 8hrs 23min");
});

test("overnight shift counts past midnight and needs a confirm, not a block", () => {
  const n = W("22:00", "02:30");
  assert.equal(H.worked(n), 270);
  const v = H.validate(n, {});
  assert.equal(v.blockers.length, 0);
  assert.equal(v.needsAck, true);
  assert.equal(H.validate(n, { ack: H.ackKey(n) }).needsAck, false);
  // break after midnight inside an overnight shift is fine
  assert.equal(H.validate(W("22:00", "06:00", [["01:00", "01:30"]]), {}).blockers.length, 0);
});

test("long day needs a confirm", () => {
  const v = H.validate(W("05:00", "20:00"), {});
  assert.equal(v.blockers.length, 0);
  assert.equal(v.needsAck, true);
});

test("blockers: break outside shift, overlap, placeholders, unconfirmed end, incomplete, zero-length", () => {
  const b = (en, ui) => H.validate(en, ui || {}).blockers;
  assert.match(b(W("09:00", "17:00", [["18:00", "18:30"]]))[0], /inside your work hours/);
  assert.match(b(W("09:00", "17:00", [["12:00", "12:30"], ["12:15", "12:45"]])).join(), /overlap/);
  assert.match(b(W("09:00", "17:00", [["12:00", "12:30"]]), { breakPlaceholders: true })[0], /placeholders/);
  assert.match(b(W("09:00", "17:00"), { endUnconfirmed: true })[0], /Confirm your end time/);
  assert.match(b({ start: "09:00", end: "", brk: 0 })[0], /Set a start and end/);
  assert.match(b({ start: "09:00", end: "17:00", brk: 0, breaks: [{ s: "12:00", e: "" }] })[0], /Set both break times/);
  assert.match(b(W("09:00", "09:00")).join(), /same time/);
  assert.match(b(W("09:00", "17:00", [["12:00", "12:00"]])).join(), /same time/);
  assert.deepEqual(b(W("09:00", "17:00", [["12:00", "12:30"], ["15:00", "15:15"]])), []);
});

test("week boundary: Sunday counts in its week, Monday starts fresh", () => {
  const e = { [MON]: W("09:00", "17:00"), [SUN]: W("10:00", "12:00") };
  assert.equal(H.weekTotal(e, SUN), 600);
  assert.equal(H.monday(SUN), MON);
  const r = H.compose(e, NEXT_MON, W("09:00", "10:00"), S);
  assert.equal(r.text, "11/16 9am-10am 1hr 0min\n1hr 0min total for the week.");
  assert.deepEqual(H.weekDates(SUN)[0], MON);
});

test("nothing is marked sent until the user confirms", () => {
  const e = { [MON]: W("09:00", "19:00") };
  const r = H.compose(e, MON, e[MON], S);
  assert.ok(r.records[MON]);
  assert.equal(e[MON].sent, undefined);             // compose never changes data
  H.applySent(e, r.records, 5);
  assert.equal(e[MON].sent.snap.k, "work");
  assert.equal(e[MON].sent.weekMins, 600);
  assert.equal(compose(e, MON).kind, "resend");     // nothing new to say
});

test("fix before today's text: correction rides on top of today's text", () => {
  const e = { [MON]: W("09:00", "19:00") };
  send(e, MON);
  send(e, TUE, W("09:00", "18:15"));
  e[MON] = Object.assign(W("09:00", "19:30"), { sent: e[MON].sent });     // edit Monday on Wednesday
  const r = send(e, WED, W("09:00", "17:00"), S, 9);
  assert.equal(r.text, "Correction: 11/9 9am-7:30pm 10hrs 30min\n11/11 9am-5pm 8hrs 0min\n27hrs 45min total for the week.");
  assert.equal(r.kind, "daily+fix");
  assert.deepEqual(r.fixed, [MON]);
  assert.equal(compose(e, MON).kind, "resend");     // Monday now matches what was sent
});

test("fix after today's text: standalone correction with latest total", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00"));
  send(e, TUE, W("09:00", "18:15"));
  send(e, WED, W("09:00", "17:00"));
  e[TUE] = Object.assign(W("08:45", "18:15"), { sent: e[TUE].sent });
  const r = compose(e, TUE);
  assert.equal(r.text, "Correction: 11/10 8:45am-6:15pm 9hrs 30min\n27hrs 30min total for the week.");
  assert.equal(r.kind, "fix");
  assert.equal(r.anchor, WED);
  H.applySent(e, r.records);
  assert.equal(compose(e, WED).kind, "resend");
  assert.equal(e[WED].sent.weekMins, 1650);
});

test("late add: a day logged after a later day was sent goes out as a correction", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00"));
  send(e, WED, W("09:00", "17:00"));
  const r = H.compose(e, TUE, W("09:00", "18:15"), S);
  assert.equal(r.text, "Correction: 11/10 9am-6:15pm 9hrs 15min\n27hrs 15min total for the week.");
  assert.deepEqual(r.added, [TUE]);
  // also caught when viewing the latest sent day instead
  const r2 = H.compose(Object.assign(e, { [TUE]: W("09:00", "18:15") }), WED, e[WED], S);
  assert.equal(r2.text, "Correction: 11/10 9am-6:15pm 9hrs 15min\n27hrs 15min total for the week.");
});

test("skipped day: the next text includes the unsent day's line", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00"));
  e[TUE] = W("09:00", "18:15");                       // logged, never sent
  const r = H.compose(e, WED, W("09:00", "17:00"), S);
  assert.equal(r.text, "11/10 9am-6:15pm 9hrs 15min\n11/11 9am-5pm 8hrs 0min\n27hrs 15min total for the week.");
  assert.equal(r.kind, "daily");
});

test("first app text of the week doesn't repeat days texted by hand", () => {
  const e = { [MON]: W("09:00", "19:00") };          // texted by hand before using the app
  const r = send(e, TUE, W("09:00", "18:15"));
  assert.equal(r.text, "11/10 9am-6:15pm 9hrs 15min\n19hrs 15min total for the week.");
  assert.ok(e[MON].sent, "Monday is covered by the total that was sent");
  assert.equal(H.compose(e, WED, W("09:00", "17:00"), S).kind, "daily");
});

test("deleting a sent day keeps a record and sends 'removed'", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00"));
  send(e, TUE, W("09:00", "18:15"));
  H.removeDay(e, MON);
  assert.deepEqual(Object.keys(e[MON]).sort(), ["removed", "sent"]);
  const r = H.compose(e, MON, e[MON], S);
  assert.equal(r.text, "Correction: 11/9 removed\n9hrs 15min total for the week.");
  H.applySent(e, r.records);
  assert.equal(e[MON], undefined, "record cleared once the removal is sent");
  assert.equal(compose(e, TUE).kind, "resend");
});

test("deleting the latest (only) sent day is still communicated", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00"));
  H.removeDay(e, MON);
  const r = H.compose(e, MON, e[MON], S);
  assert.equal(r.text, "Correction: 11/9 removed\n0min total for the week.");
});

test("deleting an unsent day just deletes it", () => {
  const e = { [MON]: W("09:00", "19:00") };
  H.removeDay(e, MON);
  assert.equal(e[MON], undefined);
});

test("removed day can be restored to what was sent with no correction", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00", [["12:00", "12:30"]]));
  H.removeDay(e, MON);
  H.restoreRemoved(e, MON);
  assert.equal(compose(e, MON).kind, "resend");
  assert.equal(H.worked(e[MON]), 570);
});

test("day off: untexted is silent; replacing a sent day sends 'off'", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00"));
  H.setOff(e, TUE);
  assert.equal(compose(e, TUE), null);
  H.setOff(e, MON);
  const r = compose(e, MON);
  assert.equal(r.text, "Correction: 11/9 off\n0min total for the week.");
});

test("settings and wording changes never cause false corrections", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00", [["12:00", "12:30"]]));
  send(e, TUE, W("09:00", "18:00"));
  for (const st of [{ showBrk: false }, { showBrk: true }]) {
    assert.equal(H.compose(e, TUE, e[TUE], st).kind, "resend");
    assert.deepEqual(H.compose(e, WED, W("09:00", "17:00"), st).fixed, []);
  }
});

test("pending send that's never confirmed changes nothing", () => {
  const e = { [MON]: W("09:00", "19:00") };
  const before = clone(e);
  H.compose(e, MON, e[MON], S);                       // user opened Messages, then backed out
  assert.deepEqual(e, before);
});

test("records what was sent, even if edited before confirming", () => {
  const e = { [MON]: W("09:00", "19:00") };
  const r = H.compose(e, MON, e[MON], S);
  e[MON] = W("09:00", "20:00");                       // edited after sending, before tapping Sent
  H.applySent(e, r.records);
  assert.equal(compose(e, MON).kind, "fix", "the edit is still flagged against what was sent");
});

test("unmark sent", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00"));
  H.unmarkSent(e, MON);
  assert.equal(e[MON].sent, undefined);
  assert.equal(compose(e, MON).kind, "daily");
});

test("legacy saves migrate: matching text becomes data, mismatched flags a correction", () => {
  const e = {
    [MON]: Object.assign(W("09:00", "19:00"), { sent: { line: "11/9 9am-7pm 10hrs", total: "10hrs total for the week.", at: 1 } }),
    [TUE]: Object.assign(W("09:00", "18:15", [["12:10", "12:47"]]), { sent: { line: "11/10 9am-6:15pm (37min break) 8hrs 38min", total: "18hrs 38min total for the week.", at: 2 } }),
  };
  assert.equal(H.migrate(e), true);
  assert.equal(e[MON].sent.snap.k, "work");
  assert.equal(e[MON].sent.weekMins, 600);
  assert.equal(e[TUE].sent.snap.k, "legacy");        // old duration-style break text can't be matched
  assert.ok(H.sameSnap(H.snap(e[MON]), e[MON].sent.snap), "Monday matches what was sent");
  const r = compose(e, TUE);
  assert.equal(r.kind, "fix");
  assert.deepEqual(r.fixed, [TUE]);
  assert.equal(H.migrate(e), false, "idempotent");
});

test("older entry shapes still load", () => {
  assert.equal(H.worked({ start: "09:00", end: "17:00", brk: 30 }), 450);
  assert.equal(H.worked({ start: "09:00", end: "17:00", brk: 30, bStart: "12:00", bEnd: "12:30" }), 450);
});

test("backup round trip keeps work, off, removed and sent records", () => {
  const e = {};
  send(e, MON, W("09:00", "19:00", [["12:00", "12:30"]]));
  send(e, TUE, W("09:00", "18:15"));
  H.setOff(e, WED);
  H.removeDay(e, MON);
  const back = H.parseBackup("notes before\n" + H.backupText(e, THU) + "\ntrailing");
  assert.deepEqual(back, e);
  assert.equal(H.parseBackup("hello"), null);
  assert.deepEqual(H.parseBackup('{"entries":{"bad":{"start":"9"},"2026-11-09":{"start":"09:00","end":"10:00"}}}'),
    { [MON]: { start: "09:00", end: "10:00", brk: 0 } });
});

test("copy week", () => {
  const e = { [MON]: W("09:00", "19:00"), [TUE]: W("09:00", "18:15") };
  H.setOff(e, WED);
  assert.equal(H.weekText(e, WED, S), "Week of 11/9\n11/9 9am-7pm 10hrs 0min\n11/10 9am-6:15pm 9hrs 15min\n11/11 off\n19hrs 15min total for the week.");
});

test("day deleted after sending but before tapping Sent: client still has it, so it becomes a removal", () => {
  const e = { [MON]: W("09:00", "19:00") };
  const r = H.compose(e, MON, e[MON], S);
  H.removeDay(e, MON);                                // never marked sent, so it just deletes
  H.applySent(e, r.records);                          // then the user confirms the text went out
  assert.equal(e[MON].removed, true);
  assert.equal(compose(e, MON).text, "Correction: 11/9 removed\n0min total for the week.");
});

// ---------- travel days and other unusual hours ----------
test("travel day 4am-1am: 21hrs, dated by its start, needs a one-tap confirm", () => {
  const t = W("04:00", "01:00");
  assert.equal(H.worked(t), 21 * 60);
  const v = H.validate(t, {});
  assert.deepEqual(v.blockers, []);
  assert.equal(v.needsAck, true);
  const r = H.compose({}, TUE, t, S);
  assert.equal(r.text, "11/10 4am-1am 21hrs 0min\n21hrs 0min total for the week.");
});

test("travel day ending exactly at midnight", () => {
  const t = W("04:00", "00:00");
  assert.equal(H.worked(t), 20 * 60);
  assert.equal(H.dayLine(TUE, t, S), "11/10 4am-12am 20hrs 0min");
});

test("travel day ending at 12:30am and 3am", () => {
  assert.equal(H.dayLine(TUE, W("04:00", "00:30"), S), "11/10 4am-12:30am 20hrs 30min");
  assert.equal(H.dayLine(TUE, W("04:00", "03:00"), S), "11/10 4am-3am 23hrs 0min");
});

test("break spanning midnight on a travel day", () => {
  const t = W("04:00", "01:00", [["23:30", "00:15"]]);
  assert.deepEqual(H.validate(t, {}).blockers, []);
  assert.equal(H.worked(t), 21 * 60 - 45);
  assert.equal(H.dayLine(TUE, t, S), "11/10 4am-1am (11:30pm-12:15am break) 20hrs 15min");
});

test("breaks before and after midnight; a break after the day ends is blocked", () => {
  const ok = W("04:00", "01:00", [["12:00", "12:30"], ["00:20", "00:40"]]);
  assert.deepEqual(H.validate(ok, {}).blockers, []);
  assert.equal(H.dayLine(TUE, ok, S), "11/10 4am-1am (12pm-12:30pm, 12:20am-12:40am breaks) 20hrs 10min");
  const bad = W("04:00", "01:00", [["01:30", "02:00"]]);
  assert.match(H.validate(bad, {}).blockers.join(), /inside your work hours/);
  const early = W("04:00", "01:00", [["03:30", "03:45"]]);    // before the 4am start
  assert.match(H.validate(early, {}).blockers.join(), /inside your work hours/);
});

test("back-to-back travel days add up and don't overlap", () => {
  const e = { [MON]: W("04:00", "01:00"), [TUE]: W("04:00", "01:00") };
  assert.equal(H.weekTotal(e, TUE), 42 * 60);
  assert.deepEqual(H.validate(e[TUE], { entries: e, date: TUE }).blockers, []);
  assert.deepEqual(H.validate(e[MON], { entries: e, date: MON }).blockers, []);
  const r = H.compose({ [MON]: e[MON] }, TUE, e[TUE], S);
  assert.equal(r.text, "11/10 4am-1am 21hrs 0min\n42hrs 0min total for the week.");
});

test("a day running into the next day's start is blocked (would double-count)", () => {
  const e = { [MON]: W("06:00", "05:00"), [TUE]: W("04:00", "18:00") };   // Mon runs to 5am Tue
  assert.match(H.validate(e[TUE], { entries: e, date: TUE }).blockers.join(), /overlaps/);
  assert.match(H.validate(e[MON], { entries: e, date: MON }).blockers.join(), /overlaps/);
  e[MON] = W("04:00", "04:00");                                            // 24h days aren't allowed anyway
  e[MON] = W("06:00", "03:59");                                            // ends just before Tue's 4am start
  assert.deepEqual(H.validate(e[TUE], { entries: e, date: TUE }).blockers, []);
});

test("Sunday travel day ending Monday 1am counts in Sunday's week", () => {
  const e = { [SUN]: W("04:00", "01:00") };
  assert.equal(H.weekTotal(e, SUN), 21 * 60);
  const r = H.compose(e, NEXT_MON, W("09:00", "17:00"), S);
  assert.equal(r.text, "11/16 9am-5pm 8hrs 0min\n8hrs 0min total for the week.");
});

test("correcting a travel day after it was sent", () => {
  const e = {};
  send(e, TUE, W("04:00", "01:00"));
  e[TUE] = Object.assign(W("04:00", "01:30"), { sent: e[TUE].sent });
  assert.equal(compose(e, TUE).text, "Correction: 11/10 4am-1:30am 21hrs 30min\n21hrs 30min total for the week.");
});

test("odd clock times: 12am/12pm, starting after midnight, 1-minute days", () => {
  assert.equal(H.dayLine(TUE, W("00:30", "12:00"), S), "11/10 12:30am-12pm 11hrs 30min");
  assert.equal(H.dayLine(TUE, W("12:00", "12:01"), S), "11/10 12pm-12:01pm 1min");
  assert.equal(H.validate(W("00:30", "12:00"), {}).needsAck, false);
  assert.equal(H.worked(W("23:59", "00:00")), 1);
});
