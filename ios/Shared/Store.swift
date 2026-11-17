import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Saved data, shared by the app and the widgets through an App Group.
enum Store {
    static let groupID = "group.tv.firman.hours"
    private static let fileName = "hours.json"

    private static var url: URL {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> AppState {
        var state = AppState()
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(AppState.self, from: data) {
            state = s
        }
        if state.drafts == nil { state.drafts = [:] }
        if state.acks == nil { state.acks = [:] }
        if let migrated = Core.shared.migrate(state.entries) {
            state.entries = migrated
            save(state, reloadWidgets: false)
        }
        return state
    }

    @discardableResult
    static func save(_ state: AppState, reloadWidgets: Bool = true) -> Bool {
        do {
            let data = try JSONEncoder().encode(state)
            let coordinator = NSFileCoordinator()
            var err: NSError?
            var ok = false
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
                ok = (try? data.write(to: u, options: .atomic)) != nil
            }
            if reloadWidgets { Self.reloadWidgets() }
            return ok && err == nil
        } catch {
            return false
        }
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// Dates and times as the web app stores them: "YYYY-MM-DD" and "HH:MM", local time.
enum Clock {
    static func iso(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func hhmm(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }
    static func hour(_ d: Date = Date()) -> Int { Calendar.current.component(.hour, from: d) }

    /// A Date on `day` at "HH:MM" (for pickers and live timers).
    static func date(day: String, time: String) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        let t = time.split(separator: ":").compactMap { Int($0) }
        guard p.count == 3, t.count == 2 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: t[0], minute: t[1]))
    }
    static func parse(_ day: String) -> Date? { date(day: day, time: "12:00") }

    static let dow = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// Monday = 0
    static func weekdayIndex(_ day: String) -> Int {
        guard let d = parse(day) else { return 0 }
        return (Calendar.current.component(.weekday, from: d) + 5) % 7
    }
    static func dayName(_ day: String) -> String { "\(dow[weekdayIndex(day)]) \(Core.shared.md(day))" }
    static func longName(_ day: String) -> String {
        guard let d = parse(day) else { return day }
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        return "\(dow[weekdayIndex(day)]), \(mon[c.month! - 1]) \(c.day!)"
    }
}
