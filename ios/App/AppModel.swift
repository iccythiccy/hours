import SwiftUI
import UIKit
import MessageUI

struct BreakEdit: Identifiable, Equatable {
    let id = UUID()
    var s: String
    var e: String
    var sDef = false   // placeholder start, not chosen yet
    var eDef = false
}

enum TimeField: Equatable {
    case start, end, breakStart(UUID), breakEnd(UUID)
}

struct Toast: Equatable {
    var text: String
    var undoable = false
    var id = UUID()
}

struct Warning: Identifiable {
    let id = UUID()
    var text: String
    var blocker: Bool
}

/// A text ready for the Messages sheet, plus what the client will know once it's sent.
struct Outgoing: Identifiable {
    let id = UUID()
    var text: String
    var recipients: [String]
    var records: JSONValue
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// The main screen's state and behavior — a port of the web app's screen logic.
/// All hours math, wording, corrections and checks come from core.js (see Core.swift).
@MainActor
final class AppModel: ObservableObject {
    static let version = "1.0"
    private let core = Core.shared

    @Published var state: AppState
    @Published var today: String
    @Published var cur: String
    @Published var start = ""            // "HH:MM" or "" when blank
    @Published var end = ""
    @Published var brks: [BreakEdit] = []
    @Published var endIsDefault = false  // end time filled in by the app, not chosen
    @Published var toast: Toast?
    @Published var offArmed = false
    @Published var deleteArmed = false

    private var undo: (date: String, prev: Entry?)?
    private var undoExpiry: DispatchWorkItem?
    private var toastExpiry: DispatchWorkItem?

    init() {
        state = Store.load()
        today = Clock.iso()
        cur = Clock.iso()
        openDay(announce: false)
    }

    // MARK: - basics

    var saved: Entry? { state.entries[cur] }
    var isOff: Bool { saved?.isOff == true }
    var isRemoved: Bool { saved?.isRemoved == true }
    var isWork: Bool { !isOff && !isRemoved }
    private func valid(_ t: String) -> Bool { t.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil }
    private func validBreak(_ b: BreakEdit) -> Bool { valid(b.s) && valid(b.e) }
    private func fromMin(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 24, m % 60) }

    func fmtTime(_ t: String) -> String { t.isEmpty ? "—" : core.fmtTime(t) }
    func fmtDur(_ m: Int) -> String { core.fmtDur(m) }

    private func persist() { Store.save(state) }

    private var lastWorkEntry: Entry? {
        state.entries.keys.sorted().reversed().compactMap { state.entries[$0] }.first { $0.isWork }
    }

    /// Back in the foreground: pick up widget clock-ins/outs and a new day.
    func refresh() {
        state = Store.load()
        let t = Clock.iso()
        if t != today { today = t; openDay(announce: true); return }
        if cur == today, endIsDefault, saved == nil { end = Clock.hhmm() }
        loadDate(cur, keepEdits: false)
    }

    /// Yesterday's unfinished clock-in (a day past midnight) until noon, else today.
    func openDay(announce: Bool) {
        let y = core.addDays(today, -1)
        if state.entries[y] == nil, let d = state.drafts?[y], Clock.hour() < 12 {
            loadDate(y, keepEdits: false)
            if announce { show("Finishing \(Clock.dayName(y)) (started \(core.fmtTime(d.start)))") }
        } else {
            loadDate(today, keepEdits: false)
        }
    }

    private func releaseHeld(_ next: String) {
        guard let h = state.held, h.date != next else { return }
        if state.entries[h.date] == nil { state.entries[h.date] = Entry(sent: h.sent, removed: true) }
        state.held = nil
        persist()
    }

    func loadDate(_ s: String, keepEdits: Bool = false) {
        releaseHeld(s)
        cur = s
        offArmed = false; deleteArmed = false
        let e = state.entries[s]
        if let e, e.isWork {
            start = e.start ?? ""; end = e.end ?? ""
            endIsDefault = false
            let list = core.entryBreaks(e)
            if !list.isEmpty { brks = list.map { BreakEdit(s: $0.s, e: $0.e) } }
            else if let b = e.brk, b > 0 { brks = [BreakEdit(s: "12:00", e: fromMin(720 + b), sDef: true, eDef: true)] }
            else { brks = [] }
        } else if e == nil {
            let draft = state.drafts?[s]
            start = draft?.start ?? lastWorkEntry?.start ?? "09:00"
            end = (s == today || draft != nil) ? Clock.hhmm() : (lastWorkEntry?.end ?? "17:00")
            endIsDefault = true
            brks = (draft?.breaks ?? []).map { BreakEdit(s: $0.s, e: $0.e) }
        } else {
            brks = []
        }
    }

    // MARK: - the day on screen

    func formEntry() -> Entry {
        if isOff { return .offDay }
        if isRemoved { return .removedDay }
        var e = Entry(start: start, end: end, brk: 0)
        if !brks.isEmpty {
            let bs = brks.map { Break(s: $0.s, e: $0.e) }
            e.breaks = bs
            if brks.allSatisfy(validBreak) { e.brk = bs.reduce(0) { $0 + core.between($1.s, $1.e) } }
        }
        return e
    }
    private func complete(_ e: Entry) -> Bool {
        guard e.isWork else { return true }
        return valid(e.start ?? "") && valid(e.end ?? "") && (e.breaks ?? []).allSatisfy { valid($0.s) && valid($0.e) }
    }
    var formComplete: Bool { complete(formEntry()) }
    var dayMinutes: Int { isWork ? (formComplete ? core.worked(formEntry()) : 0) : 0 }

    var weekThroughCur: Int {
        let f = formEntry()
        return core.weekDates(cur).filter { $0 <= cur }.reduce(0) { t, d in
            d == cur ? t + (complete(f) ? core.worked(f) : 0) : t + core.worked(state.entries[d])
        }
    }

    // MARK: - saving

    /// Until an end time is chosen, a new day's start is kept as a clock-in draft.
    @discardableResult
    func saveCurrent() -> Bool {
        if let s = saved, !s.isWork { return false }
        var e = formEntry()
        let prev = saved
        if prev == nil && endIsDefault {
            if valid(e.start ?? "") {
                state.drafts?[cur] = Draft(start: e.start!, breaks: brks.filter(validBreak).map { Break(s: $0.s, e: $0.e) })
                persist()
            }
            return false
        }
        guard complete(e) else { return false }
        if e.breaks?.isEmpty == true { e.breaks = nil }
        let changed = prev != nil && !core.sameEntry(prev, e)
        if prev != nil && !changed { return true }
        if changed { snapshot(cur) }
        if let p = prev?.sent { e.sent = p }
        else if let h = state.held, h.date == cur { e.sent = h.sent; state.held = nil }
        state.entries[cur] = e
        state.drafts?[cur] = nil
        endIsDefault = false
        persist()
        if changed { show("Updated \(Clock.dayName(cur))", undoable: true) }
        return true
    }

    // MARK: - editing

    func setTime(_ field: TimeField, _ value: String) {
        switch field {
        case .start: start = value
        case .end: end = value; endIsDefault = false
        case .breakStart(let id): if let i = brks.firstIndex(where: { $0.id == id }) { brks[i].s = value; brks[i].sDef = false }
        case .breakEnd(let id): if let i = brks.firstIndex(where: { $0.id == id }) { brks[i].e = value; brks[i].eDef = false }
        }
        saveCurrent()
    }
    func timeValue(_ field: TimeField) -> String {
        switch field {
        case .start: return start
        case .end: return end
        case .breakStart(let id): return brks.first { $0.id == id }?.s ?? ""
        case .breakEnd(let id): return brks.first { $0.id == id }?.e ?? ""
        }
    }

    func startNow() {
        Haptics.tap()
        start = Clock.hhmm(); saveCurrent()
        show("Started \(core.fmtTime(start))")
    }
    func endNow() {
        Haptics.tap()
        end = Clock.hhmm(); endIsDefault = false; saveCurrent()
        show("Finished \(core.fmtTime(end))")
    }

    func addBreak() {
        guard brks.count < 2 else { return }
        Haptics.tap()
        let i = brks.count
        let prev = state.entries.keys.sorted().reversed()
            .compactMap { state.entries[$0] }.map { core.entryBreaks($0) }.first { $0.count > i }
        let def = prev?[i] ?? (i == 0 ? Break(s: "12:00", e: "12:30") : Break(s: "15:00", e: "15:15"))
        brks.append(BreakEdit(s: def.s, e: def.e, sDef: true, eDef: true))
    }
    func removeBreak(_ id: UUID) {
        Haptics.tap()
        brks.removeAll { $0.id == id }
        saveCurrent()
    }
    func breakLabel(_ b: BreakEdit, index: Int) -> String {
        let name = brks.count > 1 ? "Break \(index + 1)" : "Break"
        return validBreak(b) ? "\(name) · \(core.fmtDur(core.between(b.s, b.e))) unpaid" : "\(name) · set both times"
    }

    func confirmLongDay() {
        Haptics.tap()
        state.acks?[cur] = core.ackKey(formEntry())
        persist()
    }

    // MARK: - what to send

    var composed: ComposeResult? { core.compose(state.entries, cur: cur, form: formEntry(), settings: state.settings) }
    var validation: Validation {
        core.validate(formEntry(), endUnconfirmed: endIsDefault, breakPlaceholders: brks.contains { $0.sDef || $0.eDef },
                      ack: state.acks?[cur], entries: state.entries, date: cur)
    }
    var canSend: Bool {
        let v = validation
        return composed != nil && v.blockers.isEmpty && !v.needsAck
    }

    var bubbleText: String {
        if let r = composed { return r.text }
        if isOff { return "Day off. Nothing to text." }
        if isWork && !formComplete { return validation.blockers.first ?? "Set a start and end time." }
        return "Nothing new to text."
    }
    var textButtonLabel: String {
        if composed?.kind == "fix" { return "Text fix" }
        return state.settings.name.isEmpty ? "Text" : "Text \(state.settings.name)"
    }

    private func missingDays(_ s: String) -> [String] {
        core.weekDates(s).enumerated().filter { $0.offset < 5 && $0.element < s && state.entries[$0.element] == nil }.map(\.element)
    }
    private func list(_ a: [String]) -> String {
        a.count <= 2 ? a.joined(separator: " and ") : a.dropLast().joined(separator: ", ") + " and " + a.last!
    }

    var warnings: [Warning] {
        var w: [Warning] = validation.blockers.map { Warning(text: $0, blocker: true) }
        let miss = missingDays(cur)
        let unfinished = miss.filter { state.drafts?[$0] != nil }
        if !unfinished.isEmpty {
            let names = unfinished.map { "\(Clock.dayName($0)) (started \(core.fmtTime(state.drafts![$0]!.start)))" }
            w.append(Warning(text: "\(list(names)) \(unfinished.count > 1 ? "were" : "was") never finished. Open \(unfinished.count > 1 ? "them" : "it") and set the end time.", blocker: false))
        }
        let missOnly = miss.filter { state.drafts?[$0] == nil }
        if !missOnly.isEmpty {
            let many = missOnly.count > 1
            w.append(Warning(text: "Nothing logged for \(list(missOnly.map(Clock.dayName))). Log the hours or mark \(many ? "them as days" : "it as a day") off. The week total doesn't include \(many ? "those days" : "that day").", blocker: false))
        }
        if let r = composed {
            let gone = r.fixed.filter { state.entries[$0]?.isRemoved == true }
            let chg = r.fixed.filter { !gone.contains($0) }
            if !chg.isEmpty { w.append(Warning(text: "\(list(chg.map(Clock.dayName))) changed after you sent \(chg.count > 1 ? "them" : "it"), so this text includes a correction.", blocker: false)) }
            if !gone.isEmpty { w.append(Warning(text: "\(list(gone.map(Clock.dayName))) \(gone.count > 1 ? "were" : "was") removed after you sent \(gone.count > 1 ? "them" : "it"), so this text tells your client.", blocker: false)) }
            if !r.added.isEmpty { w.append(Warning(text: "\(list(r.added.map(Clock.dayName))) wasn't in an earlier text, so it's included as a correction.", blocker: false)) }
        }
        return w
    }

    var showAck: Bool {
        let v = validation
        return isWork && formComplete && v.needsAck && v.blockers.isEmpty
    }
    var ackText: String { validation.confirms.joined(separator: " ") + " Is that right?" }

    enum StatusTone { case plain, good, warn }
    var status: (String, StatusTone) {
        if isRemoved { return ("Removed · correction not sent", .warn) }
        if let p = state.pending, case .object(let recs) = p.records, recs[cur] != nil { return ("Waiting: did it send?", .warn) }
        let f = formEntry()
        if let s = saved, core.sameEntry(s, f) {
            switch core.sentState(s) {
            case "ok": return ("✓ Sent", .good)
            case "stale": return ("Changed since sent", .warn)
            default: return (s.isOff ? "Day off" : "Logged · not sent", .plain)
            }
        }
        if saved == nil, let d = state.drafts?[cur] {
            return ("Started \(core.fmtTime(d.start))\(cur < today ? " · not finished" : "")", .plain)
        }
        return ("Not logged yet", .plain)
    }

    // MARK: - sending

    /// Text button: returns what to put in the Messages sheet, after saving the day.
    func prepareText() -> Outgoing? {
        guard canSend else { return nil }
        guard !state.settings.phone.trimmingCharacters(in: .whitespaces).isEmpty else {
            show("Add your client's number in Settings first"); return nil
        }
        saveCurrent()
        guard let r = composed else { return nil }
        Haptics.tap()
        return Outgoing(text: r.text, recipients: [state.settings.phone], records: r.records)
    }

    /// iPhone reports whether the text was actually sent.
    func finishedSending(_ out: Outgoing, result: MessageComposeResult) {
        switch result {
        case .sent:
            state.entries = core.applySent(state.entries, records: out.records, at: Date().timeIntervalSince1970 * 1000)
            persist(); Haptics.success()
            show("Sent")
            loadDate(cur)
        case .failed:
            show("The text didn't send. Nothing was marked as sent.")
        default:
            break
        }
    }

    /// No Messages on this device (e.g. simulator): fall back to the sms: link and ask afterwards.
    func fallbackSMSURL(_ out: Outgoing) -> URL? {
        state.pending = Pending(at: Date().timeIntervalSince1970 * 1000, via: "text", date: cur, text: out.text, records: out.records)
        persist()
        let num = state.settings.phone.filter { $0.isNumber || $0 == "+" }
        let body = out.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "sms:\(num)&body=\(body)")
    }

    func copyText() {
        guard canSend else { return }
        saveCurrent()
        guard let r = composed else { return }
        Haptics.tap()
        UIPasteboard.general.string = r.text
        state.pending = Pending(at: Date().timeIntervalSince1970 * 1000, via: "copy", date: cur, text: r.text, records: r.records)
        persist()
        show("Copied. Tap Sent once it's gone out.")
    }
    func confirmPendingSent() {
        guard let p = state.pending else { return }
        Haptics.success()
        state.entries = core.applySent(state.entries, records: p.records, at: Date().timeIntervalSince1970 * 1000)
        state.pending = nil
        persist(); show("Marked as sent")
        loadDate(cur)
    }
    func dismissPending() {
        Haptics.tap()
        state.pending = nil; persist(); show("Not marked as sent")
    }

    // MARK: - day actions

    func unmarkSent() {
        Haptics.tap(); snapshot(cur)
        state.entries = core.unmarkSent(state.entries, cur); persist(); loadDate(cur)
        show("\(Clock.dayName(cur)) marked as not sent", undoable: true)
    }

    var offButtonLabel: String {
        if isOff { return "Not a day off — log hours" }
        if isRemoved { return "Bring this day back" }
        return offArmed ? "Tap again to replace these hours with a day off" : "Mark as day off"
    }
    func offTapped() {
        Haptics.tap()
        if isRemoved {
            snapshot(cur); state.entries = core.restoreRemoved(state.entries, cur); persist(); loadDate(cur)
            show("\(Clock.dayName(cur)) brought back", undoable: true); return
        }
        if isOff {
            snapshot(cur)
            if let sent = saved?.sent { state.held = Held(date: cur, sent: sent) }
            state.entries[cur] = nil; persist(); loadDate(cur)
            show("\(Clock.dayName(cur)) is no longer a day off", undoable: true); return
        }
        if saved != nil && !offArmed {
            offArmed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.offArmed = false }
            return
        }
        offArmed = false
        snapshot(cur)
        state.entries = core.setOff(state.entries, cur)
        state.drafts?[cur] = nil
        persist(); loadDate(cur)
        show("\(Clock.dayName(cur)) marked as a day off", undoable: true)
    }

    func deleteTapped() {
        if !deleteArmed {
            deleteArmed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.deleteArmed = false }
            return
        }
        deleteArmed = false
        Haptics.tap(); snapshot(cur)
        let wasSent = saved?.sent != nil
        state.entries = core.removeDay(state.entries, cur)
        state.drafts?[cur] = nil
        persist(); loadDate(cur)
        show(wasSent ? "Deleted. Text your client the correction." : "Deleted \(Clock.dayName(cur))", undoable: true)
    }

    // MARK: - week

    var weekDays: [String] { core.weekDates(cur) }
    var weekLabel: String {
        let m = core.monday(cur)
        guard let d = Clock.parse(m) else { return "" }
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        return "Week of \(Clock.mon[c.month! - 1]) \(c.day!)"
    }
    var weekTitle: String { weekDays.contains(today) ? "This week" : "Week of \(core.md(core.monday(cur)))" }
    var canGoNextWeek: Bool { core.addDays(core.monday(cur), 7) <= today }
    func prevWeek() { Haptics.tap(); loadDate(core.addDays(cur, -7)) }
    func nextWeek() {
        Haptics.tap()
        let n = core.addDays(cur, 7)
        loadDate(n > today ? today : n)
    }

    struct Row: Identifiable {
        var id: String { day }
        var day: String
        var label: String
        var detail: String
        var hours: String
        var badge: String       // "✓", "●" or ""
        var tone: StatusTone
        var dim: Bool
        var hidden: Bool
    }
    var weekRows: [Row] {
        weekDays.enumerated().map { i, s in
            let en = state.entries[s]
            let missing = en == nil && i < 5 && s < today
            var detail = "—", hours = "", tone = StatusTone.plain
            if let en, en.isRemoved { detail = "Removed · not sent yet"; tone = .warn }
            else if let en, en.isOff { detail = "Day off" }
            else if let en {
                let bm = core.breakMins(en)
                let nb = max(core.entryBreaks(en).count, (en.brk ?? 0) > 0 ? 1 : 0)
                detail = "\(core.fmtTime(en.start ?? ""))–\(core.fmtTime(en.end ?? ""))" + (bm > 0 ? " · \(core.fmtDur(bm)) break\(nb > 1 ? "s" : "")" : "")
                hours = core.fmtDur(core.worked(en))
            } else if let d = state.drafts?[s] {
                detail = "Started \(core.fmtTime(d.start))" + (missing ? " · not finished" : ""); if missing { tone = .warn }
            } else if missing { detail = "Not logged"; tone = .warn }
            let ss = core.sentState(en)
            return Row(day: s, label: "\(Clock.dow[i]) \(core.md(s))", detail: detail, hours: hours,
                       badge: ss == "ok" ? "✓" : ss == "stale" ? "●" : "", tone: tone,
                       dim: en == nil && !missing && state.drafts?[s] == nil,
                       hidden: en == nil && s > today && s != cur)
        }
    }
    var anySent: Bool { weekDays.contains { state.entries[$0]?.sent != nil } }

    func copyWeek() {
        Haptics.tap()
        guard let t = core.weekText(state.entries, cur: cur, settings: state.settings) else { show("Nothing logged this week yet"); return }
        UIPasteboard.general.string = t
        show("Week copied")
    }

    // MARK: - settings & backup

    func updateSettings(_ s: Settings) { state.settings = s; persist() }
    var backupSummary: String {
        let keys = state.entries.keys.sorted()
        guard let f = keys.first, let l = keys.last else { return "Nothing logged yet." }
        return "\(keys.count) day\(keys.count > 1 ? "s" : "") saved (\(core.md(f)) – \(core.md(l)))."
    }
    func copyBackup() {
        Haptics.tap()
        guard !state.entries.isEmpty else { show("Nothing to back up yet"); return }
        UIPasteboard.general.string = core.backupText(state.entries, today: today)
        show("Backup copied — paste it into Notes")
    }
    /// Accepts backups from this app or the web app.
    func restore(_ text: String) -> Bool {
        Haptics.tap()
        guard let entries = core.parseBackup(text), !entries.isEmpty else { show("That doesn't look like a backup"); return false }
        state.entries.merge(entries) { _, new in new }
        persist(); loadDate(cur)
        show("Restored \(entries.count) day\(entries.count > 1 ? "s" : "")")
        return true
    }

    // MARK: - toast & undo

    func show(_ text: String, undoable: Bool = false) {
        toast = Toast(text: text, undoable: undoable)
        toastExpiry?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastExpiry = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (undoable ? 5 : 2.2), execute: item)
    }
    private func snapshot(_ d: String) {
        if undo == nil || undo?.date != d { undo = (d, state.entries[d]) }
        undoExpiry?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.undo = nil }
        undoExpiry = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
    }
    func performUndo() {
        guard let u = undo else { return }
        Haptics.tap()
        state.entries[u.date] = u.prev
        undo = nil
        persist(); loadDate(u.date)
        show("Undone")
    }
}
