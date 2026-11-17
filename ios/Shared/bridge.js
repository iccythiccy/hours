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
var HB = {
  run: function (name, argsJSON) {
    var fn = HX[name] || HoursCore[name];
    if (typeof fn !== "function") throw new Error("Unknown function " + name);
    var r = fn.apply(null, JSON.parse(argsJSON));
    return JSON.stringify(r === undefined ? null : r);
  },
  // Calls a function that changes `entries` in place; returns { entries, result }
  mutate: function (name, entriesJSON, restJSON) {
    var e = JSON.parse(entriesJSON);
    var r = HoursCore[name].apply(null, [e].concat(JSON.parse(restJSON)));
    return JSON.stringify({ entries: e, result: r === undefined ? null : r });
  }
};
