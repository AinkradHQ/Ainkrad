import Foundation

struct ScryRect: Codable, Equatable, Sendable {
    var x: Double, y: Double, width: Double, height: Double
    static let defaultCard = ScryRect(x: 40, y: 40, width: 360, height: 240)

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    // Forward-compatible decode (wave-1 idiom): every field tolerates absence.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? ScryRect.defaultCard.x
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? ScryRect.defaultCard.y
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? ScryRect.defaultCard.width
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? ScryRect.defaultCard.height
    }
}

/// Typed scry element kinds. Unknown raw strings decode to `.unknown` so a
/// document written by a newer build never crashes an older one (additive schema).
enum ScryElementKind: String, Codable, Sendable, CaseIterable {
    case text, markdown, table, diagram, chart, image, video, audio, code, status, card, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ScryElementKind(rawValue: raw) ?? .unknown
    }
}

/// How much room a card asks for. Replaces the agent supplying pixel
/// coordinates: a model can pick "full" for a table far more reliably than it
/// can pick an x/y/width/height that does not collide with everything else.
enum ScrySizeHint: String, Codable, Sendable, CaseIterable {
    case small, medium, large, full

    /// The hint used when the agent gives none.
    static func `default`(for kind: ScryElementKind) -> ScrySizeHint {
        switch kind {
        case .status:                        return .small
        case .table:                         return .full
        case .diagram, .chart, .video:       return .large
        case .text, .markdown, .code,
             .image, .audio, .card, .unknown: return .medium
        }
    }
}

struct ScryElement: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: ScryElementKind
    var title: String?
    var body: String
    var language: String?
    var pinned: Bool
    var sizeHint: ScrySizeHint

    init(id: String, kind: ScryElementKind, title: String? = nil, body: String,
         language: String? = nil,
         pinned: Bool = false, sizeHint: ScrySizeHint? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.body = body
        self.language = language; self.pinned = pinned
        self.sizeHint = sizeHint ?? .default(for: kind)
    }

    // Forward-compatible decode (wave-1 idiom). `id` is required identity;
    // every other field tolerates absence so a newer-schema document never
    // fails to load on an older build.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(ScryElementKind.self, forKey: .kind) ?? .unknown
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        sizeHint = (try? c.decodeIfPresent(ScrySizeHint.self, forKey: .sizeHint))
            .flatMap { $0 } ?? .default(for: kind)
    }
}
