// Glue between Swift and core.js: everything crosses as JSON strings.
var HX = {
  // Is this entry the same hours as the other? (data, not wording)
  sameEntry: function (a, b) { return !!(a && b) && HoursCore.sameSnap(HoursCore.snap(a), HoursCore.snap(b)); },
  // "" (never sent) | "ok" (matches what was sent) | "stale" (changed since sent)
  sentState: function (en) {
    if (!en || !en.sent) return "";
    return HoursCore.sameSnap(HoursCore.snap(en), en.sent.snap) ? "ok" : "stale";
  }
};
// Swift stores sent snaps as dictionaries, which don't keep key order, but core.js compares
// snaps with JSON.stringify. Put every snap's keys back in the order core.js's snap() uses.
function canonSnap(s) {
  if (!s || typeof s !== "object" || Array.isArray(s) || typeof s.k !== "string") return s;
  if (s.k === "work") return { k: s.k, start: s.start, end: s.end, breaks: s.breaks };
  if (s.k === "legacy") return { k: s.k, line: s.line };
  return { k: s.k };
}
function canon(x) {
  if (Array.isArray(x)) return x.map(canon);
  if (!x || typeof x !== "object") return x;
  var out = {};
  for (var key in x) out[key] = key === "snap" ? canonSnap(x[key]) : canon(x[key]);
  return out;
}
var HB = {
  run: function (name, argsJSON) {
    var fn = HX[name] || HoursCore[name];
    if (typeof fn !== "function") throw new Error("Unknown function " + name);
    var r = fn.apply(null, canon(JSON.parse(argsJSON)));
    return JSON.stringify(r === undefined ? null : r);
  },
  // Calls a function that changes `entries` in place; returns { entries, result }
  mutate: function (name, entriesJSON, restJSON) {
    var e = canon(JSON.parse(entriesJSON));
    var r = HoursCore[name].apply(null, [e].concat(canon(JSON.parse(restJSON))));
    return JSON.stringify({ entries: e, result: r === undefined ? null : r });
  }
};
