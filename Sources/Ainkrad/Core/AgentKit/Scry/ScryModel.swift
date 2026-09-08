import Foundation

struct ScryModel: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    var elements: [ScryElement] = []

    init(elements: [ScryElement] = []) { self.elements = elements }

    // Forward-compatible decode (wave-1 idiom): every field tolerates absence.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elements = try c.decodeIfPresent([ScryElement].self, forKey: .elements) ?? []
    }

    /// Z-ascending (back-to-front), stable for equal z.
    var ordered: [ScryElement] {
        elements.enumerated()
            .sorted { $0.element.z != $1.element.z ? $0.element.z < $1.element.z : $0.offset < $1.offset }
            .map(\.element)
    }

    var nextZ: Int { (elements.map(\.z).max() ?? -1) + 1 }

    mutating func upsert(_ element: ScryElement) {
        if let i = elements.firstIndex(where: { $0.id == element.id }) {
            elements[i] = element
        } else {
            elements.append(element)
        }
    }

    mutating func remove(id: String) { elements.removeAll { $0.id == id } }
}
