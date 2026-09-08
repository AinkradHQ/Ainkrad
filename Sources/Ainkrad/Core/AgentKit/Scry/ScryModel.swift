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

    mutating func upsert(_ element: ScryElement) {
        if let i = elements.firstIndex(where: { $0.id == element.id }) {
            elements[i] = element
        } else {
            elements.append(element)
        }
    }

    mutating func remove(id: String) { elements.removeAll { $0.id == id } }
}
