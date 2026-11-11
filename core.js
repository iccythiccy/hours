/* Hours — core logic (no DOM). Loaded by index.html as window.HoursCore and by tests via require().
 *
 * Entry shapes stored per date ("YYYY-MM-DD"):
 *   work     { start:"HH:MM", end:"HH:MM", brk:<mins>, breaks?:[{s,e}], sent? }
 *   day off  { off:true, sent? }
 *   removed  { removed:true, sent }   // a day deleted after it was sent; kept until the correction is sent
 *
 * sent = { snap, weekMins, at } — WHAT the client was told (data, not wording):
 *   snap = {k:"work", start, end, breaks:[[s,e],...]} | {k:"off"} | {k:"removed"} | {k:"legacy", line}
 *   weekMins = the week total (minutes) through that day, as told to the client.
 * Comparing data instead of text means format or settings changes never cause false corrections.
 */
(function (root) {
  "use strict";
  const H = {};
  const LONG_DAY = 13 * 60;
  const MAX_BREAKS = 2;
  H.LONG_DAY = LONG_DAY; H.MAX_BREAKS = MAX_BREAKS;

  // ---------- time & date ----------
  const TIME_RE = /^\d{2}:\d{2}$/, DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
  const pad = n => String(n).padStart(2, "0");
  const toMin = t => { const [h, m] = t.split(":").map(Number); return h * 60 + m; };
  const fromMin = m => pad(Math.floor(m / 60) % 24) + ":" + pad(m % 60);
  const between = (a, b) => { let d = toMin(b) - toMin(a); if (d < 0) d += 1440; return d; };
  const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const parseIso = s => { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); };
  const addDays = (s, n) => { const d = parseIso(s); d.setDate(d.getDate() + n); return iso(d); };
  const md = s => { const d = parseIso(s); return `${d.getMonth() + 1}/${d.getDate()}`; };
  const monday = s => { const d = parseIso(s); d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); return iso(d); };
  const weekDates = s => { const m = monday(s); return [0, 1, 2, 3, 4, 5, 6].map(i => addDays(m, i)); };
  Object.assign(H, { TIME_RE, DATE_RE, pad, toMin, fromMin, between, iso, parseIso, addDays, md, monday, weekDates });

  function fmtTime(t) {
    const m = toMin(t), h24 = Math.floor(m / 60), mm = m % 60;
    const h12 = (h24 % 12) || 12, ap = h24 < 12 ? "am" : "pm";
    return mm ? `${h12}:${pad(mm)}${ap}` : `${h12}${ap}`;
  }
  // Whole hours always carry minutes ("1hr 0min"); under an hour stays "45min"
  function fmtDur(m) {
    const h = Math.floor(m / 60), r = m % 60;
    if (!h) return `${r}min`;
    return `${h === 1 ? "1hr" : `${h}hrs`} ${r}min`;
  }
  // "19hrs 15min", "1hr", "45min" -> minutes (used for older saved texts)
  function parseDur(t) {
    const m = String(t || "").match(/(?:(\d+)\s*hrs?)?\s*(?:(\d+)\s*min)?/);
    if (!m || (m[1] === undefined && m[2] === undefined)) return null;
    return (+m[1] || 0) * 60 + (+m[2] || 0);
  }
  H.fmtTime = fmtTime; H.fmtDur = fmtDur; H.parseDur = parseDur;

  // ---------- entries ----------
  const isWork = en => !!en && !en.off && !en.removed;
  const validBreak = b => !!b && TIME_RE.test(b.s) && TIME_RE.test(b.e);
  const relTo = start => t => (toMin(t) - toMin(start) + 1440) % 1440;
  function entryBreaks(en) {
    if (!isWork(en)) return [];
    let list = [];
    if (Array.isArray(en.breaks)) list = en.breaks.filter(validBreak).map(b => ({ s: b.s, e: b.e }));
    else if (TIME_RE.test(en.bStart) && TIME_RE.test(en.bEnd)) list = [{ s: en.bStart, e: en.bEnd }];
    if (TIME_RE.test(en.start)) { const rel = relTo(en.start); list.sort((a, b) => rel(a.s) - rel(b.s)); }
    return list;
  }
  const breakMins = en => {
    const bs = entryBreaks(en);
    if (bs.length) return bs.reduce((t, b) => t + between(b.s, b.e), 0);
    return isWork(en) ? Math.max(0, +en.brk || 0) : 0;   // oldest saves: duration only
  };
  function worked(en) {
    if (!isWork(en) || !TIME_RE.test(en.start) || !TIME_RE.test(en.end)) return 0;
    return Math.max(0, between(en.start, en.end) - breakMins(en));
  }
  const crossesMidnight = en => isWork(en) && toMin(en.end) < toMin(en.start);
  Object.assign(H, { isWork, validBreak, entryBreaks, breakMins, worked, crossesMidnight });

  // A snapshot of the hours themselves — what gets compared to what was sent
  function snap(en) {
    if (!en || en.removed) return { k: "removed" };
    if (en.off) return { k: "off" };
    return { k: "work", start: en.start, end: en.end, breaks: entryBreaks(en).map(b => [b.s, b.e]) };
  }
  const sameSnap = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  H.snap = snap; H.sameSnap = sameSnap;

  function weekTotal(E, d) {
    return weekDates(d).filter(x => x <= d).reduce((t, x) => t + worked(E[x]), 0);
  }
  H.weekTotal = weekTotal;

  // ---------- wording ----------
  function breakText(en, settings) {
    const bs = entryBreaks(en);
    if (!bs.length || !(settings && settings.showBrk)) return "";
    return ` (${bs.map(b => `${fmtTime(b.s)}-${fmtTime(b.e)}`).join(", ")} break${bs.length > 1 ? "s" : ""})`;
  }
  function dayLine(d, en, settings) {
    if (!en || en.removed) return `${md(d)} removed`;
    if (en.off) return `${md(d)} off`;
    return `${md(d)} ${fmtTime(en.start)}-${fmtTime(en.end)}${breakText(en, settings)} ${fmtDur(worked(en))}`;
  }
  const totalLine = n => `${fmtDur(n)} total for the week.`;
  Object.assign(H, { breakText, dayLine, totalLine });

  // ---------- validation ----------
  // blockers: must be fixed before texting. confirms: allowed after a one-tap "that's right".
  // ui = { endUnconfirmed, breakPlaceholders, ack }  (ack = the ackKey the user confirmed)
  const ackKey = en => `${en.start}|${en.end}`;
  H.ackKey = ackKey;
  function validate(en, ui) {
    ui = ui || {};
    const blockers = [], confirms = [];
    if (!isWork(en)) return { blockers, confirms, needsAck: false };
    if (!TIME_RE.test(en.start) || !TIME_RE.test(en.end)) {
      blockers.push("Set a start and end time.");
      return { blockers, confirms, needsAck: false };
    }
    if (ui.endUnconfirmed) blockers.push("Confirm your end time: tap Now, or set it on the wheel.");
    if (en.start === en.end) blockers.push("Start and end are the same time.");
    const raw = Array.isArray(en.breaks) ? en.breaks : [];
    if (raw.some(b => !validBreak(b))) blockers.push("Set both break times, or remove the break.");
    else {
      if (ui.breakPlaceholders) blockers.push("Set your break times. The orange ones are placeholders.");
      const bs = entryBreaks(en), rel = relTo(en.start), L = between(en.start, en.end) || 1440;
      if (bs.some(b => b.s === b.e)) blockers.push("A break starts and ends at the same time.");
      else if (bs.some(b => !(rel(b.s) < rel(b.e) && rel(b.e) <= L)))
        blockers.push((bs.length > 1 ? "A break isn't" : "The break isn't") + " inside your work hours. Check the break times (and AM/PM).");
      for (let i = 0; i < bs.length - 1; i++)
        if (rel(bs[i].e) > rel(bs[i + 1].s)) { blockers.push("Your breaks overlap. Check the break times."); break; }
    }
    const w = worked(en);
    if (crossesMidnight(en)) confirms.push(`End is earlier than start, so this counts as working past midnight (${fmtDur(w)}).`);
    else if (w > LONG_DAY) confirms.push(`That's ${fmtDur(w)} in one day.`);
    return { blockers, confirms, needsAck: confirms.length > 0 && ui.ack !== ackKey(en) };
  }
  H.validate = validate;

  // ---------- composing the text ----------
  // entries: saved entries. cur: the day on screen. form: the day as shown (work / {off} / {removed}).
  // Returns null when there's nothing to text, else
  //   { text, kind: daily | daily+fix | fix | resend, anchor, fixed:[dates], added:[dates], records }
  // records = what the client will know once this is sent: { date: {snap, weekMins} }
  function compose(entries, cur, form, settings) {
    const week = weekDates(cur);
    const E = {};
    week.forEach(d => { if (entries[d]) E[d] = entries[d]; });
    const saved = entries[cur];
    E[cur] = Object.assign({}, form, saved && saved.sent ? { sent: saved.sent } : {});
    if (isWork(form) && (!TIME_RE.test(form.start) || !TIME_RE.test(form.end))) return null;

    const line = d => dayLine(d, E[d], settings);
    const corr = d => "Correction: " + line(d);
    const total = d => totalLine(weekTotal(E, d));
    const texted = week.filter(d => E[d] && E[d].sent);
    const latest = texted.length ? texted[texted.length - 1] : null;
    const anchor = latest && latest > cur ? latest : cur;
    const changed = texted.filter(d => !sameSnap(snap(E[d]), E[d].sent.snap));
    // Days with hours the client never got a line for, logged before an already-sent day
    const lateAdds = latest ? week.filter(d => d < latest && isWork(E[d]) && !E[d].sent) : [];
    const curTexted = !!E[cur].sent;

    let text, kind, fixed, added;
    if (anchor === cur && !curTexted) {
      // Normal daily text (plus any corrections, and unsent days since the last text)
      fixed = changed.filter(d => d < cur);
      added = lateAdds.filter(d => d < cur);
      const catchUp = latest ? week.filter(d => d > latest && d < cur && isWork(E[d]) && !E[d].sent) : [];
      const fixLines = [...new Set([...fixed, ...added])].sort().map(corr);
      if (!isWork(form)) {
        if (!fixLines.length && !catchUp.length) return null;
        text = [...fixLines, ...catchUp.map(line), total(cur)].join("\n");
        kind = fixLines.length ? "fix" : "daily";
      } else {
        text = [...fixLines, ...catchUp.map(line), line(cur), total(cur)].join("\n");
        kind = fixLines.length ? "daily+fix" : "daily";
      }
    } else {
      // Something already sent is being corrected, or a past day is being added late
      const set = new Set([...changed, ...lateAdds]);
      if (!curTexted && isWork(form)) set.add(cur);
      fixed = changed.slice(); added = [...set].filter(d => !changed.includes(d));
      const totalStale = weekTotal(E, anchor) !== E[anchor].sent.weekMins;
      if (!set.size && !totalStale) {
        if (!isWork(form)) return null;
        text = [line(cur), total(cur)].join("\n"); kind = "resend";
      } else {
        const lines = [...set].sort().map(corr);
        text = lines.length ? [...lines, total(anchor)].join("\n") : "Updated: " + total(anchor);
        kind = "fix";
      }
    }
    const records = {};
    week.forEach(d => { if (d <= anchor && E[d]) records[d] = { snap: snap(E[d]), weekMins: weekTotal(E, d) }; });
    return { text, kind, anchor, fixed: fixed.sort(), added: added.sort(), records };
  }
  H.compose = compose;

  // ---------- state changes ----------
  // The user confirmed the text went out: record what the client now knows.
  function applySent(entries, records, at) {
    for (const [d, rec] of Object.entries(records || {})) {
      const en = entries[d];
      if (rec.snap.k === "removed") { delete entries[d]; continue; }       // removal communicated
      const sent = { snap: rec.snap, weekMins: rec.weekMins, at: at || 0 };
      if (!en) entries[d] = { removed: true, sent };                      // deleted after sending: client still has it
      else en.sent = sent;
    }
    return entries;
  }
  // Delete a day. If it was sent, keep a "removed" record so the correction can be sent.
  function removeDay(entries, d) {
    const en = entries[d];
    if (!en) return entries;
    if (en.sent && !en.removed) entries[d] = { removed: true, sent: en.sent };
    else if (!en.sent) delete entries[d];
    return entries;
  }
  function setOff(entries, d) {
    const prev = entries[d];
    entries[d] = Object.assign({ off: true }, prev && prev.sent ? { sent: prev.sent } : {});
    return entries;
  }
  function unmarkSent(entries, d) {
    const en = entries[d];
    if (!en) return entries;
    if (en.removed) delete entries[d]; else delete en.sent;
    return entries;
  }
  // Bring back a removed day as it was last sent
  function restoreRemoved(entries, d) {
    const en = entries[d];
    if (!en || !en.removed) return entries;
    const s = en.sent && en.sent.snap;
    if (s && s.k === "work") {
      const breaks = s.breaks.map(([a, b]) => ({ s: a, e: b }));
      const w = { start: s.start, end: s.end, brk: breaks.reduce((t, b) => t + between(b.s, b.e), 0), sent: en.sent };
      if (breaks.length) w.breaks = breaks;
      entries[d] = w;
    } else if (s && s.k === "off") entries[d] = { off: true, sent: en.sent };
    else delete entries[d];
    return entries;
  }
  Object.assign(H, { applySent, removeDay, setOff, unmarkSent, restoreRemoved });

  // ---------- migrating older saves ----------
  // Before Nov 11 2026, "sent" stored the text ({line, total}). Convert to data when the text
  // still matches the entry (in either break-text setting); otherwise keep it as "legacy",
  // which shows as changed so a correction can be sent.
  const normOld = t => String(t || "").replace(/\b(\d+hrs?)\b(?! \d+min)/g, "$1 0min");
  function migrate(entries) {
    let changedAny = false;
    for (const [d, en] of Object.entries(entries)) {
      const s = en && en.sent;
      if (!s || s.snap) continue;
      if (typeof s.line !== "string") { delete en.sent; changedAny = true; continue; }
      const matches = [true, false].some(b => normOld(dayLine(d, en, { showBrk: b })) === normOld(s.line));
      en.sent = { snap: matches ? snap(en) : { k: "legacy", line: s.line }, weekMins: parseDur(s.total), at: +s.at || 0 };
      changedAny = true;
    }
    return changedAny;
  }
  H.migrate = migrate;

  // ---------- backup ----------
  function backupText(entries, todayIso) {
    return `Hours backup ${md(todayIso)}/${todayIso.slice(0, 4)}\n` + JSON.stringify({ v: 4, entries });
  }
  function cleanSent(s) {
    if (!s || typeof s !== "object") return null;
    if (s.snap && typeof s.snap === "object" && ["work", "off", "removed", "legacy"].includes(s.snap.k)) {
      const k = s.snap.k;
      let sn;
      if (k === "work") {
        if (!TIME_RE.test(s.snap.start) || !TIME_RE.test(s.snap.end)) return null;
        const br = Array.isArray(s.snap.breaks) ? s.snap.breaks.filter(p => Array.isArray(p) && TIME_RE.test(p[0]) && TIME_RE.test(p[1])).slice(0, MAX_BREAKS) : [];
        sn = { k, start: s.snap.start, end: s.snap.end, breaks: br.map(p => [p[0], p[1]]) };
      } else if (k === "legacy") sn = { k, line: String(s.snap.line || "").slice(0, 300) };
      else sn = { k };
      return { snap: sn, weekMins: Number.isFinite(+s.weekMins) && s.weekMins !== null ? +s.weekMins : null, at: +s.at || 0 };
    }
    if (typeof s.line === "string") return { line: s.line.slice(0, 300), total: String(s.total || "").slice(0, 100), at: +s.at || 0 };
    return null;
  }
  function parseBackup(txt) {
    const i = txt.indexOf("{"), j = txt.lastIndexOf("}");
    if (i < 0 || j < i) return null;
    let obj; try { obj = JSON.parse(txt.slice(i, j + 1)); } catch (e) { return null; }
    const src = obj && obj.entries; if (!src || typeof src !== "object") return null;
    const clean = {};
    for (const [k, v] of Object.entries(src)) {
      if (!DATE_RE.test(k) || !v || typeof v !== "object") continue;
      const sent = cleanSent(v.sent);
      let en = null;
      if (v.removed) { if (sent) en = { removed: true }; }
      else if (v.off) en = { off: true };
      else if (TIME_RE.test(v.start) && TIME_RE.test(v.end)) {
        const bs = entryBreaks(v).slice(0, MAX_BREAKS);
        en = bs.length
          ? { start: v.start, end: v.end, brk: bs.reduce((t, b) => t + between(b.s, b.e), 0), breaks: bs }
          : { start: v.start, end: v.end, brk: Math.max(0, Math.min(600, +v.brk || 0)) };
      }
      if (!en) continue;
      if (sent) en.sent = sent;
      clean[k] = en;
    }
    migrate(clean);
    return clean;
  }
  H.backupText = backupText; H.parseBackup = parseBackup;

  // Week summary for "Copy week"
  function weekText(entries, cur, settings) {
    const days = weekDates(cur).filter(d => entries[d] && !entries[d].removed);
    if (!days.length) return null;
    const total = days.reduce((t, d) => t + worked(entries[d]), 0);
    return [`Week of ${md(monday(cur))}`, ...days.map(d => dayLine(d, entries[d], settings)), totalLine(total)].join("\n");
  }
  H.weekText = weekText;

  if (typeof module !== "undefined" && module.exports) module.exports = H;
  else root.HoursCore = H;
})(typeof window !== "undefined" ? window : globalThis);
