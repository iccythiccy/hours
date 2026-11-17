import WidgetKit
import SwiftUI
import AppIntents

// MARK: - timeline

struct HoursEntry: TimelineEntry {
    let date: Date
    let summary: DaySummary
}

struct HoursProvider: TimelineProvider {
    func placeholder(in context: Context) -> HoursEntry {
        HoursEntry(date: .now, summary: DaySummary(phase: .logged, day: Clock.iso(), todayMins: 555, weekMins: 1155, sentState: "ok", startLabel: "9am"))
    }
    func getSnapshot(in context: Context, completion: @escaping (HoursEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : HoursEntry(date: .now, summary: DaySummary.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HoursEntry>) -> Void) {
        let now = Date()
        let entry = HoursEntry(date: now, summary: DaySummary.load(now: now))
        // Refresh at the next midnight (new day) or within the hour, whichever is sooner.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        let next = min(midnight, now.addingTimeInterval(3600))
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - shared bits

private extension Color {
    static let wBg = Color(red: 0.090, green: 0.090, blue: 0.102)
    static let wMuted = Color(red: 0.557, green: 0.557, blue: 0.588)
    static let wAccent = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let wGreen = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let wOrange = Color(red: 1.0, green: 0.624, blue: 0.039)
}

private let core = Core.shared

private struct StatusLine: View {
    let s: DaySummary
    var body: some View {
        switch s.phase {
        case .notStarted: Text("Not started").foregroundStyle(Color.wMuted)
        case .started: Text("Started \(s.startLabel ?? "")").foregroundStyle(Color.wAccent)
        case .off: Text("Day off").foregroundStyle(Color.wMuted)
        case .removed: Text("Correction to send").foregroundStyle(Color.wOrange)
        case .logged:
            switch s.sentState {
            case "ok": Text("✓ Sent").foregroundStyle(Color.wGreen)
            case "stale": Text("Changed · send fix").foregroundStyle(Color.wOrange)
            default: Text("Not sent yet").foregroundStyle(Color.wOrange)
            }
        }
    }
}

/// Today's hours, or a live running clock while clocked in.
private struct TodayValue: View {
    let s: DaySummary
    var size: CGFloat
    var body: some View {
        Group {
            if case .started(let since) = s.phase {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
            } else {
                Text(core.fmtDur(s.todayMins))
            }
        }
        .font(.system(size: size, weight: .bold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

// MARK: - medium: clock in / out

struct MediumView: View {
    let s: DaySummary
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOURS").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(Color.wMuted)
                TodayValue(s: s, size: 28)
                StatusLine(s: s).font(.caption.weight(.medium))
                Spacer(minLength: 0)
                Text("Week \(core.fmtDur(s.weekMins))").font(.caption).foregroundStyle(Color.wMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switch s.phase {
            case .notStarted:
                Button(intent: StartShiftIntent()) { ActionLabel(title: "Start", icon: "play.fill", tint: .wAccent) }
                    .buttonStyle(.plain)
            case .started:
                Button(intent: EndShiftIntent()) { ActionLabel(title: "End", icon: "stop.fill", tint: .wOrange) }
                    .buttonStyle(.plain)
            default:
                Link(destination: URL(string: "hours://today")!) {
                    ActionLabel(title: s.sentState == "ok" ? "Open" : "Text", icon: s.sentState == "ok" ? "arrow.up.forward" : "message.fill", tint: .wAccent)
                }
            }
        }
    }
}

private struct ActionLabel: View {
    let title: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold))
            Text(title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(width: 92, height: 92)
        .background(tint, in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - small: at a glance

struct SmallView: View {
    let s: DaySummary
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HOURS").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(Color.wMuted)
            TodayValue(s: s, size: 26)
            StatusLine(s: s).font(.caption.weight(.medium))
            Spacer(minLength: 0)
            Text("Week").font(.caption2).foregroundStyle(Color.wMuted)
            Text(core.fmtDur(s.weekMins)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Lock Screen

struct LockRectView: View {
    let s: DaySummary
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                switch s.phase {
                case .started(let since):
                    Text("Started \(s.startLabel ?? "") · ") + Text(timerInterval: since...Date.distantFuture, countsDown: false)
                case .notStarted: Text("Not started")
                case .off: Text("Day off")
                case .removed: Text("Correction to send")
                case .logged: Text("Today \(core.fmtDur(s.todayMins))\(s.sentState == "ok" ? " ✓" : "")")
                }
            }
            .font(.headline)
            Text("Week \(core.fmtDur(s.weekMins))").font(.subheadline)
        }
        .widgetAccentable()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LockInlineView: View {
    let s: DaySummary
    var body: some View {
        if case .started(let since) = s.phase {
            Text("⏱ ") + Text(timerInterval: since...Date.distantFuture, countsDown: false)
        } else {
            Text("⏱ Week \(core.fmtDur(s.weekMins))")
        }
    }
}

// MARK: - widgets

struct HoursWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry
    var body: some View {
        switch family {
        case .systemMedium: MediumView(s: entry.summary).containerBackground(Color.wBg, for: .widget)
        case .accessoryRectangular: LockRectView(s: entry.summary).containerBackground(.clear, for: .widget)
        case .accessoryInline: LockInlineView(s: entry.summary).containerBackground(.clear, for: .widget)
        default: SmallView(s: entry.summary).containerBackground(Color.wBg, for: .widget)
        }
    }
}

struct HoursWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursWidget", provider: HoursProvider()) { entry in
            HoursWidgetView(entry: entry)
                .widgetURL(URL(string: "hours://today"))
        }
        .configurationDisplayName("Hours")
        .description("Today's hours and your week total. The medium size has Start and End buttons.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct HoursWidgetBundle: WidgetBundle {
    var body: some Widget {
        HoursWidget()
        HoursStackWidget()
    }
}
