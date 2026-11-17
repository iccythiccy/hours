import XCTest
@testable import Hours

/// The hours rules themselves are covered by tests/core.test.js (37 scenarios). These check that
/// the iPhone app runs that same core.js correctly and that saved data round-trips.
final class HoursTests: XCTestCase {
    let core = Core.shared

    func testFormattingMatchesWebApp() {
        XCTAssertEqual(core.fmtTime("09:00"), "9am")
        XCTAssertEqual(core.fmtTime("18:15"), "6:15pm")
        XCTAssertEqual(core.fmtDur(555), "9hrs 15min")
        XCTAssertEqual(core.fmtDur(60), "1hr 0min")
        XCTAssertEqual(core.fmtDur(45), "45min")
    }

    func testDailyTextAndSentRoundTrip() {
        var entries: [String: Entry] = ["2026-11-09": .work(start: "09:00", end: "19:00", breaks: [])]
        let s = Settings(name: "", phone: "1", showBrk: true)
        let mon = core.compose(entries, cur: "2026-11-09", form: entries["2026-11-09"]!, settings: s)!
        entries = core.applySent(entries, records: mon.records, at: 1)
        XCTAssertEqual(core.sentState(entries["2026-11-09"]), "ok")
        let tue = Entry.work(start: "09:00", end: "18:15", breaks: [])
        let r = core.compose(entries, cur: "2026-11-10", form: tue, settings: s)!
        XCTAssertEqual(r.text, "11/10 9am-6:15pm 9hrs 15min\n19hrs 15min total for the week.")
        XCTAssertEqual(r.kind, "daily")
    }

    func testTravelDayNeedsConfirmNotBlock() {
        let t = Entry.work(start: "04:00", end: "01:00", breaks: [])
        XCTAssertEqual(core.worked(t), 21 * 60)
        let v = core.validate(t, endUnconfirmed: false, breakPlaceholders: false, ack: nil, entries: [:], date: "2026-11-10")
        XCTAssertTrue(v.blockers.isEmpty)
        XCTAssertTrue(v.needsAck)
        let ok = core.validate(t, endUnconfirmed: false, breakPlaceholders: false, ack: core.ackKey(t), entries: [:], date: "2026-11-10")
        XCTAssertFalse(ok.needsAck)
    }

    func testBlockers() {
        let bad = Entry.work(start: "09:00", end: "17:00", breaks: [Break(s: "18:00", e: "18:30")])
        let v = core.validate(bad, endUnconfirmed: true, breakPlaceholders: false, ack: nil, entries: [:], date: "2026-11-10")
        XCTAssertEqual(v.blockers.count, 2)
    }

    func testDeletingSentDayKeepsRemovalRecord() {
        var e: [String: Entry] = ["2026-11-09": .work(start: "09:00", end: "19:00", breaks: [])]
        let s = Settings()
        let r = core.compose(e, cur: "2026-11-09", form: e["2026-11-09"]!, settings: s)!
        e = core.applySent(e, records: r.records, at: 1)
        e = core.removeDay(e, "2026-11-09")
        XCTAssertEqual(e["2026-11-09"]?.isRemoved, true)
        XCTAssertEqual(core.compose(e, cur: "2026-11-09", form: .removedDay, settings: s)?.text,
                       "Correction: 11/9 removed\n0min total for the week.")
    }

    func testWebBackupImports() {
        let web = #"Hours backup 11/10/2026\n{"v":3,"entries":{"2026-11-09":{"start":"09:00","end":"19:00","brk":0,"sent":{"line":"11/9 9am-7pm 10hrs","total":"10hrs total for the week.","at":1}}}}"#
        let e = core.parseBackup(web)
        XCTAssertEqual(e?.count, 1)
        XCTAssertEqual(core.sentState(e?["2026-11-09"]), "ok", "older web 'texted' record migrates to sent data")
    }

    func testStateEncodesLikeWebApp() throws {
        var st = AppState()
        st.entries["2026-11-09"] = .work(start: "09:00", end: "17:00", breaks: [Break(s: "12:00", e: "12:30")])
        let data = try JSONEncoder().encode(st)
        let back = try JSONDecoder().decode(AppState.self, from: data)
        XCTAssertEqual(back.entries["2026-11-09"]?.breaks?.first?.e, "12:30")
        XCTAssertEqual(core.worked(back.entries["2026-11-09"]), 450)
    }
}
