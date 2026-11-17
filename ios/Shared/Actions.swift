import Foundation
import AppIntents

/// Clock in / clock out, shared by the app, the widget buttons and Siri/Shortcuts.
enum ShiftActions {
    /// The day a clock-out applies to: today's open clock-in, or yesterday's if it ran past
    /// midnight (until noon) — e.g. a 4am–1am travel day.
    static func openDay(_ s: AppState, now: Date = Date()) -> String? {
        let today = Clock.iso(now)
        if s.entries[today] == nil, s.drafts?[today] != nil { return today }
        let y = Core.shared.addDays(today, -1)
        if s.entries[y] == nil, s.drafts?[y] != nil, Clock.hour(now) < 12 { return y }
        return nil
    }

    /// Start today at the current minute. Does nothing if today is already logged.
    @discardableResult
    static func startNow(now: Date = Date()) -> Bool {
        var s = Store.load()
        let today = Clock.iso(now)
        guard s.entries[today] == nil else { return false }
        let breaks = s.drafts?[today]?.breaks
        s.drafts?[today] = Draft(start: Clock.hhmm(now), breaks: breaks)
        return Store.save(s)
    }

    /// Finish the open clock-in at the current minute and save the day.
    @discardableResult
    static func endNow(now: Date = Date()) -> Bool {
        var s = Store.load()
        guard let day = openDay(s, now: now), let draft = s.drafts?[day] else { return false }
        var e = Entry.work(start: draft.start, end: Clock.hhmm(now), breaks: draft.breaks ?? [])
        e.brk = (draft.breaks ?? []).reduce(0) { $0 + Core.shared.between($1.s, $1.e) }
        if let h = s.held, h.date == day { e.sent = h.sent; s.held = nil }
        s.entries[day] = e
        s.drafts?[day] = nil
        return Store.save(s)
    }
}

struct StartShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "Start shift"
    static var description = IntentDescription("Clock in now in Hours.")
    func perform() async throws -> some IntentResult {
        ShiftActions.startNow()
        return .result()
    }
}

struct EndShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "End shift"
    static var description = IntentDescription("Clock out now in Hours.")
    func perform() async throws -> some IntentResult {
        ShiftActions.endNow()
        return .result()
    }
}

/// What the widgets show, worked out from the saved data.
struct DaySummary {
    enum Phase { case notStarted, started(Date), logged, off, removed }
    var phase: Phase
    var day: String
    var todayMins: Int
    var weekMins: Int       // saved days this week through `day` (not counting time still running)
    var sentState: String   // "", "ok", "stale"
    var startLabel: String?

    static func load(now: Date = Date()) -> DaySummary {
        let s = Store.load()
        let core = Core.shared
        let today = Clock.iso(now)
        if let open = ShiftActions.openDay(s, now: now), let d = s.drafts?[open],
           let startDate = Clock.date(day: open, time: d.start) {
            return DaySummary(phase: .started(startDate), day: open, todayMins: 0,
                              weekMins: core.weekTotal(s.entries, through: open), sentState: "",
                              startLabel: core.fmtTime(d.start))
        }
        let e = s.entries[today]
        let week = core.weekTotal(s.entries, through: today)
        guard let e else {
            return DaySummary(phase: .notStarted, day: today, todayMins: 0, weekMins: week, sentState: "", startLabel: nil)
        }
        if e.isOff { return DaySummary(phase: .off, day: today, todayMins: 0, weekMins: week, sentState: core.sentState(e), startLabel: nil) }
        if e.isRemoved { return DaySummary(phase: .removed, day: today, todayMins: 0, weekMins: week, sentState: "stale", startLabel: nil) }
        return DaySummary(phase: .logged, day: today, todayMins: core.worked(e), weekMins: week,
                          sentState: core.sentState(e), startLabel: e.start.map(core.fmtTime))
    }
}
