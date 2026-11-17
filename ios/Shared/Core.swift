import Foundation
import JavaScriptCore

/// Runs the same core.js the web app uses (and that tests/core.test.js covers), so the
/// hours math, text wording, corrections and validation are identical on web and iPhone.
final class Core {
    static let shared = Core()
    private let ctx: JSContext
    private let lock = NSLock()
    private let enc = JSONEncoder()
    private let dec = JSONDecoder()

    private init() {
        ctx = JSContext()!
        ctx.exceptionHandler = { _, exc in
            NSLog("Hours core.js error: \(exc?.toString() ?? "unknown")")
        }
        for name in ["core", "bridge"] {
            let bundle = Bundle(for: Core.self)
            guard let url = bundle.url(forResource: name, withExtension: "js") ?? Bundle.main.url(forResource: name, withExtension: "js"),
                  let src = try? String(contentsOf: url, encoding: .utf8) else {
                fatalError("Missing \(name).js in the app bundle")
            }
            ctx.evaluateScript(src, withSourceURL: url)
        }
    }

    // MARK: - plumbing

    private func json<T: Encodable>(_ v: T) -> String {
        String(data: (try? enc.encode(v)) ?? Data("null".utf8), encoding: .utf8)!
    }
    private func decode<T: Decodable>(_ s: String?, as: T.Type) -> T? {
        guard let s, let d = s.data(using: .utf8) else { return nil }
        return try? dec.decode(T.self, from: d)
    }
    private func run(_ name: String, _ args: [JSONValue]) -> String? {
        lock.lock(); defer { lock.unlock() }
        let hb = ctx.objectForKeyedSubscript("HB")
        return hb?.invokeMethod("run", withArguments: [name, json(args)])?.toString()
    }
    private func mutate(_ name: String, _ entries: [String: Entry], _ rest: [JSONValue]) -> [String: Entry] {
        lock.lock(); defer { lock.unlock() }
        let hb = ctx.objectForKeyedSubscript("HB")
        let out = hb?.invokeMethod("mutate", withArguments: [name, json(entries), json(rest)])?.toString()
        struct R: Decodable { var entries: [String: Entry] }
        return decode(out, as: R.self)?.entries ?? entries
    }
    private func v<T: Encodable>(_ x: T) -> JSONValue {
        decode(json(x), as: JSONValue.self) ?? .null
    }

    // MARK: - formatting

    func fmtTime(_ t: String) -> String { decode(run("fmtTime", [.string(t)]), as: String.self) ?? t }
    func fmtDur(_ m: Int) -> String { decode(run("fmtDur", [.number(Double(m))]), as: String.self) ?? "\(m)min" }
    func md(_ d: String) -> String { decode(run("md", [.string(d)]), as: String.self) ?? d }

    // MARK: - dates (YYYY-MM-DD strings, like the web app)

    func monday(_ d: String) -> String { decode(run("monday", [.string(d)]), as: String.self) ?? d }
    func weekDates(_ d: String) -> [String] { decode(run("weekDates", [.string(d)]), as: [String].self) ?? [d] }
    func addDays(_ d: String, _ n: Int) -> String { decode(run("addDays", [.string(d), .number(Double(n))]), as: String.self) ?? d }

    // MARK: - hours

    func worked(_ e: Entry?) -> Int { decode(run("worked", [e.map(v) ?? .null]), as: Int.self) ?? 0 }
    func breakMins(_ e: Entry) -> Int { decode(run("breakMins", [v(e)]), as: Int.self) ?? 0 }
    func entryBreaks(_ e: Entry) -> [Break] { decode(run("entryBreaks", [v(e)]), as: [Break].self) ?? [] }
    func between(_ a: String, _ b: String) -> Int { decode(run("between", [.string(a), .string(b)]), as: Int.self) ?? 0 }
    func weekTotal(_ entries: [String: Entry], through d: String) -> Int {
        decode(run("weekTotal", [v(entries), .string(d)]), as: Int.self) ?? 0
    }
    func dayLine(_ d: String, _ e: Entry, _ s: Settings) -> String {
        decode(run("dayLine", [.string(d), v(e), v(s)]), as: String.self) ?? ""
    }
    func ackKey(_ e: Entry) -> String { decode(run("ackKey", [v(e)]), as: String.self) ?? "" }

    // MARK: - texting

    func compose(_ entries: [String: Entry], cur: String, form: Entry, settings: Settings) -> ComposeResult? {
        decode(run("compose", [v(entries), .string(cur), v(form), v(settings)]), as: ComposeResult.self)
    }
    /// ui: endUnconfirmed, breakPlaceholders, ack, entries, date
    func validate(_ form: Entry, endUnconfirmed: Bool, breakPlaceholders: Bool, ack: String?,
                  entries: [String: Entry], date: String) -> Validation {
        var ui: [String: JSONValue] = [
            "endUnconfirmed": .bool(endUnconfirmed),
            "breakPlaceholders": .bool(breakPlaceholders),
            "entries": v(entries),
            "date": .string(date),
        ]
        if let ack { ui["ack"] = .string(ack) }
        return decode(run("validate", [v(form), .object(ui)]), as: Validation.self)
            ?? Validation(blockers: [], confirms: [], needsAck: false)
    }
    func sameEntry(_ a: Entry?, _ b: Entry?) -> Bool {
        guard let a, let b else { return false }
        return decode(run("sameEntry", [v(a), v(b)]), as: Bool.self) ?? false
    }
    /// "" never sent · "ok" matches what was sent · "stale" changed since sent
    func sentState(_ e: Entry?) -> String {
        guard let e else { return "" }
        return decode(run("sentState", [v(e)]), as: String.self) ?? ""
    }

    // MARK: - changes to entries

    func applySent(_ entries: [String: Entry], records: JSONValue, at: Double) -> [String: Entry] {
        mutate("applySent", entries, [records, .number(at)])
    }
    func removeDay(_ entries: [String: Entry], _ d: String) -> [String: Entry] { mutate("removeDay", entries, [.string(d)]) }
    func setOff(_ entries: [String: Entry], _ d: String) -> [String: Entry] { mutate("setOff", entries, [.string(d)]) }
    func unmarkSent(_ entries: [String: Entry], _ d: String) -> [String: Entry] { mutate("unmarkSent", entries, [.string(d)]) }
    func restoreRemoved(_ entries: [String: Entry], _ d: String) -> [String: Entry] { mutate("restoreRemoved", entries, [.string(d)]) }

    /// Converts saves from older app versions. Returns nil when nothing changed.
    func migrate(_ entries: [String: Entry]) -> [String: Entry]? {
        lock.lock(); defer { lock.unlock() }
        let out = ctx.objectForKeyedSubscript("HB")?
            .invokeMethod("mutate", withArguments: ["migrate", json(entries), "[]"])?.toString()
        struct R: Decodable { var entries: [String: Entry]; var result: Bool? }
        guard let r = decode(out, as: R.self), r.result == true else { return nil }
        return r.entries
    }

    // MARK: - backup & week summary

    func backupText(_ entries: [String: Entry], today: String) -> String {
        decode(run("backupText", [v(entries), .string(today)]), as: String.self) ?? ""
    }
    func parseBackup(_ text: String) -> [String: Entry]? {
        decode(run("parseBackup", [.string(text)]), as: [String: Entry]?.self) ?? nil
    }
    func weekText(_ entries: [String: Entry], cur: String, settings: Settings) -> String? {
        decode(run("weekText", [v(entries), .string(cur), v(settings)]), as: String?.self) ?? nil
    }
}
