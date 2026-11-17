import WidgetKit
import SwiftUI
import AppIntents

// A widget built for the Smart Stack: it always shows the one thing to do next
// (start, a live clock with End, the text still to send, or the week once all is done),
// and tells iOS how relevant it is so Smart Rotate brings it to the top at the right moments.

// MARK: - data

/// The user's usual working pattern, learned from the last four weeks of saved days.
struct Routine {
    var startMins: Int?     // usual start, minutes after midnight
    var spanMins: Int?      // usual start-to-end span (breaks included)
    var workday: Bool       // do they usually work on this weekday?

    static func learn(_ entries: [String: Entry], today: String) -> Routine {
        let core = Core.shared
        let wd = Clock.weekdayIndex(today)
        var all: [(day: String, start: Int, span: Int)] = []
        for i in 1...28 {
            let d = core.addDays(today, -i)
            guard let e = entries[d], e.isWork, let s = e.start, let en = e.end,
                  let a = minutes(s), let b = minutes(en) else { continue }
            all.append((d, a, (b - a + 1440) % 1440))
        }
        let same = all.filter { Clock.weekdayIndex($0.day) == wd }
        let pool = same.count >= 2 ? same : all
        let workday = all.isEmpty ? wd < 5 : same.count >= 2 || (same.count == 1 && wd < 5)
        return Routine(startMins: median(pool.map(\.start)), spanMins: median(pool.map(\.span)), workday: workday)
    }

    private static func minutes(_ t: String) -> Int? {
        let p = t.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : nil
    }
    private static func median(_ xs: [Int]) -> Int? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

struct WeekBar: Hashable {
    let label: String       // M T W T F S S
    let mins: Int
    let isToday: Bool
    let isFuture: Bool
}

/// Everything the Smart Stack widget shows.
struct StackInfo {
    var summary: DaySummary
    var routine: Routine
    var bars: [WeekBar]
    var preview: String?    // today's text line, when it still needs sending

    var usualStartLabel: String? {
        routine.startMins.map { Core.shared.fmtTime(String(format: "%02d:%02d", $0 / 60, $0 % 60)) }
    }
    /// When today's open shift usually ends.
    var usualEnd: Date? {
        guard case .started(let since) = summary.phase, let span = routine.spanMins, span > 0 else { return nil }
        return since.addingTimeInterval(TimeInterval(span * 60))
    }
    /// The big number is already the week total (day off, or not a workday).
    var headlineIsWeek: Bool {
        switch summary.phase {
        case .off: return true
        case .notStarted: return !routine.workday
        default: return false
        }
    }
    var needsText: Bool {
        switch summary.phase {
        case .removed: return true
        case .logged: return summary.sentState != "ok"
        default: return false
        }
    }

    static func load(now: Date = Date()) -> StackInfo {
        let core = Core.shared
        let state = Store.load()
        let summary = DaySummary.load(now: now)
        let today = Clock.iso(now)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let bars = core.weekDates(summary.day).enumerated().map { i, d in
            WeekBar(label: letters[i], mins: core.worked(state.entries[d]), isToday: d == summary.day, isFuture: d > today)
        }
        var preview: String?
        if case .logged = summary.phase, summary.sentState != "ok", let e = state.entries[summary.day] {
            preview = core.dayLine(summary.day, e, state.settings)
        }
        return StackInfo(summary: summary, routine: Routine.learn(state.entries, today: today), bars: bars, preview: preview)
    }

    static let sample = StackInfo(
        summary: DaySummary(phase: .started(Date().addingTimeInterval(-5 * 3600 - 23 * 60)), day: Clock.iso(),
                            todayMins: 0, weekMins: 1155, sentState: "", startLabel: "9:02am"),
        routine: Routine(startMins: 540, spanMins: 555, workday: true),
        bars: [WeekBar(label: "M", mins: 600, isToday: false, isFuture: false),
               WeekBar(label: "T", mins: 555, isToday: false, isFuture: false),
               WeekBar(label: "W", mins: 0, isToday: true, isFuture: false),
               WeekBar(label: "T", mins: 0, isToday: false, isFuture: true),
               WeekBar(label: "F", mins: 0, isToday: false, isFuture: true),
               WeekBar(label: "S", mins: 0, isToday: false, isFuture: true),
               WeekBar(label: "S", mins: 0, isToday: false, isFuture: true)],
        preview: nil)

    /// How useful the widget is at `date` (0–100), so Smart Rotate surfaces it when it matters.
    func relevance(at date: Date) -> Float {
        let cal = Calendar.current
        let minuteOfDay = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        switch summary.phase {
        case .started(let since):
            if let end = usualEnd {
                if date >= end.addingTimeInterval(-30 * 60) { return 100 }     // time to clock out
                return date < since.addingTimeInterval(15 * 60) ? 70 : 45
            }
            return date.timeIntervalSince(since) > 8 * 3600 ? 90 : 50
        case .notStarted:
            guard routine.workday else { return 5 }
            let usual = routine.startMins ?? 9 * 60
            let delta = minuteOfDay - usual
            if delta >= -45 && delta <= 90 { return 90 }                       // around the usual start
            if delta > 90 && minuteOfDay < 15 * 60 { return 40 }                // not logged yet today
            return 10
        case .removed:
            return 80
        case .logged:
            return summary.sentState == "ok" ? 5 : 85                           // text still to send
        case .off:
            return 2
        }
    }
}

// MARK: - timeline

struct StackEntry: TimelineEntry {
    let date: Date
    let info: StackInfo
    let relevance: TimelineEntryRelevance?
}

struct StackProvider: TimelineProvider {
    func placeholder(in context: Context) -> StackEntry {
        StackEntry(date: .now, info: .sample, relevance: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (StackEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : StackEntry(date: .now, info: StackInfo.load(), relevance: nil))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StackEntry>) -> Void) {
        let now = Date()
        let info = StackInfo.load(now: now)
        // The content only changes when the data does (the app and the buttons reload us), but the
        // relevance changes through the day, so give iOS an entry every 15 minutes until midnight.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        var entries: [StackEntry] = []
        var t = now
        while t < midnight && entries.count < 96 {
            entries.append(StackEntry(date: t, info: info,
                                      relevance: TimelineEntryRelevance(score: info.relevance(at: t), duration: 15 * 60)))
            t = t.addingTimeInterval(15 * 60)
        }
        if entries.isEmpty { entries = [StackEntry(date: now, info: info, relevance: nil)] }
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }
}

// MARK: - look

private enum Palette {
    static let bg = Color(red: 0.090, green: 0.090, blue: 0.102)
    static let card = Color.white.opacity(0.08)
    static let muted = Color(red: 0.557, green: 0.557, blue: 0.588)
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let green = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let orange = Color(red: 1.0, green: 0.624, blue: 0.039)
}

private let core = Core.shared

/// "HOURS · TUE" with a small status dot.
private struct Header: View {
    let info: StackInfo
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text("HOURS · \(Clock.dow[Clock.weekdayIndex(info.summary.day)].uppercased())")
                .font(.caption2.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Palette.muted)
        }
    }
    private var dot: Color {
        switch info.summary.phase {
        case .started: return Palette.accent
        case .notStarted, .off: return Palette.muted
        case .removed: return Palette.orange
        case .logged: return info.needsText ? Palette.orange : Palette.green
        }
    }
}

/// The big number: live clock while working, otherwise today's or the week's hours.
private struct Headline: View {
    let info: StackInfo
    let size: CGFloat
    var body: some View {
        Group {
            switch info.summary.phase {
            case .started(let since):
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
            case .notStarted:
                Text(info.routine.workday ? "Ready" : core.fmtDur(info.summary.weekMins))
            case .off:
                Text(core.fmtDur(info.summary.weekMins))
            case .removed:
                Text("Fix")
            case .logged:
                Text(core.fmtDur(info.summary.todayMins))
            }
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .widgetAccentable()
    }
}

/// One short line under the headline saying where things stand.
private struct Subline: View {
    let info: StackInfo
    var compact = false
    var body: some View {
        let s = info.summary
        Group {
            switch s.phase {
            case .started:
                if let end = info.usualEnd {
                    let endLabel = core.fmtTime(Clock.hhmm(end))
                    Text(compact ? "Since \(s.startLabel ?? "") · ~\(endLabel)"
                                 : "Since \(s.startLabel ?? "") · usually done ~\(endLabel)")
                } else {
                    Text("Since \(s.startLabel ?? "")")
                }
            case .notStarted:
                if !info.routine.workday { Text(compact ? "This week" : "This week · nothing logged today").foregroundStyle(Palette.muted) }
                else if let u = info.usualStartLabel { Text("You usually start ~\(u)") }
                else { Text("Tap Start when you arrive") }
            case .off:
                Text(compact ? "Day off" : "Day off · this week so far").foregroundStyle(Palette.muted)
            case .removed:
                Text(compact ? "Correction to send" : "A removed day still needs a correction").foregroundStyle(Palette.orange)
            case .logged:
                switch s.sentState {
                case "ok": Text("✓ Sent").foregroundStyle(Palette.green)
                case "stale": Text(compact ? "Changed since sent" : "Changed since sent · send a fix").foregroundStyle(Palette.orange)
                default: Text("Text not sent yet").foregroundStyle(Palette.orange)
                }
            }
        }
        .font(.caption.weight(.medium))
        .lineLimit(compact ? 1 : 2)
        .minimumScaleFactor(0.85)
    }
}

/// Mon–Sun bars, today outlined.
private struct WeekBars: View {
    let bars: [WeekBar]
    var height: CGFloat = 30
    var barWidth: CGFloat = 10
    var body: some View {
        let top = max(bars.map(\.mins).max() ?? 0, 10 * 60)
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, b in
                VStack(spacing: 3) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Palette.card)
                        Capsule()
                            .fill(b.isToday ? Palette.accent : Color.white.opacity(0.6))
                            .frame(height: b.mins > 0 ? max(barWidth, height * CGFloat(b.mins) / CGFloat(top)) : 0)
                            .widgetAccentable()
                    }
                    .frame(width: barWidth, height: height)
                    Text(b.label).font(.system(size: 9, weight: b.isToday ? .bold : .medium))
                        .foregroundStyle(b.isToday ? Palette.accent : Palette.muted)
                }
                .opacity(b.isFuture ? 0.4 : 1)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Live progress toward the usual end of the day.
private struct DayProgress: View {
    let info: StackInfo
    var body: some View {
        if case .started(let since) = info.summary.phase, let end = info.usualEnd, end > since {
            ProgressView(timerInterval: since...end, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.linear)
                .tint(Palette.accent)
        }
    }
}

/// The single next step: Start, End, or open the app to text.
private struct NextAction: View {
    let info: StackInfo
    var compact: Bool
    var body: some View {
        switch info.summary.phase {
        case .notStarted where info.routine.workday:
            Button(intent: StartShiftIntent()) { label("Start", "play.fill", Palette.accent) }.buttonStyle(.plain)
        case .started:
            Button(intent: EndShiftIntent()) { label("End", "stop.fill", Palette.orange) }.buttonStyle(.plain)
        default:
            if info.needsText {
                Link(destination: URL(string: "hours://today")!) {
                    label(info.summary.sentState == "stale" || info.summary.phase.isRemoved ? "Send fix" : "Text",
                          "message.fill", Palette.green)
                }
            }
        }
    }
    @ViewBuilder private func label(_ title: String, _ icon: String, _ tint: Color) -> some View {
        if compact {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(tint, in: Capsule())
                .widgetAccentable()
        } else {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(width: 78)
            .frame(maxHeight: .infinity)
            .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .widgetAccentable()
        }
    }
}

private extension DaySummary.Phase {
    var isRemoved: Bool { if case .removed = self { return true }; return false }
}

// MARK: - sizes

struct StackMediumView: View {
    let info: StackInfo
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Header(info: info)
                Headline(info: info, size: 30)
                Subline(info: info)
                Spacer(minLength: 4)
                if let line = info.preview {
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if case .started = info.summary.phase, info.usualEnd != nil {
                    DayProgress(info: info)
                    Text("Week \(core.fmtDur(info.summary.weekMins)) + today")
                        .font(.caption2).foregroundStyle(Palette.muted)
                } else {
                    HStack(alignment: .bottom, spacing: 12) {
                        WeekBars(bars: info.bars, height: 30)
                        if !info.headlineIsWeek {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("WEEK").font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(Palette.muted)
                                Text(core.fmtDur(info.summary.weekMins)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .fixedSize()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NextAction(info: info, compact: false)
        }
    }
}

struct StackSmallView: View {
    let info: StackInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Header(info: info)
            Headline(info: info, size: 28)
            Subline(info: info, compact: true)
            Spacer(minLength: 4)
            switch info.summary.phase {
            case .notStarted where info.routine.workday:
                NextAction(info: info, compact: true)
            case .started:
                DayProgress(info: info)
                NextAction(info: info, compact: true)
            default:
                if info.needsText {
                    NextAction(info: info, compact: true)
                } else {
                    if !info.headlineIsWeek {
                        Text("Week \(core.fmtDur(info.summary.weekMins))")
                            .font(.caption2.weight(.medium)).foregroundStyle(Palette.muted).monospacedDigit()
                    }
                    WeekBars(bars: info.bars, height: 24, barWidth: 9)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct StackWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StackEntry
    var body: some View {
        Group {
            if family == .systemMedium { StackMediumView(info: entry.info) }
            else { StackSmallView(info: entry.info) }
        }
        .foregroundStyle(.white)
        .containerBackground(Palette.bg, for: .widget)
    }
}

struct HoursStackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursStackWidget", provider: StackProvider()) { entry in
            StackWidgetView(entry: entry)
                .widgetURL(URL(string: "hours://today"))
        }
        .configurationDisplayName("Up Next")
        .description("The one thing to do next: start, a live clock with End, or the text still to send. Best in a Smart Stack, where it rises to the top when it matters.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - previews

#Preview("Working", as: .systemMedium) { HoursStackWidget() } timeline: {
    StackEntry(date: .now, info: .sample, relevance: nil)
}
#Preview("Small", as: .systemSmall) { HoursStackWidget() } timeline: {
    StackEntry(date: .now, info: .sample, relevance: nil)
}
