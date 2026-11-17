import Foundation

/// Any JSON value. Used for data the Swift side passes through untouched (e.g. what was sent).
enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

struct Break: Codable, Equatable, Hashable {
    var s: String
    var e: String
}

/// One day. Same shape as the web app (core.js documents it):
/// work {start,end,brk,breaks?,sent?} · day off {off:true,sent?} · removed {removed:true,sent}
struct Entry: Codable, Equatable {
    var start: String?
    var end: String?
    var brk: Int?
    var breaks: [Break]?
    var sent: JSONValue?
    var off: Bool?
    var removed: Bool?
    var bStart: String?   // oldest saves
    var bEnd: String?

    var isOff: Bool { off == true }
    var isRemoved: Bool { removed == true }
    var isWork: Bool { !isOff && !isRemoved }

    static func work(start: String, end: String, breaks: [Break]) -> Entry {
        Entry(start: start, end: end, brk: 0, breaks: breaks.isEmpty ? nil : breaks)
    }
    static let offDay = Entry(off: true)
    static let removedDay = Entry(removed: true)
}

struct Settings: Codable, Equatable {
    var name: String = ""
    var phone: String = ""
    var showBrk: Bool = true
}

/// A clock-in with no end time yet.
struct Draft: Codable, Equatable {
    var start: String
    var breaks: [Break]?
}

/// A text that was copied (not sent through the app), waiting for "Sent" / "Not sent".
struct Pending: Codable, Equatable {
    var at: Double
    var via: String
    var date: String
    var text: String
    var records: JSONValue
}

/// What was sent for a day switched from "day off" back to hours, until the hours are saved.
struct Held: Codable, Equatable {
    var date: String
    var sent: JSONValue
}

struct AppState: Codable, Equatable {
    var entries: [String: Entry] = [:]
    var settings = Settings()
    var drafts: [String: Draft]? = [:]
    var acks: [String: String]? = [:]
    var pending: Pending?
    var held: Held?
}

/// Result of composing the text (see core.js compose).
struct ComposeResult: Codable, Equatable {
    var text: String
    var kind: String          // daily | daily+fix | fix | resend
    var anchor: String
    var fixed: [String]
    var added: [String]
    var records: JSONValue
}

struct Validation: Codable, Equatable {
    var blockers: [String]
    var confirms: [String]
    var needsAck: Bool
}
