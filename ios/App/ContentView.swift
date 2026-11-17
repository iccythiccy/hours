import SwiftUI
import MessageUI

private enum Sheet: Identifiable {
    case time(TimeField, String)   // field, title
    case date
    case settings
    case compose(Outgoing)
    var id: String {
        switch self {
        case .time(let f, _): return "time-\(f)"
        case .date: return "date"
        case .settings: return "settings"
        case .compose(let o): return "compose-\(o.id)"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openURL) private var openURL
    @State private var sheet: Sheet?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.hBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if let p = m.state.pending { pendingBar(p) }
                    dayCard
                    bubble
                    sendButtons
                    weekCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            if let t = m.toast { toastView(t) }
        }
        .animation(.easeOut(duration: 0.2), value: m.toast)
        .sheet(item: $sheet) { s in
            switch s {
            case .time(let field, let title):
                TimeWheelSheet(title: title, day: m.cur, value: m.timeValue(field)) { v in
                    m.setTime(field, v)
                }
            case .date:
                DateSheet(day: m.cur) { m.loadDate($0) }
            case .settings:
                SettingsView().environmentObject(m)
            case .compose(let out):
                MessageComposer(outgoing: out) { result in
                    sheet = nil
                    m.finishedSending(out, result: result)
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hours").font(.system(size: 30, weight: .bold)).tracking(-0.5)
                HStack(spacing: 4) {
                    Button { m.prevWeek() } label: { Image(systemName: "chevron.left") }
                    Text(m.weekLabel).foregroundStyle(Color.hMuted)
                    Button { m.nextWeek() } label: { Image(systemName: "chevron.right") }
                        .disabled(!m.canGoNextWeek)
                }
                .font(.subheadline)
                .tint(.hAccent)
            }
            Spacer()
            Button { Haptics.tap(); sheet = .settings } label: {
                Image(systemName: "gearshape").font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40).background(Color.hCard, in: Circle())
            }
            .tint(.white)
        }
        .padding(.top, 8)
    }

    private func pendingBar(_ p: Pending) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Did your text go out?").font(.headline)
            Text(p.text).font(.subheadline).foregroundStyle(Color.hMuted)
            HStack(spacing: 10) {
                Button("Not sent") { m.dismissPending() }.buttonStyle(FillButton(primary: false))
                Button("Sent") { m.confirmPendingSent() }.buttonStyle(FillButton(primary: true))
            }
        }
        .padding(14)
        .background(Color.hCard, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.hAccent.opacity(0.5)))
    }

    // MARK: day card

    private var dayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { Haptics.tap(); sheet = .date } label: {
                    Text((m.cur == m.today ? "Today · " : "") + Clock.longName(m.cur))
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.hCard2, in: RoundedRectangle(cornerRadius: 14))
                }
                .tint(.white)
                Spacer()
                let st = m.status
                Text(st.0).font(.footnote).multilineTextAlignment(.trailing)
                    .foregroundStyle(st.1 == .good ? Color.hGreen : st.1 == .warn ? Color.hOrange : Color.hMuted)
            }

            if m.isWork { workFields }
            if m.isOff { panel("Day off", "No hours counted. Nothing to text unless you're correcting something.") }
            if m.isRemoved { panel("Removed", "Your client still has the hours you sent for this day. Text the correction below, or bring the day back.") }

            HStack {
                total(m.isWork ? (m.formComplete ? m.fmtDur(m.dayMinutes) : "—") : "0min", "This day")
                total(m.fmtDur(m.weekThroughCur), "Week through this day")
            }
            .padding(.top, 4)

            let ws = m.warnings
            if !ws.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ws) { w in
                        Label(w.text, systemImage: w.blocker ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(w.blocker ? Color.hRed : Color.hOrange)
                    }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.hOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            if m.showAck {
                VStack(alignment: .leading, spacing: 10) {
                    Text(m.ackText).foregroundStyle(Color.hOrange).font(.subheadline)
                    Button("Yes, that's right") { m.confirmLongDay() }.buttonStyle(FillButton(primary: false))
                }
                .padding(12)
                .background(Color.hOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                if m.saved?.sent != nil { Button("Mark as not sent") { m.unmarkSent() } }
                Spacer()
                Button(m.offButtonLabel) { m.offTapped() }
                    .foregroundStyle(m.offArmed ? Color.hRed : Color.hMuted)
                    .multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
            .foregroundStyle(Color.hMuted)
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color.hCard, in: RoundedRectangle(cornerRadius: 20))
    }

    private var workFields: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TimeTile(label: "Start", value: m.fmtTime(m.start), attention: m.start.isEmpty,
                         onTap: { sheet = .time(.start, "Start") }, onNow: { m.startNow() })
                TimeTile(label: "End", value: m.fmtTime(m.end), attention: m.end.isEmpty || m.endIsDefault,
                         onTap: { sheet = .time(.end, "End") }, onNow: { m.endNow() })
            }
            ForEach(Array(m.brks.enumerated()), id: \.element.id) { i, b in
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        TimeTile(label: "Break start", value: m.fmtTime(b.s), attention: b.s.isEmpty || b.sDef, small: true,
                                 onTap: { sheet = .time(.breakStart(b.id), "Break start") })
                        TimeTile(label: "Break end", value: m.fmtTime(b.e), attention: b.e.isEmpty || b.eDef, small: true,
                                 onTap: { sheet = .time(.breakEnd(b.id), "Break end") })
                    }
                    HStack {
                        Text(m.breakLabel(b, index: i))
                        Spacer()
                        Button("Remove") { m.removeBreak(b.id) }.foregroundStyle(Color.hMuted)
                    }
                    .font(.subheadline).foregroundStyle(Color.hMuted).padding(.horizontal, 2)
                }
            }
            if m.brks.count < 2 {
                Button { m.addBreak() } label: {
                    HStack {
                        Text(m.brks.isEmpty ? "UNPAID BREAK" : "SECOND BREAK")
                            .font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Color.hMuted)
                        Spacer()
                        Text("+ Add").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.hAccent)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.hCard2, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func panel(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 28, weight: .bold))
            Text(sub).font(.subheadline).foregroundStyle(Color.hMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.footnote).foregroundStyle(Color.hMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: message + send

    private var bubble: some View {
        HStack {
            Spacer(minLength: 40)
            Text(m.bubbleText)
                .font(.system(size: 16))
                .foregroundStyle(m.canSend ? .white : Color.hMuted)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(m.canSend ? Color.hAccent : Color.hCard2,
                            in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20))
                .textSelection(.enabled)
        }
    }

    private var sendButtons: some View {
        HStack(spacing: 10) {
            Button { m.copyText() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(FillButton(primary: false, big: true))
            Button {
                guard let out = m.prepareText() else { return }
                if MFMessageComposeViewController.canSendText() { sheet = .compose(out) }
                else if let url = m.fallbackSMSURL(out) { openURL(url) }
            } label: { Label(m.textButtonLabel, systemImage: "message.fill") }
                .buttonStyle(FillButton(primary: true, big: true))
        }
        .disabled(!m.canSend)
        .opacity(m.canSend ? 1 : 0.4)
    }

    // MARK: week

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(m.weekTitle.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Color.hMuted)
                Spacer()
                Button("Copy week") { m.copyWeek() }.font(.subheadline.weight(.semibold)).tint(.hAccent)
            }
            .padding(.bottom, 6)
            let rows = m.weekRows.filter { !$0.hidden }
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                Button { Haptics.tap(); m.loadDate(r.day) } label: {
                    HStack(spacing: 10) {
                        Text(r.label).font(.body.weight(.semibold)).frame(minWidth: 74, alignment: .leading)
                            .foregroundStyle(r.day == m.cur ? Color.hAccent : r.tone == .warn ? Color.hOrange : r.dim ? Color.hBlank : .white)
                        Text(r.detail).font(.subheadline).foregroundStyle(r.tone == .warn ? Color.hOrange : Color.hMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(r.hours).font(.body.weight(.semibold)).monospacedDigit()
                        Text(r.badge).font(.footnote).frame(width: 16)
                            .foregroundStyle(r.badge == "●" ? Color.hOrange : Color.hGreen)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < rows.count - 1 { Divider().overlay(Color.hLine) }
            }
            if m.anySent {
                Text("✓ sent   ● changed since sent").font(.caption).foregroundStyle(Color.hMuted).padding(.top, 8)
            }
            if m.saved != nil && !m.isRemoved {
                Button(m.deleteArmed ? "Tap again to delete" : "Delete this day's entry") { m.deleteTapped() }
                    .font(.subheadline.weight(m.deleteArmed ? .semibold : .regular))
                    .foregroundStyle(m.deleteArmed ? Color.red : Color.hMuted)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .background(Color.hCard, in: RoundedRectangle(cornerRadius: 20))
    }

    private func toastView(_ t: Toast) -> some View {
        HStack(spacing: 14) {
            Text(t.text).font(.subheadline.weight(.medium))
            if t.undoable { Button("Undo") { m.performUndo() }.font(.subheadline.weight(.bold)).tint(.hAccent) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(white: 0.17), in: Capsule())
        .shadow(color: .black.opacity(0.4), radius: 15, y: 8)
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - pieces

struct TimeTile: View {
    let label: String
    let value: String
    var attention = false
    var small = false
    let onTap: () -> Void
    var onNow: (() -> Void)? = nil

    var body: some View {
        Button { Haptics.tap(); onTap() } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(.caption.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(attention ? Color.hOrange : Color.hMuted)
                Text(value).font(.system(size: small ? 24 : 30, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(value == "—" ? Color.hBlank : .white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.hCard2, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(attention ? Color.hOrange : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if let onNow {
                Button("Now") { onNow() }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.hAccent.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.hAccent)
                    .padding(9)
            }
        }
    }
}

struct FillButton: ButtonStyle {
    var primary: Bool
    var big = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: big ? 17 : 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, big ? 15 : 12)
            .background(primary ? Color.hAccent : Color.hCard2, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// Apple's time wheel (with its haptic ticks), plus Now.
struct TimeWheelSheet: View {
    let title: String
    let day: String
    let onDone: (String) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(title: String, day: String, value: String, onDone: @escaping (String) -> Void) {
        self.title = title; self.day = day; self.onDone = onDone
        _date = State(initialValue: Clock.date(day: day, time: value.isEmpty ? Clock.hhmm() : value) ?? Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Button("Now") { Haptics.tap(); date = Date() }
                    .font(.headline).tint(.hAccent)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(Clock.hhmm(date)); dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(360)])
    }
}

struct DateSheet: View {
    let onPick: (String) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(day: String, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        _date = State(initialValue: Clock.parse(day) ?? Date())
    }

    var body: some View {
        NavigationStack {
            DatePicker("", selection: $date, in: ...Date().addingTimeInterval(86400 * 7), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .navigationTitle("Pick a day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onPick(Clock.iso(date)); dismiss() }.fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
